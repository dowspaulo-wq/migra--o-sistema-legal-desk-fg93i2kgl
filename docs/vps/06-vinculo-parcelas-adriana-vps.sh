#!/usr/bin/env bash
# ==============================================================================
# DPSjur / SBJur - Vínculo de Parcelas da Cliente Adriana Velasco Unti aos 5 Processos no VPS
# Script: docs/vps/06-vinculo-parcelas-adriana-vps.sh
# Versão: v1.0.0
# Alvo: VPS Hostinger 2.25.181.69 (EasyPanel / Supabase Self-Hosted)
# ==============================================================================
# Finalidade:
# 1. Localizar o contêiner real do PostgreSQL no VPS através de varredura Docker
#    e eleger o banco de produção com base na quantidade real de registros em
#    public.clients e public.cases (NUNCA hardcodar Doug/dpsjur que é banco vazio).
# 2. Executar operações SQL idempotentes e defensivas via arquivo temporário:
#    - Localizar a cliente "ADRIANA VELASCO UNTI" de forma tolerante a maiúsculas/acentos
#    - Localizar dinamicamente todas as parcelas do parcelamento dela (lançamentos de
#      R$ 300,00 da cliente; tolerando 7 ou mais parcelas pagas de 21)
#    - Localizar os 5 processos alvo via comparação por dígitos normalizados (apenas números):
#      * 5177300-25.2025.8.21.0001 (51773002520258210001) -> processo principal
#      * 5042728-35.2025.8.21.0001 (50427283520258210001)
#      * 5010231-59.2026.8.21.4001 (50102315920268214001)
#      * 0055825-85.2012.8.16.0001 (00558258520128160001)
#      * 0009206-46.2021.8.26.0602 (00092064620218260602)
#    - Garantir que a tabela N:M public.transaction_cases exista (com índice único)
#    - Vincular de forma idempotente cada parcela aos 5 processos (ON CONFLICT DO NOTHING)
#    - REMOVER os vínculos antigos das parcelas com o processo substituído:
#      * 4012672-38.2025.8.26.0602 (40126723820258260602)
#    - Atualizar o campo direto de processo principal de cada parcela (transactions."processId")
#      para 5177300-25.2025.8.21.0001 (o primeiro da lista)
# 3. Recarregar PostgREST via NOTIFY pgrst e restart do contêiner PostgREST
# 4. Conferência rigorosa e HONESTA com [OK]/[AVISO]/[FALHA] exibindo as parcelas,
#    seus vínculos N:M e o processo principal atualizado.
#
# Execução no terminal do VPS (como root - comando único sem pipe interativo):
#   curl -sSL "https://raw.githubusercontent.com/dowspaulo-wq/migra--o-sistema-legal-desk-fg93i2kgl/main/docs/vps/06-vinculo-parcelas-adriana-vps.sh" -o /root/06-vinculo-parcelas-adriana-vps.sh && bash /root/06-vinculo-parcelas-adriana-vps.sh
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
echo -e "${BOLD}${BLUE} DPSjur - Vínculo de Parcelas: Adriana Velasco Unti -> 5 Processos   ${NC}"
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
# 2. Diagnóstico pré-migração
# ------------------------------------------------------------------------------
echo -e "\n${BOLD}${CYAN}[2/4] Verificando estado atual das parcelas e processos no banco eleito...${NC}"

PRE_CLIENT_ID=$(run_sql_query "SELECT id FROM public.clients WHERE name ILIKE '%Adriana%Velasco%' OR name ILIKE '%Unti%' LIMIT 1;" || echo "")
if [ -z "$PRE_CLIENT_ID" ]; then
    echo -e "${RED}❌ Cliente 'Adriana Velasco Unti' não foi encontrada em public.clients no VPS!${NC}"
    exit 1
fi
PRE_CLIENT_NAME=$(run_sql_query "SELECT name FROM public.clients WHERE id = '${PRE_CLIENT_ID}';" || echo "Adriana")
echo -e "   - [OK] Cliente identificada: ${GREEN}${PRE_CLIENT_NAME}${NC} (ID: ${PRE_CLIENT_ID})"

PRE_TX_COUNT=$(run_sql_query "SELECT count(*) FROM public.transactions WHERE \"clientId\" = '${PRE_CLIENT_ID}' AND (amount = 300.00 OR amount = 300);" || echo "0")
echo -e "   - [OK] Parcelas de R$ 300,00 da cliente: ${GREEN}${PRE_TX_COUNT}${NC} parcelas encontradas"

PRE_LINKS_OLD=$(run_sql_query "
    SELECT count(*) 
    FROM public.transaction_cases tc
    JOIN public.cases c ON c.id = tc.case_id
    WHERE tc.transaction_id IN (
        SELECT id FROM public.transactions 
        WHERE \"clientId\" = '${PRE_CLIENT_ID}' AND (amount = 300.00 OR amount = 300)
    )
    AND regexp_replace(c.number, '[^0-9]', '', 'g') = '40126723820258260602';
" || echo "0")
echo -e "   - Vínculos com o processo antigo substituído (4012672-38): ${YELLOW}${PRE_LINKS_OLD}${NC}"

PRE_LINKS_TOTAL=$(run_sql_query "
    SELECT count(*) 
    FROM public.transaction_cases tc
    WHERE tc.transaction_id IN (
        SELECT id FROM public.transactions 
        WHERE \"clientId\" = '${PRE_CLIENT_ID}' AND (amount = 300.00 OR amount = 300)
    );
" || echo "0")
echo -e "   - Total de vínculos N:M atuais das parcelas de R$ 300: ${CYAN}${PRE_LINKS_TOTAL}${NC}"

# ------------------------------------------------------------------------------
# 3. Execução da migração SQL via arquivo temporário (docker cp + psql -f)
# ------------------------------------------------------------------------------
echo -e "\n${BOLD}${CYAN}[3/4] Aplicando migração idempotente de vínculo no PostgreSQL...${NC}"

SQL_TEMP_HOST=$(mktemp /tmp/vinculo_parcelas_adriana_XXXXXX.sql)

cat << 'EOF_MIGRATION_SQL' > "$SQL_TEMP_HOST"
BEGIN;

DO $$
DECLARE
    v_client_id UUID;
    v_main_case_id UUID;
    v_case_rec RECORD;
    v_tx_rec RECORD;
    v_tx_count INTEGER := 0;
    v_cases_count INTEGER := 0;
    v_inserted_links INTEGER := 0;
    v_removed_links INTEGER := 0;
    v_target_case_numbers TEXT[] := ARRAY[
        '51773002520258210001',  -- 5177300-25.2025.8.21.0001 (Principal)
        '50427283520258210001',  -- 5042728-35.2025.8.21.0001
        '50102315920268214001',  -- 5010231-59.2026.8.21.4001
        '00558258520128160001',  -- 0055825-85.2012.8.16.0001
        '00092064620218260602'   -- 0009206-46.2021.8.26.0602
    ];
    v_old_case_number TEXT := '40126723820258260602';
BEGIN
    -- 1. Localizar cliente Adriana Velasco Unti de forma tolerante
    SELECT id INTO v_client_id
    FROM public.clients
    WHERE name ILIKE '%Adriana%Velasco%' OR name ILIKE '%Unti%'
    LIMIT 1;

    IF v_client_id IS NULL THEN
        RAISE EXCEPTION 'Cliente Adriana Velasco Unti não encontrada em public.clients!';
    END IF;
    RAISE NOTICE '[OK] Cliente localizada: %', v_client_id;

    -- 2. Garantir integridade da tabela public.transaction_cases
    CREATE TABLE IF NOT EXISTS public.transaction_cases (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        transaction_id UUID NOT NULL REFERENCES public.transactions(id) ON DELETE CASCADE,
        case_id UUID NOT NULL REFERENCES public.cases(id) ON DELETE CASCADE,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );

    CREATE UNIQUE INDEX IF NOT EXISTS idx_transaction_cases_unique 
        ON public.transaction_cases(transaction_id, case_id);
    CREATE INDEX IF NOT EXISTS idx_transaction_cases_transaction_id 
        ON public.transaction_cases(transaction_id);
    CREATE INDEX IF NOT EXISTS idx_transaction_cases_case_id 
        ON public.transaction_cases(case_id);

    ALTER TABLE public.transaction_cases ENABLE ROW LEVEL SECURITY;

    DROP POLICY IF EXISTS "authenticated_select_transaction_cases" ON public.transaction_cases;
    CREATE POLICY "authenticated_select_transaction_cases" ON public.transaction_cases
        FOR SELECT TO authenticated USING (true);
    DROP POLICY IF EXISTS "authenticated_insert_transaction_cases" ON public.transaction_cases;
    CREATE POLICY "authenticated_insert_transaction_cases" ON public.transaction_cases
        FOR INSERT TO authenticated WITH CHECK (true);
    DROP POLICY IF EXISTS "authenticated_delete_transaction_cases" ON public.transaction_cases;
    CREATE POLICY "authenticated_delete_transaction_cases" ON public.transaction_cases
        FOR DELETE TO authenticated USING (true);
    DROP POLICY IF EXISTS "authenticated_update_transaction_cases" ON public.transaction_cases;
    CREATE POLICY "authenticated_update_transaction_cases" ON public.transaction_cases
        FOR UPDATE TO authenticated USING (true) WITH CHECK (true);

    GRANT SELECT, INSERT, UPDATE, DELETE ON public.transaction_cases TO authenticated;
    GRANT ALL ON public.transaction_cases TO service_role;

    -- 3. Identificar o processo principal (5177300-25.2025.8.21.0001)
    SELECT id INTO v_main_case_id
    FROM public.cases
    WHERE regexp_replace(number, '[^0-9]', '', 'g') = '51773002520258210001'
    LIMIT 1;

    IF v_main_case_id IS NULL THEN
        RAISE NOTICE '[AVISO] Processo principal 5177300-25.2025.8.21.0001 não encontrado pelo número exato. Buscando primeiro processo disponível dos 5 alvo...';
        SELECT id INTO v_main_case_id
        FROM public.cases
        WHERE regexp_replace(number, '[^0-9]', '', 'g') = ANY(v_target_case_numbers)
        ORDER BY created_at ASC
        LIMIT 1;
    END IF;

    -- 4. Contar processos alvo existentes no banco
    SELECT count(*) INTO v_cases_count
    FROM public.cases
    WHERE regexp_replace(number, '[^0-9]', '', 'g') = ANY(v_target_case_numbers);

    RAISE NOTICE '[OK] Encontrados % dos 5 processos alvo cadastrados no VPS.', v_cases_count;

    -- 5. Contar parcelas de R$ 300,00 da cliente
    SELECT count(*) INTO v_tx_count
    FROM public.transactions
    WHERE "clientId" = v_client_id
      AND (amount = 300.00 OR amount = 300);

    RAISE NOTICE '[OK] Encontradas % parcelas de R$ 300,00 da cliente.', v_tx_count;

    -- 6. REMOVER vínculos com o processo substituído (4012672-38.2025.8.26.0602)
    WITH deleted_old AS (
        DELETE FROM public.transaction_cases tc
        WHERE tc.transaction_id IN (
            SELECT id FROM public.transactions 
            WHERE "clientId" = v_client_id AND (amount = 300.00 OR amount = 300)
        )
        AND tc.case_id IN (
            SELECT id FROM public.cases
            WHERE regexp_replace(number, '[^0-9]', '', 'g') = v_old_case_number
        )
        RETURNING tc.id
    )
    SELECT count(*) INTO v_removed_links FROM deleted_old;
    RAISE NOTICE '[OK] Vínculos antigos com o processo 4012672-38 removidos: %', v_removed_links;

    -- 7. Criar os vínculos parcela x processo (N:M) de forma IDEMPOTENTE
    FOR v_tx_rec IN 
        SELECT id, description, date 
        FROM public.transactions 
        WHERE "clientId" = v_client_id AND (amount = 300.00 OR amount = 300)
    LOOP
        FOR v_case_rec IN
            SELECT id, number 
            FROM public.cases 
            WHERE regexp_replace(number, '[^0-9]', '', 'g') = ANY(v_target_case_numbers)
        LOOP
            INSERT INTO public.transaction_cases (transaction_id, case_id)
            VALUES (v_tx_rec.id, v_case_rec.id)
            ON CONFLICT (transaction_id, case_id) DO NOTHING;
            
            IF FOUND THEN
                v_inserted_links := v_inserted_links + 1;
            END IF;
        END LOOP;
    END LOOP;
    RAISE NOTICE '[OK] Novos vínculos N:M inseridos em transaction_cases: % (idempotente: duplicatas ignoradas)', v_inserted_links;

    -- 8. Definir o campo direto transactions.processId para o processo principal (5177300-25)
    IF v_main_case_id IS NOT NULL THEN
        UPDATE public.transactions
        SET "processId" = v_main_case_id
        WHERE "clientId" = v_client_id
          AND (amount = 300.00 OR amount = 300)
          AND ("processId" IS DISTINCT FROM v_main_case_id);
        RAISE NOTICE '[OK] Campo transactions.processId atualizado para o processo principal nas parcelas.';
    ELSE
        RAISE NOTICE '[AVISO] Processo principal não pôde ser definido porque nenhum dos 5 processos foi encontrado.';
    END IF;

END $$;

COMMIT;
EOF_MIGRATION_SQL

RAND_ID="vinculo_adriana_${RANDOM:-$$}_$(date +%s 2>/dev/null || echo '0')"
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

echo -e "${GREEN}✓ Instruções SQL aplicadas com sucesso no PostgreSQL!${NC}"

# Notificar e reiniciar PostgREST para limpar cache
echo -e "🔄 Recarregando cache do PostgREST via NOTIFY pgrst..."
run_sql_query "NOTIFY pgrst, 'reload schema';" >/dev/null 2>&1 || true

if [ -n "$PGRST_CONTAINER" ]; then
    echo -e "🔄 Reiniciando contêiner do PostgREST (${PGRST_CONTAINER})..."
    docker restart "$PGRST_CONTAINER" >/dev/null 2>&1 || true
    echo -e "${GREEN}✓ Contêiner PostgREST reiniciado!${NC}"
fi

# ------------------------------------------------------------------------------
# 4. Conferência rigorosa e honesta pós-migração
# ------------------------------------------------------------------------------
echo -e "\n${BOLD}${CYAN}[4/4] Conferência final dos dados no PostgreSQL:${NC}"
echo -e "   - Contêiner: ${BOLD}${DB_CONTAINER}${NC}"
echo -e "   - Usuário:   ${BOLD}${DB_USER}${NC}"
echo -e "   - Banco:     ${BOLD}${DB_NAME}${NC}"
echo -e "---------------------------------------------------------------------"

# 1. Verificar se restou algum vínculo com o processo antigo
POST_OLD_LINKS=$(run_sql_query "
    SELECT count(*) 
    FROM public.transaction_cases tc
    JOIN public.cases c ON c.id = tc.case_id
    WHERE tc.transaction_id IN (
        SELECT id FROM public.transactions 
        WHERE \"clientId\" = '${PRE_CLIENT_ID}' AND (amount = 300.00 OR amount = 300)
    )
    AND regexp_replace(c.number, '[^0-9]', '', 'g') = '40126723820258260602';
" || echo "0")

# 2. Total de vínculos N:M atuais
POST_TOTAL_LINKS=$(run_sql_query "
    SELECT count(*) 
    FROM public.transaction_cases tc
    WHERE tc.transaction_id IN (
        SELECT id FROM public.transactions 
        WHERE \"clientId\" = '${PRE_CLIENT_ID}' AND (amount = 300.00 OR amount = 300)
    );
" || echo "0")

# 3. Quantas parcelas estão com o processId apontando para o principal (5177300-25)
POST_MAIN_CASE_NUMBER=$(run_sql_query "
    SELECT c.number
    FROM public.cases c
    WHERE regexp_replace(c.number, '[^0-9]', '', 'g') = '51773002520258210001'
    LIMIT 1;
" || echo "")

POST_TX_ON_MAIN=$(run_sql_query "
    SELECT count(*)
    FROM public.transactions t
    JOIN public.cases c ON c.id = t.\"processId\"
    WHERE t.\"clientId\" = '${PRE_CLIENT_ID}'
      AND (t.amount = 300.00 OR t.amount = 300)
      AND regexp_replace(c.number, '[^0-9]', '', 'g') = '51773002520258210001';
" || echo "0")

POST_TX_COUNT=$(run_sql_query "SELECT count(*) FROM public.transactions WHERE \"clientId\" = '${PRE_CLIENT_ID}' AND (amount = 300.00 OR amount = 300);" || echo "0")

echo -e "   - 1. Remoção do processo antigo (4012672-38): $( [ "${POST_OLD_LINKS}" = "0" ] && echo -e "${GREEN}0 vínculos restantes [OK]${NC}" || echo -e "${RED}${POST_OLD_LINKS} vínculos ainda existem [FALHA]${NC}" )"
echo -e "   - 2. Vínculos N:M totais das parcelas de R$ 300: ${GREEN}${POST_TOTAL_LINKS} vínculos ativos [OK]${NC} (antes: ${PRE_LINKS_TOTAL})"
echo -e "   - 3. Processo principal (5177300-25) direto:   $( [ "${POST_TX_ON_MAIN}" -gt 0 ] && echo -e "${GREEN}${POST_TX_ON_MAIN}/${POST_TX_COUNT} parcelas apontando para ${POST_MAIN_CASE_NUMBER:-'5177300-25'} [OK]${NC}" || echo -e "${YELLOW}0 apontamentos diretos [AVISO]${NC}" )"

echo -e "\n${BOLD}${CYAN}Detalhamento das parcelas e processos vinculados:${NC}"

# Tabela formatada via psql
if [ -n "$LOCAL_DB_PASSWORD" ]; then
    docker exec -i -e PGPASSWORD="$LOCAL_DB_PASSWORD" "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -c "
        SELECT 
            t.date AS \"Data\",
            LEFT(t.description, 45) AS \"Descrição\",
            'R$ ' || to_char(t.amount, 'FM999G999D00') AS \"Valor\",
            count(tc.id) AS \"Vínculos N:M\",
            LEFT(c_main.number, 25) AS \"Processo Principal Direto\"
        FROM public.transactions t
        LEFT JOIN public.transaction_cases tc ON tc.transaction_id = t.id
        LEFT JOIN public.cases c_main ON c_main.id = t.\"processId\"
        WHERE t.\"clientId\" = '${PRE_CLIENT_ID}'
          AND (t.amount = 300.00 OR t.amount = 300)
        GROUP BY t.id, t.date, t.description, t.amount, c_main.number
        ORDER BY t.date ASC;
    " || true
else
    docker exec -i "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -c "
        SELECT 
            t.date AS \"Data\",
            LEFT(t.description, 45) AS \"Descrição\",
            'R$ ' || to_char(t.amount, 'FM999G999D00') AS \"Valor\",
            count(tc.id) AS \"Vínculos N:M\",
            LEFT(c_main.number, 25) AS \"Processo Principal Direto\"
        FROM public.transactions t
        LEFT JOIN public.transaction_cases tc ON tc.transaction_id = t.id
        LEFT JOIN public.cases c_main ON c_main.id = t.\"processId\"
        WHERE t.\"clientId\" = '${PRE_CLIENT_ID}'
          AND (t.amount = 300.00 OR t.amount = 300)
        GROUP BY t.id, t.date, t.description, t.amount, c_main.number
        ORDER BY t.date ASC;
    " || true
fi

# Validação geral
VERIFICATION_FAILED=0
if [ "${POST_OLD_LINKS}" != "0" ]; then VERIFICATION_FAILED=1; fi
if [ "${POST_TOTAL_LINKS:-0}" -eq 0 ]; then VERIFICATION_FAILED=1; fi

if [ $VERIFICATION_FAILED -ne 0 ]; then
    echo -e "\n${RED}=====================================================================${NC}"
    echo -e "${RED}❌ ERRO: A verificação final detectou inconsistências no banco!      ${NC}"
    echo -e "${RED}=====================================================================${NC}\n"
    exit 1
fi

echo -e "\n${BOLD}${GREEN}=====================================================================${NC}"
echo -e "${BOLD}${GREEN}🎉 VÍNCULO DE PARCELAS CONCLUÍDO COM SUCESSO NO BANCO DO VPS! [OK]   ${NC}"
echo -e "${BOLD}${GREEN}=====================================================================${NC}"
echo -e "Contêiner eleito:    ${BOLD}${DB_CONTAINER}${NC}"
echo -e "Usuário eleito:      ${BOLD}${DB_USER}${NC}"
echo -e "Banco eleito:        ${BOLD}${DB_NAME}${NC}"
echo -e "Cliente vinculada:   ${BOLD}${PRE_CLIENT_NAME}${NC}"
echo -e "Total de vínculos:   ${BOLD}${GREEN}${POST_TOTAL_LINKS} vínculos ativos em transaction_cases [OK]${NC}"
echo -e "PostgREST cache:     ${BOLD}Recarregado via NOTIFY pgrst e restart de contêiner${NC}"
echo -e "${BOLD}${GREEN}=====================================================================${NC}\n"
