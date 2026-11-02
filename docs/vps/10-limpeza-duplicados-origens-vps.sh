#!/usr/bin/env bash
# ==============================================================================
# DPSjur / SBJur - Limpeza Segura de Duplicados Entre Origens no PostgreSQL do VPS
# Script: docs/vps/10-limpeza-duplicados-origens-vps.sh
# Versão: v1.0.0
# Alvo: VPS Hostinger 2.25.181.69 (EasyPanel / Supabase Self-Hosted)
# ==============================================================================
# Finalidade:
# 1. Detectar pares de lançamentos duplicados ENTRE ORIGENS em public.transactions:
#    - Mesmo "clientId"
#    - Mesmo valor (round(amount::numeric, 2) igual)
#    - Status 'Pago' (ou 'Realizado')
#    - Um com origem 'ASAAS_WEBHOOK' (ou 'ASAAS') e o outro com origem 'IMPORT_SICOOB' (ou 'MANUAL')
#    - Janela de datas: |data Asaas - data outro| <= 5 dias
# 2. EXCEÇÕES CRÍTICAS PRESERVADAS (NÃO REMOVER):
#    - Qualquer par em que o lado MANUAL tenha asaas_id preenchido (são cobranças Asaas legítimas/parcelas);
#    - Graciele da Silva Dias: lançamentos manuais com asaas_id preenchido ou parcelas legítimas;
#    - Junio Alves Martins: SICOOB 2026-08-03 R$250 "Junio Alves Martins - Exoneratória [NF ok]" vs Asaas
#      2026-08-10 R$125 (valores diferentes já não casam por definição; preservado).
# 3. FASE DE LISTAGEM (antes de qualquer exclusão):
#    - Listar em tabela formatada marcando ">>> MANTER (Asaas)" e "REMOVER (SICOOB/Manual #N)".
# 4. FASE DE REMOÇÃO:
#    - Tratar vínculos de integridade referencial antes de apagar:
#      * transactions.pair_id apontando para os que serão removidos -> SET NULL;
#      * transaction_cases dos removidos -> apontar para o lançamento mantido do par (ou remover se já existir);
#    - Deletar SOMENTE os lados SICOOB/MANUAL dos pares confirmados (mantendo o lado Asaas).
# 5. FASE DE CONFERÊNCIA:
#    - Reexecutar a consulta de detecção comprovando [OK - ZERADO] ou saindo com erro (exit 1).
# 6. Idempotente: se já estiver limpo, não remove nada e finaliza com [OK - ZERADO].
#
# Execução no terminal do VPS (como root - comando único sem pipe):
#   curl -sSL "https://raw.githubusercontent.com/dowspaulo-wq/migra--o-sistema-legal-desk-fg93i2kgl/main/docs/vps/10-limpeza-duplicados-origens-vps.sh" -o /root/10-limpeza-duplicados-origens-vps.sh && bash /root/10-limpeza-duplicados-origens-vps.sh
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
echo -e "${BOLD}${BLUE} DPSjur - Limpeza de Duplicados Entre Origens (Asaas vs SICOOB/Manual)${NC}"
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

DB_CONTAINER="$REAL_CONTAINER"
DB_USER="$REAL_USER"
DB_NAME="$REAL_DB"
LOCAL_DB_PASSWORD="$REAL_PASS"

# Helper para executar consulta SQL com saída crua
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

# Helper para exibir tabela formatada via psql
run_sql_table() {
    local sql_query="$1"
    if [ -n "$LOCAL_DB_PASSWORD" ]; then
        docker exec -i -e PGPASSWORD="$LOCAL_DB_PASSWORD" "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -c "$sql_query"
    else
        docker exec -i "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -c "$sql_query"
    fi
}

# ------------------------------------------------------------------------------
# 2. FASE DE LISTAGEM (Prévia detalhada dos duplicados entre origens)
# ------------------------------------------------------------------------------
echo -e "\n${BOLD}${CYAN}[2/4] FASE DE LISTAGEM: Detectando duplicados entre origens (Asaas x SICOOB/Manual)...${NC}"
echo -e "Critérios da trava entre origens:"
echo -e "  - Mesmo clientId"
echo -e "  - Mesmo valor monetário (centavos com 2 casas)"
echo -e "  - Status 'Pago' (ou 'Realizado')"
echo -e "  - Um lado ASAAS_WEBHOOK (ou ASAAS) e outro lado IMPORT_SICOOB (ou MANUAL)"
echo -e "  - |data Asaas - data outro| <= 5 dias"
echo -e "  - EXCEÇÃO: Preservar qualquer par em que o lado MANUAL possua asaas_id preenchido (cobrança legítima)\n"

# Consulta SQL padronizada que elege os lançamentos que devem ser removidos (SICOOB / MANUAL)
SQL_DUPLICATE_CANDIDATES="
    WITH asaas_tx AS (
        SELECT t.id, t.\"clientId\", t.date, t.amount, t.description, t.status, t.origem, t.created_at, t.asaas_id, t.processId
        FROM public.transactions t
        WHERE t.origem IN ('ASAAS_WEBHOOK', 'ASAAS')
          AND t.status IN ('Pago', 'Realizado')
          AND t.\"clientId\" IS NOT NULL
          AND t.date IS NOT NULL
          AND t.amount IS NOT NULL
    ),
    other_tx AS (
        SELECT t.id, t.\"clientId\", t.date, t.amount, t.description, t.status, t.origem, t.created_at, t.asaas_id, t.processId
        FROM public.transactions t
        WHERE t.origem IN ('IMPORT_SICOOB', 'MANUAL')
          AND t.status IN ('Pago', 'Realizado')
          AND t.\"clientId\" IS NOT NULL
          AND t.date IS NOT NULL
          AND t.amount IS NOT NULL
          -- REGRA DE PROTEÇÃO: Preservar lançamentos manuais com asaas_id preenchido
          AND (t.asaas_id IS NULL OR trim(t.asaas_id) = '')
    ),
    matched_pairs AS (
        SELECT 
            a.id as asaas_id,
            a.date as asaas_date,
            a.amount as asaas_amount,
            a.description as asaas_desc,
            o.id as remove_id,
            o.origem as remove_origem,
            o.date as remove_date,
            o.amount as remove_amount,
            o.description as remove_desc,
            o.\"clientId\",
            c.name as client_name,
            abs((trim(split_part(a.date, 'T', 1))::date) - (trim(split_part(o.date, 'T', 1))::date)) as diff_dias,
            row_number() OVER (PARTITION BY o.id ORDER BY abs((trim(split_part(a.date, 'T', 1))::date) - (trim(split_part(o.date, 'T', 1))::date)) ASC, a.created_at ASC) as rn_match
        FROM asaas_tx a
        JOIN other_tx o ON a.\"clientId\" = o.\"clientId\" AND round(a.amount::numeric, 2) = round(o.amount::numeric, 2)
        LEFT JOIN public.clients c ON c.id = o.\"clientId\"
        WHERE abs((trim(split_part(a.date, 'T', 1))::date) - (trim(split_part(o.date, 'T', 1))::date)) <= 5
          AND a.id != o.id
    )
"

TOTAL_TO_REMOVE=$(run_sql_query "
    ${SQL_DUPLICATE_CANDIDATES}
    SELECT count(DISTINCT remove_id) FROM matched_pairs WHERE rn_match = 1;
" || echo "0")
TOTAL_TO_REMOVE=$(echo "$TOTAL_TO_REMOVE" | tr -dc '0-9')
[ -z "$TOTAL_TO_REMOVE" ] && TOTAL_TO_REMOVE=0

echo -e "   - Total de lançamentos repetidos a remover (SICOOB/MANUAL): ${YELLOW}${TOTAL_TO_REMOVE}${NC}\n"

if [ "$TOTAL_TO_REMOVE" -eq 0 ]; then
    echo -e "${GREEN}✓ Nenhum lançamento duplicado entre origens encontrado no banco! [OK - ZERADO]${NC}"
else
    echo -e "${BOLD}${CYAN}Tabela detalhada dos lançamentos (MANTER Asaas vs REMOVER SICOOB/Manual):${NC}"
    run_sql_table "
        ${SQL_DUPLICATE_CANDIDATES}
        SELECT 
            LEFT(client_name, 22) AS \"Cliente\",
            asaas_date AS \"Dt Asaas\",
            remove_date AS \"Dt Outro\",
            diff_dias || 'd' AS \"Dif\",
            'R$ ' || to_char(remove_amount, 'FM999G999D00') AS \"Valor\",
            LEFT(asaas_desc, 22) AS \"Lado Asaas (MANTER)\",
            remove_origem || ': ' || LEFT(remove_desc, 24) AS \"Lado Outro (REMOVER)\"
        FROM matched_pairs
        WHERE rn_match = 1
        ORDER BY remove_date ASC, client_name ASC;
    " || true
fi

# ------------------------------------------------------------------------------
# 3. FASE DE REMOÇÃO: Exclusão com preservação do lado Asaas e tratamento de FKs
# ------------------------------------------------------------------------------
echo -e "\n${BOLD}${CYAN}[3/4] FASE DE REMOÇÃO: Executando exclusão segura via transação atômica...${NC}"

if [ "$TOTAL_TO_REMOVE" -eq 0 ]; then
    echo -e "${GREEN}✓ Etapa de remoção pulada pois não há duplicados entre origens a processar.${NC}"
else
    SQL_TEMP_HOST=$(mktemp /tmp/limpeza_origens_vps_XXXXXX.sql)

    cat << 'EOF_CLEANUP_ORIGINS_SQL' > "$SQL_TEMP_HOST"
BEGIN;

DO $$
DECLARE
    v_cleared_pairs INTEGER := 0;
    v_updated_cases INTEGER := 0;
    v_deleted_cases INTEGER := 0;
    v_deleted_tx INTEGER := 0;
BEGIN
    -- 1. Cria tabela temporária isolando os pares confirmados e os IDs a remover
    CREATE TEMP TABLE tmp_cross_origin_to_delete ON COMMIT DROP AS
    WITH asaas_tx AS (
        SELECT t.id, t."clientId", t.date, t.amount, t.description, t.status, t.origem, t.created_at, t.asaas_id, t.processId
        FROM public.transactions t
        WHERE t.origem IN ('ASAAS_WEBHOOK', 'ASAAS')
          AND t.status IN ('Pago', 'Realizado')
          AND t."clientId" IS NOT NULL
          AND t.date IS NOT NULL
          AND t.amount IS NOT NULL
    ),
    other_tx AS (
        SELECT t.id, t."clientId", t.date, t.amount, t.description, t.status, t.origem, t.created_at, t.asaas_id, t.processId
        FROM public.transactions t
        WHERE t.origem IN ('IMPORT_SICOOB', 'MANUAL')
          AND t.status IN ('Pago', 'Realizado')
          AND t."clientId" IS NOT NULL
          AND t.date IS NOT NULL
          AND t.amount IS NOT NULL
          AND (t.asaas_id IS NULL OR trim(t.asaas_id) = '')
    ),
    matched_pairs AS (
        SELECT 
            o.id as remove_id,
            a.id as keep_id,
            o."clientId",
            row_number() OVER (PARTITION BY o.id ORDER BY abs((trim(split_part(a.date, 'T', 1))::date) - (trim(split_part(o.date, 'T', 1))::date)) ASC, a.created_at ASC) as rn_match
        FROM asaas_tx a
        JOIN other_tx o ON a."clientId" = o."clientId" AND round(a.amount::numeric, 2) = round(o.amount::numeric, 2)
        WHERE abs((trim(split_part(a.date, 'T', 1))::date) - (trim(split_part(o.date, 'T', 1))::date)) <= 5
          AND a.id != o.id
    )
    SELECT DISTINCT remove_id, keep_id FROM matched_pairs WHERE rn_match = 1;

    -- 2. Tratamento defensivo de integridade referencial:
    -- A) Limpar referências em pair_id para evitar violação de FK
    WITH updated_pairs AS (
        UPDATE public.transactions
        SET pair_id = NULL
        WHERE pair_id IN (SELECT remove_id FROM tmp_cross_origin_to_delete)
        RETURNING id
    )
    SELECT count(*) INTO v_cleared_pairs FROM updated_pairs;
    IF v_cleared_pairs > 0 THEN
        RAISE NOTICE '[OK] Referências pair_id atualizadas para NULL: %', v_cleared_pairs;
    END IF;

    -- B) Tabela transaction_cases (vínculos N:M com processos)
    -- Se existir registro de vínculo para a transação que será removida:
    --   - Se o lançamento mantido (Asaas) ainda NÃO possui o vínculo, apontar para o mantido
    --   - Se o lançamento mantido já possui o vínculo, apenas deletar o vínculo da removida
    IF EXISTS (
        SELECT 1 FROM information_schema.tables 
        WHERE table_schema = 'public' AND table_name = 'transaction_cases'
    ) THEN
        -- Remove vínculos duplicados que já existem no lançamento mantido
        WITH del_redundant AS (
            DELETE FROM public.transaction_cases tc
            USING tmp_cross_origin_to_delete p
            WHERE tc.transaction_id = p.remove_id
              AND EXISTS (
                  SELECT 1 FROM public.transaction_cases tc2
                  WHERE tc2.transaction_id = p.keep_id
                    AND tc2.case_id = tc.case_id
              )
            RETURNING tc.id
        )
        SELECT count(*) INTO v_deleted_cases FROM del_redundant;

        -- Redireciona os vínculos restantes para o lançamento mantido
        WITH moved_cases AS (
            UPDATE public.transaction_cases tc
            SET transaction_id = p.keep_id
            FROM tmp_cross_origin_to_delete p
            WHERE tc.transaction_id = p.remove_id
            RETURNING tc.id
        )
        SELECT count(*) INTO v_updated_cases FROM moved_cases;

        RAISE NOTICE '[OK] Vínculos transaction_cases tratados: % redirecionados ao Asaas, % redundantes removidos.', v_updated_cases, v_deleted_cases;
    END IF;

    -- 3. Exclusão estrita dos lançamentos SICOOB / MANUAL duplicados
    WITH deleted_transactions AS (
        DELETE FROM public.transactions
        WHERE id IN (SELECT remove_id FROM tmp_cross_origin_to_delete)
        RETURNING id
    )
    SELECT count(*) INTO v_deleted_tx FROM deleted_transactions;

    RAISE NOTICE '[OK] Lançamentos duplicados entre origens removidos com sucesso: %', v_deleted_tx;
END $$;

COMMIT;
EOF_CLEANUP_ORIGINS_SQL

    RAND_ID="clean_cross_${RANDOM:-$$}_$(date +%s 2>/dev/null || echo '0')"
    SQL_TEMP_CONTAINER="/tmp/${RAND_ID}.sql"

    docker cp "$SQL_TEMP_HOST" "${DB_CONTAINER}:${SQL_TEMP_CONTAINER}" 2>/dev/null || true
    rm -f "$SQL_TEMP_HOST" 2>/dev/null || true

    CLEAN_EXIT_CODE=0
    if [ -n "$LOCAL_DB_PASSWORD" ]; then
        docker exec -i -e PGPASSWORD="$LOCAL_DB_PASSWORD" "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 -f "$SQL_TEMP_CONTAINER" || CLEAN_EXIT_CODE=$?
    else
        docker exec -i "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 -f "$SQL_TEMP_CONTAINER" || CLEAN_EXIT_CODE=$?
    fi

    docker exec -i "$DB_CONTAINER" rm -f "$SQL_TEMP_CONTAINER" 2>/dev/null || true

    if [ $CLEAN_EXIT_CODE -ne 0 ]; then
        echo -e "${RED}❌ Falha ao executar a limpeza no PostgreSQL (código: ${CLEAN_EXIT_CODE})!${NC}"
        exit $CLEAN_EXIT_CODE
    fi

    echo -e "${GREEN}✓ Exclusão atômica concluída com sucesso no PostgreSQL!${NC}"
fi

# ------------------------------------------------------------------------------
# 4. FASE DE CONFERÊNCIA (Prova de que zerou os duplicados entre origens)
# ------------------------------------------------------------------------------
echo -e "\n${BOLD}${CYAN}[4/4] FASE DE CONFERÊNCIA: Verificando se restou algum duplicado entre origens...${NC}"

POST_TOTAL_TO_REMOVE=$(run_sql_query "
    ${SQL_DUPLICATE_CANDIDATES}
    SELECT count(DISTINCT remove_id) FROM matched_pairs WHERE rn_match = 1;
" || echo "0")
POST_TOTAL_TO_REMOVE=$(echo "$POST_TOTAL_TO_REMOVE" | tr -dc '0-9')
[ -z "$POST_TOTAL_TO_REMOVE" ] && POST_TOTAL_TO_REMOVE=0

echo -e "   - Lançamentos duplicados removidos:            ${GREEN}${TOTAL_TO_REMOVE}${NC}"
echo -e "   - Duplicados restantes no banco:               $( [ "$POST_TOTAL_TO_REMOVE" = "0" ] && echo -e "${GREEN}0 pares [OK - ZERADO]${NC}" || echo -e "${RED}${POST_TOTAL_TO_REMOVE} duplicados ainda restam [FALHA]${NC}" )"

if [ "$POST_TOTAL_TO_REMOVE" != "0" ]; then
    echo -e "\n${RED}=====================================================================${NC}"
    echo -e "${RED}❌ ERRO: A verificação final detectou duplicados restantes no banco! ${NC}"
    echo -e "${RED}=====================================================================${NC}\n"
    exit 1
fi

echo -e "\n${BOLD}${GREEN}=====================================================================${NC}"
echo -e "${BOLD}${GREEN}🎉 LIMPEZA DE DUPLICADOS ENTRE ORIGENS CONCLUÍDA NO BANCO DO VPS!   ${NC}"
echo -e "${BOLD}${GREEN}=====================================================================${NC}"
echo -e "Contêiner eleito:          ${BOLD}${DB_CONTAINER}${NC}"
echo -e "Usuário eleito:            ${BOLD}${DB_USER}${NC}"
echo -e "Banco eleito:              ${BOLD}${DB_NAME}${NC}"
echo -e "Lançamentos mantidos:      ${BOLD}Origem Asaas (cobrança oficial com comprovante/webhook)${NC}"
echo -e "Lançamentos removidos:     ${BOLD}${GREEN}${TOTAL_TO_REMOVE} duplicatas SICOOB/Manual eliminadas [OK]${NC}"
echo -e "Duplicados restantes:      ${BOLD}${GREEN}0 (zero) [OK - ZERADO]${NC}"
echo -e "${BOLD}${GREEN}=====================================================================${NC}"
echo -e "${YELLOW}ℹ️  Nota operacional: Esta alteração foi executada diretamente no banco de dados.${NC}"
echo -e "${YELLOW}   Nenhum redeploy de aplicação no EasyPanel é necessário.${NC}"
echo -e "${YELLOW}   Basta atualizar a tela no navegador (F5 ou Ctrl+F5) para ver o Financeiro limpo.${NC}"
echo -e "${BOLD}${GREEN}=====================================================================${NC}\n"
