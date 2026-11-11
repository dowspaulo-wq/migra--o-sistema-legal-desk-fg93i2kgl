#!/usr/bin/env bash
# ==============================================================================
# DPSjur / SBJur — BACKUP DO BANCO B (PostgreSQL 18, serviço Docker Swarm
# "dpsjur_dpsjur-db", usuário "Doug", banco "dpsjur").
# Script: docs/vps/23-backup-banco-b-dpsjur.sh
# Versão: v2.0.0
#
# REGRA ABSOLUTA: este script é EXCLUSIVO do Banco B. O Banco A (PostgreSQL 15,
# sbsjur) tem script próprio (22-...) e rotina antiga /root/sbjur-backups/backup.sh
# (03h) que DEVE permanecer intocada. NÃO presumir que o PostgreSQL 18 é o banco
# principal — identificação pendente de confirmação operacional por Douglas.
#
# Mudanças v1 → v2 (auditoria d510fd9):
#   - O nome literal "dpsjur-db" NÃO é mais exigido no contêiner: a resolução é
#     DETERMINÍSTICA via serviço Swarm (bk_resolve_swarm_container), com igualdade
#     exata e recusa de resultado ausente ou ambíguo.
#   - TODAS as consultas psql usam conexão EXPLÍCITA (-U Doug -d dpsjur -p 5432).
#   - pg_dump roda com PGPASSFILE instalado DENTRO do contêiner (docker exec não
#     herda PGPASSFILE do host); sem senha em argumento, log ou arquivo versionado.
#   - Captura de erro SEM inversão; dump em temporário + PUBLICAÇÃO ATÔMICA.
# ==============================================================================

set -o errexit
set -o nounset
set -o pipefail
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/backup-lib.sh
source "${SCRIPT_DIR}/lib/backup-lib.sh"

# ------------------------------------------------------------------------------
# IDENTIDADE DO BANCO B — PostgreSQL 18, serviço Swarm dpsjur_dpsjur-db.
# O CONTÊINER NÃO é fixo (nomes de tarefa Swarm: dpsjur_dpsjur-db.<slot>.<id>)
# — o nome exato é RESOLVIDO a cada execução, sem regex genérica.
# ------------------------------------------------------------------------------
readonly SWARM_SERVICE="dpsjur_dpsjur-db"
readonly PG_MAJOR="18"
readonly PG_USER="Doug"
readonly PG_DB="dpsjur"
readonly PG_PORT="5432"
readonly PG_BIN_PREFIX=""   # pg_dump/psql no PATH do contêiner (imagem postgres:18)
readonly DUMP_LABEL="dpsjur"
readonly DUMP_PREFIX="dpsjur-"             # prefixo exclusivo DESTE banco
readonly RETENTION_DIR_NAME="diario"       # retenção apenas no diário do B
readonly HOST_BASE="/root/sbjur-backups-dupla/banco-b"

readonly KEEP_DAILY=7
readonly KEEP_WEEKLY=4
readonly KEEP_MONTHLY=12
readonly MIN_DUMP_BYTES=1024          # dump < 1 KB é tratado como inválido

readonly USAGE="Uso: 23-backup-banco-b-dpsjur.sh [--diario|--semanal|--mensal] [--aplicar-retencao]

Banco B (PostgreSQL 18) — serviço Swarm dpsjur_dpsjur-db, usuário Doug, banco dpsjur.
O contêiner exato é resolvido a cada execução via serviço Swarm (sem nome literal).

Opções:
  --diario | --semanal | --mensal   tipo do backup (padrão: --diario)
  --aplicar-retencao                HABILITA exclusão de backups antigos (padrão: MODO OBSERVAÇÃO)
  --pgpass-file CAMINHO             PGPASSFILE no host (padrão: \$HOME/.pgpass-bk-banco-b; chmod 600 obrigatório)
  --help                            esta ajuda"

MODE="diario"
APPLY_RETENTION=0
HOST_PGPASS="${HOME}/.pgpass-bk-banco-b"
CONTAINER_PGPASS="/tmp/.pgpass-bk-banco-b"

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
# Sessão: log exclusivo do Banco B
# ------------------------------------------------------------------------------
RUN_STAMP="$(date +%Y%m%d-%H%M%S)"
BASE_LOG_DIR="${HOST_BASE}/logs"
mkdir -p "${BASE_LOG_DIR}" || { printf 'Falha ao criar %s\n' "${BASE_LOG_DIR}" >&2; exit "${BK_EXIT_FS_FAIL}"; }
chmod 700 "${BASE_LOG_DIR}" 2>/dev/null || true
LOG_FILE="${BASE_LOG_DIR}/banco-b-${MODE}-${RUN_STAMP}.log"
: > "${LOG_FILE}" || { printf 'Falha ao criar log: %s\n' "${LOG_FILE}" >&2; exit "${BK_EXIT_FS_FAIL}"; }
chmod 600 "${LOG_FILE}"

cleanup() {
    # ${CONTAINER:-}: pode não estar definido se a falha ocorreu antes da
    # resolução do contêiner (bk_remove_pgpass ignora contêiner vazio).
    bk_remove_pgpass "${CONTAINER:-}" "${CONTAINER_PGPASS}" || true
    bk_tmp_cleanup || true
    bk_release_lock || true
    bk_finalize_session "Banco B"
    printf '%s FIM DA SESSÃO Banco B (exit %s)\n' "$(date '+%F %T')" "$1" >> "${LOG_FILE}" 2>/dev/null || true
}
trap 'cleanup $?' EXIT
trap 'bk_tmp_cleanup; bk_remove_pgpass "${CONTAINER:-}" "${CONTAINER_PGPASS}" || true; exit 130' INT TERM HUP

# ------------------------------------------------------------------------------
# 1) Dependências + lock (arquivo de lock PRÓPRIO do Banco B)
# ------------------------------------------------------------------------------
bk_require_deps docker gzip stat awk sort mktemp grep

bk_setup_dirs "${HOST_BASE}"
bk_acquire_lock "${HOST_BASE}/.lock-banco-b"

bk_log "=== BACKUP BANCO B (PostgreSQL ${PG_MAJOR}, serviço Swarm ${SWARM_SERVICE}) — modo ${MODE} ==="
bk_log "Rotina antiga do Banco A (/root/sbjur-backups/backup.sh, 03h) permanece intocada."

# ------------------------------------------------------------------------------
# 2) Resolução DETERMINÍSTICA do contêiner via serviço Swarm (sem nome literal;
#    recusa ausente ou ambíguo) + credenciais DENTRO do contêiner.
# ------------------------------------------------------------------------------
if ! CONTAINER="$(bk_resolve_swarm_container "${SWARM_SERVICE}")"; then
    bk_die "Não foi possível identificar o contêiner do serviço Swarm ${SWARM_SERVICE}." "${BK_EXIT_GUARD}"
fi
readonly CONTAINER

if ! bk_stage_pgpass_into_container "${CONTAINER}" "${HOST_PGPASS}" "${CONTAINER_PGPASS}" "${PG_USER}"; then
    bk_die "Staging do .pgpass no contêiner NÃO confirmado — abortando." "${BK_EXIT_GUARD}"
fi

# ------------------------------------------------------------------------------
# 3) Identificação EXPLÍCITA (versão 18, banco dpsjur, usuário Doug —
#    conexão explícita -U/-d/-p em todas as consultas)
# ------------------------------------------------------------------------------
bk_verify_container "${CONTAINER}" "${PG_MAJOR}" "${PG_DB}" "${PG_USER}" "${PG_PORT}" "${PG_BIN_PREFIX}"

# ------------------------------------------------------------------------------
# 4) Comando pg_dump (DENTRO do contêiner, PGPASSFILE interno, sem senha em
#    argumento; conexão explícita)
# ------------------------------------------------------------------------------
BK_DUMP_CMD=(docker exec "${CONTAINER}" env PGPASSFILE="${CONTAINER_PGPASS}" \
    ${PG_BIN_PREFIX}pg_dump -X -p "${PG_PORT}" -U "${PG_USER}" -d "${PG_DB}")

# ------------------------------------------------------------------------------
# 5) Destino final por modo
# ------------------------------------------------------------------------------
DEST_DIR="${HOST_BASE}/${MODE}"
OUT_FILE="${DEST_DIR}/${DUMP_PREFIX}${MODE}-${RUN_STAMP}.sql.gz"
bk_log "Destino final: ${OUT_FILE}"
if [ -e "${OUT_FILE}" ]; then
    bk_die "Destino JÁ EXISTE (${OUT_FILE}) — abortando ANTES do dump: backup preexistente nunca sobrescrito." "${BK_EXIT_FS_FAIL}"
fi

# ------------------------------------------------------------------------------
# 6) Dump + compactação em TEMPORÁRIO exclusivo (captura SEM inversão de rc)
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
bk_log "BACKUP BANCO B CONCLUÍDO: ${OUT_FILE}"

# ------------------------------------------------------------------------------
# 9) Retenção — MODO OBSERVAÇÃO por padrão. Apenas no DIÁRIO do Banco B
#    (semanal/mensal nunca são tocados aqui); prefixo exclusivo dpsjur-;
#    validação individual antes de qualquer exclusão; rotina antiga NUNCA tocada.
# ------------------------------------------------------------------------------
bk_apply_retention "${HOST_BASE}/${RETENTION_DIR_NAME}" "${DUMP_PREFIX}" "${KEEP_DAILY}" "${APPLY_RETENTION}" "${MIN_DUMP_BYTES}"

bk_log "Sessão Banco B encerrada com sucesso."
exit "${BK_EXIT_OK}"
