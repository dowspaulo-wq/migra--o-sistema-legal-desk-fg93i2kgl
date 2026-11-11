#!/usr/bin/env bash
# ==============================================================================
# DPSjur / SBJur — BACKUP DO BANCO A (PostgreSQL 15.8, contêiner
# "sbjur-local_supabase-db-1", usuário "postgres", banco "postgres").
# Script: docs/vps/22-backup-banco-a-sbjur-local.sh
# Versão: v2.0.0
#
# REGRA ABSOLUTA: a rotina antiga /root/sbjur-backups/backup.sh (diária 03h)
# DEVE permanecer intocada. Este script NÃO a substitui nem a altera.
#
# Mudanças v1 → v2 (auditoria d510fd9):
#   - bk_verify_container agora roda com PGPASSFILE DENTRO do contêiner e
#     TODAS as consultas psql com conexão EXPLÍCITA (-U postgres -d postgres
#     -p 5432) — nada de conexão implícita.
#   - Captura de erro SEM inversão: `if bk_run_dump_pipeline ...; then :;
#     else rc=$?; fi` (o `!` invertia o código antes da captura).
#   - Dump em arquivo TEMPORÁRIO exclusivo (mesmo filesystem do destino) e
#     PUBLICAÇÃO ATÔMICA — backup existente nunca sobrescrito.
# ==============================================================================

set -o errexit
set -o nounset
set -o pipefail
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/backup-lib.sh
source "${SCRIPT_DIR}/lib/backup-lib.sh"

# ------------------------------------------------------------------------------
# IDENTIDADE DO BANCO A — PostgreSQL 15.8, contêiner fixo do compose sbsjur.
# ------------------------------------------------------------------------------
readonly CONTAINER="sbjur-local_supabase-db-1"
readonly PG_MAJOR="15"
readonly PG_USER="postgres"
readonly PG_DB="postgres"
readonly PG_PORT="5432"
readonly PG_BIN_PREFIX=""   # pg_dump/psql no PATH do contêiner (imagem supabase/postgres)
readonly DUMP_LABEL="sbsjur (Banco A)"
readonly DUMP_PREFIX="sbsjur-"             # prefixo exclusivo DESTE banco
readonly RETENTION_DIR_NAME="diario"       # retenção apenas no diário do A
readonly HOST_BASE="/root/sbjur-backups-dupla/banco-a"

readonly KEEP_DAILY=7
readonly KEEP_WEEKLY=4
readonly KEEP_MONTHLY=12
readonly MIN_DUMP_BYTES=1024          # dump < 1 KB é tratado como inválido

readonly USAGE="Uso: 22-backup-banco-a-sbjur-local.sh [--diario|--semanal|--mensal] [--aplicar-retencao]

Banco A (PostgreSQL 15.8) — contêiner sbsjur-local_supabase-db-1, usuário postgres, banco postgres.
A rotina antiga /root/sbjur-backups/backup.sh (03h) NÃO é tocada.

Opções:
  --diario | --semanal | --mensal   tipo do backup (padrão: --diario)
  --aplicar-retencao                HABILITA exclusão de backups antigos (padrão: MODO OBSERVAÇÃO)
  --pgpass-file CAMINHO             PGPASSFILE no host (padrão: \$HOME/.pgpass-bk-banco-a; chmod 600 obrigatório)
  --help                            esta ajuda"

MODE="diario"
APPLY_RETENTION=0
HOST_PGPASS="${HOME}/.pgpass-bk-banco-a"
CONTAINER_PGPASS="/tmp/.pgpass-bk-banco-a"

while [ $# -gt 0 ]; do
    case "$1" in
        --diario)             MODE="diario" ;;
        --semanal)            MODE="semanal" ;;
        --mensal)             MODE="mensal" ;;
        --aplicar-retencao)   APPLY_RETENTION=1 ;;
        --pgpass-file)        shift; HOST_PGPASS="${1:?--pgpass-file requer caminho}" ;;
        --help|-h)            printf '%s\n' "${USAGE}"; exit "${BK_EXIT_OK}" ;;
        *)                    printf 'Argumento desconhecido: %s\n%s\n' "$1" "${USAGE}" >&2; exit "${BK_EXIT_USAGE}" ;;
    esac
    shift
done

# ------------------------------------------------------------------------------
# Sessão: log exclusivo do Banco A
# ------------------------------------------------------------------------------
RUN_STAMP="$(date +%Y%m%d-%H%M%S)"
BASE_LOG_DIR="${HOST_BASE}/logs"
mkdir -p "${BASE_LOG_DIR}" || { printf 'Falha ao criar %s\n' "${BASE_LOG_DIR}" >&2; exit "${BK_EXIT_FS_FAIL}"; }
chmod 700 "${BASE_LOG_DIR}" 2>/dev/null || true
LOG_FILE="${BASE_LOG_DIR}/banco-a-${MODE}-${RUN_STAMP}.log"
: > "${LOG_FILE}" || { printf 'Falha ao criar log: %s\n' "${LOG_FILE}" >&2; exit "${BK_EXIT_FS_FAIL}"; }
chmod 600 "${LOG_FILE}"

cleanup() {
    # ${CONTAINER:-}: pode não estar definido se a falha ocorreu antes da
    # identificação do contêiner (bk_remove_pgpass ignora contêiner vazio).
    bk_remove_pgpass "${CONTAINER:-}" "${CONTAINER_PGPASS}" || true
    bk_tmp_cleanup || true
    bk_release_lock || true
    bk_finalize_session "Banco A"
    printf '%s FIM DA SESSÃO Banco A (exit %s)\n' "$(date '+%F %T')" "$1" >> "${LOG_FILE}" 2>/dev/null || true
}
trap 'cleanup $?' EXIT
trap 'bk_tmp_cleanup; bk_remove_pgpass "${CONTAINER:-}" "${CONTAINER_PGPASS}" || true; exit 130' INT TERM HUP

# ------------------------------------------------------------------------------
# 1) Dependências + lock (protege contra execução simultânea; lib de lock
#    compartilhada com o Banco B, mas arquivo de lock PRÓPRIO do Banco A)
# ------------------------------------------------------------------------------
bk_require_deps docker gzip stat awk sort mktemp grep

bk_setup_dirs "${HOST_BASE}"
bk_acquire_lock "${HOST_BASE}/.lock-banco-a"

bk_log "=== BACKUP BANCO A (PostgreSQL ${PG_MAJOR}, contêiner ${CONTAINER}) — modo ${MODE} ==="
bk_log "Rotina antiga /root/sbjur-backups/backup.sh permanece intocada (proibido alterar)."

# ------------------------------------------------------------------------------
# 2) Credenciais: PGPASSFILE no HOST é só a fonte; quem executa pg_dump é o
#    contêiner. O .pgpass é INSTALADO DENTRO do contêiner (docker cp, chmod 600,
#    dono = usuário da conexão) e removido ao final — NUNCA se presume que o
#    PGPASSFILE do host chega ao docker exec (não chega).
# ------------------------------------------------------------------------------
if ! bk_stage_pgpass_into_container "${CONTAINER}" "${HOST_PGPASS}" "${CONTAINER_PGPASS}" "${PG_USER}"; then
    bk_die "Staging do .pgpass no contêiner NÃO confirmado — abortando." "${BK_EXIT_GUARD}"
fi

# ------------------------------------------------------------------------------
# 3) Identificação EXPLÍCITA do contêiner/banco/usuário/versão
#    (bk_verify_container usa conexão explícita -U/-d/-p em todas as consultas)
# ------------------------------------------------------------------------------
bk_verify_container "${CONTAINER}" "${PG_MAJOR}" "${PG_DB}" "${PG_USER}" "${PG_PORT}" "${PG_BIN_PREFIX}"

# ------------------------------------------------------------------------------
# 4) Comando pg_dump (rodará DENTRO do contêiner, autenticado via PGPASSFILE
#    interno — sem senha em argumento; conexão explícita -U/-d/-p)
# ------------------------------------------------------------------------------
BK_DUMP_CMD=(docker exec "${CONTAINER}" env PGPASSFILE="${CONTAINER_PGPASS}" \
    ${PG_BIN_PREFIX}pg_dump -X -p "${PG_PORT}" -U "${PG_USER}" -d "${PG_DB}")

# ------------------------------------------------------------------------------
# 5) Destino final por modo (diário/semanal/mensal) — diretório do próprio banco
# ------------------------------------------------------------------------------
DEST_DIR="${HOST_BASE}/${MODE}"
OUT_FILE="${DEST_DIR}/${DUMP_PREFIX}${MODE}-${RUN_STAMP}.sql.gz"
bk_log "Destino final: ${OUT_FILE}"
if [ -e "${OUT_FILE}" ]; then
    bk_die "Destino JÁ EXISTE (${OUT_FILE}) — abortando ANTES do dump: backup preexistente nunca sobrescrito." "${BK_EXIT_FS_FAIL}"
fi

# ------------------------------------------------------------------------------
# 6) Dump + compactação em TEMPORÁRIO exclusivo (mesmo filesystem do destino).
#    Captura de erro SEM inversão: sem "!" antes da chamada — o $? do else é
#    o código ORIGINAL retornado pela função.
# ------------------------------------------------------------------------------
rc=0
if bk_run_dump_pipeline "${OUT_FILE}"; then :; else rc=$?; fi
if [ "${rc}" -ne 0 ]; then
    bk_die "Pipeline de dump/compactação falhou (código original preservado: ${rc})." "${rc}"
fi

# ------------------------------------------------------------------------------
# 7) Validação de integridade (gzip -t + tamanho mínimo)
#    INTEGRIDADE gzip ≠ CONSISTÊNCIA do dump ≠ SUCESSO de restauração isolada
# ------------------------------------------------------------------------------
bk_validate_dump "${BK_TMP_FILE}" "${MIN_DUMP_BYTES}"

# ------------------------------------------------------------------------------
# 8) Publicação ATÔMICA (mv no mesmo filesystem; recusa destino existente)
# ------------------------------------------------------------------------------
bk_publish_dump "${BK_TMP_FILE}" "${OUT_FILE}"
BK_TMP_FILE=""
bk_log "BACKUP BANCO A CONCLUÍDO: ${OUT_FILE}"

# ------------------------------------------------------------------------------
# 9) Retenção — MODO OBSERVAÇÃO por padrão (nada é excluído sem
#    --aplicar-retencao). Apenas no DIÁRIO do Banco A (semanal/mensal nunca são
#    tocados aqui); candidatos limitados ao prefixo ${DUMP_PREFIX} deste banco;
#    validação individual antes de qualquer exclusão; rotina antiga NUNCA tocada.
# ------------------------------------------------------------------------------
bk_apply_retention "${HOST_BASE}/${RETENTION_DIR_NAME}" "${DUMP_PREFIX}" "${KEEP_DAILY}" "${APPLY_RETENTION}" "${MIN_DUMP_BYTES}"

bk_log "Sessão Banco A encerrada com sucesso."
exit "${BK_EXIT_OK}"
