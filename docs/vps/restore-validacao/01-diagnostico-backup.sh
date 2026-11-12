#!/usr/bin/env bash
# ==============================================================================
# DPSjur — VALIDAÇÃO DE RESTAURAÇÃO · PASSO 1
# Script: docs/vps/restore-validacao/01-diagnostico-backup.sh
# Versão: v1.0.0
#
# FINALIDADE: diagnóstico do arquivo de backup .sql.gz SEM abrir banco e SEM
# restaurar nada. O caminho do arquivo é recebido como $1.
#
#   ./01-diagnostico-backup.sh /mnt/c/Users/dowsp/DPSJUR-Backup-Teste/sbjur_backup_2026-11-11_030001.sql.gz
#
# O que é extraído (tudo via zcat/grep sobre o próprio .sql.gz):
#   - cabeçalho do pg_dump (versão do pg_dump e do servidor de origem —
#     confirma a versão REAL do PostgreSQL de origem);
#   - lista de CREATE EXTENSION;
#   - lista de papéis (CREATE ROLE / ALTER ROLE);
#   - donos (OWNER TO / ALTER ... OWNER) mais frequentes;
#   - presença do event trigger `pgrst_drop_watch` (a lição da Tentativa 2);
#   - contagem aproximada de CREATE TABLE / CREATE FUNCTION / CREATE POLICY;
#   - eventos de COPY (tabelas com dados).
#
# SAÍDA: relatório textual no stdout (e cópia em arquivo com data, ao lado do
# próprio .sql.gz) pronto para colar de volta no chat.
#
# ⚠ NÃO VALIDADO: este script NÃO foi executado e NÃO passou por `bash -n` nem
# por ShellCheck — esta plataforma não tem Bash. Executar e validar no WSL2 de
# Douglas (Docker Desktop) antes de confiar no resultado. Nenhum teste foi
# alegado como aprovado.
#
# RESTRIÇÕES ABSOLUTAS: nada na VPS; nada em banco de produção; nenhum contêiner
# existente é tocado; nenhum backup é apagado ou modificado; o script é SOMENTE
# LEITURA sobre o arquivo informado.
# ==============================================================================

set -o errexit
set -o nounset
set -o pipefail
umask 077

readonly SCRIPT_NAME="01-diagnostico-backup.sh"
readonly SCRIPT_VERSION="v1.0.0"

usage() {
    printf 'Uso: %s CAMINHO_DO_BACKUP.sql.gz [--out DIRETORIO_DE_SAIDA]\n' "${SCRIPT_NAME}"
    printf '\nDiagnóstico SOMENTE LEITURA do .sql.gz (sem banco, sem restauração).\n'
    printf '  CAMINHO_DO_BACKUP.sql.gz   arquivo de backup (ex.: /mnt/c/Users/dowsp/DPSJUR-Backup-Teste/sbjur_backup_2026-11-11_030001.sql.gz)\n'
    printf '  --out DIRETORIO            onde gravar o relatório (padrão: ao lado do .sql.gz)\n'
}

BACKUP_FILE=""
OUT_DIR=""

while [ $# -gt 0 ]; do
    case "$1" in
        --out)    shift; OUT_DIR="${1:?--out requer um diretório}" ;;
        --help|-h) usage; exit 0 ;;
        -*)       printf 'Argumento desconhecido: %s\n' "$1" >&2; usage >&2; exit 64 ;;
        *)
            if [ -z "${BACKUP_FILE}" ]; then
                BACKUP_FILE="$1"
            else
                printf 'Argumento inesperado: %s\n' "$1" >&2; usage >&2; exit 64
            fi
            ;;
    esac
    shift
done

if [ -z "${BACKUP_FILE}" ]; then
    printf 'ERRO: informe o caminho do .sql.gz como primeiro argumento.\n' >&2
    usage >&2
    exit 64
fi

if [ ! -f "${BACKUP_FILE}" ]; then
    printf 'ERRO: arquivo não encontrado: %s\n' "${BACKUP_FILE}" >&2
    exit 66
fi

# Resolve caminho absoluto e diretório de saída
BACKUP_ABS="$(cd "$(dirname "${BACKUP_FILE}")" && pwd)/$(basename "${BACKUP_FILE}")"
if [ -z "${OUT_DIR}" ]; then
    OUT_DIR="$(dirname "${BACKUP_ABS}")"
fi
mkdir -p "${OUT_DIR}"

STAMP="$(date +%Y-%m-%d_%H%M%S)"
REPORT="${OUT_DIR}/diagnostico-backup-${STAMP}.txt"

# ------------------------------------------------------------------------------
# Coleta — TODA leitura é sobre o arquivo local informado. Nada é enviado a
# nenhum host externo.
# ------------------------------------------------------------------------------

{
    printf '=================================================================\n'
    printf 'RELATÓRIO DE DIAGNÓSTICO DO BACKUP (somente leitura)\n'
    printf 'Script   : %s %s\n' "${SCRIPT_NAME}" "${SCRIPT_VERSION}"
    printf 'Gerado em: %s\n' "$(date '+%Y-%m-%d %H:%M:%S %Z')"
    printf 'Arquivo  : %s\n' "${BACKUP_ABS}"
    printf 'Tamanho  : %s bytes\n' "$(wc -c < "${BACKUP_ABS}")"
    printf 'MD5      : %s\n' "$(md5sum "${BACKUP_ABS}" | awk '{print $1}')"
    printf '=================================================================\n'
    printf '\n'

    # -- Integridade GZIP -------------------------------------------------------
    printf -- '--- Integridade GZIP ------------------------------------------------\n'
    if gzip -t "${BACKUP_ABS}" 2>/dev/null; then
        printf 'OK: o arquivo é um gzip válido.\n'
    else
        printf 'ATENÇÃO: gzip -t indicou problema no arquivo (verificar antes de seguir).\n'
    fi
    printf '\n'

    # -- Cabeçalho do pg_dump (versões) -----------------------------------------
    printf -- '--- Cabeçalho do pg_dump (versões de origem) ------------------------\n'
    zcat "${BACKUP_ABS}" | grep -E '^-- Dumped from database version' || true
    zcat "${BACKUP_ABS}" | grep -E '^-- Dumped by pg_dump version'   || true
    printf '\n'
    printf '>> A linha "Dumped from database version" confirma a versão REAL do\n'
    printf '>> PostgreSQL de ORIGEM. Compare com a versão do contêiner de teste\n'
    printf '>> (15.8.1.085 = PostgreSQL 15.8) antes de restaurar.\n'
    printf '\n'

    # -- Extensões exigidas -------------------------------------------------------
    printf -- '--- CREATE EXTENSION (extensões exigidas pelo dump) -----------------\n'
    zcat "${BACKUP_ABS}" | grep -E '^CREATE EXTENSION' || printf '(nenhuma)\n'
    printf '\n'
    printf '>> Observação conhecida: pg_net pode aparecer aqui e NÃO existir numa\n'
    printf '>> imagem supabase/postgres de restauração sem preparo (falha da\n'
    printf '>> Tentativa 1). O passo 02 prepara as extensões antes do restore.\n'
    printf '\n'

    # -- Papéis --------------------------------------------------------------------
    printf -- '--- Papéis (CREATE ROLE / ALTER ROLE) -------------------------------\n'
    zcat "${BACKUP_ABS}" | grep -E '^(CREATE ROLE|ALTER ROLE)' | sort -u || printf '(nenhum)\n'
    printf '\n'
    printf '>> Papéis citados no dump (apenas nomes):\n'
    zcat "${BACKUP_ABS}" | grep -oE '^CREATE ROLE [^;]+' | awk '{print $3}' | sort -u || true
    printf '\n'

    # -- Donos mais frequentes ------------------------------------------------------
    printf -- '--- Donos mais frequentes (OWNER TO / ALTER ... OWNER) --------------\n'
    zcat "${BACKUP_ABS}" | grep -oE 'OWNER TO [A-Za-z_][A-Za-z0-9_]*' | sort | uniq -c | sort -rn || true
    printf '\n'
    printf '>> DONOS ÚNICOS (preencha SUPABASE_RESTORE_OWNERS no passo 02 com estes nomes,\n'
    printf '>> separados por espaço; supabase_admin e postgres já são criados):\n'
    zcat "${BACKUP_ABS}" | grep -oE 'OWNER TO [A-Za-z_][A-Za-z0-9_]*' | awk '{print $3}' | sort -u | tr '\n' ' ' || true
    printf '\n\n'

    # -- pgrst_drop_watch -------------------------------------------------------------
    printf -- '--- Event trigger pgrst_drop_watch ----------------------------------\n'
    if zcat "${BACKUP_ABS}" | grep -q 'pgrst_drop_watch'; then
        printf 'PRESENTE: o dump contém o event trigger pgrst_drop_watch (pertence a\n'
        printf 'supabase_admin — restaurar como postgres produz "must be owner of event\n'
        printf 'trigger pgrst_drop_watch", a falha da Tentativa 2).\n'
    else
        printf 'AUSENTE: o dump não menciona pgrst_drop_watch.\n'
    fi
    printf '\n'

    # -- Contagens aproximadas -------------------------------------------------------
    printf -- '--- Contagens aproximadas de DDL ------------------------------------\n'
    printf 'CREATE TABLE    : %s\n' "$(zcat "${BACKUP_ABS}" | grep -cE '^CREATE TABLE ' || true)"
    printf 'CREATE FUNCTION : %s\n' "$(zcat "${BACKUP_ABS}" | grep -cE '^CREATE (OR REPLACE )?FUNCTION ' || true)"
    printf 'CREATE POLICY   : %s\n' "$(zcat "${BACKUP_ABS}" | grep -cE '^CREATE POLICY ' || true)"
    printf 'CREATE INDEX    : %s\n' "$(zcat "${BACKUP_ABS}" | grep -cE '^CREATE (UNIQUE )?INDEX ' || true)"
    printf 'CREATE SEQUENCE : %s\n' "$(zcat "${BACKUP_ABS}" | grep -cE '^CREATE SEQUENCE ' || true)"
    printf 'CREATE TRIGGER  : %s\n' "$(zcat "${BACKUP_ABS}" | grep -cE '^CREATE TRIGGER ' || true)"
    printf 'CREATE VIEW     : %s\n' "$(zcat "${BACKUP_ABS}" | grep -cE '^CREATE (MATERIALIZED )?VIEW ' || true)"
    printf '\n'

    # -- COPY (tabelas com dados) -------------------------------------------------------
    printf -- '--- COPY (tabelas com dados) ----------------------------------------\n'
    zcat "${BACKUP_ABS}" | grep -oE '^COPY [A-Za-z_"][^ ]+' | sed 's/^COPY //' | sort | uniq -c | sort -rn || true
    printf '\n'
    printf '>> Fim do relatório. Cole este arquivo de volta no chat.\n'
} > "${REPORT}" 2> >(tee "${REPORT}.stderr" >&2)

printf '\nRelatório gravado em: %s\n' "${REPORT}"
printf 'Se houve avisos, veja também: %s.stderr\n' "${REPORT}"
printf 'COPIE O CONTEÚDO DESTE ARQUIVO E COLE DE VOLTA NO CHAT.\n'
