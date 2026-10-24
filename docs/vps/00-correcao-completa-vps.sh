#!/usr/bin/env bash
# ==============================================================================
# DPSjur / SBJur - Correção Completa e Consolidada do Banco no VPS (EasyPanel)
# Script: docs/vps/00-correcao-completa-vps.sh
# Versão: v1.4.0
# ==============================================================================
# Finalidade (Consolidação em um único script idempotente):
# 1. Eleição do banco de produção real (varre contêineres Docker do Supabase,
#    testa conexão e elege o banco com dados reais baseado em public.cases e
#    public.clients — NUNCA o banco vazio errado como "Doug/dpsjur").
# 2. Execução das correções de schema e dados em arquivo SQL temporário via
#    psql -f (sem expansão indevida de variáveis ou $ pelo bash):
#    - ALTER TABLE public.cases ADD COLUMN IF NOT EXISTS "noFees" boolean NOT NULL DEFAULT false;
#    - ALTER TABLE public.cases ADD COLUMN IF NOT EXISTS "created_by" text (ou uuid se profiles existir);
#    - ALTER TABLE public.clients ADD COLUMN IF NOT EXISTS "created_by" text (ou uuid se profiles existir);
#    - ALTER TABLE public.settings ADD COLUMN IF NOT EXISTS "onboardingChecklist" jsonb;
#    - Remoção do trigger obsoleto on_client_created e function handle_new_client_tasks;
#    - Preenchimento do onboardingChecklist padrão de 8 etapas caso NULL;
#    - Preenchimento retroativo seguro de created_by herdando do "responsibleId";
#    - Garantia de permissões e RLS para as tabelas modificadas.
# 3. Reload completo do cache do PostgREST via NOTIFY pgrst e restart do contêiner PostgREST.
# 4. Conferência final honesta com [OK] / [FALHA] de consultas reais no MESMO banco
#    eleito, garantindo que o status final só é de sucesso se tudo estiver [OK].
#
# Execução no terminal do VPS (como root - comando único sem pipe):
#   curl -sSL "https://raw.githubusercontent.com/dowspaulo-wq/migra--o-sistema-legal-desk-fg93i2kgl/main/docs/vps/00-correcao-completa-vps.sh" -o /root/00-correcao-completa-vps.sh && bash /root/00-correcao-completa-vps.sh
# ==============================================================================

set -uo pipefail

SCRIPT_VERSION="v1.4.0"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${BOLD}${BLUE}=====================================================================${NC}"
echo -e "${BOLD}${BLUE} DPSjur - Correção Completa e Consolidada do Banco no VPS            ${NC}"
echo -e "${BOLD}${BLUE} Versão: ${SCRIPT_VERSION}                                                     ${NC}"
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
# 1. Varredura e eleição do contêiner Docker real do PostgreSQL e do banco ativo
# ------------------------------------------------------------------------------
echo -e "${BOLD}${CYAN}[1/4] Varrendo contêineres PostgreSQL no VPS e elegendo banco de produção...${NC}"

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
MAX_CASES_RECORDS=-1
MAX_CLIENTS_RECORDS=-1

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
        CASES_EXISTS=$(run_container_psql "$c" "$WORKING_USER" "$WORKING_PASS" "$dbname" "SELECT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='cases');")
        CLIENTS_EXISTS=$(run_container_psql "$c" "$WORKING_USER" "$WORKING_PASS" "$dbname" "SELECT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='clients');")

        CASES_CNT=0
        CLIENTS_CNT=0

        if [ "$CASES_EXISTS" = "t" ]; then
            RAW_CASES_CNT=$(run_container_psql "$c" "$WORKING_USER" "$WORKING_PASS" "$dbname" "SELECT count(*) FROM public.cases;")
            CASES_CNT=$(echo "$RAW_CASES_CNT" | tr -dc '0-9' || echo 0)
            [ -z "$CASES_CNT" ] && CASES_CNT=0
        fi

        if [ "$CLIENTS_EXISTS" = "t" ]; then
            RAW_CLIENTS_CNT=$(run_container_psql "$c" "$WORKING_USER" "$WORKING_PASS" "$dbname" "SELECT count(*) FROM public.clients;")
            CLIENTS_CNT=$(echo "$RAW_CLIENTS_CNT" | tr -dc '0-9' || echo 0)
            [ -z "$CLIENTS_CNT" ] && CLIENTS_CNT=0
        fi

        # Eleição prioritária pelo maior volume de public.cases (e desempate por public.clients)
        # Ignora bases vazias como "Doug/dpsjur"
        if [ "$CASES_CNT" -gt "$MAX_CASES_RECORDS" ] || { [ "$CASES_CNT" -eq "$MAX_CASES_RECORDS" ] && [ "$CLIENTS_CNT" -gt "$MAX_CLIENTS_RECORDS" ]; }; then
            MAX_CASES_RECORDS="$CASES_CNT"
            MAX_CLIENTS_RECORDS="$CLIENTS_CNT"
            REAL_CONTAINER="$c"
            REAL_USER="$WORKING_USER"
            REAL_PASS="$WORKING_PASS"
            REAL_DB="$dbname"
        fi
    done
done

if [ -z "$REAL_CONTAINER" ]; then
    echo -e "${RED}❌ Não foi possível determinar o contêiner com as tabelas de negócio do DPSjur!${NC}"
    exit 1
fi

echo -e "   - Contêiner eleito:    ${GREEN}${REAL_CONTAINER}${NC}"
echo -e "   - Usuário eleito:      ${GREEN}${REAL_USER}${NC}"
echo -e "   - Banco eleito:        ${GREEN}${REAL_DB}${NC}"
echo -e "   - Processos no banco:  ${GREEN}${MAX_CASES_RECORDS} registros em public.cases${NC}"
echo -e "   - Clientes no banco:   ${GREEN}${MAX_CLIENTS_RECORDS} registros em public.clients${NC}"

# Detecção do contêiner do PostgREST
PGRST_CONTAINER=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -Ei 'supa?base.*rest|postgrest' | head -n 1 || true)
if [ -n "$PGRST_CONTAINER" ]; then
    echo -e "   - Contêiner PostgREST: ${GREEN}${PGRST_CONTAINER}${NC}"
else
    echo -e "   - Contêiner PostgREST: ${YELLOW}Não encontrado diretamente por regex rest|postgrest${NC}"
fi

# Variáveis unificadas para execução
DB_CONTAINER="$REAL_CONTAINER"
DB_USER="$REAL_USER"
DB_NAME="$REAL_DB"
LOCAL_DB_PASSWORD="$REAL_PASS"

run_sql_query() {
    local sql_query="$1"
    local raw_output
    local exit_code=0

    if [ -n "$LOCAL_DB_PASSWORD" ]; then
        raw_output=$(docker exec -i -e PGPASSWORD="$LOCAL_DB_PASSWORD" "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 -tAc "$sql_query" 2>&1) || exit_code=$?
    else
        raw_output=$(docker exec -i "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 -tAc "$sql_query" 2>&1) || exit_code=$?
    fi

    if [ $exit_code -ne 0 ] || [[ "$raw_output" =~ (ERROR:|FATAL:|PANIC:|psql: error:) ]]; then
        echo -e "${RED}[ERRO PSQL] Falha ao executar: ${sql_query}${NC}" >&2
        echo -e "${RED}${raw_output}${NC}" >&2
        return $exit_code
    fi

    echo "$raw_output"
}

# ------------------------------------------------------------------------------
# 2. Execução da migração SQL consolidada via arquivo temporário (docker cp + psql -f)
# ------------------------------------------------------------------------------
echo -e "\n${BOLD}${CYAN}[2/4] Aplicando SQL consolidado via arquivo temporário no banco eleito...${NC}"

SQL_TEMP_HOST=$(mktemp /tmp/correcao_completa_vps_XXXXXX.sql)
cat << 'EOF_MIGRATION_SQL' > "$SQL_TEMP_HOST"
BEGIN;

DO $$
DECLARE
    v_has_profiles boolean := false;
BEGIN
    -- Verifica se tabela public.profiles existe para decidir tipo de created_by (uuid FK ou text)
    SELECT EXISTS (
        SELECT 1 FROM information_schema.tables 
        WHERE table_schema = 'public' AND table_name = 'profiles'
    ) INTO v_has_profiles;

    ---------------------------------------------------------------------------
    -- 1. ALTER TABLE public.cases ADD COLUMN IF NOT EXISTS "noFees" boolean NOT NULL DEFAULT false;
    ---------------------------------------------------------------------------
    IF EXISTS (
        SELECT 1 FROM information_schema.tables 
        WHERE table_schema = 'public' AND table_name = 'cases'
    ) THEN
        IF NOT EXISTS (
            SELECT 1 FROM information_schema.columns 
            WHERE table_schema = 'public' AND table_name = 'cases' AND column_name = 'noFees'
        ) THEN
            ALTER TABLE public.cases ADD COLUMN "noFees" boolean NOT NULL DEFAULT false;
            RAISE NOTICE 'Coluna cases.noFees adicionada com sucesso.';
        ELSE
            ALTER TABLE public.cases ALTER COLUMN "noFees" SET DEFAULT false;
            RAISE NOTICE 'Coluna cases.noFees já existe.';
        END IF;

        UPDATE public.cases SET "noFees" = false WHERE "noFees" IS NULL;
        COMMENT ON COLUMN public.cases."noFees" IS 'Indica se o processo/subprocesso não gera honorários advocatícios';
    ELSE
        RAISE NOTICE 'Aviso: Tabela public.cases não foi encontrada no banco!';
    END IF;

    ---------------------------------------------------------------------------
    -- 2. ALTER TABLE public.cases ADD COLUMN IF NOT EXISTS "created_by" ...
    ---------------------------------------------------------------------------
    IF EXISTS (
        SELECT 1 FROM information_schema.tables 
        WHERE table_schema = 'public' AND table_name = 'cases'
    ) THEN
        IF NOT EXISTS (
            SELECT 1 FROM information_schema.columns 
            WHERE table_schema = 'public' AND table_name = 'cases' AND column_name = 'created_by'
        ) THEN
            IF v_has_profiles THEN
                ALTER TABLE public.cases ADD COLUMN created_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL;
            ELSE
                ALTER TABLE public.cases ADD COLUMN created_by text;
            END IF;
            CREATE INDEX IF NOT EXISTS idx_cases_created_by ON public.cases(created_by);
            RAISE NOTICE 'Coluna cases.created_by adicionada com sucesso.';
        ELSE
            RAISE NOTICE 'Coluna cases.created_by já existe.';
        END IF;

        -- Preenchimento retroativo seguro herdando de responsibleId
        UPDATE public.cases
        SET created_by = "responsibleId"
        WHERE created_by IS NULL AND "responsibleId" IS NOT NULL;
    END IF;

    ---------------------------------------------------------------------------
    -- 3. ALTER TABLE public.clients ADD COLUMN IF NOT EXISTS "created_by" ...
    ---------------------------------------------------------------------------
    IF EXISTS (
        SELECT 1 FROM information_schema.tables 
        WHERE table_schema = 'public' AND table_name = 'clients'
    ) THEN
        IF NOT EXISTS (
            SELECT 1 FROM information_schema.columns 
            WHERE table_schema = 'public' AND table_name = 'clients' AND column_name = 'created_by'
        ) THEN
            IF v_has_profiles THEN
                ALTER TABLE public.clients ADD COLUMN created_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL;
            ELSE
                ALTER TABLE public.clients ADD COLUMN created_by text;
            END IF;
            CREATE INDEX IF NOT EXISTS idx_clients_created_by ON public.clients(created_by);
            RAISE NOTICE 'Coluna clients.created_by adicionada com sucesso.';
        ELSE
            RAISE NOTICE 'Coluna clients.created_by já existe.';
        END IF;

        -- Preenchimento retroativo seguro herdando de responsibleId
        UPDATE public.clients
        SET created_by = "responsibleId"
        WHERE created_by IS NULL AND "responsibleId" IS NOT NULL;
    ELSE
        RAISE NOTICE 'Aviso: Tabela public.clients não foi encontrada no banco!';
    END IF;

    ---------------------------------------------------------------------------
    -- 4. ALTER TABLE public.settings ADD COLUMN IF NOT EXISTS "onboardingChecklist" jsonb;
    -- 6. Preencher registros NULL com as 8 etapas padrão do checklist
    ---------------------------------------------------------------------------
    IF EXISTS (
        SELECT 1 FROM information_schema.tables 
        WHERE table_schema = 'public' AND table_name = 'settings'
    ) THEN
        IF NOT EXISTS (
            SELECT 1 FROM information_schema.columns 
            WHERE table_schema = 'public' AND table_name = 'settings' AND column_name = 'onboardingChecklist'
        ) THEN
            ALTER TABLE public.settings ADD COLUMN "onboardingChecklist" jsonb DEFAULT '[
                {"id": "step-1", "title": "Cadastrar cliente", "order": 1},
                {"id": "step-2", "title": "Cadastrar processo(s)", "order": 2},
                {"id": "step-3", "title": "Coletar documentos", "order": 3},
                {"id": "step-4", "title": "Tratar documentos (qualidade/PDFs)", "order": 4},
                {"id": "step-5", "title": "Redigir procuração", "order": 5},
                {"id": "step-6", "title": "Redigir contrato", "order": 6},
                {"id": "step-7", "title": "Redigir declaração de hipossuficiência", "order": 7},
                {"id": "step-8", "title": "Monitorar assinaturas", "order": 8}
            ]'::jsonb;
            RAISE NOTICE 'Coluna settings.onboardingChecklist adicionada com sucesso.';
        ELSE
            RAISE NOTICE 'Coluna settings.onboardingChecklist já existe.';
        END IF;

        -- Preenchimento se estiver NULL
        UPDATE public.settings
        SET "onboardingChecklist" = '[
            {"id": "step-1", "title": "Cadastrar cliente", "order": 1},
            {"id": "step-2", "title": "Cadastrar processo(s)", "order": 2},
            {"id": "step-3", "title": "Coletar documentos", "order": 3},
            {"id": "step-4", "title": "Tratar documentos (qualidade/PDFs)", "order": 4},
            {"id": "step-5", "title": "Redigir procuração", "order": 5},
            {"id": "step-6", "title": "Redigir contrato", "order": 6},
            {"id": "step-7", "title": "Redigir declaração de hipossuficiência", "order": 7},
            {"id": "step-8", "title": "Monitorar assinaturas", "order": 8}
        ]'::jsonb
        WHERE "onboardingChecklist" IS NULL;

        -- RLS para settings
        ALTER TABLE public.settings ENABLE ROW LEVEL SECURITY;
        DROP POLICY IF EXISTS "authenticated_select_settings" ON public.settings;
        CREATE POLICY "authenticated_select_settings" ON public.settings
            FOR SELECT TO authenticated USING (true);
        DROP POLICY IF EXISTS "authenticated_update_settings" ON public.settings;
        CREATE POLICY "authenticated_update_settings" ON public.settings
            FOR UPDATE TO authenticated USING (true) WITH CHECK (true);
    ELSE
        RAISE NOTICE 'Aviso: Tabela public.settings não foi encontrada no banco!';
    END IF;

    ---------------------------------------------------------------------------
    -- 5. Remoção do trigger obsoleto on_client_created e function handle_new_client_tasks
    ---------------------------------------------------------------------------
    IF EXISTS (
        SELECT 1 FROM information_schema.tables 
        WHERE table_schema = 'public' AND table_name = 'clients'
    ) THEN
        DROP TRIGGER IF EXISTS on_client_created ON public.clients;
        DROP FUNCTION IF EXISTS public.handle_new_client_tasks();
        RAISE NOTICE 'Trigger obsoleto on_client_created e função handle_new_client_tasks removidos.';
    END IF;

    ---------------------------------------------------------------------------
    -- Permissões para authenticated e service_role
    ---------------------------------------------------------------------------
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'cases') THEN
        GRANT SELECT, INSERT, UPDATE, DELETE ON public.cases TO authenticated;
        GRANT ALL ON public.cases TO service_role;
    END IF;

    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'clients') THEN
        GRANT SELECT, INSERT, UPDATE, DELETE ON public.clients TO authenticated;
        GRANT ALL ON public.clients TO service_role;
    END IF;

    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'settings') THEN
        GRANT SELECT, INSERT, UPDATE, DELETE ON public.settings TO authenticated;
        GRANT ALL ON public.settings TO service_role;
    END IF;

END $$;

COMMIT;
EOF_MIGRATION_SQL

RAND_ID="correcao_vps_${RANDOM:-$$}_$(date +%s 2>/dev/null || echo '0')"
SQL_TEMP_CONTAINER="/tmp/${RAND_ID}.sql"

docker cp "$SQL_TEMP_HOST" "${DB_CONTAINER}:${SQL_TEMP_CONTAINER}" 2>/dev/null || true
rm -f "$SQL_TEMP_HOST" 2>/dev/null || true

MIG_EXIT_CODE=0
if [ -n "$LOCAL_DB_PASSWORD" ]; then
    docker exec -i -e PGPASSWORD="$LOCAL_DB_PASSWORD" "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 -f "$SQL_TEMP_CONTAINER" || MIG_EXIT_CODE=$?
else
    docker exec -i "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 -f "$SQL_TEMP_CONTAINER" || MIG_EXIT_CODE=$?
fi

# Limpa o arquivo temporário no contêiner
docker exec -i "$DB_CONTAINER" rm -f "$SQL_TEMP_CONTAINER" 2>/dev/null || true

if [ $MIG_EXIT_CODE -ne 0 ]; then
    echo -e "${RED}❌ Falha ao aplicar as instruções SQL consolidadas no PostgreSQL (código de saída: ${MIG_EXIT_CODE})!${NC}"
    exit $MIG_EXIT_CODE
fi

echo -e "${GREEN}✓ Instruções SQL consolidadas aplicadas com sucesso no PostgreSQL!${NC}"

# ------------------------------------------------------------------------------
# 3. Recarregar PostgREST (NOTIFY pgrst + restart container)
# ------------------------------------------------------------------------------
echo -e "\n${BOLD}${CYAN}[3/4] Recarregando PostgREST...${NC}"
echo -e "🔄 Recarregando cache do PostgREST via NOTIFY pgrst..."
run_sql_query "NOTIFY pgrst, 'reload schema';" >/dev/null 2>&1 || true

if [ -n "$PGRST_CONTAINER" ]; then
    echo -e "🔄 Reiniciando contêiner do PostgREST (${PGRST_CONTAINER}) para garantir cache limpo..."
    docker restart "$PGRST_CONTAINER" >/dev/null 2>&1 || true
    echo -e "${GREEN}✓ Contêiner PostgREST reiniciado!${NC}"
else
    echo -e "${YELLOW}⚠️ Contêiner PostgREST não encontrado diretamente para restart via Docker.${NC}"
fi

# ------------------------------------------------------------------------------
# 4. Conferência rigorosa pós-migração no MESMO contêiner, usuário e banco
# ------------------------------------------------------------------------------
echo -e "\n${BOLD}${CYAN}[4/4] Conferência do schema no PostgreSQL:${NC}"
echo -e "   - Contêiner: ${BOLD}${DB_CONTAINER}${NC}"
echo -e "   - Usuário:   ${BOLD}${DB_USER}${NC}"
echo -e "   - Banco:     ${BOLD}${DB_NAME}${NC}"
echo -e "---------------------------------------------------------------------"

# 1. cases.noFees
CASE_NOFEES_EXISTS=$(run_sql_query "SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'cases' AND column_name = 'noFees');" || echo "erro")
CASE_NOFEES_TYPE=$(run_sql_query "SELECT data_type FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'cases' AND column_name = 'noFees';" || echo "desconhecido")
CASES_COUNT=$(run_sql_query "SELECT count(*) FROM public.cases;" || echo "0")
CASES_NOFEES_COUNT=$(run_sql_query "SELECT count(*) FROM public.cases WHERE \"noFees\" = true;" || echo "0")

# 2. cases.created_by
CASE_CB_EXISTS=$(run_sql_query "SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'cases' AND column_name = 'created_by');" || echo "erro")
CASE_CB_TYPE=$(run_sql_query "SELECT data_type FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'cases' AND column_name = 'created_by';" || echo "desconhecido")
CASES_CB_FILLED=$(run_sql_query "SELECT count(*) FROM public.cases WHERE created_by IS NOT NULL;" || echo "0")

# 3. clients.created_by
CLIENT_CB_EXISTS=$(run_sql_query "SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'clients' AND column_name = 'created_by');" || echo "erro")
CLIENT_CB_TYPE=$(run_sql_query "SELECT data_type FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'clients' AND column_name = 'created_by';" || echo "desconhecido")
CLIENTS_COUNT=$(run_sql_query "SELECT count(*) FROM public.clients;" || echo "0")
CLIENTS_CB_FILLED=$(run_sql_query "SELECT count(*) FROM public.clients WHERE created_by IS NOT NULL;" || echo "0")

# 4. settings.onboardingChecklist
SETTINGS_OB_EXISTS=$(run_sql_query "SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'settings' AND column_name = 'onboardingChecklist');" || echo "erro")
SETTINGS_OB_TYPE=$(run_sql_query "SELECT data_type FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'settings' AND column_name = 'onboardingChecklist';" || echo "desconhecido")
CHECKLIST_LEN=$(run_sql_query "SELECT jsonb_array_length(\"onboardingChecklist\") FROM public.settings WHERE \"onboardingChecklist\" IS NOT NULL LIMIT 1;" || echo "0")

# 5. trigger on_client_created
TRIGGER_CLIENT_STATUS=$(run_sql_query "SELECT EXISTS (SELECT 1 FROM information_schema.triggers WHERE event_object_table = 'clients' AND trigger_name = 'on_client_created');" || echo "erro")
FUNCTION_CLIENT_STATUS=$(run_sql_query "SELECT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'public' AND p.proname = 'handle_new_client_tasks');" || echo "erro")

# Exibição dos resultados honestos
echo -e "   - 1. Coluna 'cases.noFees':           $( [ "$CASE_NOFEES_EXISTS" = "t" ] && echo -e "${GREEN}EXISTE (tipo: ${CASE_NOFEES_TYPE}, ${CASES_NOFEES_COUNT}/${CASES_COUNT} com noFees=true) [OK]${NC}" || echo -e "${RED}NÃO ENCONTRADA [FALHA]${NC}" )"
echo -e "   - 2. Coluna 'cases.created_by':       $( [ "$CASE_CB_EXISTS" = "t" ] && echo -e "${GREEN}EXISTE (tipo: ${CASE_CB_TYPE}, preenchidos: ${CASES_CB_FILLED}/${CASES_COUNT}) [OK]${NC}" || echo -e "${RED}NÃO ENCONTRADA [FALHA]${NC}" )"
echo -e "   - 3. Coluna 'clients.created_by':     $( [ "$CLIENT_CB_EXISTS" = "t" ] && echo -e "${GREEN}EXISTE (tipo: ${CLIENT_CB_TYPE}, preenchidos: ${CLIENTS_CB_FILLED}/${CLIENTS_COUNT}) [OK]${NC}" || echo -e "${RED}NÃO ENCONTRADA [FALHA]${NC}" )"
echo -e "   - 4. Coluna 'settings.onboardingChecklist': $( [ "$SETTINGS_OB_EXISTS" = "t" ] && echo -e "${GREEN}EXISTE (tipo: ${SETTINGS_OB_TYPE}) [OK]${NC}" || echo -e "${RED}NÃO ENCONTRADA [FALHA]${NC}" )"
echo -e "   - 5. Trigger antigo em clients:       $( [ "$TRIGGER_CLIENT_STATUS" = "f" ] && echo -e "${GREEN}REMOVIDO COM SUCESSO [OK]${NC}" || echo -e "${RED}AINDA PRESENTE [FALHA]${NC}" )"
echo -e "   - 6. Função antiga de tarefas cliente: $( [ "$FUNCTION_CLIENT_STATUS" = "f" ] && echo -e "${GREEN}REMOVIDA COM SUCESSO [OK]${NC}" || echo -e "${YELLOW}PRESENTE OU INACESSÍVEL [AVISO]${NC}" )"
echo -e "   - 7. Etapas do checklist padrão:      $( [ "${CHECKLIST_LEN:-0}" -ge 8 ] && echo -e "${GREEN}${CHECKLIST_LEN} etapas preenchidas [OK]${NC}" || echo -e "${RED}${CHECKLIST_LEN:-0} etapas [FALHA]${NC}" )"

# Validação do sucesso geral
VERIFICATION_FAILED=0
if [ "$CASE_NOFEES_EXISTS" != "t" ]; then VERIFICATION_FAILED=1; fi
if [ "$CASE_CB_EXISTS" != "t" ]; then VERIFICATION_FAILED=1; fi
if [ "$CLIENT_CB_EXISTS" != "t" ]; then VERIFICATION_FAILED=1; fi
if [ "$SETTINGS_OB_EXISTS" != "t" ]; then VERIFICATION_FAILED=1; fi
if [ "$TRIGGER_CLIENT_STATUS" != "f" ]; then VERIFICATION_FAILED=1; fi
if [ "${CHECKLIST_LEN:-0}" -lt 8 ]; then VERIFICATION_FAILED=1; fi

if [ $VERIFICATION_FAILED -ne 0 ]; then
    echo -e "\n${RED}=====================================================================${NC}"
    echo -e "${RED}❌ ERRO: A verificação final detectou falhas no banco!               ${NC}"
    echo -e "${RED}Um ou mais itens não foram aplicados corretamente.                   ${NC}"
    echo -e "${RED}=====================================================================${NC}\n"
    exit 1
fi

echo -e "\n${BOLD}${GREEN}=====================================================================${NC}"
echo -e "${BOLD}${GREEN}🎉 BANCO DE DADOS CONSOLIDADO COM SUCESSO NO VPS! [OK]               ${NC}"
echo -e "${BOLD}${GREEN}=====================================================================${NC}"
echo -e "Contêiner eleito:    ${BOLD}${DB_CONTAINER}${NC}"
echo -e "Usuário eleito:      ${BOLD}${DB_USER}${NC}"
echo -e "Banco eleito:        ${BOLD}${DB_NAME}${NC}"
echo -e "Status geral:        ${BOLD}${GREEN}TODAS AS 4 COLUNAS, DADOS E TRIGGER VERIFICADOS [OK]${NC}"
echo -e "PostgREST cache:     ${BOLD}Recarregado via NOTIFY pgrst e restart de contêiner${NC}"
echo -e "${BOLD}${GREEN}=====================================================================${NC}"
echo -e "${BOLD}${YELLOW}Agora no EasyPanel: serviço dpsjur → Implantar → Ctrl+F5${NC}"
echo -e "${BOLD}${GREEN}=====================================================================${NC}\n"
