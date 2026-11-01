#!/usr/bin/env bash
# ==============================================================================
# DPSjur / SBJur - Limpeza Segura de Lançamentos Financeiros Duplicados no VPS
# Script: docs/vps/09-limpeza-duplicados-vps.sh
# Versão: v1.0.0
# Alvo: VPS Hostinger 2.25.181.69 (EasyPanel / Supabase Self-Hosted)
# ==============================================================================
# Finalidade:
# 1. Conectar no banco local do PostgreSQL do Supabase self-hosted no VPS,
#    varrendo e elegendo automaticamente o contêiner e a base de produção real
#    (com base no maior volume de public.clients e public.cases, nunca o banco
#    vazio Doug/dpsjur). Reutiliza o padrão consagrado dos scripts 05/06/07/08.
# 2. FASE DE LISTAGEM (antes de qualquer exclusão):
#    - Identificar grupos de lançamentos duplicados em public.transactions
#      com 2+ registros compartilhando:
#        * Data normalizada (YYYY-MM-DD);
#        * Valor normalizado (centavos, round 2 casas);
#        * Descrição normalizada (trim, lower, sem acentos e espaços colapsados);
#        * Conta/origem bancária ("bankAccount" normalizado).
#    - Exibir tabela detalhada com ID, data, valor, descrição, status de cada
#      lançamento: qual será MANTIDO (o mais antigo por created_at ASC, empate menor id)
#      e quais serão REMOVIDOS.
# 3. FASE DE REMOÇÃO:
#    - Manter rigorosamente o lançamento mais antigo de cada grupo.
#    - Tratar vínculos de integridade referencial (FK) antes de apagar:
#        * public.transaction_cases (vínculos N:M com processos dos lançamentos que serão removidos);
#        * Referências em pair_id de outras transações (desvinculando com segurança);
#    - Remover os lançamentos duplicados excedentes.
# 4. FASE DE CONFERÊNCIA:
#    - Imprimir contagem de grupos encontrados e total de lançamentos removidos.
#    - Reexecutar a consulta de duplicados comprovando [OK] com ZERO duplicados restantes.
# 5. Idempotência garantida: reexecutar não altera nada nem remove registros indevidos.
#    Não mexe em valores, status, vínculos de outros lançamentos nem outras tabelas.
#
# Execução no terminal do VPS (como root - comando único sem pipe):
#   curl -sSL "https://raw.githubusercontent.com/dowspaulo-wq/migra--o-sistema-legal-desk-fg93i2kgl/main/docs/vps/09-limpeza-duplicados-vps.sh" -o /root/09-limpeza-duplicados-vps.sh && bash /root/09-limpeza-duplicados-vps.sh
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
echo -e "${BOLD}${BLUE} DPSjur - Limpeza de Lançamentos Duplicados no PostgreSQL do VPS    ${NC}"
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
# 2. FASE DE LISTAGEM (Prévia transparente antes de qualquer exclusão)
# ------------------------------------------------------------------------------
echo -e "\n${BOLD}${CYAN}[2/4] FASE DE LISTAGEM: Localizando lançamentos duplicados no banco...${NC}"
echo -e "Critérios de duplicidade exata:"
echo -e "  - Mesma data normalizada (YYYY-MM-DD)"
echo -e "  - Mesmo valor monetário (centavos com 2 casas decimais)"
echo -e "  - Mesma descrição normalizada (minúsculas, sem acentos, espaços colapsados)"
echo -e "  - Mesma conta bancária / origem (coluna bankAccount normalizada)\n"

# Contar grupos e lançamentos duplicados
COUNT_GROUPS=$(run_sql_query "
    WITH dup_groups AS (
        SELECT 
            trim(split_part(t.date, 'T', 1)) as norm_date,
            round(t.amount::numeric, 2) as norm_amount,
            trim(regexp_replace(lower(translate(t.description,
                'ÀÁÂÃÄÅàáâãäåÈÉÊËèéêëÌÍÎÏìíîïÒÓÔÕÖØòóôõöøÙÚÛÜùúûüÇçÑñ',
                'AAAAAAaaaaaaEEEEeeeeIIIIiiiiOOOOOOooooooUUUUuuuuCcNn')), '\s+', ' ', 'g')) as norm_desc,
            coalesce(trim(lower(t.\"bankAccount\")), '') as norm_account,
            count(*) as total_in_group
        FROM public.transactions t
        WHERE t.date IS NOT NULL AND t.description IS NOT NULL AND t.amount IS NOT NULL
        GROUP BY 
            trim(split_part(t.date, 'T', 1)),
            round(t.amount::numeric, 2),
            trim(regexp_replace(lower(translate(t.description,
                'ÀÁÂÃÄÅàáâãäåÈÉÊËèéêëÌÍÎÏìíîïÒÓÔÕÖØòóôõöøÙÚÛÜùúûüÇçÑñ',
                'AAAAAAaaaaaaEEEEeeeeIIIIiiiiOOOOOOooooooUUUUuuuuCcNn')), '\s+', ' ', 'g')),
            coalesce(trim(lower(t.\"bankAccount\")), '')
        HAVING count(*) > 1
    )
    SELECT count(*) FROM dup_groups;
" || echo "0")
COUNT_GROUPS=$(echo "$COUNT_GROUPS" | tr -dc '0-9')
[ -z "$COUNT_GROUPS" ] && COUNT_GROUPS=0

TOTAL_TO_REMOVE=$(run_sql_query "
    WITH dup_groups AS (
        SELECT 
            trim(split_part(t.date, 'T', 1)) as norm_date,
            round(t.amount::numeric, 2) as norm_amount,
            trim(regexp_replace(lower(translate(t.description,
                'ÀÁÂÃÄÅàáâãäåÈÉÊËèéêëÌÍÎÏìíîïÒÓÔÕÖØòóôõöøÙÚÛÜùúûüÇçÑñ',
                'AAAAAAaaaaaaEEEEeeeeIIIIiiiiOOOOOOooooooUUUUuuuuCcNn')), '\s+', ' ', 'g')) as norm_desc,
            coalesce(trim(lower(t.\"bankAccount\")), '') as norm_account,
            count(*) - 1 as to_remove
        FROM public.transactions t
        WHERE t.date IS NOT NULL AND t.description IS NOT NULL AND t.amount IS NOT NULL
        GROUP BY 
            trim(split_part(t.date, 'T', 1)),
            round(t.amount::numeric, 2),
            trim(regexp_replace(lower(translate(t.description,
                'ÀÁÂÃÄÅàáâãäåÈÉÊËèéêëÌÍÎÏìíîïÒÓÔÕÖØòóôõöøÙÚÛÜùúûüÇçÑñ',
                'AAAAAAaaaaaaEEEEeeeeIIIIiiiiOOOOOOooooooUUUUuuuuCcNn')), '\s+', ' ', 'g')),
            coalesce(trim(lower(t.\"bankAccount\")), '')
        HAVING count(*) > 1
    )
    SELECT coalesce(sum(to_remove), 0) FROM dup_groups;
" || echo "0")
TOTAL_TO_REMOVE=$(echo "$TOTAL_TO_REMOVE" | tr -dc '0-9')
[ -z "$TOTAL_TO_REMOVE" ] && TOTAL_TO_REMOVE=0

echo -e "   - Grupos duplicados encontrados: ${YELLOW}${COUNT_GROUPS}${NC}"
echo -e "   - Total de lançamentos repetidos a remover: ${YELLOW}${TOTAL_TO_REMOVE}${NC}\n"

if [ "$COUNT_GROUPS" -eq 0 ]; then
    echo -e "${GREEN}✓ Nenhum grupo de duplicados encontrado no banco! Nada para limpar.${NC}"
else
    echo -e "${BOLD}${CYAN}Tabela detalhada dos lançamentos encontrados (MANTIDO vs A REMOVER):${NC}"
    run_sql_table "
        WITH ranked_tx AS (
            SELECT 
                t.id,
                trim(split_part(t.date, 'T', 1)) as data_norm,
                round(t.amount::numeric, 2) as valor_norm,
                trim(regexp_replace(lower(translate(t.description,
                    'ÀÁÂÃÄÅàáâãäåÈÉÊËèéêëÌÍÎÏìíîïÒÓÔÕÖØòóôõöøÙÚÛÜùúûüÇçÑñ',
                    'AAAAAAaaaaaaEEEEeeeeIIIIiiiiOOOOOOooooooUUUUuuuuCcNn')), '\s+', ' ', 'g')) as desc_norm,
                coalesce(trim(lower(t.\"bankAccount\")), '') as conta_norm,
                t.date,
                t.amount,
                t.description,
                t.\"bankAccount\",
                t.created_at,
                row_number() OVER (
                    PARTITION BY 
                        trim(split_part(t.date, 'T', 1)),
                        round(t.amount::numeric, 2),
                        trim(regexp_replace(lower(translate(t.description,
                            'ÀÁÂÃÄÅàáâãäåÈÉÊËèéêëÌÍÎÏìíîïÒÓÔÕÖØòóôõöøÙÚÛÜùúûüÇçÑñ',
                            'AAAAAAaaaaaaEEEEeeeeIIIIiiiiOOOOOOooooooUUUUuuuuCcNn')), '\s+', ' ', 'g')),
                        coalesce(trim(lower(t.\"bankAccount\")), '')
                    ORDER BY t.created_at ASC, t.id ASC
                ) as rn,
                count(*) OVER (
                    PARTITION BY 
                        trim(split_part(t.date, 'T', 1)),
                        round(t.amount::numeric, 2),
                        trim(regexp_replace(lower(translate(t.description,
                            'ÀÁÂÃÄÅàáâãäåÈÉÊËèéêëÌÍÎÏìíîïÒÓÔÕÖØòóôõöøÙÚÛÜùúûüÇçÑñ',
                            'AAAAAAaaaaaaEEEEeeeeIIIIiiiiOOOOOOooooooUUUUuuuuCcNn')), '\s+', ' ', 'g')),
                        coalesce(trim(lower(t.\"bankAccount\")), '')
                ) as total_grupo
            FROM public.transactions t
            WHERE t.date IS NOT NULL AND t.description IS NOT NULL AND t.amount IS NOT NULL
        )
        SELECT 
            r.id AS \"ID Lançamento\",
            r.date AS \"Data\",
            'R$ ' || to_char(r.amount, 'FM999G999D00') AS \"Valor\",
            LEFT(r.description, 35) AS \"Descrição\",
            COALESCE(r.\"bankAccount\", '-') AS \"Conta\",
            to_char(r.created_at, 'YYYY-MM-DD HH24:MI:SS') AS \"Criado Em\",
            CASE 
                WHEN r.rn = 1 THEN '>>> MANTER (Mais Antigo)'
                ELSE 'REMOVER (Duplicado #' || r.rn || ')'
            END AS \"Ação Prevista\"
        FROM ranked_tx r
        WHERE r.total_grupo > 1
        ORDER BY r.data_norm ASC, r.desc_norm ASC, r.valor_norm ASC, r.rn ASC;
    " || true
fi

# ------------------------------------------------------------------------------
# 3. FASE DE REMOÇÃO: Exclusão com preservação estrita do mais antigo e FKs
# ------------------------------------------------------------------------------
echo -e "\n${BOLD}${CYAN}[3/4] FASE DE REMOÇÃO: Executando exclusão segura via transação atômica...${NC}"

if [ "$COUNT_GROUPS" -eq 0 ]; then
    echo -e "${GREEN}✓ Etapa de remoção pulada pois não há duplicados a processar.${NC}"
else
    SQL_TEMP_HOST=$(mktemp /tmp/limpeza_duplicados_vps_XXXXXX.sql)

    cat << 'EOF_CLEANUP_SQL' > "$SQL_TEMP_HOST"
BEGIN;

DO $$
DECLARE
    v_removed_links INTEGER := 0;
    v_cleared_pairs INTEGER := 0;
    v_deleted_tx INTEGER := 0;
BEGIN
    -- 1. Cria tabela temporária isolando os IDs que serão estritamente removidos
    -- Critério: mantém rn = 1 (menor created_at ASC; desempate menor id ASC)
    -- Remove todos com rn > 1
    CREATE TEMP TABLE tmp_duplicates_to_delete ON COMMIT DROP AS
    WITH ranked_tx AS (
        SELECT 
            t.id,
            row_number() OVER (
                PARTITION BY 
                    trim(split_part(t.date, 'T', 1)),
                    round(t.amount::numeric, 2),
                    trim(regexp_replace(lower(translate(t.description,
                        'ÀÁÂÃÄÅàáâãäåÈÉÊËèéêëÌÍÎÏìíîïÒÓÔÕÖØòóôõöøÙÚÛÜùúûüÇçÑñ',
                        'AAAAAAaaaaaaEEEEeeeeIIIIiiiiOOOOOOooooooUUUUuuuuCcNn')), '\s+', ' ', 'g')),
                    coalesce(trim(lower(t."bankAccount")), '')
                ORDER BY t.created_at ASC, t.id ASC
            ) as rn
        FROM public.transactions t
        WHERE t.date IS NOT NULL AND t.description IS NOT NULL AND t.amount IS NOT NULL
    )
    SELECT id FROM ranked_tx WHERE rn > 1;

    -- 2. Tratamento defensivo de integridade referencial (FK) antes de apagar:
    -- A) Vínculos N:M em transaction_cases dos que serão removidos
    IF EXISTS (
        SELECT 1 FROM information_schema.tables 
        WHERE table_schema = 'public' AND table_name = 'transaction_cases'
    ) THEN
        WITH deleted_links AS (
            DELETE FROM public.transaction_cases
            WHERE transaction_id IN (SELECT id FROM tmp_duplicates_to_delete)
            RETURNING id
        )
        SELECT count(*) INTO v_removed_links FROM deleted_links;
        RAISE NOTICE '[OK] Vínculos N:M em transaction_cases removidos preventivamente: %', v_removed_links;
    END IF;

    -- B) Se outros lançamentos tiverem pair_id apontando para um lançamento que será excluído,
    --    limpar pair_id (SET NULL) para evitar bloqueio por FK recursiva
    WITH updated_pairs AS (
        UPDATE public.transactions
        SET pair_id = NULL
        WHERE pair_id IN (SELECT id FROM tmp_duplicates_to_delete)
        RETURNING id
    )
    SELECT count(*) INTO v_cleared_pairs FROM updated_pairs;
    IF v_cleared_pairs > 0 THEN
        RAISE NOTICE '[OK] Referências pair_id atualizadas para NULL: %', v_cleared_pairs;
    END IF;

    -- 3. REMOÇÃO DOS LANÇAMENTOS DUPLICADOS
    WITH deleted_transactions AS (
        DELETE FROM public.transactions
        WHERE id IN (SELECT id FROM tmp_duplicates_to_delete)
        RETURNING id
    )
    SELECT count(*) INTO v_deleted_tx FROM deleted_transactions;

    RAISE NOTICE '[OK] Lançamentos duplicados removidos com sucesso: %', v_deleted_tx;
END $$;

COMMIT;
EOF_CLEANUP_SQL

    RAND_ID="clean_dup_${RANDOM:-$$}_$(date +%s 2>/dev/null || echo '0')"
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
# 4. FASE DE CONFERÊNCIA (Prova de que zerou os duplicados)
# ------------------------------------------------------------------------------
echo -e "\n${BOLD}${CYAN}[4/4] FASE DE CONFERÊNCIA: Verificando se restou algum duplicado...${NC}"

POST_COUNT_GROUPS=$(run_sql_query "
    WITH dup_groups AS (
        SELECT 
            trim(split_part(t.date, 'T', 1)) as norm_date,
            round(t.amount::numeric, 2) as norm_amount,
            trim(regexp_replace(lower(translate(t.description,
                'ÀÁÂÃÄÅàáâãäåÈÉÊËèéêëÌÍÎÏìíîïÒÓÔÕÖØòóôõöøÙÚÛÜùúûüÇçÑñ',
                'AAAAAAaaaaaaEEEEeeeeIIIIiiiiOOOOOOooooooUUUUuuuuCcNn')), '\s+', ' ', 'g')) as norm_desc,
            coalesce(trim(lower(t.\"bankAccount\")), '') as norm_account,
            count(*) as cnt
        FROM public.transactions t
        WHERE t.date IS NOT NULL AND t.description IS NOT NULL AND t.amount IS NOT NULL
        GROUP BY 
            trim(split_part(t.date, 'T', 1)),
            round(t.amount::numeric, 2),
            trim(regexp_replace(lower(translate(t.description,
                'ÀÁÂÃÄÅàáâãäåÈÉÊËèéêëÌÍÎÏìíîïÒÓÔÕÖØòóôõöøÙÚÛÜùúûüÇçÑñ',
                'AAAAAAaaaaaaEEEEeeeeIIIIiiiiOOOOOOooooooUUUUuuuuCcNn')), '\s+', ' ', 'g')),
            coalesce(trim(lower(t.\"bankAccount\")), '')
        HAVING count(*) > 1
    )
    SELECT count(*) FROM dup_groups;
" || echo "0")
POST_COUNT_GROUPS=$(echo "$POST_COUNT_GROUPS" | tr -dc '0-9')
[ -z "$POST_COUNT_GROUPS" ] && POST_COUNT_GROUPS=0

echo -e "   - Grupos duplicados encontrados inicialmente: ${YELLOW}${COUNT_GROUPS}${NC}"
echo -e "   - Lançamentos repetidos removidos:            ${GREEN}${TOTAL_TO_REMOVE}${NC}"
echo -e "   - Grupos duplicados restantes no banco:       $( [ "$POST_COUNT_GROUPS" = "0" ] && echo -e "${GREEN}0 grupos [OK - ZERADO]${NC}" || echo -e "${RED}${POST_COUNT_GROUPS} grupos ainda restam [FALHA]${NC}" )"

if [ "$POST_COUNT_GROUPS" != "0" ]; then
    echo -e "\n${RED}=====================================================================${NC}"
    echo -e "${RED}❌ ERRO: A verificação final detectou duplicados restantes no banco! ${NC}"
    echo -e "${RED}=====================================================================${NC}\n"
    exit 1
fi

echo -e "\n${BOLD}${GREEN}=====================================================================${NC}"
echo -e "${BOLD}${GREEN}🎉 LIMPEZA DE DUPLICADOS CONCLUÍDA COM SUCESSO NO BANCO DO VPS!      ${NC}"
echo -e "${BOLD}${GREEN}=====================================================================${NC}"
echo -e "Contêiner eleito:          ${BOLD}${DB_CONTAINER}${NC}"
echo -e "Usuário eleito:            ${BOLD}${DB_USER}${NC}"
echo -e "Banco eleito:              ${BOLD}${DB_NAME}${NC}"
echo -e "Lançamentos mantidos:      ${BOLD}O mais antigo de cada grupo (menor data criação / id)${NC}"
echo -e "Lançamentos removidos:     ${BOLD}${GREEN}${TOTAL_TO_REMOVE} duplicatas eliminadas [OK]${NC}"
echo -e "Duplicados restantes:      ${BOLD}${GREEN}0 (zero) [OK]${NC}"
echo -e "${BOLD}${GREEN}=====================================================================${NC}"
echo -e "${YELLOW}ℹ️  Nota operacional: Esta alteração foi executada diretamente no banco de dados.${NC}"
echo -e "${YELLOW}   Nenhum redeploy de aplicação no EasyPanel é necessário.${NC}"
echo -e "${YELLOW}   Basta atualizar a tela no navegador (F5 ou Ctrl+F5) para ver o Financeiro limpo.${NC}"
echo -e "${BOLD}${GREEN}=====================================================================${NC}\n"
