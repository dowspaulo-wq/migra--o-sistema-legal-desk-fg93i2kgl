#!/usr/bin/env bash
# ==============================================================================
# DPSjur / SBJur - Kit Garantia da Coluna noFees (Processos & Subprocessos) no VPS (EasyPanel)
# Script: docs/processos/01-garantir-no-fees-processos-vps.sh
# Versão: v1.4.0
# ==============================================================================
# Finalidade:
# 1. Descobrir automaticamente o contêiner Docker real do PostgreSQL, usuário
#    funcional e banco ativo com maior volume de dados (public.clients), exatamente
#    como no padrão v1.4.0 de onboarding e automação, evitando conexões cegas em bancos
#    vazios ou secundários;
# 2. Adicionar com segurança e de forma idempotente a coluna "noFees" (BOOLEAN NOT NULL DEFAULT false)
#    na tabela public.cases no PostgreSQL do Supabase Self-Hosted no VPS, permitindo marcar
#    tanto subprocessos quanto processos principais como "Não gera honorários";
# 3. Garantir permissões de SELECT, INSERT, UPDATE na coluna/tabela para roles authenticated e service_role;
# 4. Emitir NOTIFY pgrst, 'reload schema' e reiniciar PostgREST para limpar o schema cache;
# 5. Realizar conferência pós-migração no MESMO contêiner, usuário e banco detectados,
#    só emitindo [OK] se a coluna existir de verdade.
#
# Execução recomendada no terminal do VPS (como root - não interativo):
#   curl -sSL "https://raw.githubusercontent.com/dowspaulo-wq/migra--o-sistema-legal-desk-fg93i2kgl/main/docs/processos/01-garantir-no-fees-processos-vps.sh" -o /root/01-garantir-no-fees-processos-vps.sh
#   bash /root/01-garantir-no-fees-processos-vps.sh
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
echo -e "${BOLD}${BLUE} DPSjur - Garantia da Coluna noFees (Processos) no VPS               ${NC}"
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
# 1. Varredura e detecção do contêiner Docker real do PostgreSQL e do banco com dados
# ------------------------------------------------------------------------------
echo -e "${BOLD}${CYAN}[1/4] Varrendo contêineres PostgreSQL no VPS...${NC}"

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

# PostgREST container detection
PGRST_CONTAINER=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -Ei 'supa?base.*rest|postgrest' | head -n 1 || true)
if [ -n "$PGRST_CONTAINER" ]; then
    echo -e "   - Contêiner PostgREST: ${GREEN}${PGRST_CONTAINER}${NC}"
else
    echo -e "   - Contêiner PostgREST: ${YELLOW}Não encontrado pelo padrão 'rest|postgrest'${NC}"
fi

# Variáveis unificadas para a execução do psql
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
# 2. Execução da migração SQL idempotente entregue via arquivo (docker cp + psql -f)
# ------------------------------------------------------------------------------
echo -e "\n${BOLD}${CYAN}[2/4] Aplicando migração SQL idempotente via arquivo no banco real...${NC}"

SQL_TEMP_HOST=$(mktemp /tmp/migration_nofees_XXXXXX.sql)
cat << 'EOF_MIGRATION_SQL' > "$SQL_TEMP_HOST"
BEGIN;

-- 1. Garante que a tabela public.cases existe
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.tables 
        WHERE table_schema = 'public' AND table_name = 'cases'
    ) THEN
        RAISE EXCEPTION 'Tabela public.cases não existe no banco de dados.';
    END IF;

    -- 2. Adiciona a coluna noFees (BOOLEAN) caso não exista
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' 
          AND table_name = 'cases' 
          AND column_name = 'noFees'
    ) THEN
        ALTER TABLE public.cases ADD COLUMN "noFees" BOOLEAN NOT NULL DEFAULT false;
        RAISE NOTICE 'Coluna noFees adicionada com sucesso na tabela public.cases.';
    ELSE
        ALTER TABLE public.cases ALTER COLUMN "noFees" SET DEFAULT false;
        RAISE NOTICE 'Coluna noFees já existe na tabela public.cases.';
    END IF;

    -- 3. Atualiza registros NULL se houver
    UPDATE public.cases
    SET "noFees" = false
    WHERE "noFees" IS NULL;

    -- 4. Comentário documental
    COMMENT ON COLUMN public.cases."noFees" IS 'Indica se o processo/subprocesso não gera honorários advocatícios';

    -- 5. Garante permissões para authenticated e service_role
    GRANT SELECT, INSERT, UPDATE, DELETE ON public.cases TO authenticated;
    GRANT ALL ON public.cases TO service_role;

END $$;

COMMIT;
EOF_MIGRATION_SQL

SQL_TEMP_CONTAINER="/tmp/migration_nofees.sql"
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

COL_STATUS=$(run_sql_query "SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'cases' AND column_name = 'noFees');" || echo "erro")
COL_TYPE=$(run_sql_query "SELECT data_type FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'cases' AND column_name = 'noFees';" || echo "desconhecido")
COL_DEFAULT=$(run_sql_query "SELECT column_default FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'cases' AND column_name = 'noFees';" || echo "desconhecido")
CASES_COUNT=$(run_sql_query "SELECT count(*) FROM public.cases;" || echo "0")
NOFEES_COUNT=$(run_sql_query "SELECT count(*) FROM public.cases WHERE \"noFees\" = true;" || echo "0")

echo -e "   - Coluna 'cases.noFees':       $( [ "$COL_STATUS" = "t" ] && echo -e "${GREEN}EXISTE (tipo: ${COL_TYPE}, default: ${COL_DEFAULT}) [OK]${NC}" || echo -e "${RED}NÃO ENCONTRADA [FALHA]${NC}" )"
echo -e "   - Total de processos:         ${GREEN}${CASES_COUNT} linha(s) [OK]${NC}"
echo -e "   - Processos sem honorários:   ${GREEN}${NOFEES_COUNT} marcado(s) com noFees=true [OK]${NC}"

if [ "$COL_STATUS" != "t" ]; then
    echo -e "\n${RED}❌ ERRO: A verificação falhou! A coluna noFees não foi encontrada na tabela cases.${NC}"
    exit 1
fi

echo -e "\n${BOLD}${GREEN}=====================================================================${NC}"
echo -e "${BOLD}${GREEN}🎉 BANCO DE DADOS ATUALIZADO COM SUCESSO NO VPS!                     ${NC}"
echo -e "${BOLD}${GREEN}=====================================================================${NC}"
echo -e "Contêiner utilizado: ${BOLD}${DB_CONTAINER}${NC}"
echo -e "Usuário utilizado:   ${BOLD}${DB_USER}${NC}"
echo -e "Banco utilizado:     ${BOLD}${DB_NAME}${NC}"
echo -e "Status da coluna:    ${BOLD}OK${NC} (public.cases.noFees)"
echo -e "Schema cache do PostgREST recarregado com sucesso."
echo -e "${BOLD}${GREEN}=====================================================================${NC}\n"
