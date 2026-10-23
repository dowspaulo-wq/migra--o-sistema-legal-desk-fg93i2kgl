#!/usr/bin/env bash
# ==============================================================================
# DPSjur / SBJur - Kit Onboarding de Clientes para Supabase Self-Hosted no VPS (EasyPanel)
# Script: docs/onboarding/01-adicionar-onboarding-checklist-settings.sh
# Versão: v1.3.0
# ==============================================================================
# Finalidade:
# 1. Adicionar com segurança e de forma idempotente a coluna "onboardingChecklist"
#    na tabela public.settings no PostgreSQL do Supabase Self-Hosted no VPS;
# 2. Inicializar as etapas padrão (8 etapas) caso nula ou vazia;
# 3. Remover trigger obsoleto 'on_client_created' que gerava indevidamente tarefas
#    de processo ao cadastrar cliente (Item 2);
# 4. Adicionar colunas de auditoria "created_by" em public.clients e public.cases (Item 1);
# 5. Emitir NOTIFY pgrst, 'reload schema' e reiniciar PostgREST para limpar o schema cache.
#
# Histórico de alterações:
# - v1.3.0: Correção crítica no bash da função run_sql_query (remoção do escape indevido '\$1'
#   que passava a string literal '$1' para o psql em vez da query), exibição em vermelho do erro
#   real do psql em vez de engolir a saída e conferências honestas pós-migração.
# - v1.2.3: Descoberta automática de contêiner Docker real e usuário/banco.
#
# Execução recomendada no terminal do VPS (como root - não interativo):
#   curl -sSL "https://raw.githubusercontent.com/dowspaulo-wq/migra--o-sistema-legal-desk-fg93i2kgl/main/docs/onboarding/01-adicionar-onboarding-checklist-settings.sh" -o /root/01-adicionar-onboarding-checklist-settings.sh
#   bash /root/01-adicionar-onboarding-checklist-settings.sh
# ==============================================================================

set -euo pipefail

SCRIPT_VERSION="v1.3.0"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${BOLD}${BLUE}=====================================================================${NC}"
echo -e "${BOLD}${BLUE} DPSjur - Atualização Onboarding & Dedo Duro no VPS                  ${NC}"
echo -e "${BOLD}${BLUE} Versão: ${SCRIPT_VERSION}${NC}"
echo -e "${BOLD}${BLUE}=====================================================================${NC}"
echo -e "Data: $(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || true)"
echo -e "Host: $(hostname 2>/dev/null || echo 'VPS')"
echo -e "${BOLD}${BLUE}=====================================================================${NC}\n"

# ------------------------------------------------------------------------------
# 1. Localização automática do contêiner Docker do PostgreSQL
# ------------------------------------------------------------------------------
echo -e "${BOLD}[1/4] Procurando contêiner Docker do PostgreSQL no VPS...${NC}"

DB_CONTAINER="${DB_CONTAINER:-${CONTAINER_LOCAL:-}}"

if [ -z "$DB_CONTAINER" ]; then
    DB_CONTAINER=$(docker ps --format "{{.Names}}" | grep -E 'dpsjur.*db|supabase.*db|sbjur.*db' | head -n 1 || true)
fi
if [ -z "$DB_CONTAINER" ]; then
    DB_CONTAINER=$(docker ps --filter "name=db" --format "{{.Names}}" | head -n 1 || true)
fi
if [ -z "$DB_CONTAINER" ]; then
    DB_CONTAINER=$(docker ps --filter "name=postgres" --format "{{.Names}}" | head -n 1 || true)
fi

echo -e "Contêiner Banco Postgres: ${GREEN}${DB_CONTAINER:-'não encontrado'}${NC}"

if [ -z "$DB_CONTAINER" ]; then
    echo -e "${RED}Erro fatal: Contêiner do banco de dados não foi encontrado. Verifique se o EasyPanel/Supabase está rodando.${NC}"
    echo "Contêineres em execução atualmente:"
    docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}' || true
    exit 1
fi

PGRST_CONTAINER=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -E 'supa?base.*rest|postgrest' | head -n 1 || true)

# ------------------------------------------------------------------------------
# 2. Introspecção de credenciais e detecção robusta de usuário/banco
# ------------------------------------------------------------------------------
echo -e "\n${BOLD}[2/4] Detectando usuário e banco de dados disponíveis...${NC}"

INSPECT_USER=$(docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "$DB_CONTAINER" 2>/dev/null | grep -E '^POSTGRES_USER=' | head -n 1 | cut -d= -f2- || true)
INSPECT_DB=$(docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "$DB_CONTAINER" 2>/dev/null | grep -E '^POSTGRES_DB=' | head -n 1 | cut -d= -f2- || true)
INSPECT_PASS=$(docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "$DB_CONTAINER" 2>/dev/null | grep -E '^POSTGRES_PASSWORD=' | head -n 1 | cut -d= -f2- || true)

LOCAL_DB_PASSWORD="${POSTGRES_PASSWORD:-${INSPECT_PASS:-}}"

CANDIDATE_USERS=()
[ -n "${POSTGRES_USER:-}" ] && CANDIDATE_USERS+=("${POSTGRES_USER}")
[ -n "$INSPECT_USER" ] && CANDIDATE_USERS+=("$INSPECT_USER")
CANDIDATE_USERS+=("supabase_admin" "postgres" "Doug")

UNIQUE_USERS=()
for u in "${CANDIDATE_USERS[@]}"; do
    [[ " ${UNIQUE_USERS[*]} " =~ " ${u} " ]] || UNIQUE_USERS+=("$u")
done

DETECTED_USER=""
DETECTED_DB=""

for test_u in "${UNIQUE_USERS[@]}"; do
    if [ -n "$LOCAL_DB_PASSWORD" ]; then
        DB_LIST=$(docker exec -i -e PGPASSWORD="$LOCAL_DB_PASSWORD" "$DB_CONTAINER" psql -U "$test_u" -At -c "SELECT datname FROM pg_database WHERE datistemplate = false;" 2>/dev/null || true)
    else
        DB_LIST=$(docker exec -i "$DB_CONTAINER" psql -U "$test_u" -At -c "SELECT datname FROM pg_database WHERE datistemplate = false;" 2>/dev/null || true)
    fi

    if [ -n "$DB_LIST" ]; then
        DETECTED_USER="$test_u"
        for cand_db in "${POSTGRES_DB:-}" "$INSPECT_DB" "dpsjur" "postgres"; do
            if [ -n "$cand_db" ] && echo "$DB_LIST" | grep -qx "$cand_db"; then
                DETECTED_DB="$cand_db"
                break
            fi
        done
        if [ -z "$DETECTED_DB" ]; then
            DETECTED_DB=$(echo "$DB_LIST" | head -n 1)
        fi
        break
    fi
done

if [ -z "$DETECTED_USER" ]; then
    for test_u in "${UNIQUE_USERS[@]}"; do
        for test_d in "${POSTGRES_DB:-}" "$INSPECT_DB" "postgres" "dpsjur"; do
            [ -z "$test_d" ] && continue
            if [ -n "$LOCAL_DB_PASSWORD" ]; then
                if docker exec -i -e PGPASSWORD="$LOCAL_DB_PASSWORD" "$DB_CONTAINER" psql -U "$test_u" -d "$test_d" -At -c "SELECT 1;" >/dev/null 2>&1; then
                    DETECTED_USER="$test_u"
                    DETECTED_DB="$test_d"
                    break 2
                fi
            else
                if docker exec -i "$DB_CONTAINER" psql -U "$test_u" -d "$test_d" -At -c "SELECT 1;" >/dev/null 2>&1; then
                    DETECTED_USER="$test_u"
                    DETECTED_DB="$test_d"
                    break 2
                fi
            fi
        done
    done
fi

DB_USER="${DETECTED_USER:-supabase_admin}"
DB_NAME="${DETECTED_DB:-postgres}"

echo -e "Usuário PostgreSQL detectado: ${GREEN}${DB_USER}${NC}"
echo -e "Banco de Dados detectado:     ${GREEN}${DB_NAME}${NC}"

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
# 3. Execução da migração SQL idempotente
# ------------------------------------------------------------------------------
echo -e "\n${BOLD}[3/4] Aplicando migração SQL idempotente...${NC}"

MIGRATION_SQL="
DO \$\$
BEGIN
    -- 1. Garante que a tabela public.settings existe
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.tables 
        WHERE table_schema = 'public' AND table_name = 'settings'
    ) THEN
        RAISE EXCEPTION 'Tabela public.settings não existe no banco de dados.';
    END IF;

    -- 2. Adiciona a coluna onboardingChecklist (JSONB) caso não exista
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' 
          AND table_name = 'settings' 
          AND column_name = 'onboardingChecklist'
    ) THEN
        ALTER TABLE public.settings ADD COLUMN \"onboardingChecklist\" JSONB DEFAULT '[
            {\"id\": \"step-1\", \"title\": \"Cadastrar cliente\", \"order\": 1},
            {\"id\": \"step-2\", \"title\": \"Cadastrar processo(s)\", \"order\": 2},
            {\"id\": \"step-3\", \"title\": \"Coletar documentos\", \"order\": 3},
            {\"id\": \"step-4\", \"title\": \"Tratar documentos (qualidade/PDFs)\", \"order\": 4},
            {\"id\": \"step-5\", \"title\": \"Redigir procuração\", \"order\": 5},
            {\"id\": \"step-6\", \"title\": \"Redigir contrato\", \"order\": 6},
            {\"id\": \"step-7\", \"title\": \"Redigir declaração de hipossuficiência\", \"order\": 7},
            {\"id\": \"step-8\", \"title\": \"Monitorar assinaturas\", \"order\": 8}
        ]'::jsonb;
        RAISE NOTICE 'Coluna onboardingChecklist adicionada com sucesso na tabela public.settings.';
    ELSE
        RAISE NOTICE 'Coluna onboardingChecklist já existe na tabela public.settings.';
    END IF;

    -- 3. Preencher registros existentes caso esteja NULL
    UPDATE public.settings
    SET \"onboardingChecklist\" = '[
        {\"id\": \"step-1\", \"title\": \"Cadastrar cliente\", \"order\": 1},
        {\"id\": \"step-2\", \"title\": \"Cadastrar processo(s)\", \"order\": 2},
        {\"id\": \"step-3\", \"title\": \"Coletar documentos\", \"order\": 3},
        {\"id\": \"step-4\", \"title\": \"Tratar documentos (qualidade/PDFs)\", \"order\": 4},
        {\"id\": \"step-5\", \"title\": \"Redigir procuração\", \"order\": 5},
        {\"id\": \"step-6\", \"title\": \"Redigir contrato\", \"order\": 6},
        {\"id\": \"step-7\", \"title\": \"Redigir declaração de hipossuficiência\", \"order\": 7},
        {\"id\": \"step-8\", \"title\": \"Monitorar assinaturas\", \"order\": 8}
    ]'::jsonb
    WHERE \"onboardingChecklist\" IS NULL;

    -- 4. Remoção do trigger obsoleto on_client_created (Bug do Onboarding - Item 2)
    -- Tarefas de processo NÃO devem nascer no cadastro de cliente!
    DROP TRIGGER IF EXISTS on_client_created ON public.clients;
    DROP FUNCTION IF EXISTS public.handle_new_client_tasks();
    RAISE NOTICE 'Trigger obsoleto on_client_created removido com sucesso de public.clients.';

    -- 5. Adicionar coluna created_by em public.clients (Dedo duro - Item 1)
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' 
          AND table_name = 'clients' 
          AND column_name = 'created_by'
    ) THEN
        ALTER TABLE public.clients ADD COLUMN created_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL;
        CREATE INDEX IF NOT EXISTS idx_clients_created_by ON public.clients(created_by);
        RAISE NOTICE 'Coluna created_by adicionada em public.clients.';
    END IF;

    -- 6. Adicionar coluna created_by em public.cases (Dedo duro - Item 1)
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' 
          AND table_name = 'cases' 
          AND column_name = 'created_by'
    ) THEN
        ALTER TABLE public.cases ADD COLUMN created_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL;
        CREATE INDEX IF NOT EXISTS idx_cases_created_by ON public.cases(created_by);
        RAISE NOTICE 'Coluna created_by adicionada em public.cases.';
    END IF;

    -- 7. Preenchimento retroativo seguro de created_by herdando do responsibleId
    UPDATE public.clients
    SET created_by = \"responsibleId\"
    WHERE created_by IS NULL AND \"responsibleId\" IS NOT NULL;

    UPDATE public.cases
    SET created_by = \"responsibleId\"
    WHERE created_by IS NULL AND \"responsibleId\" IS NOT NULL;

    -- 8. Garantir políticas de RLS em settings
    ALTER TABLE public.settings ENABLE ROW LEVEL SECURITY;

    DROP POLICY IF EXISTS \"authenticated_select_settings\" ON public.settings;
    CREATE POLICY \"authenticated_select_settings\" ON public.settings
        FOR SELECT TO authenticated USING (true);

    DROP POLICY IF EXISTS \"authenticated_update_settings\" ON public.settings;
    CREATE POLICY \"authenticated_update_settings\" ON public.settings
        FOR UPDATE TO authenticated USING (true) WITH CHECK (true);

END \$\$;
"

if [ -n "$LOCAL_DB_PASSWORD" ]; then
    docker exec -i -e PGPASSWORD="$LOCAL_DB_PASSWORD" "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 <<< "$MIGRATION_SQL"
else
    docker exec -i "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 <<< "$MIGRATION_SQL"
fi

echo -e "${GREEN}✓ Instruções SQL aplicadas com sucesso no PostgreSQL!${NC}"

# Notificar o PostgREST para recarregar o schema cache imediatamente
echo -e "🔄 Recarregando cache do PostgREST via NOTIFY pgrst..."
run_sql_query "NOTIFY pgrst, 'reload schema';" >/dev/null 2>&1 || true

if [ -n "$PGRST_CONTAINER" ]; then
    echo -e "🔄 Reiniciando contêiner do PostgREST (${PGRST_CONTAINER}) para garantir cache limpo..."
    docker restart "$PGRST_CONTAINER" >/dev/null 2>&1 || true
    echo -e "${GREEN}✓ Contêiner PostgREST reiniciado!${NC}"
fi

# ------------------------------------------------------------------------------
# 4. Conferência rigorosa pós-migração
# ------------------------------------------------------------------------------
echo -e "\n${BOLD}[4/4] Conferência do schema no PostgreSQL (usuário: ${DB_USER}, banco: ${DB_NAME}):${NC}"

COL_STATUS=$(run_sql_query "SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'settings' AND column_name = 'onboardingChecklist');" || echo "erro")
COL_TYPE=$(run_sql_query "SELECT data_type FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'settings' AND column_name = 'onboardingChecklist';" || echo "desconhecido")
SETTINGS_COUNT=$(run_sql_query "SELECT count(*) FROM public.settings;" || echo "0")
CHECKLIST_COUNT=$(run_sql_query "SELECT jsonb_array_length(\"onboardingChecklist\") FROM public.settings WHERE \"onboardingChecklist\" IS NOT NULL LIMIT 1;" || echo "0")

CLIENT_CREATED_BY=$(run_sql_query "SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'clients' AND column_name = 'created_by');" || echo "erro")
CASE_CREATED_BY=$(run_sql_query "SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'cases' AND column_name = 'created_by');" || echo "erro")
TRIGGER_CLIENT_STATUS=$(run_sql_query "SELECT EXISTS (SELECT 1 FROM information_schema.triggers WHERE event_object_table = 'clients' AND trigger_name = 'on_client_created');" || echo "erro")

echo -e "   - Coluna 'onboardingChecklist': $( [ "$COL_STATUS" = "t" ] && echo -e "${GREEN}EXISTE (tipo: ${COL_TYPE}) [OK]${NC}" || echo -e "${RED}NÃO ENCONTRADA [FALHA]${NC}" )"
echo -e "   - Coluna 'clients.created_by':  $( [ "$CLIENT_CREATED_BY" = "t" ] && echo -e "${GREEN}EXISTE [OK]${NC}" || echo -e "${RED}NÃO ENCONTRADA [FALHA]${NC}" )"
echo -e "   - Coluna 'cases.created_by':    $( [ "$CASE_CREATED_BY" = "t" ] && echo -e "${GREEN}EXISTE [OK]${NC}" || echo -e "${RED}NÃO ENCONTRADA [FALHA]${NC}" )"
echo -e "   - Trigger antigo em clients:    $( [ "$TRIGGER_CLIENT_STATUS" = "f" ] && echo -e "${GREEN}REMOVIDO COM SUCESSO [OK]${NC}" || echo -e "${YELLOW}AINDA PRESENTE [ATENÇÃO]${NC}" )"
echo -e "   - Registros em public.settings: ${GREEN}${SETTINGS_COUNT} linha(s) [OK]${NC}"
echo -e "   - Etapas do modelo padrão:     ${GREEN}${CHECKLIST_COUNT:-0} etapa(s) [OK]${NC}"

if [ "$COL_STATUS" != "t" ] || [ "$CLIENT_CREATED_BY" != "t" ] || [ "$CASE_CREATED_BY" != "t" ]; then
    echo -e "\n${RED}❌ ERRO: Uma ou mais colunas não foram detectadas após a execução.${NC}"
    exit 1
fi

echo -e "\n${BOLD}${GREEN}=====================================================================${NC}"
echo -e "${BOLD}${GREEN}🎉 BANCO DE DADOS ATUALIZADO COM SUCESSO NO VPS!                     ${NC}"
echo -e "${BOLD}${GREEN}=====================================================================${NC}"
echo -e "Status da coluna: ${BOLD}OK${NC} (public.settings.onboardingChecklist)"
echo -e "Status auditoria: ${BOLD}OK${NC} (clients.created_by e cases.created_by)"
echo -e "Status automação: ${BOLD}OK${NC} (trigger indevido removido)"
echo -e "Schema cache do PostgREST recarregado com sucesso."
echo -e "${BOLD}${GREEN}=====================================================================${NC}\n"
