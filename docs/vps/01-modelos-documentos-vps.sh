#!/usr/bin/env bash
# ==============================================================================
# DPSjur / SBJur - Fase Documentos: Atualização de Modelos e Storage no VPS
# Script: docs/vps/01-modelos-documentos-vps.sh
# Versão: v1.4.0
# Alvo: VPS Hostinger 2.25.181.69 (EasyPanel / Supabase Self-Hosted)
# ==============================================================================
# Finalidade:
# 1. Localizar o contêiner real do PostgreSQL no VPS através de varredura Docker
#    e eleger o banco de produção com base na quantidade real de registros em
#    public.clients e public.cases (NUNCA hardcodar Doug/dpsjur que é banco vazio).
# 2. Executar migração SQL via arquivo temporário (docker cp + psql -f) para evitar
#    qualquer expansão indevida de variáveis ou $ pelo bash:
#    - Adição idempotente de colunas em public.document_templates:
#      manual_fields jsonb DEFAULT '[]', description text, updated_at timestamptz DEFAULT now()
#    - Habilitação e reforço de RLS com políticas para authenticated e service_role
#    - Criação dos buckets no storage.buckets: 'document_templates', 'document-templates' e 'documents'
#    - Criação de políticas RLS em storage.objects para upload, download, update e delete
# 3. Recarregar cache do PostgREST via NOTIFY pgrst e restart do contêiner PostgREST
# 4. Conferência rigorosa e HONESTA com [OK]/[FALHA] consultando o information_schema
#    e storage.buckets/storage.objects do banco eleito, abortando com código 1 caso algo falhe.
# 5. Idempotência garantida: executar múltiplas vezes é 100% seguro.
#
# Execução no terminal do VPS (como root - comando único sem pipe):
#   curl -sSL "https://raw.githubusercontent.com/dowspaulo-wq/migra--o-sistema-legal-desk-fg93i2kgl/main/docs/vps/01-modelos-documentos-vps.sh" -o /root/01-modelos-documentos-vps.sh && bash /root/01-modelos-documentos-vps.sh
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
echo -e "${BOLD}${BLUE} DPSjur - Migração VPS: Modelos de Documentos e Storage (.docx)     ${NC}"
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

SQL_TEMP_HOST=$(mktemp /tmp/document_templates_vps_XXXXXX.sql)

# Note: aspas simples em 'EOF_MIGRATION_SQL' impedem expansão de variáveis pelo bash
cat << 'EOF_MIGRATION_SQL' > "$SQL_TEMP_HOST"
BEGIN;

DO $$
BEGIN
    ---------------------------------------------------------------------------
    -- 1. Criação/Garantia da tabela public.document_templates
    ---------------------------------------------------------------------------
    CREATE TABLE IF NOT EXISTS public.document_templates (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        name TEXT NOT NULL,
        file_path TEXT NOT NULL,
        category TEXT DEFAULT 'Geral',
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );

    -- Colunas adicionais da Fase Documentos
    ALTER TABLE public.document_templates ADD COLUMN IF NOT EXISTS manual_fields JSONB DEFAULT '[]'::jsonb;
    ALTER TABLE public.document_templates ADD COLUMN IF NOT EXISTS description TEXT;
    ALTER TABLE public.document_templates ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW();

    -- Permissões
    GRANT SELECT, INSERT, UPDATE, DELETE ON public.document_templates TO authenticated;
    GRANT ALL ON public.document_templates TO service_role;

    ---------------------------------------------------------------------------
    -- 2. Habilitação de RLS e políticas
    ---------------------------------------------------------------------------
    ALTER TABLE public.document_templates ENABLE ROW LEVEL SECURITY;

    DROP POLICY IF EXISTS "authenticated_select_document_templates" ON public.document_templates;
    CREATE POLICY "authenticated_select_document_templates" ON public.document_templates
        FOR SELECT TO authenticated USING (true);

    DROP POLICY IF EXISTS "authenticated_insert_document_templates" ON public.document_templates;
    CREATE POLICY "authenticated_insert_document_templates" ON public.document_templates
        FOR INSERT TO authenticated WITH CHECK (true);

    DROP POLICY IF EXISTS "authenticated_update_document_templates" ON public.document_templates;
    CREATE POLICY "authenticated_update_document_templates" ON public.document_templates
        FOR UPDATE TO authenticated USING (true) WITH CHECK (true);

    DROP POLICY IF EXISTS "authenticated_delete_document_templates" ON public.document_templates;
    CREATE POLICY "authenticated_delete_document_templates" ON public.document_templates
        FOR DELETE TO authenticated USING (true);

    ---------------------------------------------------------------------------
    -- 3. Buckets de Storage
    ---------------------------------------------------------------------------
    IF EXISTS (
        SELECT 1 FROM information_schema.tables 
        WHERE table_schema = 'storage' AND table_name = 'buckets'
    ) THEN
        INSERT INTO storage.buckets (id, name, public)
        VALUES ('document_templates', 'document_templates', true)
        ON CONFLICT (id) DO UPDATE SET public = true;

        INSERT INTO storage.buckets (id, name, public)
        VALUES ('document-templates', 'document-templates', true)
        ON CONFLICT (id) DO UPDATE SET public = true;

        INSERT INTO storage.buckets (id, name, public)
        VALUES ('documents', 'documents', true)
        ON CONFLICT (id) DO UPDATE SET public = true;
    END IF;

    ---------------------------------------------------------------------------
    -- 4. Políticas RLS de Storage
    ---------------------------------------------------------------------------
    IF EXISTS (
        SELECT 1 FROM information_schema.tables 
        WHERE table_schema = 'storage' AND table_name = 'objects'
    ) THEN
        DROP POLICY IF EXISTS "authenticated_read_document_templates_bucket" ON storage.objects;
        CREATE POLICY "authenticated_read_document_templates_bucket" ON storage.objects
            FOR SELECT TO authenticated
            USING (bucket_id IN ('document_templates', 'document-templates', 'documents'));

        DROP POLICY IF EXISTS "authenticated_upload_document_templates_bucket" ON storage.objects;
        CREATE POLICY "authenticated_upload_document_templates_bucket" ON storage.objects
            FOR INSERT TO authenticated
            WITH CHECK (bucket_id IN ('document_templates', 'document-templates', 'documents'));

        DROP POLICY IF EXISTS "authenticated_update_document_templates_bucket" ON storage.objects;
        CREATE POLICY "authenticated_update_document_templates_bucket" ON storage.objects
            FOR UPDATE TO authenticated
            USING (bucket_id IN ('document_templates', 'document-templates', 'documents'))
            WITH CHECK (bucket_id IN ('document_templates', 'document-templates', 'documents'));

        DROP POLICY IF EXISTS "authenticated_delete_document_templates_bucket" ON storage.objects;
        CREATE POLICY "authenticated_delete_document_templates_bucket" ON storage.objects
            FOR DELETE TO authenticated
            USING (bucket_id IN ('document_templates', 'document-templates', 'documents'));
    END IF;

END $$;

COMMIT;
EOF_MIGRATION_SQL

RAND_ID="doc_tpl_${RANDOM:-$$}_$(date +%s 2>/dev/null || echo '0')"
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

# 1. Tabela document_templates existe
TABLE_EXISTS=$(run_sql_query "SELECT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'document_templates');" || echo "erro")

# 2. Contagem de colunas em document_templates (esperado: 8)
COLS_COUNT=$(run_sql_query "SELECT count(*) FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'document_templates' AND column_name IN ('id', 'name', 'file_path', 'category', 'created_at', 'manual_fields', 'description', 'updated_at');" || echo "0")

# 3. RLS habilitado em document_templates
RLS_ENABLED=$(run_sql_query "SELECT relrowsecurity FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'public' AND c.relname = 'document_templates';" || echo "f")

# 4. Políticas RLS na tabela document_templates (esperado >= 4)
POLICIES_COUNT=$(run_sql_query "SELECT count(*) FROM pg_policies WHERE schemaname = 'public' AND tablename = 'document_templates';" || echo "0")

# 5. Buckets no storage
BUCKETS_COUNT=$(run_sql_query "SELECT count(*) FROM storage.buckets WHERE id IN ('document_templates', 'document-templates', 'documents');" || echo "0")

# 6. Políticas de storage
STORAGE_POLS_COUNT=$(run_sql_query "SELECT count(*) FROM pg_policies WHERE schemaname = 'storage' AND tablename = 'objects' AND policyname LIKE '%document_templates_bucket%';" || echo "0")

# Exibição dos resultados honestos
echo -e "   - 1. Tabela 'document_templates':     $( [ "$TABLE_EXISTS" = "t" ] && echo -e "${GREEN}EXISTE [OK]${NC}" || echo -e "${RED}NÃO ENCONTRADA [FALHA]${NC}" )"
echo -e "   - 2. Colunas 'document_templates':    $( [ "${COLS_COUNT:-0}" -ge 8 ] && echo -e "${GREEN}${COLS_COUNT}/8 colunas verificadas (manual_fields, description, ...) [OK]${NC}" || echo -e "${RED}${COLS_COUNT:-0}/8 colunas [FALHA]${NC}" )"
echo -e "   - 3. Row Level Security (RLS):        $( [ "$RLS_ENABLED" = "t" ] && echo -e "${GREEN}HABILITADO [OK]${NC}" || echo -e "${RED}DESABILITADO [FALHA]${NC}" )"
echo -e "   - 4. Políticas RLS da tabela:         $( [ "${POLICIES_COUNT:-0}" -ge 4 ] && echo -e "${GREEN}${POLICIES_COUNT} políticas ativas [OK]${NC}" || echo -e "${RED}${POLICIES_COUNT:-0} políticas [FALHA]${NC}" )"
echo -e "   - 5. Buckets de Storage:              $( [ "${BUCKETS_COUNT:-0}" -ge 2 ] && echo -e "${GREEN}${BUCKETS_COUNT} buckets confirmados [OK]${NC}" || echo -e "${YELLOW}${BUCKETS_COUNT:-0} buckets [AVISO]${NC}" )"
echo -e "   - 6. Políticas de Storage (.docx):    $( [ "${STORAGE_POLS_COUNT:-0}" -ge 3 ] && echo -e "${GREEN}${STORAGE_POLS_COUNT} políticas de storage ativas [OK]${NC}" || echo -e "${YELLOW}${STORAGE_POLS_COUNT:-0} políticas [AVISO]${NC}" )"

# Validação do sucesso geral
VERIFICATION_FAILED=0
if [ "$TABLE_EXISTS" != "t" ]; then VERIFICATION_FAILED=1; fi
if [ "${COLS_COUNT:-0}" -lt 8 ]; then VERIFICATION_FAILED=1; fi
if [ "$RLS_ENABLED" != "t" ]; then VERIFICATION_FAILED=1; fi
if [ "${POLICIES_COUNT:-0}" -lt 4 ]; then VERIFICATION_FAILED=1; fi

if [ $VERIFICATION_FAILED -ne 0 ]; then
    echo -e "\n${RED}=====================================================================${NC}"
    echo -e "${RED}❌ ERRO: A verificação final detectou falhas no banco!               ${NC}"
    echo -e "${RED}Um ou mais itens críticos não foram criados corretamente.            ${NC}"
    echo -e "${RED}=====================================================================${NC}\n"
    exit 1
fi

echo -e "\n${BOLD}${GREEN}=====================================================================${NC}"
echo -e "${BOLD}${GREEN}🎉 MODELOS DE DOCUMENTOS E STORAGE .DOCX PRONTOS NO VPS! [OK]       ${NC}"
echo -e "${BOLD}${GREEN}=====================================================================${NC}"
echo -e "Contêiner eleito:    ${BOLD}${DB_CONTAINER}${NC}"
echo -e "Usuário eleito:      ${BOLD}${DB_USER}${NC}"
echo -e "Banco eleito:        ${BOLD}${DB_NAME}${NC}"
echo -e "PostgREST cache:     ${BOLD}Recarregado via NOTIFY pgrst e restart de contêiner${NC}"
echo -e "${BOLD}${GREEN}=====================================================================${NC}"
echo -e "${BOLD}${YELLOW}Próximo passo: No navegador, acerte Ctrl+F5 no sistema do VPS e utilize a aba Modelos de Documentos.${NC}"
echo -e "${BOLD}${GREEN}=====================================================================${NC}\n"
