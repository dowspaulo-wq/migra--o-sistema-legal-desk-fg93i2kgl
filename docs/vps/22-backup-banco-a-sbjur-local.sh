#!/usr/bin/env bash
# ==============================================================================
# DPSjur / SBJur — Backup INDEPENDENTE do BANCO A (PostgreSQL 15.8)
# Script: docs/vps/22-backup-banco-a-sbjur-local.sh
# Versão: v1.0.0
# Destino de execução: VPS Hostinger de produção (2.25.181.69 / srv1737667).
#
# BANCO A — IDENTIDADE FIXA E VALIDADA (sem regex genérica):
#   Projeto .......: sbjur-local (EasyPanel)
#   Contêiner .....: sbjur-local_supabase-db-1 (comparação por IGUALDADE EXATA)
#   PostgreSQL ....: 15.8 (major 15 — a versão é PROVADA antes do dump)
#   Usuário .......: postgres
#   Banco .........: postgres
#
# SOBREPOSIÇÃO COM A ROTINA ATUAL (Requisito 8 — migração segura):
#   A rotina atual (/root/sbjur-backups/backup.sh, diário 03h) PERMANECE em
#   produção e NÃO é tocada por este script. Durante o período de sobreposição,
#   a retenção aqui roda em MODO OBSERVAÇÃO (nada é apagado); exclusões só
#   acontecem após Douglas autorizar com --aplicar-retencao.
#
# REQUISITOS ATENDIDOS (numeração do pedido de Douglas):
#   1. Rotina independente para o PG 15.8 (o Banco B tem script próprio, 23).
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
#   O dump gerado é um .sql.gz plain-format (pg_dump sem -Fc), que o auditor
#   restaura com `gunzip -c | psql` em laboratório isolado. Este script gera
#   EXATAMENTE esse formato, no diretório /root/sbjur-backups/diario (mesma
#   base que a rotina atual usa), com nome prefixado por banco:
#       bk-a-sbjur15-A-diario-<timestamp>.sql.gz
#
# USO:
#   bash 22-backup-banco-a-sbjur-local.sh                     # backup diário
#   bash 22-backup-banco-a-sbjur-local.sh --semanal           # backup semanal
#   bash 22-backup-banco-a-sbjur-local.sh --mensal            # backup mensal
#   bash 22-backup-banco-a-sbjur-local.sh --aplicar-retencao  # habilita exclusões
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
# CONFIGURAÇÃO DO BANCO A (FIXA — não depende de ambiente, não é genérica)
# ------------------------------------------------------------------------------
BANK_ID="A"
PG_CONTAINER="sbjur-local_supabase-db-1"   # contêiner EXATO
PG_MAJOR_WANTED="15"                        # PostgreSQL 15.8 → major 15
PG_USER="postgres"                          # usuário FIXO
PG_DB="postgres"                            # banco FIXO
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
PGPASS_FILE="/root/.pgpass-sbjur-a"
TS_STAMP="$(date +%Y%m%d-%H%M%S)"
BASE_DIR="/root/sbjur-backups"
LOG_FILE="${BASE_DIR}/logs/bk-a-sbjur15-$(date +%Y%m%d).log"
LOCK_PATH="${BASE_DIR}/.lock-bk-a"

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

Backup independente do BANCO A (PostgreSQL 15.8, contêiner sbjur-local_supabase-db-1,
usuário postgres, banco postgres).

Opções:
  --diario                 Backup no diretório diário (padrão)
  --semanal                Backup no diretório semanal
  --mensal                 Backup no diretório mensal
  --aplicar-retencao       Aplica retenção (remove backups antigos JÁ VALIDADOS).
                           SEM esta flag: modo observação, nada é apagado.
  -h, --help               Exibe esta ajuda.

Arquivo de senha esperado: ${PGPASS_FILE} (formato .pgpass, chmod 600)
  Formato da linha:  <host>:<porta>:<db>:<user>:<senha>
  Exemplo:           localhost:5432:postgres:postgres:SUA_SENHA
EOF
}

# ------------------------------------------------------------------------------
# TRAP de saída — veredito SUCESSO/FALHA no log (Requisito 7)
# ------------------------------------------------------------------------------
trap 'bk_finalize_session "Banco A (PG15, ${PG_CONTAINER})"' EXIT
trap 'exit $((128 + $1))' INT TERM 2>/dev/null || true

# ------------------------------------------------------------------------------
# PRE-VOO — dependências, diretórios, lock, .pgpass
# ------------------------------------------------------------------------------
bk_log "=== Início backup Banco A (PG15) ${SCRIPT_VERSION} — freq ${FREQ} ==="
bk_require_deps docker gzip stat flock

if [ "$(id -u)" != "0" ]; then
    bk_die "Este script deve rodar como root (padrão da VPS: docker exec requer root)." "${BK_EXIT_USAGE}"
fi

bk_setup_dirs "${BASE_DIR}"

if [ ! -e "${LOG_FILE}" ]; then
    touch "${LOG_FILE}" || bk_die "Falha ao criar log: ${LOG_FILE}" "${BK_EXIT_FS_FAIL}"
    chmod 600 "${LOG_FILE}" || bk_die "Falha no chmod 600 do log." "${BK_EXIT_FS_FAIL}"
fi
bk_verify_fs_file "${LOG_FILE}" "log do Banco A"
bk_log "Arquivo de log da sessão: ${LOG_FILE}"
bk_log "Arquivo .pgpass do banco A: ${PGPASS_FILE} (chmod 600 validado abaixo)"

# Lock anti-simultâneo — Requisito 9 (por banco; Banco B tem lock próprio)
bk_acquire_lock "${LOCK_PATH}"
BK_LOCK_KIND="flock"
BK_LOCK_PATH="${LOCK_PATH}"

# PGPASSFILE — senha NUNCA na linha de comando (Requisito 3)
if [ ! -f "${PGPASS_FILE}" ]; then
    bk_die "Arquivo .pgpass não encontrado: ${PGPASS_FILE}. Crie-o com chmod 600 antes de rodar o backup (veja --help)." "${BK_EXIT_CONFIG_FAIL}"
fi
bk_verify_fs_file "${PGPASS_FILE}" "PGPASSFILE do Banco A"
export PGPASSFILE="${PGPASS_FILE}"

# ------------------------------------------------------------------------------
# IDENTIFICAÇÃO E PROVA DO CONTÊINER (Requisito 2) — sem regex genérica
# ------------------------------------------------------------------------------
bk_verify_container "${PG_CONTAINER}" "${PG_MAJOR_WANTED}" "${PG_DB}" "${PG_USER}" "${PG_BIN_PREFIX}"

# ------------------------------------------------------------------------------
# DUMP — nome com timestamp + noclobber (Requisito 9)
# ------------------------------------------------------------------------------
OUT_DIR="${BASE_DIR}/${FREQ}"
OUT_FILE="${OUT_DIR}/bk-a-sbjur15-A-${FREQ}-${TS_STAMP}.sql.gz"
bk_log "Destino do dump: ${OUT_FILE}"

# No Banco A (Supabase self-hosted) o usuário postgres usa TRUST no socket
# local Unix dentro do contêiner (padrão do kit Supabase/EasyPanel): a conexão
# do pg_dump vai por SOCKET, sem senha em argumento e sem senha em log. O
# .pgpass do host (/root/.pgpass-sbjur-a) é validado e usado pelo psql do
# pre-voo; no dump, o trust local dispensa senha, MAS a flag -w (nunca pedir
# senha) deixa explícito que nenhuma senha é solicitada ou exibida.
export BK_DUMP_CMD=(docker exec -u postgres "${PG_CONTAINER}" pg_dump -w -h /var/run/postgresql -p 5432 -U "${PG_USER}" -d "${PG_DB}" "${PG_DUMP_FORMAT_ARGS[@]}")

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
bk_apply_retention "${BASE_DIR}/diario"  "bk-a-sbjur15-A" "${RETENTION_DAILY}"  "${APPLY_RETENTION}"
ret_rc=$?
[ "${ret_rc}" -eq 0 ] || bk_die "Falha na retenção diária." "${BK_EXIT_RETENTION_FAIL}"
bk_apply_retention "${BASE_DIR}/semanal" "bk-a-sbjur15-A" "${RETENTION_WEEKLY}" "${APPLY_RETENTION}"
ret_rc=$?
[ "${ret_rc}" -eq 0 ] || bk_die "Falha na retenção semanal." "${BK_EXIT_RETENTION_FAIL}"
bk_apply_retention "${BASE_DIR}/mensal"  "bk-a-sbjur15-A" "${RETENTION_MONTHLY}" "${APPLY_RETENTION}"
ret_rc=$?
[ "${ret_rc}" -eq 0 ] || bk_die "Falha na retenção mensal." "${BK_EXIT_RETENTION_FAIL}"

# ------------------------------------------------------------------------------
# FIM
# ------------------------------------------------------------------------------
bk_log "Backup Banco A concluído: ${OUT_FILE}"
exit "${BK_EXIT_OK}"
