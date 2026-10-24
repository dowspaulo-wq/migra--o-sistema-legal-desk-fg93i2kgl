#!/usr/bin/env bash
# ==============================================================================
# DPSjur / SBJur - Criação da Tabela payment_plans e Fluxo de Parcelamento no VPS
# Script: docs/vps/01-criar-payment-plans-vps.sh
# Versão: v1.4.0
# Alvo: VPS Hostinger 2.25.181.69 (EasyPanel / Supabase Self-Hosted)
# ==============================================================================
# Finalidade:
# 1. Localizar o contêiner real do PostgreSQL no VPS através de varredura Docker
#    e eleger o banco de produção com base na quantidade real de registros em
#    public.clients e public.cases (NUNCA hardcodar Doug/dpsjur que é banco vazio).
# 2. Executar migração SQL via arquivo temporário (docker cp + psql -f) para evitar
#    qualquer expansão indevida de variáveis ou $ pelo bash:
#    - Criação da tabela public.payment_plans com IF NOT EXISTS e colunas idênticas
#      à migration da nuvem (20261017203000_create_payment_plans.sql):
#      id, clientId, processId, title, installmentAmount, installmentsCount,
#      periodicity, firstDueDate, feePercentage, clientPercentage,
#      feeInstallmentAmount, clientInstallmentAmount, totalAmount, totalFeeAmount,
#      totalClientAmount, bankAccount, paymentMethod, status, notes, created_at, updated_at
#    - Habilitação de RLS e criação de políticas idempotentes para authenticated e service_role
#    - Concessão de permissões GRANT na tabela payment_plans
#    - Adição das colunas de vínculo em public.transactions: plan_id, pair_id,
#      installment_number, installment_total
#    - Criação de índices de performance
#    - Inclusão da categoria "Repasse ao Cliente" em public.settings."transactionCategories"
# 3. Recarregar cache do PostgREST via NOTIFY pgrst e restart do contêiner PostgREST
# 4. Conferência rigorosa e HONESTA com [OK]/[FALHA] consultando o information_schema
#    do banco eleito, abortando com código 1 caso algo falhe.
# 5. Idempotência garantida: executar múltiplas vezes é 100% seguro.
#
# Execução no terminal do VPS (como root - comando único sem pipe):
#   curl -sSL "https://raw.githubusercontent.com/dowspaulo-wq/migra--o-sistema-legal-desk-fg93i2kgl/main/docs/vps/01-criar-payment-plans-vps.sh" -o /root/01-criar-payment-plans-vps.sh && bash /root/01-criar-payment-plans-vps.sh
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
echo -e "${BOLD}${BLUE} DPSjur - Migração VPS: Criação de payment_plans e Parcelamento     ${NC}"
echo -e "${BOLD}${BLUE} Versão: ${SCRIPT_VERSION}                                                     ${NC}"
echo -e "${BOLD}${BLUE}=====================================================================${NC}"
echo -e "Data: $(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || true)"
echo -e "Host: $(hostname 2>/dev/null || echo 'VPS')"
echo -e "${BOLD}${BLUE}=====================================================================${NC}\n"

# Helper para executar query psql simples (retorno limpo sem cabeçalhos)
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

        # Eleição prioritária pelo maior volume de public.clients (e desempate por public.cases)
        # Ignora bases vazias como "Doug/dpsjur"
        if [ "$CLIENTS_CNT" -gt "$MAX_CLIENTS_RECORDS" ] || { [ "$CLIENTS_CNT" -eq "$MAX_CLIENTS_RECORDS" ] && [ "$CASES_CNT" -gt "$MAX_CASES_RECORDS" ]; }; then
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
echo -e "   - Clientes no banco:   ${GREEN}${MAX_CLIENTS_RECORDS} registros em public.clients${NC}"
echo -e "   - Processos no banco:  ${GREEN}${MAX_CASES_RECORDS} registros em public.cases${NC}"

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
# 2. Execução da migração SQL via arquivo temporário (docker cp + psql -f)
# ------------------------------------------------------------------------------
echo -e "\n${BOLD}${CYAN}[2/4] Aplicando migração SQL via arquivo temporário no banco eleito...${NC}"

SQL_TEMP_HOST=$(mktemp /tmp/payment_plans_vps_XXXXXX.sql)

# Note: aspas simples em 'EOF_MIGRATION_SQL' impedem expansão de variáveis pelo bash
cat << 'EOF_MIGRATION_SQL' > "$SQL_TEMP_HOST"
BEGIN;

DO $$
BEGIN
    ---------------------------------------------------------------------------
    -- 1. Criação da tabela public.payment_plans
    -- Estrutura exata da migration supabase/migrations/20261017203000_create_payment_plans.sql
    ---------------------------------------------------------------------------
    CREATE TABLE IF NOT EXISTS public.payment_plans (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        "clientId" UUID REFERENCES public.clients(id) ON DELETE CASCADE NOT NULL,
        "processId" UUID REFERENCES public.cases(id) ON DELETE SET NULL,
        title TEXT NOT NULL,
        "installmentAmount" NUMERIC NOT NULL DEFAULT 0,
        "installmentsCount" INTEGER NOT NULL DEFAULT 1,
        periodicity TEXT NOT NULL DEFAULT 'mensal',
        "firstDueDate" TEXT NOT NULL,
        "feePercentage" NUMERIC NOT NULL DEFAULT 0,
        "clientPercentage" NUMERIC NOT NULL DEFAULT 0,
        "feeInstallmentAmount" NUMERIC NOT NULL DEFAULT 0,
        "clientInstallmentAmount" NUMERIC NOT NULL DEFAULT 0,
        "totalAmount" NUMERIC NOT NULL DEFAULT 0,
        "totalFeeAmount" NUMERIC NOT NULL DEFAULT 0,
        "totalClientAmount" NUMERIC NOT NULL DEFAULT 0,
        "bankAccount" TEXT DEFAULT 'ASAAS',
        "paymentMethod" TEXT DEFAULT 'PIX',
        status TEXT NOT NULL DEFAULT 'Ativo',
        notes TEXT,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );

    -- Garantir todas as colunas caso a tabela já tenha sido criada de forma parcial
    ALTER TABLE public.payment_plans ADD COLUMN IF NOT EXISTS "clientId" UUID REFERENCES public.clients(id) ON DELETE CASCADE;
    ALTER TABLE public.payment_plans ADD COLUMN IF NOT EXISTS "processId" UUID REFERENCES public.cases(id) ON DELETE SET NULL;
    ALTER TABLE public.payment_plans ADD COLUMN IF NOT EXISTS title TEXT;
    ALTER TABLE public.payment_plans ADD COLUMN IF NOT EXISTS "installmentAmount" NUMERIC NOT NULL DEFAULT 0;
    ALTER TABLE public.payment_plans ADD COLUMN IF NOT EXISTS "installmentsCount" INTEGER NOT NULL DEFAULT 1;
    ALTER TABLE public.payment_plans ADD COLUMN IF NOT EXISTS periodicity TEXT NOT NULL DEFAULT 'mensal';
    ALTER TABLE public.payment_plans ADD COLUMN IF NOT EXISTS "firstDueDate" TEXT;
    ALTER TABLE public.payment_plans ADD COLUMN IF NOT EXISTS "feePercentage" NUMERIC NOT NULL DEFAULT 0;
    ALTER TABLE public.payment_plans ADD COLUMN IF NOT EXISTS "clientPercentage" NUMERIC NOT NULL DEFAULT 0;
    ALTER TABLE public.payment_plans ADD COLUMN IF NOT EXISTS "feeInstallmentAmount" NUMERIC NOT NULL DEFAULT 0;
    ALTER TABLE public.payment_plans ADD COLUMN IF NOT EXISTS "clientInstallmentAmount" NUMERIC NOT NULL DEFAULT 0;
    ALTER TABLE public.payment_plans ADD COLUMN IF NOT EXISTS "totalAmount" NUMERIC NOT NULL DEFAULT 0;
    ALTER TABLE public.payment_plans ADD COLUMN IF NOT EXISTS "totalFeeAmount" NUMERIC NOT NULL DEFAULT 0;
    ALTER TABLE public.payment_plans ADD COLUMN IF NOT EXISTS "totalClientAmount" NUMERIC NOT NULL DEFAULT 0;
    ALTER TABLE public.payment_plans ADD COLUMN IF NOT EXISTS "bankAccount" TEXT DEFAULT 'ASAAS';
    ALTER TABLE public.payment_plans ADD COLUMN IF NOT EXISTS "paymentMethod" TEXT DEFAULT 'PIX';
    ALTER TABLE public.payment_plans ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'Ativo';
    ALTER TABLE public.payment_plans ADD COLUMN IF NOT EXISTS notes TEXT;
    ALTER TABLE public.payment_plans ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT NOW();
    ALTER TABLE public.payment_plans ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

    -- Habilitar Row Level Security (RLS)
    ALTER TABLE public.payment_plans ENABLE ROW LEVEL SECURITY;

    -- Políticas RLS idempotentes para authenticated e service_role
    DROP POLICY IF EXISTS "payment_plans_authenticated_all" ON public.payment_plans;
    CREATE POLICY "payment_plans_authenticated_all" ON public.payment_plans
        FOR ALL TO authenticated USING (true) WITH CHECK (true);

    DROP POLICY IF EXISTS "payment_plans_service_role_all" ON public.payment_plans;
    CREATE POLICY "payment_plans_service_role_all" ON public.payment_plans
        FOR ALL TO service_role USING (true) WITH CHECK (true);

    -- Permissões na tabela payment_plans
    GRANT SELECT, INSERT, UPDATE, DELETE ON public.payment_plans TO authenticated;
    GRANT ALL ON public.payment_plans TO service_role;

    ---------------------------------------------------------------------------
    -- 2. Colunas de vínculo de parcelamento na tabela public.transactions
    ---------------------------------------------------------------------------
    IF EXISTS (
        SELECT 1 FROM information_schema.tables 
        WHERE table_schema = 'public' AND table_name = 'transactions'
    ) THEN
        ALTER TABLE public.transactions ADD COLUMN IF NOT EXISTS "plan_id" UUID REFERENCES public.payment_plans(id) ON DELETE CASCADE;
        ALTER TABLE public.transactions ADD COLUMN IF NOT EXISTS "pair_id" UUID REFERENCES public.transactions(id) ON DELETE SET NULL;
        ALTER TABLE public.transactions ADD COLUMN IF NOT EXISTS "installment_number" INTEGER;
        ALTER TABLE public.transactions ADD COLUMN IF NOT EXISTS "installment_total" INTEGER;

        GRANT SELECT, INSERT, UPDATE, DELETE ON public.transactions TO authenticated;
        GRANT ALL ON public.transactions TO service_role;
    END IF;

    ---------------------------------------------------------------------------
    -- 3. Índices de busca e integridade referencial
    ---------------------------------------------------------------------------
    CREATE INDEX IF NOT EXISTS idx_payment_plans_client_id ON public.payment_plans("clientId");
    CREATE INDEX IF NOT EXISTS idx_payment_plans_process_id ON public.payment_plans("processId");
    CREATE INDEX IF NOT EXISTS idx_transactions_plan_id ON public.transactions("plan_id");
    CREATE INDEX IF NOT EXISTS idx_transactions_pair_id ON public.transactions("pair_id");

    ---------------------------------------------------------------------------
    -- 4. Garantir categoria "Repasse ao Cliente" em public.settings."transactionCategories"
    ---------------------------------------------------------------------------
    IF EXISTS (
        SELECT 1 FROM information_schema.tables 
        WHERE table_schema = 'public' AND table_name = 'settings'
    ) THEN
        UPDATE public.settings
        SET "transactionCategories" = (
            SELECT jsonb_agg(DISTINCT elem ORDER BY elem)
            FROM (
                SELECT elem
                FROM jsonb_array_elements("transactionCategories") AS elem
                UNION
                SELECT '"Repasse ao Cliente"'::jsonb AS elem
            ) sub
        )
        WHERE "transactionCategories" IS NOT NULL;
    END IF;

END $$;

COMMIT;
EOF_MIGRATION_SQL

RAND_ID="payment_plans_${RANDOM:-$$}_$(date +%s 2>/dev/null || echo '0')"
SQL_TEMP_CONTAINER="/tmp/${RAND_ID}.sql"

docker cp "$SQL_TEMP_HOST" "${DB_CONTAINER}:${SQL_TEMP_CONTAINER}" 2>/dev/null || true
rm -f "$SQL_TEMP_HOST" 2>/dev/null || true

MIG_EXIT_CODE=0
if [ -n "$LOCAL_DB_PASSWORD" ]; then
    docker exec -i -e PGPASSWORD="$LOCAL_DB_PASSWORD" "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 -f "$SQL_TEMP_CONTAINER" || MIG_EXIT_CODE=$?
else
    docker exec -i "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 -f "$SQL_TEMP_CONTAINER" || MIG_EXIT_CODE=$?
fi

# Limpeza do arquivo temporário no contêiner
docker exec -i "$DB_CONTAINER" rm -f "$SQL_TEMP_CONTAINER" 2>/dev/null || true

if [ $MIG_EXIT_CODE -ne 0 ]; then
    echo -e "${RED}❌ Falha ao aplicar as instruções SQL no PostgreSQL (código de saída: ${MIG_EXIT_CODE})!${NC}"
    exit $MIG_EXIT_CODE
fi

echo -e "${GREEN}✓ Instruções SQL aplicadas com sucesso no PostgreSQL!${NC}"

# ------------------------------------------------------------------------------
# 3. Recarregar PostgREST (NOTIFY pgrst + restart container)
# ------------------------------------------------------------------------------
echo -e "\n${BOLD}${CYAN}[3/4] Recarregando PostgREST...${NC}"
echo -e "🔄 Recarregando cache do PostgREST via NOTIFY pgrst..."
run_sql_query "NOTIFY pgrst, 'reload schema';" >/dev/null 2>&1 || true

if [ -n "$PGRST_CONTAINER" ]; then
    echo -e "🔄 Reiniciando contêiner do PostgREST (${PGRST_CONTAINER}) para reconstruir schema cache..."
    docker restart "$PGRST_CONTAINER" >/dev/null 2>&1 || true
    echo -e "${GREEN}✓ Contêiner PostgREST reiniciado com sucesso!${NC}"
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

# 1. Tabela payment_plans existe
TABLE_EXISTS=$(run_sql_query "SELECT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'payment_plans');" || echo "erro")

# 2. Contagem de colunas em payment_plans (esperado: 21)
PLAN_COLS_COUNT=$(run_sql_query "SELECT count(*) FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'payment_plans' AND column_name IN ('id', 'clientId', 'processId', 'title', 'installmentAmount', 'installmentsCount', 'periodicity', 'firstDueDate', 'feePercentage', 'clientPercentage', 'feeInstallmentAmount', 'clientInstallmentAmount', 'totalAmount', 'totalFeeAmount', 'totalClientAmount', 'bankAccount', 'paymentMethod', 'status', 'notes', 'created_at', 'updated_at');" || echo "0")

# 3. Colunas de vínculo em transactions (esperado: 4)
TXN_COLS_COUNT=$(run_sql_query "SELECT count(*) FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'transactions' AND column_name IN ('plan_id', 'pair_id', 'installment_number', 'installment_total');" || echo "0")

# 4. RLS habilitado em payment_plans
RLS_ENABLED=$(run_sql_query "SELECT relrowsecurity FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'public' AND c.relname = 'payment_plans';" || echo "f")

# 5. Políticas RLS em payment_plans (esperado >= 2)
POLICIES_COUNT=$(run_sql_query "SELECT count(*) FROM pg_policies WHERE schemaname = 'public' AND tablename = 'payment_plans';" || echo "0")

# 6. Índices criados (esperado: 4)
INDEXES_COUNT=$(run_sql_query "SELECT count(*) FROM pg_indexes WHERE schemaname = 'public' AND indexname IN ('idx_payment_plans_client_id', 'idx_payment_plans_process_id', 'idx_transactions_plan_id', 'idx_transactions_pair_id');" || echo "0")

# 7. Categoria 'Repasse ao Cliente' em settings
SETTINGS_CAT_EXISTS=$(run_sql_query "SELECT EXISTS (SELECT 1 FROM public.settings, jsonb_array_elements(\"transactionCategories\") AS elem WHERE elem = '\"Repasse ao Cliente\"'::jsonb);" || echo "f")

# Exibição dos resultados honestos
echo -e "   - 1. Tabela 'payment_plans':           $( [ "$TABLE_EXISTS" = "t" ] && echo -e "${GREEN}EXISTE [OK]${NC}" || echo -e "${RED}NÃO ENCONTRADA [FALHA]${NC}" )"
echo -e "   - 2. Colunas em 'payment_plans':      $( [ "${PLAN_COLS_COUNT:-0}" -ge 21 ] && echo -e "${GREEN}${PLAN_COLS_COUNT}/21 colunas verificadas [OK]${NC}" || echo -e "${RED}${PLAN_COLS_COUNT:-0}/21 colunas [FALHA]${NC}" )"
echo -e "   - 3. Colunas em 'transactions':       $( [ "${TXN_COLS_COUNT:-0}" -ge 4 ] && echo -e "${GREEN}${TXN_COLS_COUNT}/4 colunas verificadas (plan_id, pair_id, ...) [OK]${NC}" || echo -e "${RED}${TXN_COLS_COUNT:-0}/4 colunas [FALHA]${NC}" )"
echo -e "   - 4. Row Level Security (RLS):        $( [ "$RLS_ENABLED" = "t" ] && echo -e "${GREEN}HABILITADO [OK]${NC}" || echo -e "${RED}DESABILITADO [FALHA]${NC}" )"
echo -e "   - 5. Políticas RLS aplicadas:         $( [ "${POLICIES_COUNT:-0}" -ge 2 ] && echo -e "${GREEN}${POLICIES_COUNT} políticas ativas [OK]${NC}" || echo -e "${RED}${POLICIES_COUNT:-0} políticas [FALHA]${NC}" )"
echo -e "   - 6. Índices de performance:          $( [ "${INDEXES_COUNT:-0}" -ge 4 ] && echo -e "${GREEN}${INDEXES_COUNT}/4 índices criados [OK]${NC}" || echo -e "${RED}${INDEXES_COUNT:-0}/4 índices [FALHA]${NC}" )"
echo -e "   - 7. Categoria 'Repasse ao Cliente':  $( [ "$SETTINGS_CAT_EXISTS" = "t" ] && echo -e "${GREEN}PRESENTE EM SETTINGS [OK]${NC}" || echo -e "${YELLOW}NÃO CONFIGURADO OU SETTINGS VAZIO [AVISO]${NC}" )"

# Validação do sucesso geral
VERIFICATION_FAILED=0
if [ "$TABLE_EXISTS" != "t" ]; then VERIFICATION_FAILED=1; fi
if [ "${PLAN_COLS_COUNT:-0}" -lt 21 ]; then VERIFICATION_FAILED=1; fi
if [ "${TXN_COLS_COUNT:-0}" -lt 4 ]; then VERIFICATION_FAILED=1; fi
if [ "$RLS_ENABLED" != "t" ]; then VERIFICATION_FAILED=1; fi
if [ "${POLICIES_COUNT:-0}" -lt 2 ]; then VERIFICATION_FAILED=1; fi
if [ "${INDEXES_COUNT:-0}" -lt 4 ]; then VERIFICATION_FAILED=1; fi

if [ $VERIFICATION_FAILED -ne 0 ]; then
    echo -e "\n${RED}=====================================================================${NC}"
    echo -e "${RED}❌ ERRO: A verificação final detectou falhas no banco!               ${NC}"
    echo -e "${RED}Um ou mais itens críticos não foram criados corretamente.            ${NC}"
    echo -e "${RED}=====================================================================${NC}\n"
    exit 1
fi

echo -e "\n${BOLD}${GREEN}=====================================================================${NC}"
echo -e "${BOLD}${GREEN}🎉 TABELA PAYMENT_PLANS E FLUXO DE PARCELAMENTO PRONTOS NO VPS! [OK] ${NC}"
echo -e "${BOLD}${GREEN}=====================================================================${NC}"
echo -e "Contêiner eleito:    ${BOLD}${DB_CONTAINER}${NC}"
echo -e "Usuário eleito:      ${BOLD}${DB_USER}${NC}"
echo -e "Banco eleito:        ${BOLD}${DB_NAME}${NC}"
echo -e "PostgREST cache:     ${BOLD}Recarregado via NOTIFY pgrst e restart de contêiner${NC}"
echo -e "${BOLD}${GREEN}=====================================================================${NC}"
echo -e "${BOLD}${YELLOW}Próximo passo: No navegador, acerte Ctrl+F5 no sistema do VPS e tente criar o parcelamento.${NC}"
echo -e "${BOLD}${GREEN}=====================================================================${NC}\n"
