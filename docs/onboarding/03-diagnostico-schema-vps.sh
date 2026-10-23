#!/usr/bin/env bash
# ==============================================================================
# DPSjur / SBJur - Script de Diagnóstico de Schema no VPS (EasyPanel / Docker)
# Script: docs/onboarding/03-diagnostico-schema-vps.sh
# Versão: v1.0.0
# ==============================================================================
# Finalidade (SOMENTE LEITURA - NÃO MODIFICA NADA):
# 1. Descobrir contêiner Docker real do PostgreSQL, usuário funcional e banco ativo no VPS.
# 2. Diagnosticar a presença e tipo das colunas críticas reportadas em toasts de erro:
#    - public.settings."onboardingChecklist"
#    - public.clients.created_by
#    - public.cases.created_by
# 3. Conferir se o trigger obsoleto 'on_client_created' ainda existe em public.clients.
# 4. Imprimir relatório visual com diagnóstico claro para envio ao suporte.
#
# Execução no terminal do VPS (como root - comando único sem pipe):
#   curl -sSL "https://raw.githubusercontent.com/dowspaulo-wq/migra--o-sistema-legal-desk-fg93i2kgl/main/docs/onboarding/03-diagnostico-schema-vps.sh" -o /root/03-diagnostico-schema-vps.sh && bash /root/03-diagnostico-schema-vps.sh
# ==============================================================================

set -uo pipefail

SCRIPT_VERSION="v1.0.0"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${BOLD}${BLUE}=====================================================================${NC}"
echo -e "${BOLD}${BLUE} DPSjur - Diagnóstico de Schema do PostgreSQL no VPS                 ${NC}"
echo -e "${BOLD}${BLUE} Versão: ${SCRIPT_VERSION} (Somente Leitura)                              ${NC}"
echo -e "${BOLD}${BLUE}=====================================================================${NC}"
echo -e "Data: $(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || true)"
echo -e "Host: $(hostname 2>/dev/null || echo 'VPS')"
echo -e "${BOLD}${BLUE}=====================================================================${NC}\n"

# Helper para executar query psql simples (retorno limpo)
run_container_psql() {
    local container="$1"
    local user="$2"
    local pass="$3"
    local dbname="$4"
    local query="$5"

    if [ -n "$pass" ]; then
        docker exec -i -e PGPASSWORD="$pass" "$container" psql -U "$user" -d "$dbname" -tAc "$query" 2>/dev/null || true
    else
        docker exec -i "$container" psql -U "$user" -d "$dbname" -tAc "$query" 2>/dev/null || true
    fi
}

# ------------------------------------------------------------------------------
# 1. Localizar contêineres PostgreSQL em execução no VPS
# ------------------------------------------------------------------------------
echo -e "${BOLD}${CYAN}[Etapa 1/3] Varrendo contêineres PostgreSQL no VPS...${NC}"

ALL_DB_CONTAINERS=()
while IFS= read -r c_name; do
    [ -z "$c_name" ] && continue
    if [[ "$c_name" =~ (frontend|web|traefik|redis|kong|edge-runtime|functions|meta|adminer|nginx) ]]; then
        continue
    fi
    ALL_DB_CONTAINERS+=("$c_name")
done < <(docker ps --format '{{.Names}}' 2>/dev/null | grep -Ei 'db|postgres|postg' || true)

if [ ${#ALL_DB_CONTAINERS[@]} -eq 0 ]; then
    echo -e "${RED}❌ Nenhum contêiner PostgreSQL detectado!${NC}"
    echo "Contêineres em execução no VPS:"
    docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}' || true
    exit 1
fi

REAL_CONTAINER=""
REAL_USER=""
REAL_PASS=""
REAL_DB=""
MAX_RECORDS=-1

for c in "${ALL_DB_CONTAINERS[@]}"; do
    ENV_USER=$(docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "$c" 2>/dev/null | grep -E '^POSTGRES_USER=' | head -n 1 | cut -d= -f2- || true)
    [ -z "$ENV_USER" ] && ENV_USER=$(docker exec "$c" env 2>/dev/null | grep -E '^POSTGRES_USER=' | head -n 1 | cut -d= -f2- || true)

    ENV_PASS=$(docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "$c" 2>/dev/null | grep -E '^POSTGRES_PASSWORD=' | head -n 1 | cut -d= -f2- || true)
    [ -z "$ENV_PASS" ] && ENV_PASS=$(docker exec "$c" env 2>/dev/null | grep -E '^POSTGRES_PASSWORD=' | head -n 1 | cut -d= -f2- || true)

    ENV_DB=$(docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "$c" 2>/dev/null | grep -E '^POSTGRES_DB=' | head -n 1 | cut -d= -f2- || true)
    [ -z "$ENV_DB" ] && ENV_DB=$(docker exec "$c" env 2>/dev/null | grep -E '^POSTGRES_DB=' | head -n 1 | cut -d= -f2- || true)

    CAND_USERS=()
    [ -n "$ENV_USER" ] && CAND_USERS+=("$ENV_USER")
    CAND_USERS+=("supabase_admin" "postgres" "Doug")

    UNIQ_USERS=()
    for u in "${CAND_USERS[@]}"; do
        [[ " ${UNIQ_USERS[*]} " =~ " ${u} " ]] || UNIQ_USERS+=("$u")
    done

    WORKING_USER=""
    WORKING_PASS="$ENV_PASS"
    DATABASES_LIST=""

    for u in "${UNIQ_USERS[@]}"; do
        for cand_db in "${ENV_DB:-}" "postgres" "dpsjur" "template1"; do
            [ -z "$cand_db" ] && continue
            CHECK_ONE=$(run_container_psql "$c" "$u" "$WORKING_PASS" "$cand_db" "SELECT 1;")
            if [ "$CHECK_ONE" = "1" ]; then
                WORKING_USER="$u"
                DB_QUERY_OUT=$(run_container_psql "$c" "$u" "$WORKING_PASS" "$cand_db" "SELECT datname FROM pg_database WHERE datistemplate = false AND datname NOT IN ('rdsadmin');")
                if [ -n "$DB_QUERY_OUT" ]; then
                    DATABASES_LIST="$DB_QUERY_OUT"
                else
                    DATABASES_LIST="$cand_db"
                fi
                break 2
            fi
        done
    done

    [ -z "$WORKING_USER" ] && continue

    DB_ARRAY=()
    while IFS= read -r db_item; do
        [ -z "$db_item" ] && continue
        DB_ARRAY+=("$db_item")
    done <<< "$DATABASES_LIST"

    [ ${#DB_ARRAY[@]} -eq 0 ] && [ -n "$ENV_DB" ] && DB_ARRAY+=("$ENV_DB")

    for dbname in "${DB_ARRAY[@]}"; do
        CLIENTS_EXISTS=$(run_container_psql "$c" "$WORKING_USER" "$WORKING_PASS" "$dbname" "SELECT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='clients');")
        if [ "$CLIENTS_EXISTS" = "t" ]; then
            RAW_CNT=$(run_container_psql "$c" "$WORKING_USER" "$WORKING_PASS" "$dbname" "SELECT count(*) FROM public.clients;")
            CNT=$(echo "$RAW_CNT" | tr -dc '0-9' || echo 0)
            [ -z "$CNT" ] && CNT=0
            if [ "$CNT" -gt "$MAX_RECORDS" ]; then
                MAX_RECORDS="$CNT"
                REAL_CONTAINER="$c"
                REAL_USER="$WORKING_USER"
                REAL_PASS="$WORKING_PASS"
                REAL_DB="$dbname"
            fi
        fi
    done
done

if [ -z "$REAL_CONTAINER" ]; then
    echo -e "${RED}❌ Não foi possível determinar o contêiner com as tabelas de negócio do DPSjur!${NC}"
    exit 1
fi

echo -e "   - Contêiner detectado: ${GREEN}${REAL_CONTAINER}${NC}"
echo -e "   - Usuário detectado:   ${GREEN}${REAL_USER}${NC}"
echo -e "   - Banco detectado:     ${GREEN}${REAL_DB}${NC}"
echo -e "   - Clientes no banco:   ${GREEN}${MAX_RECORDS} registros em public.clients${NC}"

# ------------------------------------------------------------------------------
# 2. Diagnóstico de PostgREST
# ------------------------------------------------------------------------------
echo -e "\n${BOLD}${CYAN}[Etapa 2/3] Verificando serviço PostgREST...${NC}"
PGRST_CONTAINER=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -Ei 'supa?base.*rest|postgrest' | head -n 1 || true)
if [ -n "$PGRST_CONTAINER" ]; then
    echo -e "   - Contêiner PostgREST: ${GREEN}${PGRST_CONTAINER}${NC}"
else
    echo -e "   - Contêiner PostgREST: ${YELLOW}Não encontrado pelo padrão 'rest|postgrest'${NC}"
fi

# ------------------------------------------------------------------------------
# 3. Diagnóstico detalhado de schema (colunas críticas e trigger)
# ------------------------------------------------------------------------------
echo -e "\n${BOLD}${CYAN}[Etapa 3/3] Consultando schema no PostgreSQL...${NC}"

# settings.onboardingChecklist
COL_ONBOARDING=$(run_container_psql "$REAL_CONTAINER" "$REAL_USER" "$REAL_PASS" "$REAL_DB" "SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'settings' AND column_name = 'onboardingChecklist');")
COL_ONBOARDING_TYPE=$(run_container_psql "$REAL_CONTAINER" "$REAL_USER" "$REAL_PASS" "$REAL_DB" "SELECT data_type FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'settings' AND column_name = 'onboardingChecklist';")
SETTINGS_COUNT=$(run_container_psql "$REAL_CONTAINER" "$REAL_USER" "$REAL_PASS" "$REAL_DB" "SELECT count(*) FROM public.settings;")
SETTINGS_CHECKLIST_LEN=$(run_container_psql "$REAL_CONTAINER" "$REAL_USER" "$REAL_PASS" "$REAL_DB" "SELECT jsonb_array_length(\"onboardingChecklist\") FROM public.settings WHERE \"onboardingChecklist\" IS NOT NULL LIMIT 1;")

# clients.created_by
COL_CLIENTS_CB=$(run_container_psql "$REAL_CONTAINER" "$REAL_USER" "$REAL_PASS" "$REAL_DB" "SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'clients' AND column_name = 'created_by');")
COL_CLIENTS_CB_TYPE=$(run_container_psql "$REAL_CONTAINER" "$REAL_USER" "$REAL_PASS" "$REAL_DB" "SELECT data_type FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'clients' AND column_name = 'created_by';")
CLIENTS_WITH_CB=$(run_container_psql "$REAL_CONTAINER" "$REAL_USER" "$REAL_PASS" "$REAL_DB" "SELECT count(*) FROM public.clients WHERE created_by IS NOT NULL;")

# cases.created_by
COL_CASES_CB=$(run_container_psql "$REAL_CONTAINER" "$REAL_USER" "$REAL_PASS" "$REAL_DB" "SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'cases' AND column_name = 'created_by');")
COL_CASES_CB_TYPE=$(run_container_psql "$REAL_CONTAINER" "$REAL_USER" "$REAL_PASS" "$REAL_DB" "SELECT data_type FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'cases' AND column_name = 'created_by';")
CASES_COUNT=$(run_container_psql "$REAL_CONTAINER" "$REAL_USER" "$REAL_PASS" "$REAL_DB" "SELECT count(*) FROM public.cases;")
CASES_WITH_CB=$(run_container_psql "$REAL_CONTAINER" "$REAL_USER" "$REAL_PASS" "$REAL_DB" "SELECT count(*) FROM public.cases WHERE created_by IS NOT NULL;")

# Trigger on_client_created
TRIGGER_STATUS=$(run_container_psql "$REAL_CONTAINER" "$REAL_USER" "$REAL_PASS" "$REAL_DB" "SELECT EXISTS (SELECT 1 FROM information_schema.triggers WHERE event_object_table = 'clients' AND trigger_name = 'on_client_created');")

echo -e "\n${BOLD}${BLUE}=====================================================================${NC}"
echo -e "${BOLD}${BLUE}                    RELATÓRIO DO SCHEMA NO VPS                       ${NC}"
echo -e "${BOLD}${BLUE}=====================================================================${NC}"
echo -e "Contêiner: ${BOLD}${REAL_CONTAINER}${NC} | Usuário: ${BOLD}${REAL_USER}${NC} | Banco: ${BOLD}${REAL_DB}${NC}"
echo -e "---------------------------------------------------------------------"

# 1. settings.onboardingChecklist
if [ "$COL_ONBOARDING" = "t" ]; then
    echo -e "1. settings.\"onboardingChecklist\": ${GREEN}${BOLD}EXISTE${NC} (tipo: ${COL_ONBOARDING_TYPE}, etapas no modelo: ${SETTINGS_CHECKLIST_LEN:-0})"
else
    echo -e "1. settings.\"onboardingChecklist\": ${RED}${BOLD}NÃO EXISTE${NC} ❌"
fi

# 2. clients.created_by
if [ "$COL_CLIENTS_CB" = "t" ]; then
    echo -e "2. clients.created_by:             ${GREEN}${BOLD}EXISTE${NC} (tipo: ${COL_CLIENTS_CB_TYPE}, preenchidos: ${CLIENTS_WITH_CB:-0}/${MAX_RECORDS})"
else
    echo -e "2. clients.created_by:             ${RED}${BOLD}NÃO EXISTE${NC} ❌"
fi

# 3. cases.created_by
if [ "$COL_CASES_CB" = "t" ]; then
    echo -e "3. cases.created_by:               ${GREEN}${BOLD}EXISTE${NC} (tipo: ${COL_CASES_CB_TYPE}, preenchidos: ${CASES_WITH_CB:-0}/${CASES_COUNT:-0})"
else
    echo -e "3. cases.created_by:               ${RED}${BOLD}NÃO EXISTE${NC} ❌"
fi

# 4. trigger on_client_created
if [ "$TRIGGER_STATUS" = "t" ]; then
    echo -e "4. trigger on_client_created:      ${YELLOW}${BOLD}AINDA EXISTE${NC} ⚠️ (deve ser removido para não duplicar tarefas no cadastro de cliente)"
else
    echo -e "4. trigger on_client_created:      ${GREEN}${BOLD}REMOVIDO / AUSENTE [OK]${NC}"
fi

echo -e "${BOLD}${BLUE}=====================================================================${NC}"

if [ "$COL_ONBOARDING" = "t" ] && [ "$COL_CLIENTS_CB" = "t" ] && [ "$COL_CASES_CB" = "t" ]; then
    echo -e "\n${BOLD}${GREEN}✅ Todas as 3 colunas de onboarding e auditoria existem no banco do VPS!${NC}"
    echo -e "Se a aplicação web ainda acusar erro de schema cache no VPS, basta recarregar o PostgREST:"
    echo -e "  docker restart ${PGRST_CONTAINER:-<nome-do-conteiner-postgrest>}"
else
    echo -e "\n${BOLD}${YELLOW}⚠️ Uma ou mais colunas ainda não existem no banco do VPS.${NC}"
    echo -e "Para aplicar a migração correta, execute:"
    echo -e "  bash docs/onboarding/01-adicionar-onboarding-checklist-settings.sh"
fi
echo -e "${BOLD}${BLUE}=====================================================================${NC}\n"
