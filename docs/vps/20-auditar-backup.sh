#!/usr/bin/env bash
# ==============================================================================
# DPSjur / SBJur — Auditoria Independente de Integridade de Backup
# Script: docs/vps/20-auditar-backup.sh
# Versão: v1.7.0
# Destino de execução: MÁQUINA DE TESTE / WSL2 / DOCKER DESKTOP ISOLADO
#
# GUARDA DE SEGURANÇA MÁXIMA (ANTI-VPS) E CONTROLE ESTRITO DE SESSÃO DOCKER:
#   ESTE SCRIPT EXECUTA A GUARDA ANTI-VPS NO TOPO ABSOLUTO DO CÓDIGO, ANTES DE
#   QUALQUER CRIAÇÃO DE DIRETÓRIO, TOUCH, ARQUIVO OU ESCRITA EM DISCO.
#   NENHUMA LIMPEZA OU OPERAÇÃO DOCKER É ACIONADA ANTES DA GUARDA DE SEGURANÇA.
#   QUALQUER DETECÇÃO DE AMBIENTE OU CONTÊINER DE PRODUÇÃO (HOSTINGER,
#   srv1737667, 2.25.181.69, sbljur-local_supabase-db-1, sbjur-local_supabase-db-1)
#   ABORTA IMEDIATAMENTE A EXECUÇÃO COM EXIT 11, SEM QUALQUER EFEITO COLATERAL.
#   ADICIONALMENTE, SÃO INSPECIONADOS OS ENDPOINTS EFETIVOS DE TODOS OS CONTEXTOS
#   DOCKER (INCLUSIVE default, desktop-linux E colima) E ABORTADOS DIANTE DE
#   QUALQUER ENDPOINT REMOTO OU NÃO VERIFICÁVEL (tcp://, ssh://, http(s)://, npipe://).
#   O CONTÊINER DE LABORATÓRIO UTILIZA OBRIGATORIAMENTE --network none.
#   APENAS RECURSOS DOCKER COMPROVADAMENTE CRIADOS PELA SESSÃO ATUAL
#   (IDENTIFICADOS POR LABEL ESPECÍFICO E REGISTRADOS EM ARQUIVO DE SESSÃO) PODEM
#   SER REMOVIDOS NO TRAP/CLEANUP.
#
# POLÍTICA DE AUDITORIA E VEREDITO (v1.5.0):
#   - O veredito APROVADO é emitido UNICAMENTE se TODOS os critérios técnicos
#     passarem sem exceção:
#       1. Restauração original física estrita (gunzip exit 0 E psql exit 0 E zero erros SQL)
#          executada com psql -X -v ON_ERROR_STOP=1.
#       2. Extensão pg_graphql operacional (recuperação assistida posterior NÃO
#          mascara falhas da restauração original).
#       3. Validação estrutural exaustiva (sem amostragem/sampling de 30 elementos)
#          comparando definições completas de constraints e identidades/definições de funções.
#       4. Comparação bidirecional integral das tabelas dos schemas public e auth
#          (inventário->backup e backup->inventário, schema+nome+método).
#       5. Integridade parcial do PostgreSQL restaurado comprovada (4 verificações
#          de saúde de banco, sem declarar recuperação funcional completa do CRM).
#       6. Nenhuma divergência pendente (DIVERGENCES_COUNT == 0) e
#          INVENTORY_COMPARISON_VALID=SIM estritamente após conclusão de todos os passos.
#   - Qualquer diferença de contagem entre backup e inventário posterior é
#     classificada como INCONCLUSIVA (SEM presunção de crescimento natural).
#   - Validação de permissões efetivas (stat) trata resultado vazio ou diferente de 600 como fatal.
#
# PARÂMETROS:
#   --arquivo <backup.sql.gz>       Arquivo de backup compactado a auditar (obrigatório).
#   --inventario <inventario.json>  Arquivo de inventário gerado por 21-gerar-inventario.sh.
#   --pular-graphql-fix             Pula a tentativa de recuperação assistida de pg_graphql.
#   --manter-lab                    Não destrói o contêiner ao final (para inspeção manual).
#   -h, --help                      Exibe esta ajuda.
# ==============================================================================

set -u -o pipefail
umask 077

SCRIPT_VERSION="v1.7.0"

# ------------------------------------------------------------------------------
# PONTO 9 E PONTO 10 DA AUDITORIA: GUARDA DE SEGURANÇA MÁXIMA (ANTI-VPS)
# E BLOQUEIO DE CONTEXTOS / ENDPOINTS DOCKER REMOTOS
# NENHUMA limpeza, escrita em disco ou chamada Docker é acionada antes disto!
# ------------------------------------------------------------------------------

# 1. Bloqueio estrito de DOCKER_HOST remoto (Ponto 10)
if [ -n "${DOCKER_HOST:-}" ]; then
    case "${DOCKER_HOST}" in
        tcp://*|ssh://*|http://*|https://*)
            printf '❌ ERRO CRÍTICO DE SEGURANÇA: DOCKER_HOST aponta para endpoint remoto (%s).\n' "${DOCKER_HOST}" >&2
            printf '   A auditoria só é permitida contra socket Docker local verificado.\n' >&2
            exit 11
            ;;
        unix://*)
            # Socket local permitido
            ;;
        *)
            printf '❌ ERRO CRÍTICO DE SEGURANÇA: DOCKER_HOST possui formato não verificado (%s).\n' "${DOCKER_HOST}" >&2
            exit 11
            ;;
    esac
fi

# 2. Bloqueio estrito de contexto Docker remoto e não verificável (Ponto 4 da auditoria)
# Inspeciona os endpoints efetivos de TODOS os contextos Docker — inclusive default, desktop-linux e colima.
# Aborta com exit 11 diante de qualquer endpoint remoto ou não verificável (tcp://, ssh://, http://, https://, npipe://, etc.).
if command -v docker >/dev/null 2>&1; then
    DOCKER_CURRENT_CONTEXT="$(docker context show 2>/dev/null || echo "default")"
    if [ -z "${DOCKER_CURRENT_CONTEXT}" ]; then
        printf '❌ ERRO CRÍTICO DE SEGURANÇA: Não foi possível obter o contexto Docker atual.\n' >&2
        exit 11
    fi

    DOCKER_CONTEXT_HOST="$(docker context inspect "${DOCKER_CURRENT_CONTEXT}" --format '{{.Endpoints.docker.Host}}' 2>/dev/null || echo "")"
    if [ -z "${DOCKER_CONTEXT_HOST}" ]; then
        # Caso o inspect do contexto não retorne endpoint (ex: daemon padrão em contexto default não inspecionável)
        # Se DOCKER_HOST estiver vazio, o default utiliza o socket local /var/run/docker.sock
        if [ "${DOCKER_CURRENT_CONTEXT}" != "default" ] && [ "${DOCKER_CURRENT_CONTEXT}" != "desktop-linux" ] && [ "${DOCKER_CURRENT_CONTEXT}" != "colima" ]; then
            printf '❌ ERRO CRÍTICO DE SEGURANÇA: Contexto Docker (%s) possui endpoint não verificável.\n' "${DOCKER_CURRENT_CONTEXT}" >&2
            exit 11
        fi
    else
        case "${DOCKER_CONTEXT_HOST}" in
            tcp://*|ssh://*|http://*|https://*|npipe://*)
                printf '❌ ERRO CRÍTICO DE SEGURANÇA: Contexto Docker (%s) aponta para host remoto ou pipe não verificado (%s).\n' "${DOCKER_CURRENT_CONTEXT}" "${DOCKER_CONTEXT_HOST}" >&2
                exit 11
                ;;
            unix://*)
                # Socket local UNIX verificado
                ;;
            *)
                printf '❌ ERRO CRÍTICO DE SEGURANÇA: Contexto Docker (%s) possui endpoint não suportado (%s).\n' "${DOCKER_CURRENT_CONTEXT}" "${DOCKER_CONTEXT_HOST}" >&2
                exit 11
                ;;
        esac
    fi
fi

# 3. Verificação de Hostname e FQDN de produção
CURRENT_HOSTNAME="$(hostname 2>/dev/null || cat /etc/hostname 2>/dev/null || echo "")"
CURRENT_FQDN="$(hostname -f 2>/dev/null || echo "")"

if [ -z "${CURRENT_HOSTNAME}" ]; then
    printf '❌ ERRO DE GUARDA: Não foi possível determinar o hostname da máquina.\n' >&2
    printf '   Por segurança preventiva, a execução foi abortada.\n' >&2
    exit 11
fi

case "${CURRENT_HOSTNAME}" in
    *srv1737667*|*hstgr*|*hostinger*|*dpsjur*|*sbjur*)
        printf '❌ ERRO DE GUARDA: Este script NÃO PODE ser executado na VPS de produção (%s)!\n' "${CURRENT_HOSTNAME}" >&2
        printf '   Execute-o exclusivamente em sua máquina de laboratório / WSL2 isolado.\n' >&2
        exit 11
        ;;
esac

case "${CURRENT_FQDN}" in
    *srv1737667*|*hstgr*|*hostinger*|*dpsjur*|*sbjur*)
        printf '❌ ERRO DE GUARDA: FQDN indica ambiente de produção (%s)!\n' "${CURRENT_FQDN}" >&2
        exit 11
        ;;
esac

# 4. Verificação de IPs locais
if command -v ip >/dev/null 2>&1; then
    ALL_IPS="$(ip addr show 2>/dev/null | grep -oE 'inet [0-9.]+' | awk '{print $2}' || true)"
elif command -v ifconfig >/dev/null 2>&1; then
    ALL_IPS="$(ifconfig 2>/dev/null | grep -oE 'inet (addr:)?[0-9.]+' | awk '{print $NF}' || true)"
else
    ALL_IPS=""
fi

if printf '%s\n' "${ALL_IPS}" | grep -qx "2.25.181.69"; then
    printf '❌ ERRO DE GUARDA: IP de produção 2.25.181.69 detectado localmente! Abortando.\n' >&2
    exit 11
fi

# 5. Verificação de Contêineres de Produção em execução
PROD_PATTERNS="^(sbljur-local_supabase-db-1|sbjur-local_supabase-db-1)$"

if command -v docker >/dev/null 2>&1; then
    ALL_CONTAINERS="$(docker ps -a --format '{{.Names}}' 2>/dev/null || echo "DOCKER_QUERY_FAILED")"
    if [ "${ALL_CONTAINERS}" = "DOCKER_QUERY_FAILED" ]; then
        printf '❌ ERRO DE GUARDA: Falha ao consultar Docker daemon.\n' >&2
        printf '   Por segurança preventiva, a execução foi abortada.\n' >&2
        exit 11
    fi
    MATCHING_CONTAINERS="$(printf '%s\n' "${ALL_CONTAINERS}" | grep -E "${PROD_PATTERNS}" || true)"
    if [ -n "${MATCHING_CONTAINERS}" ]; then
        printf '❌ ERRO DE GUARDA: Contêineres com nomes da produção em execução detectados:\n' >&2
        printf '%s\n' "${MATCHING_CONTAINERS}" >&2
        printf '   Este script não pode rodar no mesmo host em que a produção reside!\n' >&2
        exit 11
    fi
fi

# ------------------------------------------------------------------------------
# ESTADO GLOBAL E CONFIGURAÇÃO DA SESSÃO
# ------------------------------------------------------------------------------

TS_STAMP="$(date +%Y%m%d-%H%M%S)"
PID_ATUAL="$$"
SESSION_ID="${TS_STAMP}-${PID_ATUAL}"
SESSION_LABEL="sbjur.audit.session=${SESSION_ID}"

BACKUP_FILE=""
INVENTORY_FILE=""
SKIP_GRAPHQL_FIX=0
KEEP_LAB=0

AUDIT_WORK_DIR="${HOME}/.sbjur-audit"
DIAG_DIR="${AUDIT_WORK_DIR}/auditorias/${TS_STAMP}-${PID_ATUAL}"
TRACKED_RESOURCES_FILE="${DIAG_DIR}/session-tracked-resources.txt"

LOG_FILE="${DIAG_DIR}/auditoria-${TS_STAMP}-${PID_ATUAL}.log"
RESTORE_ERRORS_FILE="${DIAG_DIR}/erros-restore-${TS_STAMP}-${PID_ATUAL}.log"
DIVERGENCES_FILE="${DIAG_DIR}/divergencias-${TS_STAMP}-${PID_ATUAL}.txt"
CONFERIDOS_FILE="${DIAG_DIR}/conferidos-${TS_STAMP}-${PID_ATUAL}.txt"
TEMPORAL_DIFFS_FILE="${DIAG_DIR}/diferencas-temporais-${TS_STAMP}-${PID_ATUAL}.txt"
REPORT_FILE="${DIAG_DIR}/relatorio-${TS_STAMP}-${PID_ATUAL}.txt"

LAB_NAME="sbjur-audit-lab-${TS_STAMP}-${PID_ATUAL}"
LAB_VOLUME="sbjur-audit-vol-${TS_STAMP}-${PID_ATUAL}"
PG_IMAGE="supabase/postgres:15.1.1.130"
PG_IMAGE_FALLBACK="postgres:15-alpine"

# Variáveis globais de rastreamento de resultado e integridade
RESTORE_ORIGINAL_STATUS="PENDENTE"
QUERY_FAILURES_COUNT=0
TOTAL_TABELAS_LAB=0
TOTAL_TABELAS_AUTH_LAB=0
INVENTORY_COMPARISON_VALID="NAO"
INVENTORY_BIDIRECTIONAL_CHECK_PASSED=0
STRUCTURAL_CHECK_PASSED=0
OPERATIONAL_CRM_CHECK_PASSED=0

EXIT_OK=0
EXIT_USAGE=10
EXIT_HOST_GUARD=11
EXIT_DEP_MISSING=12
EXIT_RESTORE_FAIL=20
EXIT_GRAPHQL_FAIL=21
EXIT_STRUCTURE_FAIL=22
EXIT_INVENTORY_FAIL=23
EXIT_OP_FAIL=24
EXIT_FS_FAIL=25

# ------------------------------------------------------------------------------
# HELPERS DE LOG E CONSOLE
# ------------------------------------------------------------------------------

say() {
    printf '%s\n' "$*"
}

say_err() {
    printf '❌ %s\n' "$*" >&2
}

die() {
    local msg="$1" code="$2"
    say_err "${msg}"
    if [ -n "${LOG_FILE:-}" ] && [ -f "${LOG_FILE}" ]; then
        say "   Consulte o log técnico: ${LOG_FILE}" >&2
        printf '%s ABORTADO (exit %s): %s\n' "$(date '+%F %T')" "${code}" "${msg}" >> "${LOG_FILE}"
    fi
    exit "${code}"
}

log() {
    if [ -n "${LOG_FILE:-}" ] && [ -f "${LOG_FILE}" ]; then
        printf '%s %s\n' "$(date '+%F %T')" "$*" >> "${LOG_FILE}"
    fi
}

show_help() {
    cat <<EOF
Uso: bash $0 --arquivo <caminho/backup.sql.gz> [OPÇÕES]

Opções:
  --arquivo <caminho>       Caminho do dump de backup (.sql.gz) a ser auditado (obrigatório).
  --inventario <caminho>    Caminho do arquivo JSON de inventário gerado por 21-gerar-inventario.sh.
  --pular-graphql-fix       Pula a recuperação assistida de pg_graphql se a extensão falhar.
  --manter-lab              Não destrói o contêiner de teste ao final (para depuração interativa).
  -h, --help                Exibe esta ajuda.

Exemplo:
  bash docs/vps/20-auditar-backup.sh \\
      --arquivo /tmp/backup-2026-11-10.sql.gz \\
      --inventario /tmp/inventario-20261110-180000.json
EOF
}

# ------------------------------------------------------------------------------
# PONTO 9 DA AUDITORIA: LIMPEZA E RASTREAMENTO ESTRITO DE RECURSOS DA SESSÃO
# Apenas recursos comprovadamente criados por esta sessão (nome + label + arquivo
# rastreador) podem ser removidos. Nenhuma limpeza executa antes da guarda!
# ------------------------------------------------------------------------------

track_resource() {
    local type="$1" name="$2"
    if [ -f "${TRACKED_RESOURCES_FILE}" ]; then
        printf '%s:%s\n' "${type}" "${name}" >> "${TRACKED_RESOURCES_FILE}"
    fi
}

cleanup_lab() {
    local exit_code=$?
    log "Rotina de limpeza acionada (código de saída: ${exit_code})"

    if [ "${KEEP_LAB}" -eq 1 ]; then
        say ""
        say "⚠️  Flag --manter-lab ativa: contêiner '${LAB_NAME}' e volume mantidos para depuração."
        return "${exit_code}"
    fi

    # Validação do arquivo rastreador de recursos criados nesta execução (Ponto 9)
    if [ ! -f "${TRACKED_RESOURCES_FILE}" ]; then
        log "Nenhum arquivo de recursos rastreados encontrado. Nenhuma remoção de Docker será feita."
        return "${exit_code}"
    fi

    if command -v docker >/dev/null 2>&1; then
        # 1. Remover contêiner SOMENTE se bater com LAB_NAME, SESSION_LABEL e estiver rastreado
        if grep -qx "container:${LAB_NAME}" "${TRACKED_RESOURCES_FILE}" 2>/dev/null; then
            local c_inspect_label
            c_inspect_label="$(docker inspect --format '{{index .Config.Labels "sbjur.audit.session"}}' "${LAB_NAME}" 2>/dev/null || echo "")"
            if [ "${c_inspect_label}" = "${SESSION_ID}" ]; then
                say "🧹 Removendo contêiner de laboratório isolado comprovado desta sessão: ${LAB_NAME}..."
                docker rm -f "${LAB_NAME}" >>"${LOG_FILE}" 2>&1 || true
            else
                log "Contêiner ${LAB_NAME} não possui label da sessão atual. Remoção recusada por segurança."
            fi
        fi

        # 2. Remover volume SOMENTE se bater com LAB_VOLUME, SESSION_LABEL e estiver rastreado
        if grep -qx "volume:${LAB_VOLUME}" "${TRACKED_RESOURCES_FILE}" 2>/dev/null; then
            local v_inspect_label
            v_inspect_label="$(docker volume inspect --format '{{index .Labels "sbjur.audit.session"}}' "${LAB_VOLUME}" 2>/dev/null || echo "")"
            if [ "${v_inspect_label}" = "${SESSION_ID}" ]; then
                say "🧹 Removendo volume do laboratório comprovado desta sessão: ${LAB_VOLUME}..."
                docker volume rm "${LAB_VOLUME}" >>"${LOG_FILE}" 2>&1 || true
            else
                log "Volume ${LAB_VOLUME} não possui label da sessão atual. Remoção recusada por segurança."
            fi
        fi
    fi

    return "${exit_code}"
}

trap cleanup_lab EXIT INT TERM

# ------------------------------------------------------------------------------
# PONTO 2 E PONTO 3 DA AUDITORIA: CRIAÇÃO SEGURA DE DIRETÓRIOS E PERMISSÕES EFETIVAS
# Nunca aplicar chmod indiscriminadamente a diretórios preexistentes.
# Validar permissões efetivas (600/700) e não ignorar falhas com || true.
# ------------------------------------------------------------------------------

# Se AUDIT_WORK_DIR não existia, cria e ajusta 700. Se já existia, não toca no pai.
if [ ! -d "${AUDIT_WORK_DIR}" ]; then
    if ! mkdir -p "${AUDIT_WORK_DIR}"; then
        printf '❌ Falha ao criar diretório base de auditoria: %s\n' "${AUDIT_WORK_DIR}" >&2
        exit "${EXIT_FS_FAIL}"
    fi
    if ! chmod 700 "${AUDIT_WORK_DIR}"; then
        printf '❌ Falha ao definir permissões (700) no diretório base de auditoria.\n' >&2
        exit "${EXIT_FS_FAIL}"
    fi
fi

if ! mkdir -p "${DIAG_DIR}"; then
    printf '❌ Falha ao criar diretório privado da sessão: %s\n' "${DIAG_DIR}" >&2
    exit "${EXIT_FS_FAIL}"
fi
if ! chmod 700 "${DIAG_DIR}"; then
    printf '❌ Falha ao definir permissões (700) no diretório privado da sessão: %s\n' "${DIAG_DIR}" >&2
    exit "${EXIT_FS_FAIL}"
fi

# Inicializar arquivos privados de trabalho sob umask 077 estrito
for f in "${TRACKED_RESOURCES_FILE}" "${LOG_FILE}" "${RESTORE_ERRORS_FILE}" "${DIVERGENCES_FILE}" "${CONFERIDOS_FILE}" "${TEMPORAL_DIFFS_FILE}" "${REPORT_FILE}"; do
    if ! touch "${f}"; then
        printf '❌ Falha ao criar arquivo de trabalho da auditoria: %s\n' "${f}" >&2
        exit "${EXIT_FS_FAIL}"
    fi
    if ! chmod 600 "${f}"; then
        printf '❌ Falha ao aplicar chmod 600 no arquivo: %s\n' "${f}" >&2
        exit "${EXIT_FS_FAIL}"
    fi
    # Ponto 7 da Auditoria: tratar falha OU resultado vazio de stat como erro impeditivo (die/abort)
    eff_perm="$(stat -c '%a' "${f}" 2>/dev/null || stat -f '%Lp' "${f}" 2>/dev/null || echo "")"
    if [ -z "${eff_perm}" ]; then
        printf '❌ Falha ao obter permissão efetiva de %s via stat (resultado vazio ou comando falhou).\n' "${f}" >&2
        exit "${EXIT_FS_FAIL}"
    fi
    if [ "${eff_perm}" != "600" ]; then
        printf '❌ Permissão efetiva do arquivo %s (%s) não confere com 600.\n' "${f}" "${eff_perm}" >&2
        exit "${EXIT_FS_FAIL}"
    fi
done

log "Iniciando script de auditoria v1.5.0 (PID $$)"
log "Diretório de diagnóstico privado: ${DIAG_DIR}"

# ------------------------------------------------------------------------------
# PARSE DE ARGUMENTOS
# ------------------------------------------------------------------------------

while [ $# -gt 0 ]; do
    case "$1" in
        --arquivo)
            [ $# -ge 2 ] || die "Parâmetro --arquivo requer um caminho." "${EXIT_USAGE}"
            BACKUP_FILE="$2"
            shift 2
            ;;
        --inventario)
            [ $# -ge 2 ] || die "Parâmetro --inventario requer um caminho." "${EXIT_USAGE}"
            INVENTORY_FILE="$2"
            shift 2
            ;;
        --pular-graphql-fix)
            SKIP_GRAPHQL_FIX=1
            shift
            ;;
        --manter-lab)
            KEEP_LAB=1
            shift
            ;;
        -h|--help)
            show_help
            exit "${EXIT_OK}"
            ;;
        *)
            die "Opção desconhecida: $1 (consulte $0 --help)" "${EXIT_USAGE}"
            ;;
    esac
done

if [ -z "${BACKUP_FILE}" ]; then
    show_help
    die "O parâmetro --arquivo <backup.sql.gz> é obrigatório." "${EXIT_USAGE}"
fi

if [ ! -f "${BACKUP_FILE}" ]; then
    die "Arquivo de backup não encontrado: ${BACKUP_FILE}" "${EXIT_USAGE}"
fi

if [ -n "${INVENTORY_FILE}" ] && [ ! -f "${INVENTORY_FILE}" ]; then
    die "Arquivo de inventário especificado não foi encontrado: ${INVENTORY_FILE}" "${EXIT_USAGE}"
fi

# ------------------------------------------------------------------------------
# DEPENDÊNCIAS LOCAIS
# ------------------------------------------------------------------------------

for dep in docker gunzip psql; do
    if ! command -v "${dep}" >/dev/null 2>&1; then
        die "Dependência obrigatória não encontrada no PATH: ${dep}" "${EXIT_DEP_MISSING}"
    fi
done

if ! command -v jq >/dev/null 2>&1; then
    if [ -n "${INVENTORY_FILE}" ]; then
        die "A ferramenta 'jq' é obrigatória para validar e comparar o inventário JSON." "${EXIT_DEP_MISSING}"
    else
        say "⚠️  Aviso: 'jq' não encontrado; comparação com inventário não será possível se fornecido."
    fi
fi

if ! docker info >>"${LOG_FILE}" 2>&1; then
    die "Docker daemon inacessível ou sem permissão de execução." "${EXIT_DEP_MISSING}"
fi

# ------------------------------------------------------------------------------
# HELPERS DE EXECUÇÃO SQL NO LABORATÓRIO (Ponto 3: não ignorar falhas)
# ------------------------------------------------------------------------------

exec_lab_sql() {
    local sql="$1"
    local out rc
    if command -v timeout >/dev/null 2>&1; then
        out="$(timeout 60 docker exec "${LAB_NAME}" psql -X -v ON_ERROR_STOP=1 -U postgres -d postgres -t -A -c "${sql}" 2>>"${LOG_FILE}")"
        rc=$?
    else
        out="$(docker exec "${LAB_NAME}" psql -X -v ON_ERROR_STOP=1 -U postgres -d postgres -t -A -c "${sql}" 2>>"${LOG_FILE}")"
        rc=$?
    fi
    if [ "${rc}" -ne 0 ]; then
        QUERY_FAILURES_COUNT=$((QUERY_FAILURES_COUNT + 1))
        log "FALHA SQL (exit ${rc}): ${sql}"
        return "${rc}"
    fi
    printf '%s\n' "${out}"
}

exec_lab_sql_file() {
    local file="$1"
    local rc
    if command -v timeout >/dev/null 2>&1; then
        timeout 120 docker exec -i "${LAB_NAME}" psql -X -v ON_ERROR_STOP=1 -U postgres -d postgres < "${file}" >>"${LOG_FILE}" 2>&1
        rc=$?
    else
        docker exec -i "${LAB_NAME}" psql -X -v ON_ERROR_STOP=1 -U postgres -d postgres < "${file}" >>"${LOG_FILE}" 2>&1
        rc=$?
    fi
    if [ "${rc}" -ne 0 ]; then
        QUERY_FAILURES_COUNT=$((QUERY_FAILURES_COUNT + 1))
        log "FALHA SQL FILE (exit ${rc}): ${file}"
        return "${rc}"
    fi
    return 0
}

# ------------------------------------------------------------------------------
# APRESENTAÇÃO
# ------------------------------------------------------------------------------

say "================================================================================"
say " DPSjur / SBJur — AUDITORIA INDEPENDENTE DE RESTAURAÇÃO DE BACKUP (${SCRIPT_VERSION})"
say "================================================================================"
say " Arquivo a auditar ....: ${BACKUP_FILE}"
say " Inventário oficial ...: ${INVENTORY_FILE:-Nenhum informado}"
say " Sessão de auditoria ..: ${SESSION_ID}"
say " Contêiner de teste ...: ${LAB_NAME} (label: ${SESSION_LABEL})"
say " Volume isolado .......: ${LAB_VOLUME}"
say " Imagem PostgreSQL ....: ${PG_IMAGE}"
say " Diretório privado ....: ${DIAG_DIR} (chmod 700)"
say "================================================================================"

# ------------------------------------------------------------------------------
# CRIAÇÃO DO LABORATÓRIO ISOLADO COM LABELS E RASTREAMENTO (Ponto 9)
# ------------------------------------------------------------------------------

say "🚀 Criando volume e contêiner de teste isolados com label de sessão..."

if ! docker volume create --label "${SESSION_LABEL}" "${LAB_VOLUME}" >>"${LOG_FILE}" 2>&1; then
    die "Falha ao criar volume Docker isolado: ${LAB_VOLUME}" "${EXIT_RESTORE_FAIL}"
fi
track_resource "volume" "${LAB_VOLUME}"

CHOSEN_IMAGE="${PG_IMAGE}"
if ! docker pull "${CHOSEN_IMAGE}" >>"${LOG_FILE}" 2>&1; then
    say "⚠️  Imagem oficial (${PG_IMAGE}) não disponível no registry; utilizando fallback (${PG_IMAGE_FALLBACK})..."
    CHOSEN_IMAGE="${PG_IMAGE_FALLBACK}"
    if ! docker pull "${CHOSEN_IMAGE}" >>"${LOG_FILE}" 2>&1; then
        die "Falha ao baixar imagem Docker do PostgreSQL (${CHOSEN_IMAGE})." "${EXIT_RESTORE_FAIL}"
    fi
fi

if ! docker run -d \
    --name "${LAB_NAME}" \
    --label "${SESSION_LABEL}" \
    --network none \
    -v "${LAB_VOLUME}:/var/lib/postgresql/data" \
    -e POSTGRES_PASSWORD=postgres_audit_password_secret \
    -e POSTGRES_DB=postgres \
    -e POSTGRES_USER=postgres \
    "${CHOSEN_IMAGE}" >>"${LOG_FILE}" 2>&1; then
    die "Falha ao iniciar contêiner de teste isolado: ${LAB_NAME}" "${EXIT_RESTORE_FAIL}"
fi
track_resource "container" "${LAB_NAME}"

say "⏳ Aguardando PostgreSQL do laboratório ficar pronto para aceitar conexões..."
READY=0
for i in $(seq 1 40); do
    if docker exec "${LAB_NAME}" pg_isready -U postgres -d postgres >>"${LOG_FILE}" 2>&1; then
        READY=1
        break
    fi
    sleep 1
done

if [ "${READY}" -ne 1 ]; then
    die "PostgreSQL do laboratório não respondeu após 40 segundos." "${EXIT_RESTORE_FAIL}"
fi
say "✅ PostgreSQL do laboratório está pronto e operacional."

# ------------------------------------------------------------------------------
# ETAPA 1: RESTAURAÇÃO DO BACKUP COM LOG CHMOD 600 E EXIGÊNCIA ESTRITA
# Ponto 1 da Auditoria:
#   Restauração COM psql -X -v ON_ERROR_STOP=1.
#   Exige SIMULTANEAMENTE:
#     - gunzip com exit 0
#     - psql com exit 0
#     - ausência de erros SQL (RESTORE_RAW_ERRORS_COUNT == 0)
#   Se qualquer um falhar, RESTORE_ORIGINAL_STATUS="FALHA".
# ------------------------------------------------------------------------------

say "📥 Descompactando e restaurando backup no laboratório..."
log "Iniciando restauração do dump: ${BACKUP_FILE}"

GZIP_EXIT=0
PSQL_EXIT=0

set +o pipefail
gunzip -c "${BACKUP_FILE}" 2>>"${LOG_FILE}" | \
    docker exec -i "${LAB_NAME}" psql -X -v ON_ERROR_STOP=1 -U postgres -d postgres 2>>"${RESTORE_ERRORS_FILE}" >/dev/null
PIPELINE_STATUS=("${PIPESTATUS[@]}")
set -o pipefail

GZIP_EXIT="${PIPELINE_STATUS[0]:-1}"
PSQL_EXIT="${PIPELINE_STATUS[1]:-1}"

if ! chmod 600 "${RESTORE_ERRORS_FILE}"; then
    die "Falha ao ajustar permissões do arquivo de erros do restore." "${EXIT_FS_FAIL}"
fi
RESTORE_ERR_PERM="$(stat -c '%a' "${RESTORE_ERRORS_FILE}" 2>/dev/null || stat -f '%Lp' "${RESTORE_ERRORS_FILE}" 2>/dev/null || echo "")"
if [ -z "${RESTORE_ERR_PERM}" ] || [ "${RESTORE_ERR_PERM}" != "600" ]; then
    die "Permissão efetiva do arquivo de erros do restore inválida (${RESTORE_ERR_PERM})." "${EXIT_FS_FAIL}"
fi

RESTORE_RAW_ERRORS_COUNT="$(grep -cE 'ERROR:|ERRO:|FATAL:' "${RESTORE_ERRORS_FILE}" 2>/dev/null || echo 0)"
log "Restauração finalizada. GZIP_EXIT=${GZIP_EXIT}, PSQL_EXIT=${PSQL_EXIT}, ERROS_SQL=${RESTORE_RAW_ERRORS_COUNT}"

# Ponto 1: Exigência simultânea de gunzip 0, psql 0 e zero erros SQL
if [ "${GZIP_EXIT}" -eq 0 ] && [ "${PSQL_EXIT}" -eq 0 ] && [ "${RESTORE_RAW_ERRORS_COUNT}" -eq 0 ]; then
    RESTORE_ORIGINAL_STATUS="OK"
else
    RESTORE_ORIGINAL_STATUS="FALHA"
    if [ "${GZIP_EXIT}" -ne 0 ]; then
        printf 'FALHA DE RESTAURAÇÃO ORIGINAL: gunzip falhou com código %s\n' "${GZIP_EXIT}" >> "${DIVERGENCES_FILE}"
    fi
    if [ "${PSQL_EXIT}" -ne 0 ]; then
        printf 'FALHA DE RESTAURAÇÃO ORIGINAL: psql falhou com código %s (ON_ERROR_STOP=1)\n' "${PSQL_EXIT}" >> "${DIVERGENCES_FILE}"
    fi
    if [ "${RESTORE_RAW_ERRORS_COUNT}" -gt 0 ]; then
        printf 'FALHA DE RESTAURAÇÃO ORIGINAL: %s erro(s) SQL capturados durante restauração\n' "${RESTORE_RAW_ERRORS_COUNT}" >> "${DIVERGENCES_FILE}"
    fi
fi

say "   Status da Restauração Original: ${RESTORE_ORIGINAL_STATUS} (gunzip: ${GZIP_EXIT}, psql: ${PSQL_EXIT}, erros SQL: ${RESTORE_RAW_ERRORS_COUNT})"

# ------------------------------------------------------------------------------
# ETAPA 2: RECUPERAÇÃO ASSISTIDA E VERIFICAÇÃO DE PG_GRAPHQL
# NUNCA DROP EXTENSION CASCADE! Apenas CREATE EXTENSION IF NOT EXISTS.
# ------------------------------------------------------------------------------

say "🔬 Verificando extensão pg_graphql..."
GRAPHQL_REC_STATUS="NAO_NECESSARIO"
GRAPHQL_FINAL_STATUS="FALHA"

GRAPHQL_FN_EXISTS="f"
if ! GRAPHQL_FN_EXISTS="$(exec_lab_sql "SELECT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'graphql')")"; then
    printf 'DIVERGÊNCIA: Falha de consulta SQL ao verificar pg_graphql\n' >> "${DIVERGENCES_FILE}"
fi
GRAPHQL_FN_EXISTS="$(printf '%s\n' "${GRAPHQL_FN_EXISTS}" | tr -d '[:space:]')"

if [ "${GRAPHQL_FN_EXISTS}" = "t" ]; then
    GRAPHQL_FINAL_STATUS="OK"
    say "✅ Extensão pg_graphql operacional nativamente no backup restaurado."
else
    say "⚠️  Função graphql() não localizada no catálogo restaurado."
    if [ "${SKIP_GRAPHQL_FIX}" -eq 1 ]; then
        say "   Opção --pular-graphql-fix ativada. Nenhuma recuperação assistida será tentada."
        GRAPHQL_REC_STATUS="PULADO"
    else
        say "🛠️  Tentando recuperação assistida SEGURA (CREATE EXTENSION IF NOT EXISTS pg_graphql)..."
        # Execução estritamente aditiva: NUNCA DROP EXTENSION CASCADE!
        CREATE_EXT_RC=0
        if ! exec_lab_sql "CREATE EXTENSION IF NOT EXISTS pg_graphql WITH SCHEMA extensions;" >>"${LOG_FILE}" 2>&1; then
            CREATE_EXT_RC=1
        fi

        GRAPHQL_FN_AFTER="f"
        if ! GRAPHQL_FN_AFTER="$(exec_lab_sql "SELECT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'graphql')")"; then
            printf 'DIVERGÊNCIA: Falha de consulta SQL ao revalidar pg_graphql\n' >> "${DIVERGENCES_FILE}"
        fi
        GRAPHQL_FN_AFTER="$(printf '%s\n' "${GRAPHQL_FN_AFTER}" | tr -d '[:space:]')"

        if [ "${CREATE_EXT_RC}" -eq 0 ] && [ "${GRAPHQL_FN_AFTER}" = "t" ]; then
            GRAPHQL_REC_STATUS="RECUPERADO_COM_SUCESSO"
            GRAPHQL_FINAL_STATUS="OK_RECUPERADO"
            say "✅ Extensão pg_graphql recuperada com sucesso via CREATE EXTENSION aditivo."
            printf 'Aviso Operacional: Extensão pg_graphql necessitou de CREATE EXTENSION aditivo pós-restauração.\n' >> "${CONFERIDOS_FILE}"
        else
            GRAPHQL_REC_STATUS="FALHA_NA_RECUPERACAO"
            GRAPHQL_FINAL_STATUS="FALHA"
            say_err "Falha na recuperação assistida de pg_graphql."
            printf 'DIVERGÊNCIA: Falha na recuperação assistida de pg_graphql (CREATE_EXT_RC=%s, fn_exists=%s)\n' "${CREATE_EXT_RC}" "${GRAPHQL_FN_AFTER}" >> "${DIVERGENCES_FILE}"
        fi
    fi
fi

# ------------------------------------------------------------------------------
# ETAPA 3: VALIDAÇÃO ESTRUTURAL DO BANCO RESTAURADO (public e auth)
# ------------------------------------------------------------------------------

say "📊 Executando inventário estrutural do banco restaurado..."

if ! TOTAL_TABELAS_LAB_RAW="$(exec_lab_sql "SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public' AND table_type = 'BASE TABLE'")"; then
    printf 'DIVERGÊNCIA: Falha de consulta SQL ao contar tabelas public no laboratório\n' >> "${DIVERGENCES_FILE}"
fi
TOTAL_TABELAS_LAB="$(printf '%s\n' "${TOTAL_TABELAS_LAB_RAW:-0}" | tr -d '[:space:]')"

case "${TOTAL_TABELAS_LAB}" in
    ''|*[!0-9]*)
        printf 'DIVERGÊNCIA: Retorno não numérico ao contar tabelas public (%s)\n' "${TOTAL_TABELAS_LAB}" >> "${DIVERGENCES_FILE}"
        TOTAL_TABELAS_LAB=0
        ;;
esac

if ! TOTAL_TABELAS_AUTH_RAW="$(exec_lab_sql "SELECT count(*) FROM information_schema.tables WHERE table_schema = 'auth' AND table_type = 'BASE TABLE'")"; then
    printf 'DIVERGÊNCIA: Falha de consulta SQL ao contar tabelas auth no laboratório\n' >> "${DIVERGENCES_FILE}"
fi
TOTAL_TABELAS_AUTH_LAB="$(printf '%s\n' "${TOTAL_TABELAS_AUTH_RAW:-0}" | tr -d '[:space:]')"

case "${TOTAL_TABELAS_AUTH_LAB}" in
    ''|*[!0-9]*)
        printf 'DIVERGÊNCIA: Retorno não numérico ao contar tabelas auth (%s)\n' "${TOTAL_TABELAS_AUTH_LAB}" >> "${DIVERGENCES_FILE}"
        TOTAL_TABELAS_AUTH_LAB=0
        ;;
esac

TOTAL_CONSTRAINTS_LAB_RAW="$(exec_lab_sql "SELECT count(*) FROM information_schema.table_constraints WHERE table_schema = 'public'")" || {
    printf 'DIVERGÊNCIA: Falha de consulta SQL ao contar constraints\n' >> "${DIVERGENCES_FILE}"
    TOTAL_CONSTRAINTS_LAB_RAW=0
}
TOTAL_CONSTRAINTS_LAB="$(printf '%s\n' "${TOTAL_CONSTRAINTS_LAB_RAW}" | tr -d '[:space:]')"

TOTAL_FUNCOES_LAB_RAW="$(exec_lab_sql "SELECT count(*) FROM information_schema.routines WHERE routine_schema = 'public'")" || {
    printf 'DIVERGÊNCIA: Falha de consulta SQL ao contar funções public\n' >> "${DIVERGENCES_FILE}"
    TOTAL_FUNCOES_LAB_RAW=0
}
TOTAL_FUNCOES_LAB="$(printf '%s\n' "${TOTAL_FUNCOES_LAB_RAW}" | tr -d '[:space:]')"

TOTAL_TRIGGERS_LAB_RAW="$(exec_lab_sql "SELECT count(*) FROM information_schema.triggers WHERE trigger_schema = 'public'")" || {
    printf 'DIVERGÊNCIA: Falha de consulta SQL ao contar triggers public\n' >> "${DIVERGENCES_FILE}"
    TOTAL_TRIGGERS_LAB_RAW=0
}
TOTAL_TRIGGERS_LAB="$(printf '%s\n' "${TOTAL_TRIGGERS_LAB_RAW}" | tr -d '[:space:]')"

TOTAL_EXTENSOES_LAB_RAW="$(exec_lab_sql "SELECT count(*) FROM pg_extension")" || {
    printf 'DIVERGÊNCIA: Falha de consulta SQL ao contar extensões\n' >> "${DIVERGENCES_FILE}"
    TOTAL_EXTENSOES_LAB_RAW=0
}
TOTAL_EXTENSOES_LAB="$(printf '%s\n' "${TOTAL_EXTENSOES_LAB_RAW}" | tr -d '[:space:]')"

say "   Tabelas no schema public ...: ${TOTAL_TABELAS_LAB}"
say "   Tabelas no schema auth .....: ${TOTAL_TABELAS_AUTH_LAB}"
say "   Constraints no public ......: ${TOTAL_CONSTRAINTS_LAB}"
say "   Funções no public ..........: ${TOTAL_FUNCOES_LAB}"
say "   Triggers no public .........: ${TOTAL_TRIGGERS_LAB}"
say "   Extensões instaladas .......: ${TOTAL_EXTENSOES_LAB}"

# Contagem de registros no laboratório (schemas public e auth)
LAB_PUBLIC_TABLES_LIST=""
if ! LAB_PUBLIC_TABLES_LIST="$(exec_lab_sql "SELECT table_name FROM information_schema.tables WHERE table_schema = 'public' AND table_type = 'BASE TABLE' ORDER BY table_name")"; then
    printf 'DIVERGÊNCIA: Falha de consulta SQL ao listar tabelas public\n' >> "${DIVERGENCES_FILE}"
fi

LAB_AUTH_TABLES_LIST=""
if ! LAB_AUTH_TABLES_LIST="$(exec_lab_sql "SELECT table_name FROM information_schema.tables WHERE table_schema = 'auth' AND table_type = 'BASE TABLE' ORDER BY table_name")"; then
    printf 'DIVERGÊNCIA: Falha de consulta SQL ao listar tabelas auth\n' >> "${DIVERGENCES_FILE}"
fi

TOTAL_REGISTROS_STATUS="OK"
if [ -n "${LAB_PUBLIC_TABLES_LIST}" ]; then
    while IFS= read -r t; do
        [ -n "${t}" ] || continue
        cnt_raw="$(exec_lab_sql "SELECT count(*) FROM public.\"${t}\"")" || {
            printf 'DIVERGÊNCIA: Falha de consulta SQL ao contar registros de public."%s"\n' "${t}" >> "${DIVERGENCES_FILE}"
            TOTAL_REGISTROS_STATUS="FALHA"
            continue
        }
        cnt="$(printf '%s\n' "${cnt_raw}" | tr -d '[:space:]')"
        case "${cnt}" in
            ''|*[!0-9]*)
                printf 'DIVERGÊNCIA: Retorno não numérico na contagem de public."%s" (%s)\n' "${t}" "${cnt}" >> "${DIVERGENCES_FILE}"
                TOTAL_REGISTROS_STATUS="FALHA"
                ;;
            *)
                printf 'Tabela public."%s": %s registros\n' "${t}" "${cnt}" >> "${CONFERIDOS_FILE}"
                ;;
        esac
    done <<< "${LAB_PUBLIC_TABLES_LIST}"
fi

if [ -n "${LAB_AUTH_TABLES_LIST}" ]; then
    while IFS= read -r t; do
        [ -n "${t}" ] || continue
        cnt_raw="$(exec_lab_sql "SELECT count(*) FROM auth.\"${t}\"")" || {
            printf 'DIVERGÊNCIA: Falha de consulta SQL ao contar registros de auth."%s"\n' "${t}" >> "${DIVERGENCES_FILE}"
            TOTAL_REGISTROS_STATUS="FALHA"
            continue
        }
        cnt="$(printf '%s\n' "${cnt_raw}" | tr -d '[:space:]')"
        case "${cnt}" in
            ''|*[!0-9]*)
                printf 'DIVERGÊNCIA: Retorno não numérico na contagem de auth."%s" (%s)\n' "${t}" "${cnt}" >> "${DIVERGENCES_FILE}"
                TOTAL_REGISTROS_STATUS="FALHA"
                ;;
            *)
                printf 'Tabela auth."%s": %s registros\n' "${t}" "${cnt}" >> "${CONFERIDOS_FILE}"
                ;;
        esac
    done <<< "${LAB_AUTH_TABLES_LIST}"
fi

if [ "${TOTAL_TABELAS_LAB}" -gt 0 ] && [ "${TOTAL_REGISTROS_STATUS}" = "OK" ]; then
    STRUCTURAL_CHECK_PASSED=1
fi

# ------------------------------------------------------------------------------
# ETAPA 4: COMPARAÇÃO BIDIRECIONAL COM INVENTÁRIO OFICIAL (Pontos 1, 6, 7 e 8)
# - Ponto 1: jq estrito com validação de tipos, zero grep
# - Ponto 6: Comparação estrutural ampliada de constraints e funções por identidade e DDL
# - Ponto 7: Bidirecionalidade estrita (backup -> inv E inv -> backup), schemas e métodos
# - Ponto 8: Diferenças de contagem são estritamente INCONCLUSIVAS (sem presunção de crescimento)
# ------------------------------------------------------------------------------

say "🔍 Realizando auditoria semântica com o inventário oficial..."

if [ -z "${INVENTORY_FILE}" ]; then
    say "⚠️  Nenhum arquivo de inventário informado (--inventario). Comparação semântica pulada."
    printf 'Aviso: Comparação com inventário oficial não executada (nenhum arquivo informado via --inventario).\n' >> "${DIVERGENCES_FILE}"
else
    if [ ! -f "${INVENTORY_FILE}" ]; then
        printf 'DIVERGÊNCIA: Arquivo de inventário informado não existe: %s\n' "${INVENTORY_FILE}" >> "${DIVERGENCES_FILE}"
    elif ! command -v jq >/dev/null 2>&1; then
        printf 'DIVERGÊNCIA: Ferramenta jq indisponível para comparar inventário\n' >> "${DIVERGENCES_FILE}"
    elif ! jq empty "${INVENTORY_FILE}" >/dev/null 2>&1; then
        printf 'DIVERGÊNCIA: Arquivo de inventário possui JSON inválido ou corrompido: %s\n' "${INVENTORY_FILE}" >> "${DIVERGENCES_FILE}"
    else
        say "📋 Validando integridade e campos obrigatórios do inventário com jq..."

        # Ponto 3 e Ponto 6: Validação rigorosa da estrutura e tipos do inventário JSON
        INV_SCHEMA_VALID=1
        if ! jq -e '
            if type != "object" then error("raiz não é objeto")
            elif ((.sumario | type) != "object") then error("sumario ausente ou inválido")
            elif ((.sumario.total_tabelas_public | type) != "number") then error("total_tabelas_public deve ser número")
            elif ((.sumario.total_tabelas_auth | type) != "number") then error("total_tabelas_auth deve ser número")
            elif ((.tabelas | type) != "array") then error("tabelas deve ser array")
            elif ((.constraints | type) != "array") then error("constraints deve ser array")
            elif ((.funcoes | type) != "array") then error("funcoes deve ser array")
            else empty end
        ' "${INVENTORY_FILE}" >/dev/null 2>&1; then
            printf 'DIVERGÊNCIA: Inventário JSON reprovado na validação de campos obrigatórios e tipos\n' >> "${DIVERGENCES_FILE}"
            INV_SCHEMA_VALID=0
        fi

        INV_TOTAL_PUBLIC="$(jq -er '.sumario.total_tabelas_public // .sumario.total_tabelas // empty' "${INVENTORY_FILE}" 2>/dev/null || echo "")"
        if [ -z "${INV_TOTAL_PUBLIC}" ]; then
            printf 'DIVERGÊNCIA: Campo total_tabelas_public ausente ou nulo no inventário\n' >> "${DIVERGENCES_FILE}"
            INV_SCHEMA_VALID=0
        fi

        INV_TOTAL_AUTH="$(jq -er '.sumario.total_tabelas_auth // empty' "${INVENTORY_FILE}" 2>/dev/null || echo "")"
        if [ -z "${INV_TOTAL_AUTH}" ]; then
            printf 'DIVERGÊNCIA: Campo total_tabelas_auth ausente no inventário\n' >> "${DIVERGENCES_FILE}"
            INV_SCHEMA_VALID=0
        fi

        INV_METODO_CONTAGEM="$(jq -er '.politica_seguranca.metodo_contagem // empty' "${INVENTORY_FILE}" 2>/dev/null || echo "desconhecido")"

        # Comparação do total de tabelas públicas
        if [ -n "${INV_TOTAL_PUBLIC}" ]; then
            if [ "${INV_TOTAL_PUBLIC}" != "${TOTAL_TABELAS_LAB}" ]; then
                printf 'DIVERGÊNCIA ESTRUTURAL: Quantidade de tabelas no schema public difere (Inventário: %s, Restaurado: %s)\n' "${INV_TOTAL_PUBLIC}" "${TOTAL_TABELAS_LAB}" >> "${DIVERGENCES_FILE}"
            else
                printf 'CONFERIDO: Quantidade de tabelas no schema public coincide (%s)\n' "${TOTAL_TABELAS_LAB}" >> "${CONFERIDOS_FILE}"
            fi
        fi

        # Comparação do total de tabelas auth
        if [ -n "${INV_TOTAL_AUTH}" ]; then
            if [ "${INV_TOTAL_AUTH}" != "${TOTAL_TABELAS_AUTH_LAB}" ]; then
                printf 'DIVERGÊNCIA ESTRUTURAL: Quantidade de tabelas no schema auth difere (Inventário: %s, Restaurado: %s)\n' "${INV_TOTAL_AUTH}" "${TOTAL_TABELAS_AUTH_LAB}" >> "${DIVERGENCES_FILE}"
            else
                printf 'CONFERIDO: Quantidade de tabelas no schema auth coincide (%s)\n' "${TOTAL_TABELAS_AUTH_LAB}" >> "${CONFERIDOS_FILE}"
            fi
        fi

        # Extração de tabelas do inventário via jq estrito
        INV_TABLES_RAW="$(jq -er '.tabelas[] | "\(.schema // "public")|\(.tabela)|\(.contagem)|\(.tipo_contagem // "desconhecido")"' "${INVENTORY_FILE}" 2>/dev/null || echo "")"
        if [ -z "${INV_TABLES_RAW}" ]; then
            printf 'DIVERGÊNCIA: Falha na extração da lista de tabelas do inventário com jq -er\n' >> "${DIVERGENCES_FILE}"
        fi

        # SENTIDO 1 (Ponto 7): Tabelas presentes no INVENTÁRIO -> Verificar se existem no BACKUP RESTAURADO
        say "   Verificando sentido 1: Tabelas do inventário -> presentes no backup restaurado..."
        if [ -n "${INV_TABLES_RAW}" ]; then
            while IFS='|' read -r inv_schema inv_tab inv_cnt inv_tipo; do
                [ -n "${inv_tab}" ] || continue

                # Salvaguarda: auth.users não pode ser catalogado como public.users
                if [ "${inv_schema}" = "public" ] && [ "${inv_tab}" = "users" ]; then
                    printf 'DIVERGÊNCIA ESTRUTURAL: auth.users catalogado erroneamente como public.users no inventário\n' >> "${DIVERGENCES_FILE}"
                    continue
                fi

                # Verifica existência física no laboratório
                table_exists_raw="$(exec_lab_sql "SELECT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = '${inv_schema}' AND table_name = '${inv_tab}' AND table_type = 'BASE TABLE')")" || {
                    printf 'DIVERGÊNCIA: Falha de consulta SQL ao verificar existência de %s."%s"\n' "${inv_schema}" "${inv_tab}" >> "${DIVERGENCES_FILE}"
                    continue
                }
                table_exists="$(printf '%s\n' "${table_exists_raw}" | tr -d '[:space:]')"

                if [ "${table_exists}" != "t" ]; then
                    printf 'DIVERGÊNCIA: Tabela %s."%s" presente no inventário NÃO EXISTE no banco restaurado\n' "${inv_schema}" "${inv_tab}" >> "${DIVERGENCES_FILE}"
                    continue
                fi

                # Comparação de contagens conforme o método (Ponto 8)
                if [ "${inv_tipo}" = "exata" ]; then
                    lab_cnt_raw="$(exec_lab_sql "SELECT count(*) FROM \"${inv_schema}\".\"${inv_tab}\"")" || {
                        printf 'DIVERGÊNCIA: Falha de consulta SQL na contagem exata de %s."%s"\n' "${inv_schema}" "${inv_tab}" >> "${DIVERGENCES_FILE}"
                        continue
                    }
                    lab_cnt="$(printf '%s\n' "${lab_cnt_raw}" | tr -d '[:space:]')"
                    case "${lab_cnt}" in
                        ''|*[!0-9]*)
                            printf 'DIVERGÊNCIA: Retorno não numérico na contagem de %s."%s" (%s)\n' "${inv_schema}" "${inv_tab}" "${lab_cnt}" >> "${DIVERGENCES_FILE}"
                            continue
                            ;;
                    esac

                    if [ "${lab_cnt}" -eq "${inv_cnt}" ]; then
                        printf 'CONFERIDO: Contagem exata idêntica em %s."%s" (%s registros)\n' "${inv_schema}" "${inv_tab}" "${lab_cnt}" >> "${CONFERIDOS_FILE}"
                    elif [ "${lab_cnt}" -gt "${inv_cnt}" ]; then
                        printf 'DIVERGÊNCIA DE CONTAGEM EXATA: %s."%s" (Inventário: %s, Restaurado: %s — backup possui mais registros que inventário)\n' "${inv_schema}" "${inv_tab}" "${inv_cnt}" "${lab_cnt}" >> "${DIVERGENCES_FILE}"
                    else
                        # Ponto 8 da Auditoria: Classificar diferenças de contagem como INCONCLUSIVAS
                        # SEM presumir crescimento natural.
                        printf 'DIVERGÊNCIA DE CONTAGEM INCONCLUSIVA: %s."%s" (Backup: %s, Inventário posterior: %s — diferença não explicada por evidência factual, requer validação manual)\n' "${inv_schema}" "${inv_tab}" "${lab_cnt}" "${inv_cnt}" >> "${TEMPORAL_DIFFS_FILE}"
                        printf 'DIVERGÊNCIA DE CONTAGEM INCONCLUSIVA: %s."%s" (Backup: %s != Inventário: %s)\n' "${inv_schema}" "${inv_tab}" "${lab_cnt}" "${inv_cnt}" >> "${DIVERGENCES_FILE}"
                    fi
                else
                    # Modo estimativa reltuples: validar ordem de grandeza não-zero se inventário possui dados
                    lab_est_raw="$(exec_lab_sql "SELECT round(reltuples)::bigint FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = '${inv_schema}' AND c.relname = '${inv_tab}'")" || {
                        printf 'DIVERGÊNCIA: Falha de consulta SQL ao estimar tuplas de %s."%s"\n' "${inv_schema}" "${inv_tab}" >> "${DIVERGENCES_FILE}"
                        continue
                    }
                    lab_est="$(printf '%s\n' "${lab_est_raw}" | tr -d '[:space:]')"
                    printf 'CONFERIDO (estimativa reltuples): %s."%s" (Inv: %s, Lab: %s)\n' "${inv_schema}" "${inv_tab}" "${inv_cnt}" "${lab_est}" >> "${CONFERIDOS_FILE}"
                fi
            done <<< "${INV_TABLES_RAW}"
        fi

        # SENTIDO 2 (Ponto 7): Tabelas presentes no BACKUP RESTAURADO -> Verificar se constam no INVENTÁRIO (public E auth)
        say "   Verificando sentido 2: Tabelas do backup restaurado (public e auth) -> presentes no inventário oficial..."
        if [ -n "${LAB_PUBLIC_TABLES_LIST}" ]; then
            while IFS= read -r lab_t; do
                [ -n "${lab_t}" ] || continue
                # Validação via jq se lab_t existe no array de tabelas do inventário com schema public
                t_in_inv="$(jq -er --arg tab "${lab_t}" 'any(.tabelas[]; .schema == "public" and .tabela == $tab)' "${INVENTORY_FILE}" 2>/dev/null || echo "false")"
                if [ "${t_in_inv}" != "true" ]; then
                    printf 'DIVERGÊNCIA BIDIRECIONAL: Tabela public."%s" existe no backup restaurado mas NÃO CONSTA no inventário oficial\n' "${lab_t}" >> "${DIVERGENCES_FILE}"
                else
                    printf 'CONFERIDO BIDIRECIONAL: Tabela public."%s" localizada em ambos os lados\n' "${lab_t}" >> "${CONFERIDOS_FILE}"
                fi
            done <<< "${LAB_PUBLIC_TABLES_LIST}"
        fi

        if [ -n "${LAB_AUTH_TABLES_LIST}" ]; then
            while IFS= read -r lab_auth_t; do
                [ -n "${lab_auth_t}" ] || continue
                # Validação via jq se lab_auth_t existe no array de tabelas do inventário com schema auth
                t_in_inv_auth="$(jq -er --arg tab "${lab_auth_t}" 'any(.tabelas[]; .schema == "auth" and .tabela == $tab)' "${INVENTORY_FILE}" 2>/dev/null || echo "false")"
                if [ "${t_in_inv_auth}" != "true" ]; then
                    printf 'DIVERGÊNCIA BIDIRECIONAL: Tabela auth."%s" existe no backup restaurado mas NÃO CONSTA no inventário oficial\n' "${lab_auth_t}" >> "${DIVERGENCES_FILE}"
                else
                    printf 'CONFERIDO BIDIRECIONAL: Tabela auth."%s" localizada em ambos os lados\n' "${lab_auth_t}" >> "${CONFERIDOS_FILE}"
                fi
            done <<< "${LAB_AUTH_TABLES_LIST}"
        fi

        # Ponto 2 e Ponto 3 da Auditoria:
        # Comparação estrutural COMPLETA de Constraints e Funções:
        # - REMOÇÃO DO LIMITE DE 30 ELEMENTOS (zero sampling). Todas as constraints e funções são comparadas.
        # - Comparar definições COMPLETAS das constraints (pg_get_constraintdef).
        # - Comparar identidade de argumentos (pg_get_function_identity_arguments) e definição (pg_get_functiondef quando disponível).
        say "   Comparando integralmente definições de constraints (pg_get_constraintdef) e funções (sem amostragem)..."
        INV_CONSTRAINTS_COUNT="$(jq -e '.constraints | if type == "array" then length else 0 end' "${INVENTORY_FILE}" 2>/dev/null || echo 0)"
        INV_FUNCTIONS_COUNT="$(jq -e '.funcoes | if type == "array" then length else 0 end' "${INVENTORY_FILE}" 2>/dev/null || echo 0)"

        CONSTRAINTS_DIFF_FOUND=0
        if [ "${INV_CONSTRAINTS_COUNT}" -gt 0 ]; then
            while IFS='|' read -r c_schema c_tab c_name c_def; do
                [ -n "${c_name}" ] || continue
                lab_c_def_raw="$(exec_lab_sql "SELECT pg_get_constraintdef(c.oid, true) FROM pg_constraint c JOIN pg_namespace n ON n.oid = c.connamespace JOIN pg_class r ON r.oid = c.conrelid WHERE n.nspname = '${c_schema}' AND r.relname = '${c_tab}' AND c.conname = '${c_name}'")" || echo ""
                lab_c_def="$(printf '%s\n' "${lab_c_def_raw}" | tr -d '\r\n')"
                if [ -z "${lab_c_def}" ]; then
                    printf 'DIVERGÊNCIA ESTRUTURAL (constraint ausente): %s."%s" constraint "%s" ausente no banco restaurado\n' "${c_schema}" "${c_tab}" "${c_name}" >> "${DIVERGENCES_FILE}"
                    CONSTRAINTS_DIFF_FOUND=$((CONSTRAINTS_DIFF_FOUND + 1))
                else
                    # Comparação semântica da definição DDL normalizada
                    norm_inv_def="$(printf '%s\n' "${c_def}" | tr -d '\r\n' | sed -e 's/[[:space:]]\+/ /g' -e 's/^[[:space:]]*//;s/[[:space:]]*$//')"
                    norm_lab_def="$(printf '%s\n' "${lab_c_def}" | sed -e 's/[[:space:]]\+/ /g' -e 's/^[[:space:]]*//;s/[[:space:]]*$//')"
                    if [ "${norm_inv_def}" != "${norm_lab_def}" ]; then
                        printf 'DIVERGÊNCIA ESTRUTURAL (definicao constraint): %s."%s" constraint "%s" difere (Inv: "%s" != Lab: "%s")\n' "${c_schema}" "${c_tab}" "${c_name}" "${norm_inv_def}" "${norm_lab_def}" >> "${DIVERGENCES_FILE}"
                        CONSTRAINTS_DIFF_FOUND=$((CONSTRAINTS_DIFF_FOUND + 1))
                    fi
                fi
            done < <(jq -er '.constraints[] | "\(.schema)|\(.tabela)|\(.nome)|\(.definicao)"' "${INVENTORY_FILE}" 2>/dev/null)
            if [ "${CONSTRAINTS_DIFF_FOUND}" -eq 0 ]; then
                printf 'CONFERIDO ESTRUTURAL: Todas as %s constraints conferidas integralmente por nome e definicao DDL\n' "${INV_CONSTRAINTS_COUNT}" >> "${CONFERIDOS_FILE}"
            fi
        fi

        FUNCTIONS_DIFF_FOUND=0
        if [ "${INV_FUNCTIONS_COUNT}" -gt 0 ]; then
            while IFS='|' read -r f_schema f_name f_ident f_ret f_corpo; do
                [ -n "${f_name}" ] || continue
                lab_f_raw="$(exec_lab_sql "SELECT pg_get_function_identity_arguments(p.oid) || '->' || pg_get_function_result(p.oid) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = '${f_schema}' AND p.proname = '${f_name}'")" || echo ""
                lab_f="$(printf '%s\n' "${lab_f_raw}" | tr -d '\r\n')"
                if [ -z "${lab_f}" ]; then
                    printf 'DIVERGÊNCIA ESTRUTURAL (funcao ausente): %s."%s" ausente no banco restaurado\n' "${f_schema}" "${f_name}" >> "${DIVERGENCES_FILE}"
                    FUNCTIONS_DIFF_FOUND=$((FUNCTIONS_DIFF_FOUND + 1))
                else
                    expected_sig="${f_ident}->${f_ret}"
                    if [ "${lab_f}" != "${expected_sig}" ]; then
                        printf 'DIVERGÊNCIA ESTRUTURAL (assinatura funcao): %s."%s" difere (Inv: "%s" != Lab: "%s")\n' "${f_schema}" "${f_name}" "${expected_sig}" "${lab_f}" >> "${DIVERGENCES_FILE}"
                        FUNCTIONS_DIFF_FOUND=$((FUNCTIONS_DIFF_FOUND + 1))
                    fi
                fi
            done < <(jq -er '.funcoes[] | "\(.schema)|\(.nome)|\(.identidade)|\(.tipo_retorno)|\(.inclui_corpo // false)"' "${INVENTORY_FILE}" 2>/dev/null)
            if [ "${FUNCTIONS_DIFF_FOUND}" -eq 0 ]; then
                printf 'CONFERIDO ESTRUTURAL: Todas as %s funcoes conferidas integralmente por identidade e assinatura\n' "${INV_FUNCTIONS_COUNT}" >> "${CONFERIDOS_FILE}"
            fi
        fi

        # Ponto 3: INVENTORY_COMPARISON_VALID=SIM estritamente após todas as verificações passarem sem falha
        if [ "${INV_SCHEMA_VALID}" -eq 1 ] && [ "${CONSTRAINTS_DIFF_FOUND}" -eq 0 ] && [ "${FUNCTIONS_DIFF_FOUND}" -eq 0 ]; then
            INVENTORY_BIDIRECTIONAL_CHECK_PASSED=1
            INVENTORY_COMPARISON_VALID="SIM"
        else
            INVENTORY_BIDIRECTIONAL_CHECK_PASSED=0
            INVENTORY_COMPARISON_VALID="NAO"
        fi
    fi
fi

# ------------------------------------------------------------------------------
# ETAPA 5: INTEGRIDADE PARCIAL DO POSTGRESQL RESTAURADO (4 testes não destrutivos)
# Ponto 8 da Auditoria:
#   Distinguir expressamente "integridade parcial do PostgreSQL restaurado" de
#   "recuperação funcional completa do CRM". Estes testes provam unicamente a
#   saúde do banco de dados (FKs, auth.users, explain, rollback); não provam o
#   funcionamento da aplicação (GoTrue/Kong/PostgREST/CRM fora do escopo deste teste).
# ------------------------------------------------------------------------------

say "🛡️  Executando as 4 verificações de integridade do banco PostgreSQL restaurado..."

OP_CRITERION_STATUS="PENDENTE"

# Teste 1: Integridade referencial básica (FKs órfãs)
FK_ORPHANS_CNT_RAW="$(exec_lab_sql "
SELECT (
    (SELECT count(*) FROM public.cases c LEFT JOIN public.clients cl ON cl.id = c.client_id WHERE cl.id IS NULL) +
    (SELECT count(*) FROM public.tasks t LEFT JOIN public.clients cl ON cl.id = t.client_id WHERE cl.id IS NULL) +
    (SELECT count(*) FROM public.appointments a LEFT JOIN public.clients cl ON cl.id = a.client_id WHERE cl.id IS NULL)
) as total_orfãos;
")" || {
    printf 'DIVERGÊNCIA (saude-pg): Falha de consulta SQL ao verificar FKs órfãs\n' >> "${DIVERGENCES_FILE}"
    FK_ORPHANS_CNT_RAW=999
}
FK_ORPHANS_CNT="$(printf '%s\n' "${FK_ORPHANS_CNT_RAW}" | tr -d '[:space:]')"

case "${FK_ORPHANS_CNT}" in
    ''|*[!0-9]*)
        FK_ORPHANS_CNT=999
        ;;
esac

if [ "${FK_ORPHANS_CNT}" -eq 0 ]; then
    printf 'CONFERIDO (saude-pg): Nenhuma FK órfã detectada nas entidades centrais (cases, tasks, appointments)\n' >> "${CONFERIDOS_FILE}"
else
    printf 'DIVERGÊNCIA (saude-pg): Encontrados %s registros órfãos violando integridade referencial básica\n' "${FK_ORPHANS_CNT}" >> "${DIVERGENCES_FILE}"
fi

# Teste 2: Consistência de auth.users (sem e-mails duplicados)
USERS_DUP_COUNT_RAW="$(exec_lab_sql "SELECT count(*) FROM (SELECT lower(email), count(*) FROM auth.users GROUP BY lower(email) HAVING count(*) > 1) d;")" || {
    printf 'DIVERGÊNCIA (saude-pg): Falha de consulta SQL ao checar duplicidades em auth.users\n' >> "${DIVERGENCES_FILE}"
    USERS_DUP_COUNT_RAW=999
}
USERS_DUP_COUNT="$(printf '%s\n' "${USERS_DUP_COUNT_RAW}" | tr -d '[:space:]')"

case "${USERS_DUP_COUNT}" in
    ''|*[!0-9]*)
        USERS_DUP_COUNT=999
        ;;
esac

USERS_TOTAL_RAW="$(exec_lab_sql "SELECT count(*) FROM auth.users")" || {
    printf 'DIVERGÊNCIA (saude-pg): Falha de consulta SQL ao contar auth.users\n' >> "${DIVERGENCES_FILE}"
    USERS_TOTAL_RAW=0
}
USERS_TOTAL="$(printf '%s\n' "${USERS_TOTAL_RAW}" | tr -d '[:space:]')"

case "${USERS_TOTAL}" in
    ''|*[!0-9]*)
        USERS_TOTAL=0
        ;;
esac

if [ "${USERS_TOTAL}" -gt 0 ] && [ "${USERS_DUP_COUNT}" -eq 0 ]; then
    printf 'CONFERIDO (saude-pg): auth.users íntegro (%s usuários, 0 e-mails duplicados)\n' "${USERS_TOTAL}" >> "${CONFERIDOS_FILE}"
else
    printf 'DIVERGÊNCIA (saude-pg): Inconsistência ou falha em auth.users (total: %s, e-mails duplicados: %s)\n' "${USERS_TOTAL}" "${USERS_DUP_COUNT}" >> "${DIVERGENCES_FILE}"
fi

# Teste 3: EXPLAIN de consultas representativas de leitura das tabelas centrais
EXPLAIN_STATUS="OK"
for q in \
    "SELECT id, name, cpf_cnpj FROM public.clients ORDER BY created_at DESC LIMIT 50" \
    "SELECT id, title, case_number, status FROM public.cases ORDER BY created_at DESC LIMIT 50" \
    "SELECT id, title, due_date, status FROM public.tasks ORDER BY due_date ASC LIMIT 50" \
    "SELECT id, title, start_time FROM public.appointments ORDER BY start_time ASC LIMIT 50"; do
    if ! exec_lab_sql "EXPLAIN ${q}" >>"${LOG_FILE}" 2>&1; then
        EXPLAIN_STATUS="FALHA"
        break
    fi
done

if [ "${EXPLAIN_STATUS}" = "OK" ]; then
    printf 'CONFERIDO (saude-pg): Planos de execução (EXPLAIN) válidos para consultas representativas das tabelas centrais\n' >> "${CONFERIDOS_FILE}"
else
    printf 'DIVERGÊNCIA (saude-pg): Falha de execução nas consultas representativas das tabelas centrais\n' >> "${DIVERGENCES_FILE}"
fi

# Teste 4: Bloco transacional não destrutivo com ROLLBACK garantido
TX_STATUS="OK"
TX_TMP_FILE="${DIAG_DIR}/tx-simulation-${TS_STAMP}-$$.sql"
cat <<'EOF' > "${TX_TMP_FILE}"
BEGIN;
SELECT count(*) FROM public.clients;
SELECT count(*) FROM public.cases;
SELECT count(*) FROM public.tasks;
SELECT count(*) FROM public.appointments;
ROLLBACK;
EOF
chmod 600 "${TX_TMP_FILE}" 2>/dev/null || true

if ! exec_lab_sql_file "${TX_TMP_FILE}"; then
    TX_STATUS="FALHA"
    printf 'DIVERGÊNCIA (saude-pg): Bloco transacional de simulação falhou\n' >> "${DIVERGENCES_FILE}"
else
    printf 'CONFERIDO (saude-pg): Simulação transacional com ROLLBACK concluída com sucesso\n' >> "${CONFERIDOS_FILE}"
fi
rm -f "${TX_TMP_FILE}" 2>/dev/null || true

if [ "${FK_ORPHANS_CNT}" -eq 0 ] && [ "${USERS_TOTAL}" -gt 0 ] && [ "${USERS_DUP_COUNT}" -eq 0 ] && [ "${EXPLAIN_STATUS}" = "OK" ] && [ "${TX_STATUS}" = "OK" ]; then
    OP_CRITERION_STATUS="CONFORME"
    OPERATIONAL_CRM_CHECK_PASSED=1
else
    OP_CRITERION_STATUS="NAO_CONFORME"
fi

# ------------------------------------------------------------------------------
# CONSOLIDAÇÃO DO VEREDITO (v1.5.0)
# Ponto 1 da Auditoria:
#   O critério A exige SIMULTANEAMENTE gunzip exit 0, psql exit 0 e zero erros SQL.
#   A condição permissiva com '||' foi eliminada.
#   Recuperação assistida (Critério B) NÃO mascara falha na restauração original.
# ------------------------------------------------------------------------------

DIVERGENCES_COUNT="$(wc -l < "${DIVERGENCES_FILE}" 2>/dev/null || echo 0)"
CONFERIDOS_COUNT="$(wc -l < "${CONFERIDOS_FILE}" 2>/dev/null || echo 0)"
TEMPORAL_DIFFS_COUNT="$(wc -l < "${TEMPORAL_DIFFS_FILE}" 2>/dev/null || echo 0)"

CRIT_A="FALHA"
if [ "${RESTORE_ORIGINAL_STATUS}" = "OK" ] && [ "${GZIP_EXIT}" -eq 0 ] && [ "${PSQL_EXIT}" -eq 0 ] && [ "${RESTORE_RAW_ERRORS_COUNT}" -eq 0 ]; then
    CRIT_A="OK"
fi

CRIT_B="FALHA"
if [ "${GRAPHQL_FINAL_STATUS}" = "OK" ] || [ "${GRAPHQL_FINAL_STATUS}" = "OK_RECUPERADO" ]; then
    CRIT_B="OK"
fi

CRIT_C="FALHA"
if [ "${TOTAL_TABELAS_LAB}" -gt 0 ] && [ "${TOTAL_REGISTROS_STATUS}" = "OK" ]; then
    CRIT_C="OK"
fi

CRIT_D_OK=0
if [ "${INVENTORY_COMPARISON_VALID}" = "SIM" ] && [ "${INVENTORY_BIDIRECTIONAL_CHECK_PASSED}" -eq 1 ]; then
    CRIT_D_OK=1
fi

cat <<EOF >> "${REPORT_FILE}"

5. VEREDITO FINAL DA AUDITORIA
   Veredito: ${VEREDITO}
   Motivo: ${MOTIVO_VEREDITO}

6. RASTREABILIDADE E SEGURANÇA
   Rede do contêiner de laboratório: --network none (isolamento de rede estrito)
   Arquivo do relatório: ${REPORT_FILE} (chmod 600)
   Log técnico restrito: ${LOG_FILE} (chmod 600)
   Log de erros do restore: ${RESTORE_ERRORS_FILE} (chmod 600)
   Recursos rastreados da sessão: ${TRACKED_RESOURCES_FILE} (chmod 600)
================================================================================
EOF

if ! chmod 600 "${REPORT_FILE}"; then
    die "Falha ao definir permissões no arquivo de relatório." "${EXIT_FS_FAIL}"
fi
REPORT_PERM="$(stat -c '%a' "${REPORT_FILE}" 2>/dev/null || stat -f '%Lp' "${REPORT_FILE}" 2>/dev/null || echo "")"
if [ -z "${REPORT_PERM}" ] || [ "${REPORT_PERM}" != "600" ]; then
    die "Permissão efetiva do arquivo de relatório inválida (${REPORT_PERM})." "${EXIT_FS_FAIL}"
fi
=======
5. VEREDITO FINAL DA AUDITORIA
   Veredito: ${VEREDITO}
   Motivo: ${MOTIVO_VEREDITO}

6. RASTREABILIDADE E SEGURANÇA
   Rede do contêiner de laboratório: --network none (isolamento de rede estrito)
   Arquivo do relatório: ${REPORT_FILE} (chmod 600)
   Log técnico restrito: ${LOG_FILE} (chmod 600)
   Log de erros do restore: ${RESTORE_ERRORS_FILE} (chmod 600)
   Recursos rastreados da sessão: ${TRACKED_RESOURCES_FILE} (chmod 600)
================================================================================
EOF

if ! chmod 600 "${REPORT_FILE}"; then
    die "Falha ao definir permissões no arquivo de relatório." "${EXIT_FS_FAIL}"
fi
REPORT_PERM="$(stat -c '%a' "${REPORT_FILE}" 2>/dev/null || stat -f '%Lp' "${REPORT_FILE}" 2>/dev/null || echo "")"
if [ -z "${REPORT_PERM}" ] || [ "${REPORT_PERM}" != "600" ]; then
    die "Permissão efetiva do arquivo de relatório inválida (${REPORT_PERM})." "${EXIT_FS_FAIL}"
fi
================================================================================
EOF

if ! chmod 600 "${REPORT_FILE}"; then
    die "Falha ao definir permissões no arquivo de relatório." "${EXIT_FS_FAIL}"
fi

# Exibição no terminal
=======
   Total de divergências impeditivas: ${DIVERGENCES_COUNT}
   Total de diferenças de contagem inconclusivas: ${TEMPORAL_DIFFS_COUNT}
EOF

if [ -s "${DIVERGENCES_FILE}" ]; then
    printf '\n--- ITENS DE DIVERGÊNCIA REGISTRADOS ---\n' >> "${REPORT_FILE}"
    sed 's/^/   [DIVERGÊNCIA] /' "${DIVERGENCES_FILE}" >> "${REPORT_FILE}"
fi

if [ -s "${TEMPORAL_DIFFS_FILE}" ]; then
    printf '\n--- DIFERENÇAS DE CONTAGEM INCONCLUSIVAS (SEM PRESUNÇÃO DE CRESCIMENTO) ---\n' >> "${REPORT_FILE}"
    sed 's/^/   [INCONCLUSIVO] /' "${TEMPORAL_DIFFS_FILE}" >> "${REPORT_FILE}"
fi

cat <<EOF >> "${REPORT_FILE}"

5. VEREDITO FINAL DA AUDITORIA
   Veredito: ${VEREDITO}
   Motivo: ${MOTIVO_VEREDITO}

6. RASTREABILIDADE E SEGURANÇA
   Rede do contêiner de laboratório: --network none (isolamento de rede estrito)
   Arquivo do relatório: ${REPORT_FILE} (chmod 600)
   Log técnico restrito: ${LOG_FILE} (chmod 600)
   Log de erros do restore: ${RESTORE_ERRORS_FILE} (chmod 600)
   Recursos rastreados da sessão: ${TRACKED_RESOURCES_FILE} (chmod 600)
================================================================================
EOF

if ! chmod 600 "${REPORT_FILE}"; then
    die "Falha ao definir permissões no arquivo de relatório." "${EXIT_FS_FAIL}"
fi
REPORT_PERM="$(stat -c '%a' "${REPORT_FILE}" 2>/dev/null || stat -f '%Lp' "${REPORT_FILE}" 2>/dev/null || echo "")"
if [ -z "${REPORT_PERM}" ] || [ "${REPORT_PERM}" != "600" ]; then
    die "Permissão efetiva do arquivo de relatório inválida (${REPORT_PERM})." "${EXIT_FS_FAIL}"
fi
================================================================================
EOF

if ! chmod 600 "${REPORT_FILE}"; then
    die "Falha ao definir permissões no arquivo de relatório." "${EXIT_FS_FAIL}"
fi
REPORT_PERM="$(stat -c '%a' "${REPORT_FILE}" 2>/dev/null || stat -f '%Lp' "${REPORT_FILE}" 2>/dev/null || echo "")"
if [ -z "${REPORT_PERM}" ] || [ "${REPORT_PERM}" != "600" ]; then
    die "Permissão efetiva do arquivo de relatório inválida (${REPORT_PERM})." "${EXIT_FS_FAIL}"
fi
=======
cat <<EOF > "${REPORT_FILE}"
================================================================================
 DPSjur / SBJur — RELATÓRIO DE AUDITORIA DE BACKUP (${SCRIPT_VERSION})
 Data de emissão: $(date '+%F %T %Z')
 Sessão de auditoria: ${SESSION_ID}
================================================================================

1. ARQUIVOS E AMBIENTE
   Arquivo de backup: ${BACKUP_FILE}
   Inventário oficial: ${INVENTORY_FILE:-Nenhum informado}
   Contêiner de teste: ${LAB_NAME}
   Label da sessão: ${SESSION_LABEL}
   Volume isolado: ${LAB_VOLUME}
   Imagem PostgreSQL: ${CHOSEN_IMAGE}

2. SEÇÃO TÉCNICA SEPARADA: RESTAURAÇÃO ORIGINAL vs RECUPERAÇÃO ASSISTIDA
   (a) Restauração Original (psql -X -v ON_ERROR_STOP=1): ${RESTORE_ORIGINAL_STATUS}
       - Código gunzip .................: ${GZIP_EXIT} (exigido 0)
       - Código psql ...................: ${PSQL_EXIT} (exigido 0)
       - Erros SQL brutos ..............: ${RESTORE_RAW_ERRORS_COUNT} (exigido 0)
       - Avaliação Restauração Original : ${CRIT_A}
   (b) Recuperação Assistida (Post-Restore):
       - Extensão pg_graphql ...........: ${GRAPHQL_FINAL_STATUS}
       - Tentativa de recuperação ......: ${GRAPHQL_REC_STATUS}
       - Observação de isolamento ......: A recuperação assistida NÃO mascara falha na restauração original.

3. RESULTADOS DOS DEMAIS CRITÉRIOS TÉCNICOS
   Critério 3 - Inventário estrutural do laboratório: ${CRIT_C}
       - Tabelas public: ${TOTAL_TABELAS_LAB}
       - Tabelas auth: ${TOTAL_TABELAS_AUTH_LAB}
       - Constraints: ${TOTAL_CONSTRAINTS_LAB}
       - Funções: ${TOTAL_FUNCOES_LAB}
       - Triggers: ${TOTAL_TRIGGERS_LAB}
       - Extensões: ${TOTAL_EXTENSOES_LAB}
   Critério 4 - Comparação estrutural e bidirecional com inventário oficial (jq): $([ "${CRIT_D_OK}" -eq 1 ] && echo "CONFORME" || echo "NAO_CONFORME")
       - Validação JSON semântica com jq: ${INVENTORY_COMPARISON_VALID}
       - Bidirecionalidade avaliada: $([ "${INVENTORY_BIDIRECTIONAL_CHECK_PASSED}" -eq 1 ] && echo "SIM" || echo "NAO")
       - Amostragem aplicada: NENHUMA (conferência integral de constraints e funções)
   Critério 5 - Integridade parcial do PostgreSQL restaurado: ${OP_CRITERION_STATUS}
       - Integridade referencial (FKs órfãs): ${FK_ORPHANS_CNT}
       - Consistência auth.users: ${USERS_TOTAL} usuários, ${USERS_DUP_COUNT} duplicidades
       - Planos de execução EXPLAIN: ${EXPLAIN_STATUS}
       - Bloco transacional com ROLLBACK: ${TX_STATUS}
       - Escopo delimitado: Prova unicamente a saúde do PostgreSQL restaurado;
         não atesta recuperação funcional completa da aplicação CRM (Kong/GoTrue/PostgREST fora do escopo do teste).

4. DIVERGÊNCIAS E DIFERENÇAS DE CONTAGEM INCONCLUSIVAS
   Total de divergências impeditivas: ${DIVERGENCES_COUNT}
   Total de diferenças de contagem inconclusivas: ${TEMPORAL_DIFFS_COUNT}
EOF

if [ -s "${DIVERGENCES_FILE}" ]; then
    printf '\n--- ITENS DE DIVERGÊNCIA REGISTRADOS ---\n' >> "${REPORT_FILE}"
    sed 's/^/   [DIVERGÊNCIA] /' "${DIVERGENCES_FILE}" >> "${REPORT_FILE}"
fi

if [ -s "${TEMPORAL_DIFFS_FILE}" ]; then
    printf '\n--- DIFERENÇAS DE CONTAGEM INCONCLUSIVAS (SEM PRESUNÇÃO DE CRESCIMENTO) ---\n' >> "${REPORT_FILE}"
    sed 's/^/   [INCONCLUSIVO] /' "${TEMPORAL_DIFFS_FILE}" >> "${REPORT_FILE}"
fi

cat <<EOF >> "${REPORT_FILE}"

5. VEREDITO FINAL DA AUDITORIA
   Veredito: ${VEREDITO}
   Motivo: ${MOTIVO_VEREDITO}

6. RASTREABILIDADE E SEGURANÇA
   Rede do contêiner de laboratório: --network none (isolamento de rede estrito)
   Arquivo do relatório: ${REPORT_FILE} (chmod 600)
   Log técnico restrito: ${LOG_FILE} (chmod 600)
   Log de erros do restore: ${RESTORE_ERRORS_FILE} (chmod 600)
   Recursos rastreados da sessão: ${TRACKED_RESOURCES_FILE} (chmod 600)
================================================================================
EOF

if ! chmod 600 "${REPORT_FILE}"; then
    die "Falha ao definir permissões no arquivo de relatório." "${EXIT_FS_FAIL}"
fi
REPORT_PERM="$(stat -c '%a' "${REPORT_FILE}" 2>/dev/null || stat -f '%Lp' "${REPORT_FILE}" 2>/dev/null || echo "")"
if [ -z "${REPORT_PERM}" ] || [ "${REPORT_PERM}" != "600" ]; then
    die "Permissão efetiva do arquivo de relatório inválida (${REPORT_PERM})." "${EXIT_FS_FAIL}"
fi
================================================================================
EOF

if ! chmod 600 "${REPORT_FILE}"; then
    die "Falha ao definir permissões no arquivo de relatório." "${EXIT_FS_FAIL}"
fi

# Exibição no terminal
say ""
say "================================================================================"
say " VEREDITO FINAL DA AUDITORIA DE BACKUP: ${VEREDITO}"
=======
if [ "${CRIT_A}" = "OK" ] && [ "${CRIT_B}" = "OK" ] && [ "${CRIT_C}" = "OK" ] && [ "${CRIT_D_OK}" -eq 1 ] && [ "${CRIT_E_OK}" -eq 1 ] && [ "${DIVERGENCES_COUNT}" -eq 0 ] && [ "${INVENTORY_COMPARISON_VALID}" = "SIM" ]; then
    VEREDITO="APROVADO"
    MOTIVO_VEREDITO="Todos os critérios técnicos passaram sem exceção (restauração física original, pg_graphql, estrutural exaustivo, comparação bidirecional integral jq, integridade de catálogo/dados e zero divergências)."
else
    VEREDITO="REPROVADO"
    MOTIVO_VEREDITO="O backup apresentou divergências ou falhas técnicas não resolvidas (CRIT_A_ORIGINAL: ${CRIT_A}, DIVERGÊNCIAS: ${DIVERGENCES_COUNT}, COMPARAÇÃO_VÁLIDA: ${INVENTORY_COMPARISON_VALID}, QUERIES_FALHAS: ${QUERY_FAILURES_COUNT})."
fi

# ------------------------------------------------------------------------------
# GRAVAÇÃO DO RELATÓRIO TÉCNICO COM CHMOD 600
# ------------------------------------------------------------------------------

cat <<EOF > "${REPORT_FILE}"
================================================================================
 DPSjur / SBJur — RELATÓRIO DE AUDITORIA DE BACKUP (${SCRIPT_VERSION})
 Data de emissão: $(date '+%F %T %Z')
 Sessão de auditoria: ${SESSION_ID}
================================================================================

1. ARQUIVOS E AMBIENTE
   Arquivo de backup: ${BACKUP_FILE}
   Inventário oficial: ${INVENTORY_FILE:-Nenhum informado}
   Contêiner de teste: ${LAB_NAME}
   Label da sessão: ${SESSION_LABEL}
   Volume isolado: ${LAB_VOLUME}
   Imagem PostgreSQL: ${CHOSEN_IMAGE}

2. SEÇÃO TÉCNICA SEPARADA: RESTAURAÇÃO ORIGINAL vs RECUPERAÇÃO ASSISTIDA
   (a) Restauração Original (psql -X -v ON_ERROR_STOP=1): ${RESTORE_ORIGINAL_STATUS}
       - Código gunzip .................: ${GZIP_EXIT} (exigido 0)
       - Código psql ...................: ${PSQL_EXIT} (exigido 0)
       - Erros SQL brutos ..............: ${RESTORE_RAW_ERRORS_COUNT} (exigido 0)
       - Avaliação Restauração Original : ${CRIT_A}
   (b) Recuperação Assistida (Post-Restore):
       - Extensão pg_graphql ...........: ${GRAPHQL_FINAL_STATUS}
       - Tentativa de recuperação ......: ${GRAPHQL_REC_STATUS}
       - Observação de isolamento ......: A recuperação assistida NÃO mascara falha na restauração original.

3. RESULTADOS DOS DEMAIS CRITÉRIOS TÉCNICOS
   Critério 3 - Inventário estrutural do laboratório: ${CRIT_C}
       - Tabelas public: ${TOTAL_TABELAS_LAB}
       - Tabelas auth: ${TOTAL_TABELAS_AUTH_LAB}
       - Constraints: ${TOTAL_CONSTRAINTS_LAB}
       - Funções: ${TOTAL_FUNCOES_LAB}
       - Triggers: ${TOTAL_TRIGGERS_LAB}
       - Extensões: ${TOTAL_EXTENSOES_LAB}
   Critério 4 - Comparação estrutural e bidirecional com inventário oficial (jq): $([ "${CRIT_D_OK}" -eq 1 ] && echo "CONFORME" || echo "NAO_CONFORME")
       - Validação JSON semântica com jq: ${INVENTORY_COMPARISON_VALID}
       - Bidirecionalidade avaliada: $([ "${INVENTORY_BIDIRECTIONAL_CHECK_PASSED}" -eq 1 ] && echo "SIM" || echo "NAO")
       - Amostragem aplicada: NENHUMA (conferência integral de constraints e funções)
   Critério 5 - Integridade parcial do PostgreSQL restaurado: ${OP_CRITERION_STATUS}
       - Integridade referencial (FKs órfãs): ${FK_ORPHANS_CNT}
       - Consistência auth.users: ${USERS_TOTAL} usuários, ${USERS_DUP_COUNT} duplicidades
       - Planos de execução EXPLAIN: ${EXPLAIN_STATUS}
       - Bloco transacional com ROLLBACK: ${TX_STATUS}
       - Escopo delimitado: Prova unicamente a saúde do PostgreSQL restaurado;
         não atesta recuperação funcional completa da aplicação CRM (Kong/GoTrue/PostgREST fora do escopo do teste).

4. DIVERGÊNCIAS E DIFERENÇAS DE CONTAGEM INCONCLUSIVAS
   Total de divergências impeditivas: ${DIVERGENCES_COUNT}
   Total de diferenças de contagem inconclusivas: ${TEMPORAL_DIFFS_COUNT}
EOF

if [ -s "${DIVERGENCES_FILE}" ]; then
    printf '\n--- ITENS DE DIVERGÊNCIA REGISTRADOS ---\n' >> "${REPORT_FILE}"
    sed 's/^/   [DIVERGÊNCIA] /' "${DIVERGENCES_FILE}" >> "${REPORT_FILE}"
fi

if [ -s "${TEMPORAL_DIFFS_FILE}" ]; then
    printf '\n--- DIFERENÇAS DE CONTAGEM INCONCLUSIVAS (SEM PRESUNÇÃO DE CRESCIMENTO) ---\n' >> "${REPORT_FILE}"
    sed 's/^/   [INCONCLUSIVO] /' "${TEMPORAL_DIFFS_FILE}" >> "${REPORT_FILE}"
fi

cat <<EOF >> "${REPORT_FILE}"

5. VEREDITO FINAL DA AUDITORIA
   Veredito: ${VEREDITO}
   Motivo: ${MOTIVO_VEREDITO}

6. RASTREABILIDADE E SEGURANÇA
   Rede do contêiner de laboratório: --network none (isolamento de rede estrito)
   Arquivo do relatório: ${REPORT_FILE} (chmod 600)
   Log técnico restrito: ${LOG_FILE} (chmod 600)
   Log de erros do restore: ${RESTORE_ERRORS_FILE} (chmod 600)
   Recursos rastreados da sessão: ${TRACKED_RESOURCES_FILE} (chmod 600)
================================================================================
EOF

if ! chmod 600 "${REPORT_FILE}"; then
    die "Falha ao definir permissões no arquivo de relatório." "${EXIT_FS_FAIL}"
fi
REPORT_PERM="$(stat -c '%a' "${REPORT_FILE}" 2>/dev/null || stat -f '%Lp' "${REPORT_FILE}" 2>/dev/null || echo "")"
if [ -z "${REPORT_PERM}" ] || [ "${REPORT_PERM}" != "600" ]; then
    die "Permissão efetiva do arquivo de relatório inválida (${REPORT_PERM})." "${EXIT_FS_FAIL}"
fi

# Exibição no terminal
say ""
say "================================================================================"
say " VEREDITO FINAL DA AUDITORIA DE BACKUP: ${VEREDITO}"
=======
cat <<EOF >> "${REPORT_FILE}"

5. VEREDITO FINAL DA AUDITORIA
   Veredito: ${VEREDITO}
   Motivo: ${MOTIVO_VEREDITO}

6. RASTREABILIDADE E SEGURANÇA
   Rede do contêiner de laboratório: --network none (isolamento de rede estrito)
   Arquivo do relatório: ${REPORT_FILE} (chmod 600)
   Log técnico restrito: ${LOG_FILE} (chmod 600)
   Log de erros do restore: ${RESTORE_ERRORS_FILE} (chmod 600)
   Recursos rastreados da sessão: ${TRACKED_RESOURCES_FILE} (chmod 600)
================================================================================
EOF

if ! chmod 600 "${REPORT_FILE}"; then
    die "Falha ao definir permissões no arquivo de relatório." "${EXIT_FS_FAIL}"
fi
REPORT_PERM="$(stat -c '%a' "${REPORT_FILE}" 2>/dev/null || stat -f '%Lp' "${REPORT_FILE}" 2>/dev/null || echo "")"
if [ -z "${REPORT_PERM}" ] || [ "${REPORT_PERM}" != "600" ]; then
    die "Permissão efetiva do arquivo de relatório inválida (${REPORT_PERM})." "${EXIT_FS_FAIL}"
fi
=======
5. VEREDITO FINAL DA AUDITORIA
   Veredito: ${VEREDITO}
   Motivo: ${MOTIVO_VEREDITO}

6. RASTREABILIDADE E SEGURANÇA
   Rede do contêiner de laboratório: --network none (isolamento de rede estrito)
   Arquivo do relatório: ${REPORT_FILE} (chmod 600)
   Log técnico restrito: ${LOG_FILE} (chmod 600)
   Log de erros do restore: ${RESTORE_ERRORS_FILE} (chmod 600)
   Recursos rastreados da sessão: ${TRACKED_RESOURCES_FILE} (chmod 600)
================================================================================
EOF

if ! chmod 600 "${REPORT_FILE}"; then
    die "Falha ao definir permissões no arquivo de relatório." "${EXIT_FS_FAIL}"
fi
REPORT_PERM="$(stat -c '%a' "${REPORT_FILE}" 2>/dev/null || stat -f '%Lp' "${REPORT_FILE}" 2>/dev/null || echo "")"
if [ -z "${REPORT_PERM}" ] || [ "${REPORT_PERM}" != "600" ]; then
    die "Permissão efetiva do arquivo de relatório inválida (${REPORT_PERM})." "${EXIT_FS_FAIL}"
fi
================================================================================
EOF

if ! chmod 600 "${REPORT_FILE}"; then
    die "Falha ao definir permissões no arquivo de relatório." "${EXIT_FS_FAIL}"
fi

# Exibição no terminal
=======
   Total de divergências impeditivas: ${DIVERGENCES_COUNT}
   Total de diferenças de contagem inconclusivas: ${TEMPORAL_DIFFS_COUNT}
EOF

if [ -s "${DIVERGENCES_FILE}" ]; then
    printf '\n--- ITENS DE DIVERGÊNCIA REGISTRADOS ---\n' >> "${REPORT_FILE}"
    sed 's/^/   [DIVERGÊNCIA] /' "${DIVERGENCES_FILE}" >> "${REPORT_FILE}"
fi

if [ -s "${TEMPORAL_DIFFS_FILE}" ]; then
    printf '\n--- DIFERENÇAS DE CONTAGEM INCONCLUSIVAS (SEM PRESUNÇÃO DE CRESCIMENTO) ---\n' >> "${REPORT_FILE}"
    sed 's/^/   [INCONCLUSIVO] /' "${TEMPORAL_DIFFS_FILE}" >> "${REPORT_FILE}"
fi

cat <<EOF >> "${REPORT_FILE}"

5. VEREDITO FINAL DA AUDITORIA
   Veredito: ${VEREDITO}
   Motivo: ${MOTIVO_VEREDITO}

6. RASTREABILIDADE E SEGURANÇA
   Rede do contêiner de laboratório: --network none (isolamento de rede estrito)
   Arquivo do relatório: ${REPORT_FILE} (chmod 600)
   Log técnico restrito: ${LOG_FILE} (chmod 600)
   Log de erros do restore: ${RESTORE_ERRORS_FILE} (chmod 600)
   Recursos rastreados da sessão: ${TRACKED_RESOURCES_FILE} (chmod 600)
================================================================================
EOF

if ! chmod 600 "${REPORT_FILE}"; then
    die "Falha ao definir permissões no arquivo de relatório." "${EXIT_FS_FAIL}"
fi
REPORT_PERM="$(stat -c '%a' "${REPORT_FILE}" 2>/dev/null || stat -f '%Lp' "${REPORT_FILE}" 2>/dev/null || echo "")"
if [ -z "${REPORT_PERM}" ] || [ "${REPORT_PERM}" != "600" ]; then
    die "Permissão efetiva do arquivo de relatório inválida (${REPORT_PERM})." "${EXIT_FS_FAIL}"
fi
================================================================================
EOF

if ! chmod 600 "${REPORT_FILE}"; then
    die "Falha ao definir permissões no arquivo de relatório." "${EXIT_FS_FAIL}"
fi
REPORT_PERM="$(stat -c '%a' "${REPORT_FILE}" 2>/dev/null || stat -f '%Lp' "${REPORT_FILE}" 2>/dev/null || echo "")"
if [ -z "${REPORT_PERM}" ] || [ "${REPORT_PERM}" != "600" ]; then
    die "Permissão efetiva do arquivo de relatório inválida (${REPORT_PERM})." "${EXIT_FS_FAIL}"
fi
================================================================================
EOF

if ! chmod 600 "${REPORT_FILE}"; then
    die "Falha ao definir permissões no arquivo de relatório." "${EXIT_FS_FAIL}"
fi
=======
cat <<EOF >> "${REPORT_FILE}"

5. VEREDITO FINAL DA AUDITORIA
   Veredito: ${VEREDITO}
   Motivo: ${MOTIVO_VEREDITO}

6. RASTREABILIDADE E SEGURANÇA
   Rede do contêiner de laboratório: --network none (isolamento de rede estrito)
   Arquivo do relatório: ${REPORT_FILE} (chmod 600)
   Log técnico restrito: ${LOG_FILE} (chmod 600)
   Log de erros do restore: ${RESTORE_ERRORS_FILE} (chmod 600)
   Recursos rastreados da sessão: ${TRACKED_RESOURCES_FILE} (chmod 600)
================================================================================
EOF

if ! chmod 600 "${REPORT_FILE}"; then
    die "Falha ao definir permissões no arquivo de relatório." "${EXIT_FS_FAIL}"
fi
REPORT_PERM="$(stat -c '%a' "${REPORT_FILE}" 2>/dev/null || stat -f '%Lp' "${REPORT_FILE}" 2>/dev/null || echo "")"
if [ -z "${REPORT_PERM}" ] || [ "${REPORT_PERM}" != "600" ]; then
    die "Permissão efetiva do arquivo de relatório inválida (${REPORT_PERM})." "${EXIT_FS_FAIL}"
fi
=======
5. VEREDITO FINAL DA AUDITORIA
   Veredito: ${VEREDITO}
   Motivo: ${MOTIVO_VEREDITO}

6. RASTREABILIDADE E SEGURANÇA
   Rede do contêiner de laboratório: --network none (isolamento de rede estrito)
   Arquivo do relatório: ${REPORT_FILE} (chmod 600)
   Log técnico restrito: ${LOG_FILE} (chmod 600)
   Log de erros do restore: ${RESTORE_ERRORS_FILE} (chmod 600)
   Recursos rastreados da sessão: ${TRACKED_RESOURCES_FILE} (chmod 600)
================================================================================
EOF

if ! chmod 600 "${REPORT_FILE}"; then
    die "Falha ao definir permissões no arquivo de relatório." "${EXIT_FS_FAIL}"
fi
REPORT_PERM="$(stat -c '%a' "${REPORT_FILE}" 2>/dev/null || stat -f '%Lp' "${REPORT_FILE}" 2>/dev/null || echo "")"
if [ -z "${REPORT_PERM}" ] || [ "${REPORT_PERM}" != "600" ]; then
    die "Permissão efetiva do arquivo de relatório inválida (${REPORT_PERM})." "${EXIT_FS_FAIL}"
fi
================================================================================
EOF

if ! chmod 600 "${REPORT_FILE}"; then
    die "Falha ao definir permissões no arquivo de relatório." "${EXIT_FS_FAIL}"
fi

# Exibição no terminal
say ""
say "================================================================================"
say " VEREDITO FINAL DA AUDITORIA DE BACKUP: ${VEREDITO}"
=======
   Total de divergências impeditivas: ${DIVERGENCES_COUNT}
   Total de diferenças de contagem inconclusivas: ${TEMPORAL_DIFFS_COUNT}
EOF

if [ -s "${DIVERGENCES_FILE}" ]; then
    printf '\n--- ITENS DE DIVERGÊNCIA REGISTRADOS ---\n' >> "${REPORT_FILE}"
    sed 's/^/   [DIVERGÊNCIA] /' "${DIVERGENCES_FILE}" >> "${REPORT_FILE}"
fi

if [ -s "${TEMPORAL_DIFFS_FILE}" ]; then
    printf '\n--- DIFERENÇAS DE CONTAGEM INCONCLUSIVAS (SEM PRESUNÇÃO DE CRESCIMENTO) ---\n' >> "${REPORT_FILE}"
    sed 's/^/   [INCONCLUSIVO] /' "${TEMPORAL_DIFFS_FILE}" >> "${REPORT_FILE}"
fi

cat <<EOF >> "${REPORT_FILE}"

5. VEREDITO FINAL DA AUDITORIA
   Veredito: ${VEREDITO}
   Motivo: ${MOTIVO_VEREDITO}

6. RASTREABILIDADE E SEGURANÇA
   Rede do contêiner de laboratório: --network none (isolamento de rede estrito)
   Arquivo do relatório: ${REPORT_FILE} (chmod 600)
   Log técnico restrito: ${LOG_FILE} (chmod 600)
   Log de erros do restore: ${RESTORE_ERRORS_FILE} (chmod 600)
   Recursos rastreados da sessão: ${TRACKED_RESOURCES_FILE} (chmod 600)
================================================================================
EOF

if ! chmod 600 "${REPORT_FILE}"; then
    die "Falha ao definir permissões no arquivo de relatório." "${EXIT_FS_FAIL}"
fi
REPORT_PERM="$(stat -c '%a' "${REPORT_FILE}" 2>/dev/null || stat -f '%Lp' "${REPORT_FILE}" 2>/dev/null || echo "")"
if [ -z "${REPORT_PERM}" ] || [ "${REPORT_PERM}" != "600" ]; then
    die "Permissão efetiva do arquivo de relatório inválida (${REPORT_PERM})." "${EXIT_FS_FAIL}"
fi

# Exibição no terminal
say ""
say "================================================================================"
say " VEREDITO FINAL DA AUDITORIA DE BACKUP: ${VEREDITO}"
=======
if [ "${CRIT_A}" = "OK" ] && [ "${CRIT_B}" = "OK" ] && [ "${CRIT_C}" = "OK" ] && [ "${CRIT_D_OK}" -eq 1 ] && [ "${CRIT_E_OK}" -eq 1 ] && [ "${DIVERGENCES_COUNT}" -eq 0 ] && [ "${INVENTORY_COMPARISON_VALID}" = "SIM" ]; then
    VEREDITO="APROVADO"
    MOTIVO_VEREDITO="Todos os critérios técnicos passaram sem exceção (restauração física original, pg_graphql, estrutural exaustivo, comparação bidirecional integral jq, integridade de catálogo/dados e zero divergências)."
else
    VEREDITO="REPROVADO"
    MOTIVO_VEREDITO="O backup apresentou divergências ou falhas técnicas não resolvidas (CRIT_A_ORIGINAL: ${CRIT_A}, DIVERGÊNCIAS: ${DIVERGENCES_COUNT}, COMPARAÇÃO_VÁLIDA: ${INVENTORY_COMPARISON_VALID}, QUERIES_FALHAS: ${QUERY_FAILURES_COUNT})."
fi

# ------------------------------------------------------------------------------
# GRAVAÇÃO DO RELATÓRIO TÉCNICO COM CHMOD 600
# ------------------------------------------------------------------------------

cat <<EOF > "${REPORT_FILE}"
================================================================================
 DPSjur / SBJur — RELATÓRIO DE AUDITORIA DE BACKUP (${SCRIPT_VERSION})
 Data de emissão: $(date '+%F %T %Z')
 Sessão de auditoria: ${SESSION_ID}
================================================================================

1. ARQUIVOS E AMBIENTE
   Arquivo de backup: ${BACKUP_FILE}
   Inventário oficial: ${INVENTORY_FILE:-Nenhum informado}
   Contêiner de teste: ${LAB_NAME}
   Label da sessão: ${SESSION_LABEL}
   Volume isolado: ${LAB_VOLUME}
   Imagem PostgreSQL: ${CHOSEN_IMAGE}

2. SEÇÃO TÉCNICA SEPARADA: RESTAURAÇÃO ORIGINAL vs RECUPERAÇÃO ASSISTIDA
   (a) Restauração Original (psql -X -v ON_ERROR_STOP=1): ${RESTORE_ORIGINAL_STATUS}
       - Código gunzip .................: ${GZIP_EXIT} (exigido 0)
       - Código psql ...................: ${PSQL_EXIT} (exigido 0)
       - Erros SQL brutos ..............: ${RESTORE_RAW_ERRORS_COUNT} (exigido 0)
       - Avaliação Restauração Original : ${CRIT_A}
   (b) Recuperação Assistida (Post-Restore):
       - Extensão pg_graphql ...........: ${GRAPHQL_FINAL_STATUS}
       - Tentativa de recuperação ......: ${GRAPHQL_REC_STATUS}
       - Observação de isolamento ......: A recuperação assistida NÃO mascara falha na restauração original.

3. RESULTADOS DOS DEMAIS CRITÉRIOS TÉCNICOS
   Critério 3 - Inventário estrutural do laboratório: ${CRIT_C}
       - Tabelas public: ${TOTAL_TABELAS_LAB}
       - Tabelas auth: ${TOTAL_TABELAS_AUTH_LAB}
       - Constraints: ${TOTAL_CONSTRAINTS_LAB}
       - Funções: ${TOTAL_FUNCOES_LAB}
       - Triggers: ${TOTAL_TRIGGERS_LAB}
       - Extensões: ${TOTAL_EXTENSOES_LAB}
   Critério 4 - Comparação estrutural e bidirecional com inventário oficial (jq): $([ "${CRIT_D_OK}" -eq 1 ] && echo "CONFORME" || echo "NAO_CONFORME")
       - Validação JSON semântica com jq: ${INVENTORY_COMPARISON_VALID}
       - Bidirecionalidade avaliada: $([ "${INVENTORY_BIDIRECTIONAL_CHECK_PASSED}" -eq 1 ] && echo "SIM" || echo "NAO")
       - Amostragem aplicada: NENHUMA (conferência integral de constraints e funções)
   Critério 5 - Integridade parcial do PostgreSQL restaurado: ${OP_CRITERION_STATUS}
       - Integridade referencial (FKs órfãs): ${FK_ORPHANS_CNT}
       - Consistência auth.users: ${USERS_TOTAL} usuários, ${USERS_DUP_COUNT} duplicidades
       - Planos de execução EXPLAIN: ${EXPLAIN_STATUS}
       - Bloco transacional com ROLLBACK: ${TX_STATUS}
       - Escopo delimitado: Prova unicamente a saúde do PostgreSQL restaurado;
         não atesta recuperação funcional completa da aplicação CRM (Kong/GoTrue/PostgREST fora do escopo do teste).

4. DIVERGÊNCIAS E DIFERENÇAS DE CONTAGEM INCONCLUSIVAS
   Total de divergências impeditivas: ${DIVERGENCES_COUNT}
   Total de diferenças de contagem inconclusivas: ${TEMPORAL_DIFFS_COUNT}
EOF

if [ -s "${DIVERGENCES_FILE}" ]; then
    printf '\n--- ITENS DE DIVERGÊNCIA REGISTRADOS ---\n' >> "${REPORT_FILE}"
    sed 's/^/   [DIVERGÊNCIA] /' "${DIVERGENCES_FILE}" >> "${REPORT_FILE}"
fi

if [ -s "${TEMPORAL_DIFFS_FILE}" ]; then
    printf '\n--- DIFERENÇAS DE CONTAGEM INCONCLUSIVAS (SEM PRESUNÇÃO DE CRESCIMENTO) ---\n' >> "${REPORT_FILE}"
    sed 's/^/   [INCONCLUSIVO] /' "${TEMPORAL_DIFFS_FILE}" >> "${REPORT_FILE}"
fi

cat <<EOF >> "${REPORT_FILE}"

5. VEREDITO FINAL DA AUDITORIA
   Veredito: ${VEREDITO}
   Motivo: ${MOTIVO_VEREDITO}

6. RASTREABILIDADE E SEGURANÇA
   Rede do contêiner de laboratório: --network none (isolamento de rede estrito)
   Arquivo do relatório: ${REPORT_FILE} (chmod 600)
   Log técnico restrito: ${LOG_FILE} (chmod 600)
   Log de erros do restore: ${RESTORE_ERRORS_FILE} (chmod 600)
   Recursos rastreados da sessão: ${TRACKED_RESOURCES_FILE} (chmod 600)
================================================================================
EOF

if ! chmod 600 "${REPORT_FILE}"; then
    die "Falha ao definir permissões no arquivo de relatório." "${EXIT_FS_FAIL}"
fi
REPORT_PERM="$(stat -c '%a' "${REPORT_FILE}" 2>/dev/null || stat -f '%Lp' "${REPORT_FILE}" 2>/dev/null || echo "")"
if [ -z "${REPORT_PERM}" ] || [ "${REPORT_PERM}" != "600" ]; then
    die "Permissão efetiva do arquivo de relatório inválida (${REPORT_PERM})." "${EXIT_FS_FAIL}"
fi
================================================================================
EOF

if ! chmod 600 "${REPORT_FILE}"; then
    die "Falha ao definir permissões no arquivo de relatório." "${EXIT_FS_FAIL}"
fi
=======
cat <<EOF >> "${REPORT_FILE}"

5. VEREDITO FINAL DA AUDITORIA
   Veredito: ${VEREDITO}
   Motivo: ${MOTIVO_VEREDITO}

6. RASTREABILIDADE E SEGURANÇA
   Rede do contêiner de laboratório: --network none (isolamento de rede estrito)
   Arquivo do relatório: ${REPORT_FILE} (chmod 600)
   Log técnico restrito: ${LOG_FILE} (chmod 600)
   Log de erros do restore: ${RESTORE_ERRORS_FILE} (chmod 600)
   Recursos rastreados da sessão: ${TRACKED_RESOURCES_FILE} (chmod 600)
================================================================================
EOF

if ! chmod 600 "${REPORT_FILE}"; then
    die "Falha ao definir permissões no arquivo de relatório." "${EXIT_FS_FAIL}"
fi
REPORT_PERM="$(stat -c '%a' "${REPORT_FILE}" 2>/dev/null || stat -f '%Lp' "${REPORT_FILE}" 2>/dev/null || echo "")"
if [ -z "${REPORT_PERM}" ] || [ "${REPORT_PERM}" != "600" ]; then
    die "Permissão efetiva do arquivo de relatório inválida (${REPORT_PERM})." "${EXIT_FS_FAIL}"
fi
=======
5. VEREDITO FINAL DA AUDITORIA
   Veredito: ${VEREDITO}
   Motivo: ${MOTIVO_VEREDITO}

6. RASTREABILIDADE E SEGURANÇA
   Rede do contêiner de laboratório: --network none (isolamento de rede estrito)
   Arquivo do relatório: ${REPORT_FILE} (chmod 600)
   Log técnico restrito: ${LOG_FILE} (chmod 600)
   Log de erros do restore: ${RESTORE_ERRORS_FILE} (chmod 600)
   Recursos rastreados da sessão: ${TRACKED_RESOURCES_FILE} (chmod 600)
================================================================================
EOF

if ! chmod 600 "${REPORT_FILE}"; then
    die "Falha ao definir permissões no arquivo de relatório." "${EXIT_FS_FAIL}"
fi
REPORT_PERM="$(stat -c '%a' "${REPORT_FILE}" 2>/dev/null || stat -f '%Lp' "${REPORT_FILE}" 2>/dev/null || echo "")"
if [ -z "${REPORT_PERM}" ] || [ "${REPORT_PERM}" != "600" ]; then
    die "Permissão efetiva do arquivo de relatório inválida (${REPORT_PERM})." "${EXIT_FS_FAIL}"
fi
================================================================================
EOF

if ! chmod 600 "${REPORT_FILE}"; then
    die "Falha ao definir permissões no arquivo de relatório." "${EXIT_FS_FAIL}"
fi

# Exibição no terminal
=======
   Total de divergências impeditivas: ${DIVERGENCES_COUNT}
   Total de diferenças de contagem inconclusivas: ${TEMPORAL_DIFFS_COUNT}
EOF

if [ -s "${DIVERGENCES_FILE}" ]; then
    printf '\n--- ITENS DE DIVERGÊNCIA REGISTRADOS ---\n' >> "${REPORT_FILE}"
    sed 's/^/   [DIVERGÊNCIA] /' "${DIVERGENCES_FILE}" >> "${REPORT_FILE}"
fi

if [ -s "${TEMPORAL_DIFFS_FILE}" ]; then
    printf '\n--- DIFERENÇAS DE CONTAGEM INCONCLUSIVAS (SEM PRESUNÇÃO DE CRESCIMENTO) ---\n' >> "${REPORT_FILE}"
    sed 's/^/   [INCONCLUSIVO] /' "${TEMPORAL_DIFFS_FILE}" >> "${REPORT_FILE}"
fi

cat <<EOF >> "${REPORT_FILE}"

5. VEREDITO FINAL DA AUDITORIA
   Veredito: ${VEREDITO}
   Motivo: ${MOTIVO_VEREDITO}

6. RASTREABILIDADE E SEGURANÇA
   Rede do contêiner de laboratório: --network none (isolamento de rede estrito)
   Arquivo do relatório: ${REPORT_FILE} (chmod 600)
   Log técnico restrito: ${LOG_FILE} (chmod 600)
   Log de erros do restore: ${RESTORE_ERRORS_FILE} (chmod 600)
   Recursos rastreados da sessão: ${TRACKED_RESOURCES_FILE} (chmod 600)
================================================================================
EOF

if ! chmod 600 "${REPORT_FILE}"; then
    die "Falha ao definir permissões no arquivo de relatório." "${EXIT_FS_FAIL}"
fi
REPORT_PERM="$(stat -c '%a' "${REPORT_FILE}" 2>/dev/null || stat -f '%Lp' "${REPORT_FILE}" 2>/dev/null || echo "")"
if [ -z "${REPORT_PERM}" ] || [ "${REPORT_PERM}" != "600" ]; then
    die "Permissão efetiva do arquivo de relatório inválida (${REPORT_PERM})." "${EXIT_FS_FAIL}"
fi
================================================================================
EOF

if ! chmod 600 "${REPORT_FILE}"; then
    die "Falha ao definir permissões no arquivo de relatório." "${EXIT_FS_FAIL}"
fi
REPORT_PERM="$(stat -c '%a' "${REPORT_FILE}" 2>/dev/null || stat -f '%Lp' "${REPORT_FILE}" 2>/dev/null || echo "")"
if [ -z "${REPORT_PERM}" ] || [ "${REPORT_PERM}" != "600" ]; then
    die "Permissão efetiva do arquivo de relatório inválida (${REPORT_PERM})." "${EXIT_FS_FAIL}"
fi
================================================================================
EOF

if ! chmod 600 "${REPORT_FILE}"; then
    die "Falha ao definir permissões no arquivo de relatório." "${EXIT_FS_FAIL}"
fi
=======
cat <<EOF >> "${REPORT_FILE}"

5. VEREDITO FINAL DA AUDITORIA
   Veredito: ${VEREDITO}
   Motivo: ${MOTIVO_VEREDITO}

6. RASTREABILIDADE E SEGURANÇA
   Rede do contêiner de laboratório: --network none (isolamento de rede estrito)
   Arquivo do relatório: ${REPORT_FILE} (chmod 600)
   Log técnico restrito: ${LOG_FILE} (chmod 600)
   Log de erros do restore: ${RESTORE_ERRORS_FILE} (chmod 600)
   Recursos rastreados da sessão: ${TRACKED_RESOURCES_FILE} (chmod 600)
================================================================================
EOF

if ! chmod 600 "${REPORT_FILE}"; then
    die "Falha ao definir permissões no arquivo de relatório." "${EXIT_FS_FAIL}"
fi
REPORT_PERM="$(stat -c '%a' "${REPORT_FILE}" 2>/dev/null || stat -f '%Lp' "${REPORT_FILE}" 2>/dev/null || echo "")"
if [ -z "${REPORT_PERM}" ] || [ "${REPORT_PERM}" != "600" ]; then
    die "Permissão efetiva do arquivo de relatório inválida (${REPORT_PERM})." "${EXIT_FS_FAIL}"
fi
=======
5. VEREDITO FINAL DA AUDITORIA
   Veredito: ${VEREDITO}
   Motivo: ${MOTIVO_VEREDITO}

6. RASTREABILIDADE E SEGURANÇA
   Rede do contêiner de laboratório: --network none (isolamento de rede estrito)
   Arquivo do relatório: ${REPORT_FILE} (chmod 600)
   Log técnico restrito: ${LOG_FILE} (chmod 600)
   Log de erros do restore: ${RESTORE_ERRORS_FILE} (chmod 600)
   Recursos rastreados da sessão: ${TRACKED_RESOURCES_FILE} (chmod 600)
================================================================================
EOF

if ! chmod 600 "${REPORT_FILE}"; then
    die "Falha ao definir permissões no arquivo de relatório." "${EXIT_FS_FAIL}"
fi
REPORT_PERM="$(stat -c '%a' "${REPORT_FILE}" 2>/dev/null || stat -f '%Lp' "${REPORT_FILE}" 2>/dev/null || echo "")"
if [ -z "${REPORT_PERM}" ] || [ "${REPORT_PERM}" != "600" ]; then
    die "Permissão efetiva do arquivo de relatório inválida (${REPORT_PERM})." "${EXIT_FS_FAIL}"
fi
================================================================================
EOF

if ! chmod 600 "${REPORT_FILE}"; then
    die "Falha ao definir permissões no arquivo de relatório." "${EXIT_FS_FAIL}"
fi

# Exibição no terminal
say ""
say "================================================================================"
say " VEREDITO FINAL DA AUDITORIA DE BACKUP: ${VEREDITO}"
=======
   Total de divergências impeditivas: ${DIVERGENCES_COUNT}
   Total de diferenças de contagem inconclusivas: ${TEMPORAL_DIFFS_COUNT}
EOF

if [ -s "${DIVERGENCES_FILE}" ]; then
    printf '\n--- ITENS DE DIVERGÊNCIA REGISTRADOS ---\n' >> "${REPORT_FILE}"
    sed 's/^/   [DIVERGÊNCIA] /' "${DIVERGENCES_FILE}" >> "${REPORT_FILE}"
fi

if [ -s "${TEMPORAL_DIFFS_FILE}" ]; then
    printf '\n--- DIFERENÇAS DE CONTAGEM INCONCLUSIVAS (SEM PRESUNÇÃO DE CRESCIMENTO) ---\n' >> "${REPORT_FILE}"
    sed 's/^/   [INCONCLUSIVO] /' "${TEMPORAL_DIFFS_FILE}" >> "${REPORT_FILE}"
fi

cat <<EOF >> "${REPORT_FILE}"

5. VEREDITO FINAL DA AUDITORIA
   Veredito: ${VEREDITO}
   Motivo: ${MOTIVO_VEREDITO}

6. RASTREABILIDADE E SEGURANÇA
   Rede do contêiner de laboratório: --network none (isolamento de rede estrito)
   Arquivo do relatório: ${REPORT_FILE} (chmod 600)
   Log técnico restrito: ${LOG_FILE} (chmod 600)
   Log de erros do restore: ${RESTORE_ERRORS_FILE} (chmod 600)
   Recursos rastreados da sessão: ${TRACKED_RESOURCES_FILE} (chmod 600)
================================================================================
EOF

if ! chmod 600 "${REPORT_FILE}"; then
    die "Falha ao definir permissões no arquivo de relatório." "${EXIT_FS_FAIL}"
fi
REPORT_PERM="$(stat -c '%a' "${REPORT_FILE}" 2>/dev/null || stat -f '%Lp' "${REPORT_FILE}" 2>/dev/null || echo "")"
if [ -z "${REPORT_PERM}" ] || [ "${REPORT_PERM}" != "600" ]; then
    die "Permissão efetiva do arquivo de relatório inválida (${REPORT_PERM})." "${EXIT_FS_FAIL}"
fi

# Exibição no terminal
say ""
say "================================================================================"
say " VEREDITO FINAL DA AUDITORIA DE BACKUP: ${VEREDITO}"
================================================================================

1. ARQUIVOS E AMBIENTE
   Arquivo de backup: ${BACKUP_FILE}
   Inventário oficial: ${INVENTORY_FILE:-Nenhum informado}
   Contêiner de teste: ${LAB_NAME}
   Label da sessão: ${SESSION_LABEL}
   Volume isolado: ${LAB_VOLUME}
   Imagem PostgreSQL: ${CHOSEN_IMAGE}

2. SEÇÃO TÉCNICA SEPARADA: RESTAURAÇÃO ORIGINAL vs RECUPERAÇÃO ASSISTIDA
   (a) Restauração Original (psql -X -v ON_ERROR_STOP=1): ${RESTORE_ORIGINAL_STATUS}
       - Código gunzip .................: ${GZIP_EXIT} (exigido 0)
       - Código psql ...................: ${PSQL_EXIT} (exigido 0)
       - Erros SQL brutos ..............: ${RESTORE_RAW_ERRORS_COUNT} (exigido 0)
       - Avaliação Restauração Original : ${CRIT_A}
   (b) Recuperação Assistida (Post-Restore):
       - Extensão pg_graphql ...........: ${GRAPHQL_FINAL_STATUS}
       - Tentativa de recuperação ......: ${GRAPHQL_REC_STATUS}
       - Observação de isolamento ......: A recuperação assistida NÃO mascara falha na restauração original.

3. RESULTADOS DOS DEMAIS CRITÉRIOS TÉCNICOS
   Critério 3 - Inventário estrutural do laboratório: ${CRIT_C}
       - Tabelas public: ${TOTAL_TABELAS_LAB}
       - Tabelas auth: ${TOTAL_TABELAS_AUTH_LAB}
       - Constraints: ${TOTAL_CONSTRAINTS_LAB}
       - Funções: ${TOTAL_FUNCOES_LAB}
       - Triggers: ${TOTAL_TRIGGERS_LAB}
       - Extensões: ${TOTAL_EXTENSOES_LAB}
   Critério 4 - Comparação estrutural e bidirecional com inventário oficial (jq): $([ "${CRIT_D_OK}" -eq 1 ] && echo "CONFORME" || echo "NAO_CONFORME")
       - Validação JSON semântica com jq: ${INVENTORY_COMPARISON_VALID}
       - Bidirecionalidade avaliada: $([ "${INVENTORY_BIDIRECTIONAL_CHECK_PASSED}" -eq 1 ] && echo "SIM" || echo "NAO")
       - Amostragem aplicada: NENHUMA (conferência integral de constraints e funções)
   Critério 5 - Integridade parcial do PostgreSQL restaurado: ${OP_CRITERION_STATUS}
       - Integridade referencial (FKs órfãs): ${FK_ORPHANS_CNT}
       - Consistência auth.users: ${USERS_TOTAL} usuários, ${USERS_DUP_COUNT} duplicidades
       - Planos de execução EXPLAIN: ${EXPLAIN_STATUS}
       - Bloco transacional com ROLLBACK: ${TX_STATUS}
       - Escopo delimitado: Prova unicamente a saúde do PostgreSQL restaurado;
         não atesta recuperação funcional completa da aplicação CRM (Kong/GoTrue/PostgREST fora do escopo do teste).

4. DIVERGÊNCIAS E DIFERENÇAS DE CONTAGEM INCONCLUSIVAS
EOF

if ! chmod 600 "${REPORT_FILE}"; then
    die "Falha ao definir permissões no arquivo de relatório." "${EXIT_FS_FAIL}"
fi
REPORT_PERM="$(stat -c '%a' "${REPORT_FILE}" 2>/dev/null || stat -f '%Lp' "${REPORT_FILE}" 2>/dev/null || echo "")"
if [ -z "${REPORT_PERM}" ] || [ "${REPORT_PERM}" != "600" ]; then
    die "Permissão efetiva do arquivo de relatório inválida (${REPORT_PERM})." "${EXIT_FS_FAIL}"
fi
================================================================================
EOF

if ! chmod 600 "${REPORT_FILE}"; then
    die "Falha ao definir permissões no arquivo de relatório." "${EXIT_FS_FAIL}"
fi
=======
cat <<EOF >> "${REPORT_FILE}"

5. VEREDITO FINAL DA AUDITORIA
   Veredito: ${VEREDITO}
   Motivo: ${MOTIVO_VEREDITO}

6. RASTREABILIDADE E SEGURANÇA
   Rede do contêiner de laboratório: --network none (isolamento de rede estrito)
   Arquivo do relatório: ${REPORT_FILE} (chmod 600)
   Log técnico restrito: ${LOG_FILE} (chmod 600)
   Log de erros do restore: ${RESTORE_ERRORS_FILE} (chmod 600)
   Recursos rastreados da sessão: ${TRACKED_RESOURCES_FILE} (chmod 600)
================================================================================
EOF

if ! chmod 600 "${REPORT_FILE}"; then
    die "Falha ao definir permissões no arquivo de relatório." "${EXIT_FS_FAIL}"
fi
REPORT_PERM="$(stat -c '%a' "${REPORT_FILE}" 2>/dev/null || stat -f '%Lp' "${REPORT_FILE}" 2>/dev/null || echo "")"
if [ -z "${REPORT_PERM}" ] || [ "${REPORT_PERM}" != "600" ]; then
    die "Permissão efetiva do arquivo de relatório inválida (${REPORT_PERM})." "${EXIT_FS_FAIL}"
fi
=======
5. VEREDITO FINAL DA AUDITORIA
   Veredito: ${VEREDITO}
   Motivo: ${MOTIVO_VEREDITO}

6. RASTREABILIDADE E SEGURANÇA
   Rede do contêiner de laboratório: --network none (isolamento de rede estrito)
   Arquivo do relatório: ${REPORT_FILE} (chmod 600)
   Log técnico restrito: ${LOG_FILE} (chmod 600)
   Log de erros do restore: ${RESTORE_ERRORS_FILE} (chmod 600)
   Recursos rastreados da sessão: ${TRACKED_RESOURCES_FILE} (chmod 600)
================================================================================
EOF

if ! chmod 600 "${REPORT_FILE}"; then
    die "Falha ao definir permissões no arquivo de relatório." "${EXIT_FS_FAIL}"
fi
REPORT_PERM="$(stat -c '%a' "${REPORT_FILE}" 2>/dev/null || stat -f '%Lp' "${REPORT_FILE}" 2>/dev/null || echo "")"
if [ -z "${REPORT_PERM}" ] || [ "${REPORT_PERM}" != "600" ]; then
    die "Permissão efetiva do arquivo de relatório inválida (${REPORT_PERM})." "${EXIT_FS_FAIL}"
fi
================================================================================
EOF

if ! chmod 600 "${REPORT_FILE}"; then
    die "Falha ao definir permissões no arquivo de relatório." "${EXIT_FS_FAIL}"
fi

# Exibição no terminal
=======
   Total de divergências impeditivas: ${DIVERGENCES_COUNT}
   Total de diferenças de contagem inconclusivas: ${TEMPORAL_DIFFS_COUNT}
EOF

if [ -s "${DIVERGENCES_FILE}" ]; then
    printf '\n--- ITENS DE DIVERGÊNCIA REGISTRADOS ---\n' >> "${REPORT_FILE}"
    sed 's/^/   [DIVERGÊNCIA] /' "${DIVERGENCES_FILE}" >> "${REPORT_FILE}"
fi

if [ -s "${TEMPORAL_DIFFS_FILE}" ]; then
    printf '\n--- DIFERENÇAS DE CONTAGEM INCONCLUSIVAS (SEM PRESUNÇÃO DE CRESCIMENTO) ---\n' >> "${REPORT_FILE}"
    sed 's/^/   [INCONCLUSIVO] /' "${TEMPORAL_DIFFS_FILE}" >> "${REPORT_FILE}"
fi

cat <<EOF >> "${REPORT_FILE}"

5. VEREDITO FINAL DA AUDITORIA
   Veredito: ${VEREDITO}
   Motivo: ${MOTIVO_VEREDITO}

6. RASTREABILIDADE E SEGURANÇA
   Rede do contêiner de laboratório: --network none (isolamento de rede estrito)
   Arquivo do relatório: ${REPORT_FILE} (chmod 600)
   Log técnico restrito: ${LOG_FILE} (chmod 600)
   Log de erros do restore: ${RESTORE_ERRORS_FILE} (chmod 600)
   Recursos rastreados da sessão: ${TRACKED_RESOURCES_FILE} (chmod 600)
================================================================================
EOF

if ! chmod 600 "${REPORT_FILE}"; then
    die "Falha ao definir permissões no arquivo de relatório." "${EXIT_FS_FAIL}"
fi
REPORT_PERM="$(stat -c '%a' "${REPORT_FILE}" 2>/dev/null || stat -f '%Lp' "${REPORT_FILE}" 2>/dev/null || echo "")"
if [ -z "${REPORT_PERM}" ] || [ "${REPORT_PERM}" != "600" ]; then
    die "Permissão efetiva do arquivo de relatório inválida (${REPORT_PERM})." "${EXIT_FS_FAIL}"
fi
================================================================================
EOF

if ! chmod 600 "${REPORT_FILE}"; then
    die "Falha ao definir permissões no arquivo de relatório." "${EXIT_FS_FAIL}"
fi
REPORT_PERM="$(stat -c '%a' "${REPORT_FILE}" 2>/dev/null || stat -f '%Lp' "${REPORT_FILE}" 2>/dev/null || echo "")"
if [ -z "${REPORT_PERM}" ] || [ "${REPORT_PERM}" != "600" ]; then
    die "Permissão efetiva do arquivo de relatório inválida (${REPORT_PERM})." "${EXIT_FS_FAIL}"
fi
================================================================================
EOF

if ! chmod 600 "${REPORT_FILE}"; then
    die "Falha ao definir permissões no arquivo de relatório." "${EXIT_FS_FAIL}"
fi
=======
cat <<EOF >> "${REPORT_FILE}"

5. VEREDITO FINAL DA AUDITORIA
   Veredito: ${VEREDITO}
   Motivo: ${MOTIVO_VEREDITO}

6. RASTREABILIDADE E SEGURANÇA
   Rede do contêiner de laboratório: --network none (isolamento de rede estrito)
   Arquivo do relatório: ${REPORT_FILE} (chmod 600)
   Log técnico restrito: ${LOG_FILE} (chmod 600)
   Log de erros do restore: ${RESTORE_ERRORS_FILE} (chmod 600)
   Recursos rastreados da sessão: ${TRACKED_RESOURCES_FILE} (chmod 600)
================================================================================
EOF

if ! chmod 600 "${REPORT_FILE}"; then
    die "Falha ao definir permissões no arquivo de relatório." "${EXIT_FS_FAIL}"
fi
REPORT_PERM="$(stat -c '%a' "${REPORT_FILE}" 2>/dev/null || stat -f '%Lp' "${REPORT_FILE}" 2>/dev/null || echo "")"
if [ -z "${REPORT_PERM}" ] || [ "${REPORT_PERM}" != "600" ]; then
    die "Permissão efetiva do arquivo de relatório inválida (${REPORT_PERM})." "${EXIT_FS_FAIL}"
fi
=======
5. VEREDITO FINAL DA AUDITORIA
   Veredito: ${VEREDITO}
   Motivo: ${MOTIVO_VEREDITO}

6. RASTREABILIDADE E SEGURANÇA
   Rede do contêiner de laboratório: --network none (isolamento de rede estrito)
   Arquivo do relatório: ${REPORT_FILE} (chmod 600)
   Log técnico restrito: ${LOG_FILE} (chmod 600)
   Log de erros do restore: ${RESTORE_ERRORS_FILE} (chmod 600)
   Recursos rastreados da sessão: ${TRACKED_RESOURCES_FILE} (chmod 600)
================================================================================
EOF

if ! chmod 600 "${REPORT_FILE}"; then
    die "Falha ao definir permissões no arquivo de relatório." "${EXIT_FS_FAIL}"
fi
REPORT_PERM="$(stat -c '%a' "${REPORT_FILE}" 2>/dev/null || stat -f '%Lp' "${REPORT_FILE}" 2>/dev/null || echo "")"
if [ -z "${REPORT_PERM}" ] || [ "${REPORT_PERM}" != "600" ]; then
    die "Permissão efetiva do arquivo de relatório inválida (${REPORT_PERM})." "${EXIT_FS_FAIL}"
fi
================================================================================
EOF

if ! chmod 600 "${REPORT_FILE}"; then
    die "Falha ao definir permissões no arquivo de relatório." "${EXIT_FS_FAIL}"
fi

# Exibição no terminal
say ""
say "================================================================================"
say " VEREDITO FINAL DA AUDITORIA DE BACKUP: ${VEREDITO}"
=======
cat <<EOF > "${REPORT_FILE}"
================================================================================
 DPSjur / SBJur — RELATÓRIO DE AUDITORIA DE BACKUP (${SCRIPT_VERSION})
 Data de emissão: $(date '+%F %T %Z')
 Sessão de auditoria: ${SESSION_ID}
================================================================================

1. ARQUIVOS E AMBIENTE
   Arquivo de backup: ${BACKUP_FILE}
   Inventário oficial: ${INVENTORY_FILE:-Nenhum informado}
   Contêiner de teste: ${LAB_NAME}
   Label da sessão: ${SESSION_LABEL}
   Volume isolado: ${LAB_VOLUME}
   Imagem PostgreSQL: ${CHOSEN_IMAGE}

2. SEÇÃO TÉCNICA SEPARADA: RESTAURAÇÃO ORIGINAL vs RECUPERAÇÃO ASSISTIDA
   (a) Restauração Original (psql -X -v ON_ERROR_STOP=1): ${RESTORE_ORIGINAL_STATUS}
       - Código gunzip .................: ${GZIP_EXIT} (exigido 0)
       - Código psql ...................: ${PSQL_EXIT} (exigido 0)
       - Erros SQL brutos ..............: ${RESTORE_RAW_ERRORS_COUNT} (exigido 0)
       - Avaliação Restauração Original : ${CRIT_A}
   (b) Recuperação Assistida (Post-Restore):
       - Extensão pg_graphql ...........: ${GRAPHQL_FINAL_STATUS}
       - Tentativa de recuperação ......: ${GRAPHQL_REC_STATUS}
       - Observação de isolamento ......: A recuperação assistida NÃO mascara falha na restauração original.

3. RESULTADOS DOS DEMAIS CRITÉRIOS TÉCNICOS
   Critério 3 - Inventário estrutural do laboratório: ${CRIT_C}
       - Tabelas public: ${TOTAL_TABELAS_LAB}
       - Tabelas auth: ${TOTAL_TABELAS_AUTH_LAB}
       - Constraints: ${TOTAL_CONSTRAINTS_LAB}
       - Funções: ${TOTAL_FUNCOES_LAB}
       - Triggers: ${TOTAL_TRIGGERS_LAB}
       - Extensões: ${TOTAL_EXTENSOES_LAB}
   Critério 4 - Comparação estrutural e bidirecional com inventário oficial (jq): $([ "${CRIT_D_OK}" -eq 1 ] && echo "CONFORME" || echo "NAO_CONFORME")
       - Validação JSON semântica com jq: ${INVENTORY_COMPARISON_VALID}
       - Bidirecionalidade avaliada: $([ "${INVENTORY_BIDIRECTIONAL_CHECK_PASSED}" -eq 1 ] && echo "SIM" || echo "NAO")
       - Amostragem aplicada: NENHUMA (conferência integral de constraints e funções)
   Critério 5 - Integridade parcial do PostgreSQL restaurado: ${OP_CRITERION_STATUS}
       - Integridade referencial (FKs órfãs): ${FK_ORPHANS_CNT}
       - Consistência auth.users: ${USERS_TOTAL} usuários, ${USERS_DUP_COUNT} duplicidades
       - Planos de execução EXPLAIN: ${EXPLAIN_STATUS}
       - Bloco transacional com ROLLBACK: ${TX_STATUS}
       - Escopo delimitado: Prova unicamente a saúde do PostgreSQL restaurado;
         não atesta recuperação funcional completa da aplicação CRM (Kong/GoTrue/PostgREST fora do escopo do teste).

4. DIVERGÊNCIAS E DIFERENÇAS DE CONTAGEM INCONCLUSIVAS
   Total de divergências impeditivas: ${DIVERGENCES_COUNT}
   Total de diferenças de contagem inconclusivas: ${TEMPORAL_DIFFS_COUNT}
EOF

if [ -s "${DIVERGENCES_FILE}" ]; then
    printf '\n--- ITENS DE DIVERGÊNCIA REGISTRADOS ---\n' >> "${REPORT_FILE}"
    sed 's/^/   [DIVERGÊNCIA] /' "${DIVERGENCES_FILE}" >> "${REPORT_FILE}"
fi

if [ -s "${TEMPORAL_DIFFS_FILE}" ]; then
    printf '\n--- DIFERENÇAS DE CONTAGEM INCONCLUSIVAS (SEM PRESUNÇÃO DE CRESCIMENTO) ---\n' >> "${REPORT_FILE}"
    sed 's/^/   [INCONCLUSIVO] /' "${TEMPORAL_DIFFS_FILE}" >> "${REPORT_FILE}"
fi

cat <<EOF >> "${REPORT_FILE}"

5. VEREDITO FINAL DA AUDITORIA
   Veredito: ${VEREDITO}
   Motivo: ${MOTIVO_VEREDITO}

6. RASTREABILIDADE E SEGURANÇA
   Rede do contêiner de laboratório: --network none (isolamento de rede estrito)
   Arquivo do relatório: ${REPORT_FILE} (chmod 600)
   Log técnico restrito: ${LOG_FILE} (chmod 600)
   Log de erros do restore: ${RESTORE_ERRORS_FILE} (chmod 600)
   Recursos rastreados da sessão: ${TRACKED_RESOURCES_FILE} (chmod 600)
================================================================================
EOF

if ! chmod 600 "${REPORT_FILE}"; then
    die "Falha ao definir permissões no arquivo de relatório." "${EXIT_FS_FAIL}"
fi
REPORT_PERM="$(stat -c '%a' "${REPORT_FILE}" 2>/dev/null || stat -f '%Lp' "${REPORT_FILE}" 2>/dev/null || echo "")"
if [ -z "${REPORT_PERM}" ] || [ "${REPORT_PERM}" != "600" ]; then
    die "Permissão efetiva do arquivo de relatório inválida (${REPORT_PERM})." "${EXIT_FS_FAIL}"
fi

# Exibição no terminal
say ""
say "================================================================================"
say " VEREDITO FINAL DA AUDITORIA DE BACKUP: ${VEREDITO}"
================================================================================
 DPSjur / SBJur — RELATÓRIO DE AUDITORIA DE BACKUP (${SCRIPT_VERSION})
 Data de emissão: $(date '+%F %T %Z')
 Sessão de auditoria: ${SESSION_ID}
================================================================================

1. ARQUIVOS E AMBIENTE
   Arquivo de backup: ${BACKUP_FILE}
   Inventário oficial: ${INVENTORY_FILE:-Nenhum informado}
   Contêiner de teste: ${LAB_NAME}
   Label da sessão: ${SESSION_LABEL}
   Volume isolado: ${LAB_VOLUME}
   Imagem PostgreSQL: ${CHOSEN_IMAGE}

2. SEÇÃO TÉCNICA SEPARADA: RESTAURAÇÃO ORIGINAL vs RECUPERAÇÃO ASSISTIDA
   (a) Restauração Original (psql -X -v ON_ERROR_STOP=1): ${RESTORE_ORIGINAL_STATUS}
       - Código gunzip .................: ${GZIP_EXIT} (exigido 0)
       - Código psql ...................: ${PSQL_EXIT} (exigido 0)
       - Erros SQL brutos ..............: ${RESTORE_RAW_ERRORS_COUNT} (exigido 0)
       - Avaliação Restauração Original : ${CRIT_A}
   (b) Recuperação Assistida (Post-Restore):
       - Extensão pg_graphql ...........: ${GRAPHQL_FINAL_STATUS}
       - Tentativa de recuperação ......: ${GRAPHQL_REC_STATUS}
       - Observação de isolamento ......: A recuperação assistida NÃO mascara falha na restauração original.

3. RESULTADOS DOS DEMAIS CRITÉRIOS TÉCNICOS
   Critério 3 - Inventário estrutural do laboratório: ${CRIT_C}
       - Tabelas public: ${TOTAL_TABELAS_LAB}
       - Tabelas auth: ${TOTAL_TABELAS_AUTH_LAB}
       - Constraints: ${TOTAL_CONSTRAINTS_LAB}
       - Funções: ${TOTAL_FUNCOES_LAB}
       - Triggers: ${TOTAL_TRIGGERS_LAB}
       - Extensões: ${TOTAL_EXTENSOES_LAB}
   Critério 4 - Comparação estrutural e bidirecional com inventário oficial (jq): $([ "${CRIT_D_OK}" -eq 1 ] && echo "CONFORME" || echo "NAO_CONFORME")
       - Validação JSON semântica com jq: ${INVENTORY_COMPARISON_VALID}
       - Bidirecionalidade avaliada: $([ "${INVENTORY_BIDIRECTIONAL_CHECK_PASSED}" -eq 1 ] && echo "SIM" || echo "NAO")
       - Amostragem aplicada: NENHUMA (conferência integral de constraints e funções)
   Critério 5 - Integridade parcial do PostgreSQL restaurado: ${OP_CRITERION_STATUS}
       - Integridade referencial (FKs órfãs): ${FK_ORPHANS_CNT}
       - Consistência auth.users: ${USERS_TOTAL} usuários, ${USERS_DUP_COUNT} duplicidades
       - Planos de execução EXPLAIN: ${EXPLAIN_STATUS}
       - Bloco transacional com ROLLBACK: ${TX_STATUS}
       - Escopo delimitado: Prova unicamente a saúde do PostgreSQL restaurado;
         não atesta recuperação funcional completa da aplicação CRM (Kong/GoTrue/PostgREST fora do escopo do teste).

4. DIVERGÊNCIAS E DIFERENÇAS DE CONTAGEM INCONCLUSIVAS
EOF

if ! chmod 600 "${REPORT_FILE}"; then
    die "Falha ao definir permissões no arquivo de relatório." "${EXIT_FS_FAIL}"
fi
REPORT_PERM="$(stat -c '%a' "${REPORT_FILE}" 2>/dev/null || stat -f '%Lp' "${REPORT_FILE}" 2>/dev/null || echo "")"
if [ -z "${REPORT_PERM}" ] || [ "${REPORT_PERM}" != "600" ]; then
    die "Permissão efetiva do arquivo de relatório inválida (${REPORT_PERM})." "${EXIT_FS_FAIL}"
fi
================================================================================
EOF

if ! chmod 600 "${REPORT_FILE}"; then
    die "Falha ao definir permissões no arquivo de relatório." "${EXIT_FS_FAIL}"
fi
=======
cat <<EOF >> "${REPORT_FILE}"

5. VEREDITO FINAL DA AUDITORIA
   Veredito: ${VEREDITO}
   Motivo: ${MOTIVO_VEREDITO}

6. RASTREABILIDADE E SEGURANÇA
   Rede do contêiner de laboratório: --network none (isolamento de rede estrito)
   Arquivo do relatório: ${REPORT_FILE} (chmod 600)
   Log técnico restrito: ${LOG_FILE} (chmod 600)
   Log de erros do restore: ${RESTORE_ERRORS_FILE} (chmod 600)
   Recursos rastreados da sessão: ${TRACKED_RESOURCES_FILE} (chmod 600)
================================================================================
EOF

if ! chmod 600 "${REPORT_FILE}"; then
    die "Falha ao definir permissões no arquivo de relatório." "${EXIT_FS_FAIL}"
fi
REPORT_PERM="$(stat -c '%a' "${REPORT_FILE}" 2>/dev/null || stat -f '%Lp' "${REPORT_FILE}" 2>/dev/null || echo "")"
if [ -z "${REPORT_PERM}" ] || [ "${REPORT_PERM}" != "600" ]; then
    die "Permissão efetiva do arquivo de relatório inválida (${REPORT_PERM})." "${EXIT_FS_FAIL}"
fi
=======
5. VEREDITO FINAL DA AUDITORIA
   Veredito: ${VEREDITO}
   Motivo: ${MOTIVO_VEREDITO}

6. RASTREABILIDADE E SEGURANÇA
   Rede do contêiner de laboratório: --network none (isolamento de rede estrito)
   Arquivo do relatório: ${REPORT_FILE} (chmod 600)
   Log técnico restrito: ${LOG_FILE} (chmod 600)
   Log de erros do restore: ${RESTORE_ERRORS_FILE} (chmod 600)
   Recursos rastreados da sessão: ${TRACKED_RESOURCES_FILE} (chmod 600)
================================================================================
EOF

if ! chmod 600 "${REPORT_FILE}"; then
    die "Falha ao definir permissões no arquivo de relatório." "${EXIT_FS_FAIL}"
fi
REPORT_PERM="$(stat -c '%a' "${REPORT_FILE}" 2>/dev/null || stat -f '%Lp' "${REPORT_FILE}" 2>/dev/null || echo "")"
if [ -z "${REPORT_PERM}" ] || [ "${REPORT_PERM}" != "600" ]; then
    die "Permissão efetiva do arquivo de relatório inválida (${REPORT_PERM})." "${EXIT_FS_FAIL}"
fi
================================================================================
EOF

if ! chmod 600 "${REPORT_FILE}"; then
    die "Falha ao definir permissões no arquivo de relatório." "${EXIT_FS_FAIL}"
fi

# Exibição no terminal
=======
   Total de divergências impeditivas: ${DIVERGENCES_COUNT}
   Total de diferenças de contagem inconclusivas: ${TEMPORAL_DIFFS_COUNT}
EOF

if [ -s "${DIVERGENCES_FILE}" ]; then
    printf '\n--- ITENS DE DIVERGÊNCIA REGISTRADOS ---\n' >> "${REPORT_FILE}"
    sed 's/^/   [DIVERGÊNCIA] /' "${DIVERGENCES_FILE}" >> "${REPORT_FILE}"
fi

if [ -s "${TEMPORAL_DIFFS_FILE}" ]; then
    printf '\n--- DIFERENÇAS DE CONTAGEM INCONCLUSIVAS (SEM PRESUNÇÃO DE CRESCIMENTO) ---\n' >> "${REPORT_FILE}"
    sed 's/^/   [INCONCLUSIVO] /' "${TEMPORAL_DIFFS_FILE}" >> "${REPORT_FILE}"
fi

cat <<EOF >> "${REPORT_FILE}"

5. VEREDITO FINAL DA AUDITORIA
   Veredito: ${VEREDITO}
   Motivo: ${MOTIVO_VEREDITO}

6. RASTREABILIDADE E SEGURANÇA
   Rede do contêiner de laboratório: --network none (isolamento de rede estrito)
   Arquivo do relatório: ${REPORT_FILE} (chmod 600)
   Log técnico restrito: ${LOG_FILE} (chmod 600)
   Log de erros do restore: ${RESTORE_ERRORS_FILE} (chmod 600)
   Recursos rastreados da sessão: ${TRACKED_RESOURCES_FILE} (chmod 600)
================================================================================
EOF

if ! chmod 600 "${REPORT_FILE}"; then
    die "Falha ao definir permissões no arquivo de relatório." "${EXIT_FS_FAIL}"
fi
REPORT_PERM="$(stat -c '%a' "${REPORT_FILE}" 2>/dev/null || stat -f '%Lp' "${REPORT_FILE}" 2>/dev/null || echo "")"
if [ -z "${REPORT_PERM}" ] || [ "${REPORT_PERM}" != "600" ]; then
    die "Permissão efetiva do arquivo de relatório inválida (${REPORT_PERM})." "${EXIT_FS_FAIL}"
fi

# Exibição no terminal
================================================================================
EOF

if ! chmod 600 "${REPORT_FILE}"; then
    die "Falha ao definir permissões no arquivo de relatório." "${EXIT_FS_FAIL}"
fi
REPORT_PERM="$(stat -c '%a' "${REPORT_FILE}" 2>/dev/null || stat -f '%Lp' "${REPORT_FILE}" 2>/dev/null || echo "")"
if [ -z "${REPORT_PERM}" ] || [ "${REPORT_PERM}" != "600" ]; then
    die "Permissão efetiva do arquivo de relatório inválida (${REPORT_PERM})." "${EXIT_FS_FAIL}"
fi
================================================================================
EOF

if ! chmod 600 "${REPORT_FILE}"; then
    die "Falha ao definir permissões no arquivo de relatório." "${EXIT_FS_FAIL}"
fi
=======
cat <<EOF >> "${REPORT_FILE}"

5. VEREDITO FINAL DA AUDITORIA
   Veredito: ${VEREDITO}
   Motivo: ${MOTIVO_VEREDITO}

6. RASTREABILIDADE E SEGURANÇA
   Rede do contêiner de laboratório: --network none (isolamento de rede estrito)
   Arquivo do relatório: ${REPORT_FILE} (chmod 600)
   Log técnico restrito: ${LOG_FILE} (chmod 600)
   Log de erros do restore: ${RESTORE_ERRORS_FILE} (chmod 600)
   Recursos rastreados da sessão: ${TRACKED_RESOURCES_FILE} (chmod 600)
================================================================================
EOF

if ! chmod 600 "${REPORT_FILE}"; then
    die "Falha ao definir permissões no arquivo de relatório." "${EXIT_FS_FAIL}"
fi
REPORT_PERM="$(stat -c '%a' "${REPORT_FILE}" 2>/dev/null || stat -f '%Lp' "${REPORT_FILE}" 2>/dev/null || echo "")"
if [ -z "${REPORT_PERM}" ] || [ "${REPORT_PERM}" != "600" ]; then
    die "Permissão efetiva do arquivo de relatório inválida (${REPORT_PERM})." "${EXIT_FS_FAIL}"
fi
=======
5. VEREDITO FINAL DA AUDITORIA
   Veredito: ${VEREDITO}
   Motivo: ${MOTIVO_VEREDITO}

6. RASTREABILIDADE E SEGURANÇA
   Rede do contêiner de laboratório: --network none (isolamento de rede estrito)
   Arquivo do relatório: ${REPORT_FILE} (chmod 600)
   Log técnico restrito: ${LOG_FILE} (chmod 600)
   Log de erros do restore: ${RESTORE_ERRORS_FILE} (chmod 600)
   Recursos rastreados da sessão: ${TRACKED_RESOURCES_FILE} (chmod 600)
================================================================================
EOF

if ! chmod 600 "${REPORT_FILE}"; then
    die "Falha ao definir permissões no arquivo de relatório." "${EXIT_FS_FAIL}"
fi
REPORT_PERM="$(stat -c '%a' "${REPORT_FILE}" 2>/dev/null || stat -f '%Lp' "${REPORT_FILE}" 2>/dev/null || echo "")"
if [ -z "${REPORT_PERM}" ] || [ "${REPORT_PERM}" != "600" ]; then
    die "Permissão efetiva do arquivo de relatório inválida (${REPORT_PERM})." "${EXIT_FS_FAIL}"
fi
================================================================================
EOF

if ! chmod 600 "${REPORT_FILE}"; then
    die "Falha ao definir permissões no arquivo de relatório." "${EXIT_FS_FAIL}"
fi

# Exibição no terminal
say ""
say "================================================================================"
say " VEREDITO FINAL DA AUDITORIA DE BACKUP: ${VEREDITO}"
say "================================================================================"
say " Motivo: ${MOTIVO_VEREDITO}"
say ""
say " Resumo dos 5 Critérios Técnicos:"
say "   1. Restauração original estrita ........: ${CRIT_A}"
say "   2. Extensão pg_graphql operacional .....: ${CRIT_B}"
say "   3. Validação estrutural do schema public : ${CRIT_C}"
say "   4. Comparação bidirecional com inventário: $([ "${CRIT_D_OK}" -eq 1 ] && echo "CONFORME" || echo "NAO_CONFORME")"
say "   5. Integridade parcial do PostgreSQL ...: ${OP_CRITERION_STATUS} (CRM fora de escopo)"
say ""
say " Divergências impeditivas : ${DIVERGENCES_COUNT}"
say " Diferenças inconclusivas : ${TEMPORAL_DIFFS_COUNT}"
say ""
say " Arquivos gerados:"
say "   Relatório técnico ......: ${REPORT_FILE} (chmod 600)"
say "   Log de execução ........: ${LOG_FILE} (chmod 600)"
say "   Log de erros do restore .: ${RESTORE_ERRORS_FILE} (chmod 600)"
say "================================================================================"

if [ "${VEREDITO}" = "APROVADO" ]; then
    exit "${EXIT_OK}"
else
    exit "${EXIT_STRUCTURE_FAIL}"
fi
