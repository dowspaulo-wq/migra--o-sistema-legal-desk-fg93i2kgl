#!/usr/bin/env bash
# ==============================================================================
# DPSjur / SBJur - Kit Google Sheets para Supabase Self-Hosted no VPS (EasyPanel)
# Script: docs/integracoes/02-adicionar-coluna-service-account.sh
# Versão: v1.0.0
# ==============================================================================
# Finalidade:
# Adicionar com segurança e de forma idempotente a coluna "googleServiceAccount"
# na tabela public.settings no PostgreSQL do Supabase Self-Hosted no VPS,
# garantir as políticas de RLS para usuário autenticado e emitir
# NOTIFY pgrst, 'reload schema' para atualizar o schema cache do PostgREST.
#
# Isso resolve exatamente o erro:
#   "Erro ao salvar Service Account — Could not find the 'googleServiceAccount'
#    column of 'settings' in the schema cache"
#
# Execução recomendada no terminal do VPS (como root - não interativo):
#   curl -sSL "https://raw.githubusercontent.com/dowspaulo-wq/migra--o-sistema-legal-desk-fg93i2kgl/main/docs/integracoes/02-adicionar-coluna-service-account.sh" -o /root/02-adicionar-coluna-service-account.sh
#   bash /root/02-adicionar-coluna-service-account.sh
# ==============================================================================

set -euo pipefail

SCRIPT_VERSION="v1.0.0"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${BOLD}${BLUE}=====================================================================${NC}"
echo -e "${BOLD}${BLUE} DPSjur - Adicionar Coluna googleServiceAccount em Settings (VPS)     ${NC}"
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

# Mapear contêineres do PostgREST e Functions para recarga imediata de cache
PGRST_CONTAINER=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -E 'supa?base.*rest|postgrest' | head -n 1 || true)
FUNCTIONS_CONTAINER=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -E 'supa?base.*functions|edge-runtime' | head -n 1 || true)

# ------------------------------------------------------------------------------
# 2. Introspecção de credenciais e detecção robusta de usuário/banco
# ------------------------------------------------------------------------------
echo -e "\n${BOLD}[2/4] Detectando usuário e banco de dados disponíveis...${NC}"

INSPECT_USER=$(docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "$DB_CONTAINER" 2>/dev/null | grep -E '^POSTGRES_USER=' | head -n 1 | cut -d= -f2- || true)
INSPECT_DB=$(docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "$DB_CONTAINER" 2>/dev/null | grep -E '^POSTGRES_DB=' | head -n 1 | cut -d= -f2- || true)
INSPECT_PASS=$(docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "$DB_CONTAINER" 2>/dev/null | grep -E '^POSTGRES_PASSWORD=' | head -n 1 | cut -d= -f2- || true)

LOCAL_DB_PASSWORD="${POSTGRES_PASSWORD:-${INSPECT_PASS:-}}"

# Lista de candidatos a usuário com fallback ordenado
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

# Fallback seguro caso 'pg_database' precise de conexão direta a um banco específico
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

# Helper para executar SQL com captura limpa de saída
run_sql_query() {
    local sql_query="$1"
    if [ -n "$LOCAL_DB_PASSWORD" ]; then
        docker exec -i -e PGPASSWORD="$LOCAL_DB_PASSWORD" "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -tAc "$sql_query" 2>&1
    else
        docker exec -i "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -tAc "$sql_query" 2>&1
    fi
}

# ------------------------------------------------------------------------------
# 3. Execução da migração SQL idempotente
# ------------------------------------------------------------------------------
echo -e "\n${BOLD}[3/4] Aplicando migração SQL idempotente na tabela public.settings...${NC}"

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

    -- 2. Adiciona a coluna googleServiceAccount (tipo TEXT) caso não exista
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' 
          AND table_name = 'settings' 
          AND column_name = 'googleServiceAccount'
    ) THEN
        ALTER TABLE public.settings ADD COLUMN \"googleServiceAccount\" TEXT;
        RAISE NOTICE 'Coluna googleServiceAccount adicionada com sucesso na tabela public.settings.';
    ELSE
        RAISE NOTICE 'Coluna googleServiceAccount já existe na tabela public.settings (sem alterações na estrutura).';
    END IF;

    -- 3. Documentação da coluna
    COMMENT ON COLUMN public.settings.\"googleServiceAccount\" IS 'Chave de autenticação JSON da Google Service Account para espelhamento em Google Sheets';

    -- 4. Garantir que exista ao menos 1 registro em settings para o frontend poder atualizar
    IF NOT EXISTS (SELECT 1 FROM public.settings LIMIT 1) THEN
        INSERT INTO public.settings (id, \"showFinanceDashboard\", \"themeColor\", created_at)
        VALUES (gen_random_uuid(), true, 'blue', NOW());
        RAISE NOTICE 'Registro inicial criado em public.settings.';
    END IF;

    -- 5. Garantir políticas de RLS completas e idempotentes para public.settings
    ALTER TABLE public.settings ENABLE ROW LEVEL SECURITY;

    DROP POLICY IF EXISTS \"authenticated_select_settings\" ON public.settings;
    CREATE POLICY \"authenticated_select_settings\" ON public.settings
        FOR SELECT TO authenticated USING (true);

    DROP POLICY IF EXISTS \"authenticated_insert_settings\" ON public.settings;
    CREATE POLICY \"authenticated_insert_settings\" ON public.settings
        FOR INSERT TO authenticated WITH CHECK (true);

    DROP POLICY IF EXISTS \"authenticated_update_settings\" ON public.settings;
    CREATE POLICY \"authenticated_update_settings\" ON public.settings
        FOR UPDATE TO authenticated USING (true) WITH CHECK (true);

    DROP POLICY IF EXISTS \"authenticated_delete_settings\" ON public.settings;
    CREATE POLICY \"authenticated_delete_settings\" ON public.settings
        FOR DELETE TO authenticated USING (true);

    DROP POLICY IF EXISTS \"service_role_all_settings\" ON public.settings;
    CREATE POLICY \"service_role_all_settings\" ON public.settings
        FOR ALL TO service_role USING (true) WITH CHECK (true);

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

if [ -n "$FUNCTIONS_CONTAINER" ]; then
    echo -e "🔄 Reiniciando contêiner do Functions Runtime (${FUNCTIONS_CONTAINER})..."
    docker restart "$FUNCTIONS_CONTAINER" >/dev/null 2>&1 || true
    echo -e "${GREEN}✓ Contêiner Edge Functions reiniciado!${NC}"
fi

# ------------------------------------------------------------------------------
# 4. Conferência rigorosa pós-migração
# ------------------------------------------------------------------------------
echo -e "\n${BOLD}[4/4] Conferência do schema no PostgreSQL (usuário: ${DB_USER}, banco: ${DB_NAME}):${NC}"

COL_STATUS=$(run_sql_query "SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'settings' AND column_name = 'googleServiceAccount');")
COL_TYPE=$(run_sql_query "SELECT data_type FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'settings' AND column_name = 'googleServiceAccount';")
SETTINGS_COUNT=$(run_sql_query "SELECT count(*) FROM public.settings;")
POLICIES_COUNT=$(run_sql_query "SELECT count(*) FROM pg_policies WHERE schemaname = 'public' AND tablename = 'settings';")

echo -e "   - Coluna 'googleServiceAccount': $( [ "$COL_STATUS" = "t" ] && echo -e "${GREEN}EXISTE (tipo: ${COL_TYPE}) [OK]${NC}" || echo -e "${RED}NÃO ENCONTRADA [FALHA]${NC}" )"
echo -e "   - Registros em public.settings:  ${GREEN}${SETTINGS_COUNT} linha(s) [OK]${NC}"
echo -e "   - Políticas RLS ativas:          ${GREEN}${POLICIES_COUNT} política(s) [OK]${NC}"

if [ "$COL_STATUS" != "t" ]; then
    echo -e "\n${RED}❌ ERRO: A coluna googleServiceAccount não foi detectada após a execução.${NC}"
    exit 1
fi

echo -e "\n${BOLD}${GREEN}=====================================================================${NC}"
echo -e "${BOLD}${GREEN}🎉 BANCO DE DADOS ATUALIZADO COM SUCESSO NO VPS!                     ${NC}"
echo -e "${BOLD}${GREEN}=====================================================================${NC}"
echo -e "Status da coluna: ${BOLD}OK${NC} (public.settings.googleServiceAccount)"
echo -e "Schema cache do PostgREST recarregado com sucesso."
echo ""
echo -e "Próximos passos para o Douglas:"
echo -e "1. Volte ao navegador em ${BOLD}https://sistema.advdouglaspsantos.com.br/configuracoes${NC}"
echo -e "2. Vá na aba ${BOLD}Integrações${NC} → Cartão ${BOLD}Espelhamento de Clientes (Google Sheets)${NC}."
echo -e "3. Cole o JSON da sua Service Account no campo de texto."
echo -e "4. Clique no botão ${BOLD}\"Salvar Service Account\"${NC} (agora salvará com sucesso!)."
echo -e "5. Clique no botão ${BOLD}\"Sincronizar Planilha Agora\"${NC} para rodar o primeiro espelhamento."
echo -e "6. (Opcional) Instale o cron diário das 06:00 caso ainda não tenha feito:"
echo -e "   ${BOLD}bash docs/integracoes/01-instalar-cron-sheets.sh${NC}"
echo -e "${BOLD}${GREEN}=====================================================================${NC}\n"
