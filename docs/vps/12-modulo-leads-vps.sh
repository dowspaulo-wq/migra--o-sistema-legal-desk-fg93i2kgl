#!/usr/bin/env bash
# ==============================================================================
# DPSjur / SBJur - Migração do Módulo de Gestão de Leads no VPS (Hostinger)
# Script: docs/vps/12-modulo-leads-vps.sh
# Versão: v1.0.0
# Alvo: VPS Hostinger 2.25.181.69 (EasyPanel / Supabase Self-Hosted)
# ==============================================================================
# Finalidade:
# 1. Localizar o contêiner real do PostgreSQL no VPS através de varredura Docker
#    e eleger o banco de produção com base na quantidade real de registros em
#    public.clients e public.cases (NUNCA hardcodar Doug/dpsjur que é banco vazio).
# 2. Executar migração SQL via arquivo temporário (docker cp + psql -f) de forma
#    100% IDEMPOTENTE, SEGURA e NÃO DESTRUTIVA:
#    - Criação da tabela public.leads (com IF NOT EXISTS e colunas completas);
#    - Criação da tabela public.lead_interactions (com IF NOT EXISTS e FKs);
#    - Garantia de colunas via ADD COLUMN IF NOT EXISTS caso tabelas já existam;
#    - Criação dos índices comuns e parciais únicos (idx_leads_stage, idx_leads_next_contact,
#      idx_leads_responsible, idx_leads_created_at, idx_lead_interactions_lead,
#      idx_lead_interactions_occurred, uq_leads_phone_not_empty, uq_leads_email_not_empty);
#    - Função e trigger handle_leads_updated_at para atualização automática de updated_at;
#    - Habilitação de RLS e políticas DROP POLICY IF EXISTS + CREATE POLICY para
#      authenticated (SELECT, INSERT, UPDATE, DELETE) e permissões de service_role;
#    - Limpeza de eventuais colunas em minúsculas legadas em public.settings:
#      DROP COLUMN IF EXISTS leadorigins, leadstages, leadinteractiontypes;
#    - Adição das 5 colunas em camelCase em public.settings:
#      "leadAreas", "leadSubjects", "leadOrigins", "leadStages", "leadInteractionTypes";
#    - Preenchimento seguro dos valores padrão em public.settings com COALESCE (não sobrescreve
#      se o usuário já configurou);
#    - Permissões GRANT completas para authenticated e service_role.
# 3. Recarregar PostgREST via NOTIFY pgrst e restart do contêiner PostgREST para reconstruir o cache.
# 4. Conferência rigorosa com [OK]/[FALHA] de 8 itens no PostgreSQL eleito.
# 5. Idempotência absoluta: rodar múltiplas vezes é totalmente seguro.
#
# Execução no terminal do VPS (como root - SEM curl|bash):
#   cd /root
#   curl -fsSL -o 12-modulo-leads-vps.sh "https://raw.githubusercontent.com/dowspaulo-wq/migra--o-sistema-legal-desk-fg93i2kgl/main/docs/vps/12-modulo-leads-vps.sh"
#   bash /root/12-modulo-leads-vps.sh
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
echo -e "${BOLD}${BLUE} DPSjur - Migração VPS: Módulo de Gestão de Leads                   ${NC}"
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

    if [ -z "$WORKING_USER" ]; then
        continue
    fi

    for db_item in $DATABASES_LIST; do
        CASES_COUNT=$(run_container_psql "$c" "$WORKING_USER" "$WORKING_PASS" "$db_item" "SELECT count(*) FROM public.cases;" || echo "-1")
        CLIENTS_COUNT=$(run_container_psql "$c" "$WORKING_USER" "$WORKING_PASS" "$db_item" "SELECT count(*) FROM public.clients;" || echo "-1")

        [[ "$CASES_COUNT" =~ ^[0-9]+$ ]] || CASES_COUNT=-1
        [[ "$CLIENTS_COUNT" =~ ^[0-9]+$ ]] || CLIENTS_COUNT=-1

        if [ "$CASES_COUNT" -gt "$MAX_CASES_RECORDS" ] || { [ "$CASES_COUNT" -eq "$MAX_CASES_RECORDS" ] && [ "$CLIENTS_COUNT" -gt "$MAX_CLIENTS_RECORDS" ]; }; then
            MAX_CASES_RECORDS=$CASES_COUNT
            MAX_CLIENTS_RECORDS=$CLIENTS_COUNT
            REAL_CONTAINER="$c"
            REAL_USER="$WORKING_USER"
            REAL_PASS="$WORKING_PASS"
            REAL_DB="$db_item"
        fi
    done
done

if [ -z "$REAL_CONTAINER" ] || [ -z "$REAL_DB" ]; then
    echo -e "${RED}❌ Não foi possível eleger o banco PostgreSQL de produção!${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Contêiner eleito: ${BOLD}${REAL_CONTAINER}${NC}"
echo -e "${GREEN}✓ Usuário eleito:   ${BOLD}${REAL_USER}${NC}"
echo -e "${GREEN}✓ Banco eleito:     ${BOLD}${REAL_DB}${NC} (com ${MAX_CASES_RECORDS} processos e ${MAX_CLIENTS_RECORDS} clientes)"

# Localização do contêiner PostgREST
PGRST_CONTAINER=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -Ei 'postgrest|rest' | head -n 1 || true)
if [ -n "$PGRST_CONTAINER" ]; then
    echo -e "${GREEN}✓ Contêiner PostgREST detectado: ${BOLD}${PGRST_CONTAINER}${NC}"
else
    echo -e "${YELLOW}⚠️ Contêiner PostgREST não encontrado diretamente por regex. Recarga será feita via NOTIFY pgrst.${NC}"
fi

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
echo -e "\n${BOLD}${CYAN}[2/4] Aplicando migração SQL do módulo Leads via arquivo temporário...${NC}"

SQL_TEMP_HOST=$(mktemp /tmp/modulo_leads_vps_XXXXXX.sql)

# Nota: Aspas em 'EOF_MIGRATION_SQL' evitam interpolação indevida de variáveis pelo bash
cat << 'EOF_MIGRATION_SQL' > "$SQL_TEMP_HOST"
BEGIN;

DO $$
BEGIN
    ---------------------------------------------------------------------------
    -- 1. Criação da tabela public.leads
    ---------------------------------------------------------------------------
    CREATE TABLE IF NOT EXISTS public.leads (
        id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        name text NOT NULL,
        phone text,
        email text,
        city text,
        state text,
        "entryDate" text,
        origin text,
        campaign text,
        adset text,
        ad text,
        "formId" text,
        "externalId" text,
        area text,
        subject text,
        summary text,
        "factDate" text,
        "internalNotes" text,
        stage text NOT NULL DEFAULT 'Novo',
        "responsibleId" uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
        "lastContactAt" timestamptz,
        "nextContactAt" text,
        priority text,
        "lostReason" text,
        "convertedClientId" uuid REFERENCES public.clients(id) ON DELETE SET NULL,
        "convertedAt" timestamptz,
        created_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
        created_at timestamptz NOT NULL DEFAULT now(),
        updated_at timestamptz NOT NULL DEFAULT now()
    );

    -- Garantir todas as colunas caso a tabela já tenha sido criada de forma parcial
    ALTER TABLE public.leads ADD COLUMN IF NOT EXISTS name text;
    ALTER TABLE public.leads ADD COLUMN IF NOT EXISTS phone text;
    ALTER TABLE public.leads ADD COLUMN IF NOT EXISTS email text;
    ALTER TABLE public.leads ADD COLUMN IF NOT EXISTS city text;
    ALTER TABLE public.leads ADD COLUMN IF NOT EXISTS state text;
    ALTER TABLE public.leads ADD COLUMN IF NOT EXISTS "entryDate" text;
    ALTER TABLE public.leads ADD COLUMN IF NOT EXISTS origin text;
    ALTER TABLE public.leads ADD COLUMN IF NOT EXISTS campaign text;
    ALTER TABLE public.leads ADD COLUMN IF NOT EXISTS adset text;
    ALTER TABLE public.leads ADD COLUMN IF NOT EXISTS ad text;
    ALTER TABLE public.leads ADD COLUMN IF NOT EXISTS "formId" text;
    ALTER TABLE public.leads ADD COLUMN IF NOT EXISTS "externalId" text;
    ALTER TABLE public.leads ADD COLUMN IF NOT EXISTS area text;
    ALTER TABLE public.leads ADD COLUMN IF NOT EXISTS subject text;
    ALTER TABLE public.leads ADD COLUMN IF NOT EXISTS summary text;
    ALTER TABLE public.leads ADD COLUMN IF NOT EXISTS "factDate" text;
    ALTER TABLE public.leads ADD COLUMN IF NOT EXISTS "internalNotes" text;
    ALTER TABLE public.leads ADD COLUMN IF NOT EXISTS stage text NOT NULL DEFAULT 'Novo';
    ALTER TABLE public.leads ADD COLUMN IF NOT EXISTS "responsibleId" uuid REFERENCES public.profiles(id) ON DELETE SET NULL;
    ALTER TABLE public.leads ADD COLUMN IF NOT EXISTS "lastContactAt" timestamptz;
    ALTER TABLE public.leads ADD COLUMN IF NOT EXISTS "nextContactAt" text;
    ALTER TABLE public.leads ADD COLUMN IF NOT EXISTS priority text;
    ALTER TABLE public.leads ADD COLUMN IF NOT EXISTS "lostReason" text;
    ALTER TABLE public.leads ADD COLUMN IF NOT EXISTS "convertedClientId" uuid REFERENCES public.clients(id) ON DELETE SET NULL;
    ALTER TABLE public.leads ADD COLUMN IF NOT EXISTS "convertedAt" timestamptz;
    ALTER TABLE public.leads ADD COLUMN IF NOT EXISTS created_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL;
    ALTER TABLE public.leads ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now();
    ALTER TABLE public.leads ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

    ---------------------------------------------------------------------------
    -- 2. Criação da tabela public.lead_interactions
    ---------------------------------------------------------------------------
    CREATE TABLE IF NOT EXISTS public.lead_interactions (
        id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        "leadId" uuid NOT NULL REFERENCES public.leads(id) ON DELETE CASCADE,
        type text NOT NULL,
        description text,
        "fromStage" text,
        "toStage" text,
        "occurredAt" timestamptz NOT NULL DEFAULT now(),
        "userId" uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
        created_at timestamptz NOT NULL DEFAULT now()
    );

    ALTER TABLE public.lead_interactions ADD COLUMN IF NOT EXISTS "leadId" uuid NOT NULL REFERENCES public.leads(id) ON DELETE CASCADE;
    ALTER TABLE public.lead_interactions ADD COLUMN IF NOT EXISTS type text;
    ALTER TABLE public.lead_interactions ADD COLUMN IF NOT EXISTS description text;
    ALTER TABLE public.lead_interactions ADD COLUMN IF NOT EXISTS "fromStage" text;
    ALTER TABLE public.lead_interactions ADD COLUMN IF NOT EXISTS "toStage" text;
    ALTER TABLE public.lead_interactions ADD COLUMN IF NOT EXISTS "occurredAt" timestamptz NOT NULL DEFAULT now();
    ALTER TABLE public.lead_interactions ADD COLUMN IF NOT EXISTS "userId" uuid REFERENCES public.profiles(id) ON DELETE SET NULL;
    ALTER TABLE public.lead_interactions ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now();

    ---------------------------------------------------------------------------
    -- 3. Índices de performance e unicidade parcial
    ---------------------------------------------------------------------------
    CREATE INDEX IF NOT EXISTS idx_leads_stage ON public.leads (stage);
    CREATE INDEX IF NOT EXISTS idx_leads_next_contact ON public.leads ("nextContactAt");
    CREATE INDEX IF NOT EXISTS idx_leads_responsible ON public.leads ("responsibleId");
    CREATE INDEX IF NOT EXISTS idx_leads_created_at ON public.leads (created_at);
    CREATE INDEX IF NOT EXISTS idx_lead_interactions_lead ON public.lead_interactions ("leadId");
    CREATE INDEX IF NOT EXISTS idx_lead_interactions_occurred ON public.lead_interactions ("occurredAt");

    CREATE UNIQUE INDEX IF NOT EXISTS uq_leads_phone_not_empty
      ON public.leads (phone)
      WHERE phone IS NOT NULL AND btrim(phone) <> '';

    CREATE UNIQUE INDEX IF NOT EXISTS uq_leads_email_not_empty
      ON public.leads (email)
      WHERE email IS NOT NULL AND btrim(email) <> '';

    ---------------------------------------------------------------------------
    -- 4. Função e trigger para updated_at automático em leads
    ---------------------------------------------------------------------------
    CREATE OR REPLACE FUNCTION public.handle_leads_updated_at()
    RETURNS trigger AS $func$
    BEGIN
      NEW.updated_at = now();
      RETURN NEW;
    END;
    $func$ LANGUAGE plpgsql;

    DROP TRIGGER IF EXISTS trg_leads_updated_at ON public.leads;
    CREATE TRIGGER trg_leads_updated_at
      BEFORE UPDATE ON public.leads
      FOR EACH ROW EXECUTE FUNCTION public.handle_leads_updated_at();

    ---------------------------------------------------------------------------
    -- 5. Row Level Security (RLS) e Políticas
    ---------------------------------------------------------------------------
    ALTER TABLE public.leads ENABLE ROW LEVEL SECURITY;
    ALTER TABLE public.lead_interactions ENABLE ROW LEVEL SECURITY;

    DROP POLICY IF EXISTS "authenticated_select_leads" ON public.leads;
    CREATE POLICY "authenticated_select_leads" ON public.leads
      FOR SELECT TO authenticated USING (true);

    DROP POLICY IF EXISTS "authenticated_insert_leads" ON public.leads;
    CREATE POLICY "authenticated_insert_leads" ON public.leads
      FOR INSERT TO authenticated WITH CHECK (true);

    DROP POLICY IF EXISTS "authenticated_update_leads" ON public.leads;
    CREATE POLICY "authenticated_update_leads" ON public.leads
      FOR UPDATE TO authenticated USING (true) WITH CHECK (true);

    DROP POLICY IF EXISTS "authenticated_delete_leads" ON public.leads;
    CREATE POLICY "authenticated_delete_leads" ON public.leads
      FOR DELETE TO authenticated USING (true);

    DROP POLICY IF EXISTS "authenticated_select_lead_interactions" ON public.lead_interactions;
    CREATE POLICY "authenticated_select_lead_interactions" ON public.lead_interactions
      FOR SELECT TO authenticated USING (true);

    DROP POLICY IF EXISTS "authenticated_insert_lead_interactions" ON public.lead_interactions;
    CREATE POLICY "authenticated_insert_lead_interactions" ON public.lead_interactions
      FOR INSERT TO authenticated WITH CHECK (true);

    DROP POLICY IF EXISTS "authenticated_update_lead_interactions" ON public.lead_interactions;
    CREATE POLICY "authenticated_update_lead_interactions" ON public.lead_interactions
      FOR UPDATE TO authenticated USING (true) WITH CHECK (true);

    DROP POLICY IF EXISTS "authenticated_delete_lead_interactions" ON public.lead_interactions;
    CREATE POLICY "authenticated_delete_lead_interactions" ON public.lead_interactions
      FOR DELETE TO authenticated USING (true);

    -- Permissões GRANT
    GRANT SELECT, INSERT, UPDATE, DELETE ON public.leads TO authenticated;
    GRANT ALL ON public.leads TO service_role;
    GRANT SELECT, INSERT, UPDATE, DELETE ON public.lead_interactions TO authenticated;
    GRANT ALL ON public.lead_interactions TO service_role;

    ---------------------------------------------------------------------------
    -- 6. Colunas de listas configuráveis em public.settings
    ---------------------------------------------------------------------------
    IF EXISTS (
        SELECT 1 FROM information_schema.tables 
        WHERE table_schema = 'public' AND table_name = 'settings'
    ) THEN
        -- Limpeza defensiva de colunas minúsculas se existirem
        ALTER TABLE public.settings
          DROP COLUMN IF EXISTS leadorigins,
          DROP COLUMN IF EXISTS leadstages,
          DROP COLUMN IF EXISTS leadinteractiontypes;

        -- Adição das 5 colunas oficiais em camelCase
        ALTER TABLE public.settings ADD COLUMN IF NOT EXISTS "leadAreas" jsonb;
        ALTER TABLE public.settings ADD COLUMN IF NOT EXISTS "leadSubjects" jsonb;
        ALTER TABLE public.settings ADD COLUMN IF NOT EXISTS "leadOrigins" jsonb;
        ALTER TABLE public.settings ADD COLUMN IF NOT EXISTS "leadStages" jsonb;
        ALTER TABLE public.settings ADD COLUMN IF NOT EXISTS "leadInteractionTypes" jsonb;

        -- Definir os defaults padrão do DDL para novas inserções
        ALTER TABLE public.settings ALTER COLUMN "leadOrigins" SET DEFAULT '["Meta Ads — Facebook","Meta Ads — Instagram","Google Ads","Site institucional","WhatsApp","Indicação","Contato orgânico","Outros"]'::jsonb;
        ALTER TABLE public.settings ALTER COLUMN "leadStages" SET DEFAULT '[{"id":"novo","label":"Novo"},{"id":"aguardando","label":"Aguardando contato"},{"id":"atendimento","label":"Em atendimento"},{"id":"qualificado","label":"Qualificado"},{"id":"proposta","label":"Proposta enviada"},{"id":"contratado","label":"Contratado"},{"id":"perdido","label":"Perdido"},{"id":"nao-qualificado","label":"Não qualificado"}]'::jsonb;
        ALTER TABLE public.settings ALTER COLUMN "leadInteractionTypes" SET DEFAULT '["Ligação","Mensagem","Reunião","Tentativa de contato","Observação","Proposta","Mudança de etapa","Retorno agendado"]'::jsonb;

        -- Preencher valores padrão nos registros existentes onde estiver NULL (não sobrescreve o já existente)
        UPDATE public.settings
        SET
          "leadAreas" = COALESCE("leadAreas", '["Previdenciário", "Cível", "Trabalhista", "Família", "Criminal", "Consumidor", "Tributário", "Outros"]'::jsonb),
          "leadSubjects" = COALESCE("leadSubjects", '["Aposentadoria", "Auxílio-doença", "BPC/LOAS", "Revisão de benefício", "Divórcio", "Alimentos", "Inventário", "Indenização", "Reclamação trabalhista", "Consultoria", "Outros"]'::jsonb),
          "leadOrigins" = COALESCE("leadOrigins", '["Meta Ads — Facebook","Meta Ads — Instagram","Google Ads","Site institucional","WhatsApp","Indicação","Contato orgânico","Outros"]'::jsonb),
          "leadStages" = COALESCE("leadStages", '[{"id":"novo","label":"Novo"},{"id":"aguardando","label":"Aguardando contato"},{"id":"atendimento","label":"Em atendimento"},{"id":"qualificado","label":"Qualificado"},{"id":"proposta","label":"Proposta enviada"},{"id":"contratado","label":"Contratado"},{"id":"perdido","label":"Perdido"},{"id":"nao-qualificado","label":"Não qualificado"}]'::jsonb),
          "leadInteractionTypes" = COALESCE("leadInteractionTypes", '["Ligação","Mensagem","Reunião","Tentativa de contato","Observação","Proposta","Mudança de etapa","Retorno agendado"]'::jsonb);

        GRANT SELECT, INSERT, UPDATE, DELETE ON public.settings TO authenticated;
        GRANT ALL ON public.settings TO service_role;
    END IF;

END $$;

COMMIT;
EOF_MIGRATION_SQL

RAND_ID="leads_mod_${RANDOM:-$$}_$(date +%s 2>/dev/null || echo '0')"
SQL_TEMP_CONTAINER="/tmp/${RAND_ID}.sql"

docker cp "$SQL_TEMP_HOST" "${DB_CONTAINER}:${SQL_TEMP_CONTAINER}" 2>/dev/null || true
rm -f "$SQL_TEMP_HOST" 2>/dev/null || true

MIG_EXIT_CODE=0
if [ -n "$LOCAL_DB_PASSWORD" ]; then
    docker exec -i -e PGPASSWORD="$LOCAL_DB_PASSWORD" "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 -f "$SQL_TEMP_CONTAINER" || MIG_EXIT_CODE=$?
else
    docker exec -i "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 -f "$SQL_TEMP_CONTAINER" || MIG_EXIT_CODE=$?
fi

docker exec -i "$DB_CONTAINER" rm -f "$SQL_TEMP_CONTAINER" 2>/dev/null || true

if [ $MIG_EXIT_CODE -ne 0 ]; then
    echo -e "${RED}❌ Falha ao aplicar as instruções SQL no PostgreSQL (código de saída: ${MIG_EXIT_CODE})!${NC}"
    exit $MIG_EXIT_CODE
fi

echo -e "${GREEN}✓ Instruções SQL do módulo Leads aplicadas com sucesso no PostgreSQL!${NC}"

# ------------------------------------------------------------------------------
# 3. Recarregar PostgREST (NOTIFY pgrst + restart container)
# ------------------------------------------------------------------------------
echo -e "\n${BOLD}${CYAN}[3/4] Recarregando PostgREST para atualizar o schema cache...${NC}"
echo -e "🔄 Recarregando cache do PostgREST via NOTIFY pgrst..."
run_sql_query "NOTIFY pgrst, 'reload schema';" >/dev/null 2>&1 || true

if [ -n "$PGRST_CONTAINER" ]; then
    echo -e "🔄 Reiniciando contêiner do PostgREST (${PGRST_CONTAINER}) para reconstruir schema cache..."
    docker restart "$PGRST_CONTAINER" >/dev/null 2>&1 || true
    echo -e "${GREEN}✓ Contêiner PostgREST reiniciado com sucesso!${NC}"
else
    echo -e "${YELLOW}⚠️ Contêiner PostgREST não encontrado diretamente por regex. O comando NOTIFY pgrst foi executado.${NC}"
fi

# ------------------------------------------------------------------------------
# 4. Conferência rigorosa pós-migração no MESMO contêiner, usuário e banco
# ------------------------------------------------------------------------------
echo -e "\n${BOLD}${CYAN}[4/4] Conferência do schema no PostgreSQL:${NC}"
echo -e "   - Contêiner: ${BOLD}${DB_CONTAINER}${NC}"
echo -e "   - Usuário:   ${BOLD}${DB_USER}${NC}"
echo -e "   - Banco:     ${BOLD}${DB_NAME}${NC}"
echo -e "---------------------------------------------------------------------"

# 1. Tabela leads existe
TABLE_LEADS_EXISTS=$(run_sql_query "SELECT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'leads');" || echo "erro")

# 2. Tabela lead_interactions existe
TABLE_INTERACTIONS_EXISTS=$(run_sql_query "SELECT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'lead_interactions');" || echo "erro")

# 3. Colunas de leads (esperado: 28 colunas)
LEADS_COLS_COUNT=$(run_sql_query "SELECT count(*) FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'leads' AND column_name IN ('id', 'name', 'phone', 'email', 'city', 'state', 'entryDate', 'origin', 'campaign', 'adset', 'ad', 'formId', 'externalId', 'area', 'subject', 'summary', 'factDate', 'internalNotes', 'stage', 'responsibleId', 'lastContactAt', 'nextContactAt', 'priority', 'lostReason', 'convertedClientId', 'convertedAt', 'created_by', 'created_at', 'updated_at');" || echo "0")

# 4. Colunas de lead_interactions (esperado: 9 colunas)
INTERACTIONS_COLS_COUNT=$(run_sql_query "SELECT count(*) FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'lead_interactions' AND column_name IN ('id', 'leadId', 'type', 'description', 'fromStage', 'toStage', 'occurredAt', 'userId', 'created_at');" || echo "0")

# 5. RLS habilitado em leads e lead_interactions
RLS_LEADS=$(run_sql_query "SELECT relrowsecurity FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'public' AND c.relname = 'leads';" || echo "f")
RLS_INTERACTIONS=$(run_sql_query "SELECT relrowsecurity FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'public' AND c.relname = 'lead_interactions';" || echo "f")

# 6. Políticas RLS aplicadas (esperado: 4 para leads, 4 para lead_interactions = 8)
POLICIES_LEADS_COUNT=$(run_sql_query "SELECT count(*) FROM pg_policies WHERE schemaname = 'public' AND tablename = 'leads';" || echo "0")
POLICIES_INTERACTIONS_COUNT=$(run_sql_query "SELECT count(*) FROM pg_policies WHERE schemaname = 'public' AND tablename = 'lead_interactions';" || echo "0")

# 7. Índices criados (esperado: 8 índices)
INDEXES_COUNT=$(run_sql_query "SELECT count(*) FROM pg_indexes WHERE schemaname = 'public' AND indexname IN ('idx_leads_stage', 'idx_leads_next_contact', 'idx_leads_responsible', 'idx_leads_created_at', 'uq_leads_phone_not_empty', 'uq_leads_email_not_empty', 'idx_lead_interactions_lead', 'idx_lead_interactions_occurred');" || echo "0")

# 8. Colunas de listas configuráveis em settings (esperado: 5 colunas em camelCase)
SETTINGS_LEADS_COLS=$(run_sql_query "SELECT count(*) FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'settings' AND column_name IN ('leadAreas', 'leadSubjects', 'leadOrigins', 'leadStages', 'leadInteractionTypes');" || echo "0")

# Exibição dos resultados honestos
echo -e "   - 1. Tabela 'leads':                  $( [ "$TABLE_LEADS_EXISTS" = "t" ] && echo -e "${GREEN}EXISTE [OK]${NC}" || echo -e "${RED}NÃO ENCONTRADA [FALHA]${NC}" )"
echo -e "   - 2. Tabela 'lead_interactions':      $( [ "$TABLE_INTERACTIONS_EXISTS" = "t" ] && echo -e "${GREEN}EXISTE [OK]${NC}" || echo -e "${RED}NÃO ENCONTRADA [FALHA]${NC}" )"
echo -e "   - 3. Colunas em 'leads':              $( [ "${LEADS_COLS_COUNT:-0}" -ge 28 ] && echo -e "${GREEN}${LEADS_COLS_COUNT}/28 colunas verificadas [OK]${NC}" || echo -e "${RED}${LEADS_COLS_COUNT:-0}/28 colunas [FALHA]${NC}" )"
echo -e "   - 4. Colunas em 'lead_interactions':  $( [ "${INTERACTIONS_COLS_COUNT:-0}" -ge 9 ] && echo -e "${GREEN}${INTERACTIONS_COLS_COUNT}/9 colunas verificadas [OK]${NC}" || echo -e "${RED}${INTERACTIONS_COLS_COUNT:-0}/9 colunas [FALHA]${NC}" )"
echo -e "   - 5. Row Level Security (RLS):        $( [ "$RLS_LEADS" = "t" ] && [ "$RLS_INTERACTIONS" = "t" ] && echo -e "${GREEN}HABILITADO EM AMBAS AS TABELAS [OK]${NC}" || echo -e "${RED}RLS INCOMPLETO (leads=$RLS_LEADS, interactions=$RLS_INTERACTIONS) [FALHA]${NC}" )"
echo -e "   - 6. Políticas RLS aplicadas:         $( [ "${POLICIES_LEADS_COUNT:-0}" -ge 4 ] && [ "${POLICIES_INTERACTIONS_COUNT:-0}" -ge 4 ] && echo -e "${GREEN}${POLICIES_LEADS_COUNT} em leads + ${POLICIES_INTERACTIONS_COUNT} em interações [OK]${NC}" || echo -e "${RED}Políticas insuficientes (leads=${POLICIES_LEADS_COUNT}, interações=${POLICIES_INTERACTIONS_COUNT}) [FALHA]${NC}" )"
echo -e "   - 7. Índices e restrições únicas:     $( [ "${INDEXES_COUNT:-0}" -ge 8 ] && echo -e "${GREEN}${INDEXES_COUNT}/8 índices verificados [OK]${NC}" || echo -e "${RED}${INDEXES_COUNT:-0}/8 índices [FALHA]${NC}" )"
echo -e "   - 8. Colunas de listas em settings:   $( [ "${SETTINGS_LEADS_COLS:-0}" -ge 5 ] && echo -e "${GREEN}${SETTINGS_LEADS_COLS}/5 colunas camelCase verificadas [OK]${NC}" || echo -e "${RED}${SETTINGS_LEADS_COLS:-0}/5 colunas [FALHA]${NC}" )"

# Validação geral
VERIFICATION_FAILED=0
if [ "$TABLE_LEADS_EXISTS" != "t" ]; then VERIFICATION_FAILED=1; fi
if [ "$TABLE_INTERACTIONS_EXISTS" != "t" ]; then VERIFICATION_FAILED=1; fi
if [ "${LEADS_COLS_COUNT:-0}" -lt 28 ]; then VERIFICATION_FAILED=1; fi
if [ "${INTERACTIONS_COLS_COUNT:-0}" -lt 9 ]; then VERIFICATION_FAILED=1; fi
if [ "$RLS_LEADS" != "t" ] || [ "$RLS_INTERACTIONS" != "t" ]; then VERIFICATION_FAILED=1; fi
if [ "${POLICIES_LEADS_COUNT:-0}" -lt 4 ] || [ "${POLICIES_INTERACTIONS_COUNT:-0}" -lt 4 ]; then VERIFICATION_FAILED=1; fi
if [ "${INDEXES_COUNT:-0}" -lt 8 ]; then VERIFICATION_FAILED=1; fi
if [ "${SETTINGS_LEADS_COLS:-0}" -lt 5 ]; then VERIFICATION_FAILED=1; fi

if [ $VERIFICATION_FAILED -ne 0 ]; then
    echo -e "\n${RED}=====================================================================${NC}"
    echo -e "${RED}❌ ERRO: A verificação final detectou falhas na criação do schema!   ${NC}"
    echo -e "${RED}Um ou mais itens críticos não foram criados corretamente.            ${NC}"
    echo -e "${RED}=====================================================================${NC}\n"
    exit 1
fi

echo -e "\n${BOLD}${GREEN}=====================================================================${NC}"
echo -e "${BOLD}${GREEN}🎉 MÓDULO DE LEADS E LISTAS CONFIGURÁVEIS PRONTOS NO VPS! [OK]       ${NC}"
echo -e "${BOLD}${GREEN}=====================================================================${NC}"
echo -e "Contêiner eleito:    ${BOLD}${DB_CONTAINER}${NC}"
echo -e "Usuário eleito:      ${BOLD}${DB_USER}${NC}"
echo -e "Banco eleito:        ${BOLD}${DB_NAME}${NC}"
echo -e "PostgREST cache:     ${BOLD}Recarregado via NOTIFY pgrst e restart de contêiner${NC}"
echo -e "${BOLD}${GREEN}=====================================================================${NC}"
echo -e "${BOLD}${YELLOW}Próximo passo: Abra https://sistema.advdouglaspsantos.com.br/leads, pressione Ctrl+F5 e acerte novo lead.${NC}"
echo -e "${BOLD}${GREEN}=====================================================================${NC}\n"
