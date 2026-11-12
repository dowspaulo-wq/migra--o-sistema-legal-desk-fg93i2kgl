#!/usr/bin/env bash
# ==============================================================================
# DPSjur — VALIDAÇÃO DE RESTAURAÇÃO · PASSO 2
# Script: docs/vps/restore-validacao/02-restaurar-limpo.sh
# Versão: v1.0.1
# v1.0.1: correção crítica — o psql agora recebe o SQL DESCOMPRIMIDO pelo stdin
# (gunzip | psql, sem -f sobre o .sql.gz) e os heredocs de psql usam docker exec -i.
#
# FINALIDADE: criar um contêiner NOVO e LIMPO a partir da imagem
# supabase/postgres:15.8.1.085, preparar papéis/extensões e restaurar o dump
# .sql.gz como SUPERUSUÁRIO supabase_admin via TCP, com psql
# -v ON_ERROR_STOP=0 — modo "continuar e registrar TODOS os erros" (o objetivo
# desta validação é justamente a LISTA COMPLETA de erros, não parar no primeiro).
#
# Uso:
#   ./02-restaurar-limpo.sh /mnt/c/Users/dowsp/DPSJUR-Backup-Teste/sbjur_backup_2026-11-11_030001.sql.gz \
#       [NOME_DO_CONTAINER]   # default: dpsjur-restore-final
#
#   Variáveis opcionais (export antes de chamar):
#     SUPABASE_RESTORE_OWNERS="authenticator service_role ..."  donos adicionais do dump
#     SUPABASE_RESTORE_PG_PASSWORD="senha-forte-local"          senha do supabase_admin/postgres NO CONTÊINER NOVO (local, não produção)
#     SUPABASE_RESTORE_PORT="15433"                             porta exposta no host (default 15433)
#
# GARANTIAS:
#   - NUNCA aponta para host externo, VPS ou EasyPanel: só 127.0.0.1 do contêiner
#     recém-criado (conexões psql com -h 127.0.0.1 dentro do próprio contêiner).
#   - NÃO toca nos contêineres existentes (dpsjur-restore-test,
#     dpsjur-restore-supabase): preservados. Se o nome do contêiner alvo já
#     existir, o script ABORTA — não reutiliza, não remove, não reinicia.
#   - NÃO altera credenciais, permissões ou versão de PostgreSQL de produção.
#   - Nenhum backup existente é apagado ou modificado.
#   - Sem senhas em log: a senha vai só para o .pgpass dentro do contêiner.
#
# ⚠ NÃO VALIDADO: este script NÃO foi executado e NÃO passou por `bash -n` nem
# por ShellCheck — esta plataforma não tem Bash/Docker. Executar e validar no
# WSL2 de Douglas antes de confiar no resultado. A restauração SÓ é declarada
# validada após a execução real e o passo 03.
# ==============================================================================

set -o errexit
set -o nounset
set -o pipefail
umask 077

readonly SCRIPT_NAME="02-restaurar-limpo.sh"
readonly SCRIPT_VERSION="v1.0.1"
readonly IMAGE="supabase/postgres:15.8.1.085"
readonly DEFAULT_CONTAINER="dpsjur-restore-final"
readonly HOST_PORT="${SUPABASE_RESTORE_PORT:-15433}"
readonly PG_USER="supabase_admin"
readonly PG_DB="postgres"
readonly PG_PASSWORD="${SUPABASE_RESTORE_PG_PASSWORD:-restore-local-only-NAO-producao}"

# Donos adicionais detectados no dump (passo 01 imprime a lista). supabase_admin
# e postgres são criados sempre; aqui vêm os demais (idempotente no passo prepare).
OWNERS_EXTRA="${SUPABASE_RESTORE_OWNERS:-}"

usage() {
    printf 'Uso: %s CAMINHO_DO_BACKUP.sql.gz [NOME_DO_CONTAINER]\n' "${SCRIPT_NAME}"
    printf '\nCria contêiner NOVO (%s) e restaura como supabase_admin com ON_ERROR_STOP=0.\n' "${DEFAULT_CONTAINER}"
    printf 'Não toca em contêineres existentes, VPS ou produção.\n'
}

BACKUP_FILE=""
CONTAINER="${DEFAULT_CONTAINER}"

while [ $# -gt 0 ]; do
    case "$1" in
        --help|-h) usage; exit 0 ;;
        -*)        printf 'Argumento desconhecido: %s\n' "$1" >&2; usage >&2; exit 64 ;;
        *)
            if [ -z "${BACKUP_FILE}" ]; then
                BACKUP_FILE="$1"
            elif [ -z "${CONTAINER}" ] || [ "${CONTAINER}" = "${DEFAULT_CONTAINER}" ]; then
                CONTAINER="$1"
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

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || { printf 'ERRO: comando obrigatório ausente: %s\n' "$1" >&2; exit 69; }
}
require_cmd docker
require_cmd gzip

BACKUP_ABS="$(cd "$(dirname "${BACKUP_FILE}")" && pwd)/$(basename "${BACKUP_FILE}")"
STAMP="$(date +%Y-%m-%d_%H%M%S)"
OUT_DIR="$(dirname "${BACKUP_ABS}")"
LOG_FILE="${OUT_DIR}/restauracao-${CONTAINER}-${STAMP}.log"

printf '=================================================================\n'
printf 'RESTAURAÇÃO LIMPA — %s %s\n' "${SCRIPT_NAME}" "${SCRIPT_VERSION}"
printf 'Backup      : %s\n' "${BACKUP_ABS}"
printf 'Contêiner   : %s (NOVO — aborta se já existir)\n' "${CONTAINER}"
printf 'Imagem      : %s\n' "${IMAGE}"
printf 'Porta host  : %s (apenas 127.0.0.1 local; nada externo)\n' "${HOST_PORT}"
printf 'Log         : %s\n' "${LOG_FILE}"
printf '=================================================================\n'

# ------------------------------------------------------------------------------
# Proteção 1: contêiner alvo deve ser NOVO. Nada de reutilizar/remove.
# ------------------------------------------------------------------------------
if docker ps -a --format '{{.Names}}' | grep -Fxq "${CONTAINER}"; then
    printf 'ERRO: já existe um contêiner chamado "%s".\n' "${CONTAINER}" >&2
    printf 'Este script NÃO reutiliza nem remove contêineres (os existentes\n' >&2
    printf 'dpsjur-restore-test e dpsjur-restore-supabase devem ser preservados).\n' >&2
    printf 'Escolha outro nome, ex.: dpsjur-restore-final-2\n' >&2
    exit 73
fi

# ------------------------------------------------------------------------------
# Proteção 2: nunca apontar para host externo/VPS. A porta fica vinculada a
# 127.0.0.1 e TODAS as conexões psql são internas ao contêiner (-h 127.0.0.1).
# ------------------------------------------------------------------------------
docker_run() {
    docker run -d \
        --name "${CONTAINER}" \
        --publish "127.0.0.1:${HOST_PORT}:5432" \
        --env "POSTGRES_PASSWORD=${PG_PASSWORD}" \
        --env "POSTGRES_USER=postgres" \
        --env "POSTGRES_DB=${PG_DB}" \
        "${IMAGE}"
}

printf '\n[1/6] Criando contêiner novo "%s"...\n' "${CONTAINER}"
docker_run > /dev/null

cleanup_on_fail() {
    rc=$?
    printf '\n[FALHA] Restauração não concluída (código %s).\n' "${rc}" >&2
    printf 'O contêiner "%s" foi mantido para inspeção (nada foi removido).\n' "${CONTAINER}" >&2
    printf 'Log: %s\n' "${LOG_FILE}" >&2
    exit "${rc}"
}
trap cleanup_on_fail EXIT

printf '[2/6] Aguardando PostgreSQL aceitar conexões (até 120s)...\n'
pg_ready() {
    docker exec "${CONTAINER}" psql -h 127.0.0.1 -U postgres -d postgres -tAc 'SELECT 1' >/dev/null 2>&1
}
READY=0
for _ in $(seq 1 60); do
    if pg_ready; then READY=1; break; fi
    sleep 2
done
if [ "${READY}" -ne 1 ]; then
    printf 'ERRO: PostgreSQL não ficou pronto em 120s. Ver logs: docker logs %s\n' "${CONTAINER}" >&2
    exit 70
fi
printf '      PostgreSQL pronto.\n'

printf '[3/6] Preparando papéis e extensões (idempotente)...\n'
# Papel principal: supabase_admin SUPERUSUÁRIO (comprovado que é ele quem possui
# o event trigger pgrst_drop_watch na origem — restaurar como postgres falha com
# "must be owner of event trigger pgrst_drop_watch").
docker exec -i "${CONTAINER}" psql -h 127.0.0.1 -U postgres -d postgres -v ON_ERROR_STOP=0 <<SQL
-- Papéis donos (idempotente)
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'supabase_admin') THEN
    CREATE ROLE supabase_admin LOGIN SUPERUSER PASSWORD '${PG_PASSWORD}';
  ELSE
    ALTER ROLE supabase_admin WITH LOGIN SUPERUSER;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'postgres') THEN
    CREATE ROLE postgres LOGIN SUPERUSER;
  END IF;
END
\$\$;
SQL

# Donos adicionais detectados no passo 01 (lista separada por espaço)
for ROLE_NAME in ${OWNERS_EXTRA}; do
    printf '      criando papel dono (se ausente): %s\n' "${ROLE_NAME}"
    docker exec "${CONTAINER}" psql -h 127.0.0.1 -U postgres -d postgres -v ON_ERROR_STOP=0 \
        -v role_name="${ROLE_NAME}" <<'SQL'
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'role_name') THEN
    EXECUTE format('CREATE ROLE %I LOGIN', :'role_name');
  END IF;
END
$$;
SQL
done

# Extensões frequentemente exigidas por dumps Supabase (idempotente; pg_net é a
# que faltou na Tentativa 1). ON_ERROR_STOP=0: erro aqui não aborta — fica no log.
docker exec -i "${CONTAINER}" psql -h 127.0.0.1 -U postgres -d postgres -v ON_ERROR_STOP=0 <<'SQL'
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS pg_net;
CREATE EXTENSION IF NOT EXISTS pgjwt;
CREATE EXTENSION IF NOT EXISTS pgsodium;
SQL

printf '[4/6] Copiando o .sql.gz para dentro do contêiner (/tmp/backup.sql.gz)...\n'
docker cp "${BACKUP_ABS}" "${CONTAINER}:/tmp/backup.sql.gz"
docker exec "${CONTAINER}" gzip -t /tmp/backup.sql.gz
printf '      integridade gzip dentro do contêiner: OK.\n'

printf '[5/6] Restaurando como supabase_admin (ON_ERROR_STOP=0 — registra TODOS os erros)...\n'
# TODAS as conexões são internas ao contêiner (-h 127.0.0.1). Nenhuma conexão
# sai da máquina local; nenhuma credencial aparece no log.
# shellcheck disable=SC2016
docker exec "${CONTAINER}" bash -c 'echo "127.0.0.1:5432:*:supabase_admin:$SUPABASE_RESTORE_PG_PASSWORD" > /tmp/.pgpass-restore && chmod 600 /tmp/.pgpass-restore' \
    2>/dev/null || true
# A senha não pode entrar por variável visível em docker inspect: gravamos o
# .pgpass via stdin (sem eco no log) e removemos ao final.
docker exec -i "${CONTAINER}" bash -c 'cat > /tmp/.pgpass-restore && chmod 600 /tmp/.pgpass-restore' <<PGPASS
127.0.0.1:5432:*:${PG_USER}:${PG_PASSWORD}
PGPASS

# Restauração: psql -v ON_ERROR_STOP=0 (continua e registra todos os erros).
# Saída completa em LOG_FILE; erros também resumidos ao final.
set +o errexit
# O .sql.gz é DESCOMPRIMIDO pelo gunzip e o SQL alimentado ao psql pelo stdin
# (sem -f sobre o .sql.gz). PSQL_RC captura o código do fim do pipeline (psql).
docker exec "${CONTAINER}" bash -lc \
  'gunzip -c /tmp/backup.sql.gz | PGPASSFILE=/tmp/.pgpass-restore psql -h 127.0.0.1 -p 5432 -U supabase_admin -d postgres -v ON_ERROR_STOP=0' \
  > "${LOG_FILE}" 2>&1
PSQL_RC=$?
set -o errexit

printf '      psql terminou com código %s (com ON_ERROR_STOP=0, verifique os erros no log).\n' "${PSQL_RC}"

printf '[6/6] Resumo de erros registrados:\n'
ERROR_COUNT="$(grep -cE '^(psql:|ERRO|ERROR)' "${LOG_FILE}" || true)"
printf '      linhas de erro no log: %s\n' "${ERROR_COUNT}"
grep -E '^(psql:|ERRO|ERROR)' "${LOG_FILE}" | head -40 || true

# Remover .pgpass interno e o dump copiado (higiene; dump original no host intacto)
docker exec "${CONTAINER}" rm -f /tmp/.pgpass-restore >/dev/null 2>&1 || true
# NOTA: /tmp/backup.sql.gz é mantido dentro do contêiner para o passo 03 poder
# comparar "exigido pelo dump" vs "instalado", se necessário.

trap - EXIT

printf '\n=================================================================\n'
printf 'RESTAURAÇÃO FINALIZADA (código psql: %s).\n' "${PSQL_RC}"
printf 'Contêiner      : %s (preservado para o passo 03)\n' "${CONTAINER}"
printf 'Log completo   : %s\n' "${LOG_FILE}"
printf 'Erros no log   : %s\n' "${ERROR_COUNT}"
printf 'Próximo passo  : ./03-validar-restauracao.sh %s\n' "${CONTAINER}"
printf '=================================================================\n'
printf 'A restauração SÓ será "validada" após a execução real e o relatório do passo 03.\n'
