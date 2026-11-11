#!/usr/bin/env bash
# ==============================================================================
# DPSjur / SBJur — Backup INDEPENDENTE do BANCO B (PostgreSQL 18)
# Script: docs/vps/23-backup-banco-b-dpsjur.sh
# Versão: v1.0.0
# Destino de execução: VPS Hostinger de produção (2.25.181.69 / srv1737667).
#
# BANCO B — IDENTIDADE FIXA E VALIDADA (sem regex genérica):
#   Projeto .......: dpsjur (EasyPanel)
#   Contêiner .....: dpsjur-db (comparação por IGUALDADE EXATA)
#   PostgreSQL ....: 18 (major 18 — a versão é PROVADA antes do dump)
#   Usuário .......: Doug
#   Banco .........: dpsjur
#
# ATENÇÃO: O Banco B NÃO tem rotina de backup agendada hoje. Este script é a
# primeira rotina dele. Nenhum outro banco é alcançado por este script.
#
# REQUISITOS ATENDIDOS (numeração do pedido de Douglas):
#   1. Rotina independente para o PG 18 (o Banco A tem script próprio, 22).
#   2. Contêiner/usuário/banco EXPLÍCITOS e PROVADOS (versão + banco + usuário).
#   3. Senha via .pgpass (PGPASSFILE, chmod 600) — NUNCA em argumento/log.
#   4. pipefail + verificação SEPARADA de pg_dump e gzip (PIPESTATUS).
#   5. gzip -t + tamanho mínimo do dump.
#   6. Diretórios separados diário/semanal/mensal.
#   7. Log próprio com veredito SUCESSO/FALHA — nenhum /dev/null no pipeline.
#   8. Retenção conservadora (observação por padrão; exclusão só com flag).
#   9. Lock anti-simultâneo (flock/mkdir) + noclobber + timestamp no arquivo.
#  10. Restauração isolada documentada em docs/vps/RUN-BACKUP-DUPLA-POSTGRES.md.
#
# COMPATIBILIDADE COM A AUDITORIA (20-auditar-backup.sh):
#   O auditor atual (v2.1.3) é calibrado para o Banco A (PG15, usuário postgres,
#   banco postgres, imagem supabase/postgres). Para o Banco B (PG18, usuário
#   Doug, banco dpsjur), a auditoria exige parâmetros próprios:
#     - imagem de laboratório: postgres:18-alpine (nao supabase/postgres:15);
#     - usuário de restauração: Doug (docker exec ... -U Doug ...);
#     - RESTORE: psql -U Doug -d dpsjur (banco criado antes com owner Doug).
#   ESTA DIFERENÇA ESTÁ DOCUMENTADA EM docs/vps/RUN-BACKUP-DUPLA-POSTGRES.md —
#   o auditor 20-auditar-backup.sh CONTINUA sendo o caminho OFICIAL para o
#   Banco A; para o Banco B, o procedimento de restauração isolada da sessão
#   é o da seção 6 do documento RUN-BACKUP-DUPLA-POSTGRES.md.
#
# USO:
#   bash 23-backup-banco-b-dpsjur.sh                     # backup diário
#   bash 23-backup-banco-b-dpsjur.sh --semanal           # backup semanal
#   bash 23-backup-banco-b-dpsjur.sh --mensal            # backup mensal
#   bash 23-backup-banco-b-dpsjur.sh --aplicar-retencao  # habilita exclusões
#
# IMPORTANTE (lição do projeto): NÃO usar via curl|bash — baixar o arquivo e
# rodar via SSH com comando (bash <script> <flags>).
# ==============================================================================

set -u -o pipefail
umask 077

SCRIPT_VERSION="v1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=docs/vps/lib/backup-lib.sh
. "${SCRIPT_DIR}/lib/backup-lib.sh"

# ------------------------------------------------------------------------------
# CONFIGURAÇÃO DO BANCO B (FIXA — não depende de ambiente, não é genérica)
# ------------------------------------------------------------------------------
BANK_ID="B"
PG_CONTAINER="dpsjur-db"                   # contêiner EXATO
PG_MAJOR_WANTED="18"                        # PostgreSQL 18 → major 18
PG_USER="Doug"                              # usuário FIXO (maiúscula/minúscula importa)
PG_DB="dpsjur"                              # banco FIXO
PG_BIN_PREFIX=""                            # pg_dump/psql no PATH do contêiner
PG_DUMP_FORMAT_ARGS=(-Fp --no-owner --no-privileges)  # plain format p/ auditoria
MIN_DUMP_BYTES=10240                        # mínimo: 10 KB — abaixo disso, suspeita
                                            # de dump vazio/quebrado (ajustável por
                                            # --min-bytes após primeira execução real)
RETENTION_DAILY=14
RETENTION_WEEKLY=8
RETENTION_MONTHLY=12
APPLY_RETENTION=0
FREQ="diario"
PGPASS_FILE="/root/.pgpass-dpsjur-b"
TS_STAMP="$(date +%Y%m%d-%H%M%S)"
BASE_DIR="/root/dpsjur-backups"
LOG_FILE="${BASE_DIR}/logs/bk-b-dpsjur18-$(date +%Y%m%d).log"
LOCK_PATH="${BASE_DIR}/.lock-bk-b"

# ------------------------------------------------------------------------------
# Parsing de argumentos
# ------------------------------------------------------------------------------
while [ $# -gt 0 ]; do
    case "$1" in
        --diario)   FREQ="diario"; shift ;;
        --semanal)  FREQ="semanal"; shift ;;
        --mensal)   FREQ="mensal"; shift ;;
        --aplicar-retencao) APPLY_RETENTION=1; shift ;;
        --min-bytes)
            shift
            [ -n "${1:-}" ] || { echo "❌ --min-bytes exige um valor" >&2; exit "${BK_EXIT_USAGE}"; }
            case "$1" in (*[!0-9]*|'') echo "❌ --min-bytes exige número inteiro" >&2; exit "${BK_EXIT_USAGE}";; esac
            MIN_DUMP_BYTES="$1"; shift ;;
        -h|--help)  show_help_backup; exit "${BK_EXIT_OK}" ;;
        *) echo "❌ Opção desconhecida: $1" >&2; exit "${BK_EXIT_USAGE}" ;;
    esac
done

show_help_backup() {
    cat <<EOF
Uso: bash $0 [OPÇÕES]

Backup independente do BANCO B (PostgreSQL 18, contêiner dpsjur-db,
usuário Doug, banco dpsjur).

Opções:
  --diario                 Backup no diretório diário (padrão)
  --semanal                Backup no diretório semanal
  --mensal                 Backup no diretório mensal
  --aplicar-retencao       Aplica retenção (remove backups antigos JÁ VALIDADOS).
                           SEM esta flag: modo observação, nada é apagado.
  -h, --help               Exibe esta ajuda.

Arquivo de senha esperado: ${PGPASS_FILE} (formato .pgpass, chmod 600)
  Formato da linha:  <host>:<porta>:<db>:<user>:<senha>
  Exemplo:           localhost:5432:dpsjur:Doug:SUA_SENHA
EOF
}

# ------------------------------------------------------------------------------
# TRAP de saída — veredito SUCESSO/FALHA no log (Requisito 7)
# ------------------------------------------------------------------------------
trap 'bk_finalize_session "Banco B (PG18, ${PG_CONTAINER})"' EXIT
trap 'exit $((128 + $1))' INT TERM 2>/dev/null || true

# ------------------------------------------------------------------------------
# PRE-VOO — dependências, diretórios, lock, .pgpass
# ------------------------------------------------------------------------------
bk_log "=== Início backup Banco B (PG18) ${SCRIPT_VERSION} — freq ${FREQ} ==="
bk_require_deps docker gzip stat flock

if [ "$(id -u)" != "0" ]; then
    bk_die "Este script deve rodar como root (padrão da VPS: docker exec requer root)." "${BK_EXIT_USAGE}"
fi

bk_setup_dirs "${BASE_DIR}"

if [ ! -e "${LOG_FILE}" ]; then
    touch "${LOG_FILE}" || bk_die "Falha ao criar log: ${LOG_FILE}" "${BK_EXIT_FS_FAIL}"
    chmod 600 "${LOG_FILE}" || bk_die "Falha no chmod 600 do log." "${BK_EXIT_FS_FAIL}"
fi
bk_verify_fs_file "${LOG_FILE}" "log do Banco B"
bk_log "Arquivo de log da sessão: ${LOG_FILE}"
bk_log "Arquivo .pgpass do banco B: ${PGPASS_FILE} (chmod 600 validado abaixo)"

# Lock anti-simultâneo — Requisito 9 (por banco; Banco A tem lock próprio)
bk_acquire_lock "${LOCK_PATH}"
BK_LOCK_KIND="flock"
BK_LOCK_PATH="${LOCK_PATH}"

# PGPASSFILE — senha NUNCA na linha de comando (Requisito 3)
if [ ! -f "${PGPASS_FILE}" ]; then
    bk_die "Arquivo .pgpass não encontrado: ${PGPASS_FILE}. Crie-o com chmod 600 antes de rodar o backup (veja --help)." "${BK_EXIT_CONFIG_FAIL}"
fi
bk_verify_fs_file "${PGPASS_FILE}" "PGPASSFILE do Banco B"
export PGPASSFILE="${PGPASS_FILE}"

# ------------------------------------------------------------------------------
# IDENTIFICAÇÃO E PROVA DO CONTÊINER (Requisito 2) — sem regex genérica
# ------------------------------------------------------------------------------
bk_verify_container "${PG_CONTAINER}" "${PG_MAJOR_WANTED}" "${PG_DB}" "${PG_USER}" "${PG_BIN_PREFIX}"

# ------------------------------------------------------------------------------
# DUMP — nome com timestamp + noclobber (Requisito 9)
# ------------------------------------------------------------------------------
OUT_DIR="${BASE_DIR}/${FREQ}"
OUT_FILE="${OUT_DIR}/bk-b-dpsjur18-B-${FREQ}-${TS_STAMP}.sql.gz"
bk_log "Destino do dump: ${OUT_FILE}"

# No Banco B o usuário é 'Doug' (não é superuser padrão do contêiner) e a
# conexão é TCP dentro do próprio contêiner. O .pgpass do HOST é validado no
# pre-voo (Requisito 3); DENTRO do contêiner a sessão de implantação deve
# garantir um .pgpass equivalente (veja RUN-BACKUP-DUPLA-POSTGRES.md, seção
# 3.2). O dump abaixo assume que o pg_hba.conf do contêiner já autentica o
# usuário Doug via TCP 127.0.0.1 — nunca via senha em argumento.
export BK_DUMP_CMD=(docker exec "${PG_CONTAINER}" pg_dump -h 127.0.0.1 -p 5432 -U "${PG_USER}" -d "${PG_DB}" "${PG_DUMP_FORMAT_ARGS[@]}")
export BK_DUMP_OUT="${OUT_FILE}"
if ! bk_run_dump_pipeline "${OUT_FILE}"; then
    rc=$?
    bk_die "Pipeline de dump FALHOU (pg_dump exit ${rc}). Arquivo parcial removido." "${BK_EXIT_DUMP_FAIL}"
fi

# ------------------------------------------------------------------------------
# VALIDAÇÃO — gzip -t + tamanho mínimo (Requisito 5)
# ------------------------------------------------------------------------------
if ! bk_validate_dump "${OUT_FILE}" "${MIN_DUMP_BYTES}"; then
    bk_die "Validação de integridade/tamanho falhou." "${BK_EXIT_INTEGRITY_FAIL}"
fi

# ------------------------------------------------------------------------------
# RETENÇÃO — Requisito 8 (observação por padrão; exclusão só com flag explícita)
# ------------------------------------------------------------------------------
bk_apply_retention "${BASE_DIR}/diario"  "bk-b-dpsjur18-B" "${RETENTION_DAILY}"  "${APPLY_RETENTION}"
ret_rc=$?
[ "${ret_rc}" -eq 0 ] || bk_die "Falha na retenção diária." "${BK_EXIT_RETENTION_FAIL}"
bk_apply_retention "${BASE_DIR}/semanal" "bk-b-dpsjur18-B" "${RETENTION_WEEKLY}" "${APPLY_RETENTION}"
ret_rc=$?
[ "${ret_rc}" -eq 0 ] || bk_die "Falha na retenção semanal." "${BK_EXIT_RETENTION_FAIL}"
bk_apply_retention "${BASE_DIR}/mensal"  "bk-b-dpsjur18-B" "${RETENTION_MONTHLY}" "${APPLY_RETENTION}"
ret_rc=$?
[ "${ret_rc}" -eq 0 ] || bk_die "Falha na retenção mensal." "${BK_EXIT_RETENTION_FAIL}"

# ------------------------------------------------------------------------------
# FIM
# ------------------------------------------------------------------------------
bk_log "Backup Banco B concluído: ${OUT_FILE}"
exit "${BK_EXIT_OK}"
