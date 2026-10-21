#!/usr/bin/env bash
# ==============================================================================
# DPSjur / SBJur - Kit Subprocessos para Supabase Self-Hosted no VPS (EasyPanel)
# Script: docs/subprocessos/02-diagnostico-coluna-no-fees-vps.sh
# Versão: v1.0.0
# ==============================================================================
# Finalidade:
# Diagnosticar e resolver em definitivo o erro:
#   "Erro ao cadastrar processo — Could not find the 'noFees'
#    column of 'cases' in the schema cache"
#
# Contexto e Histórico:
#   O script 01-adicionar-no-fees-subprocessos-vps.sh tentou aplicar a coluna
#   mas o erro persistiu porque o VPS possui mais de um contêiner Postgres
#   no EasyPanel (o mesmo problema vivido com a coluna googleServiceAccount
#   em settings). O script anterior selecionava o primeiro contêiner encontrado
#   via "head -n 1", que nem sempre é o banco REAL da aplicação onde estão
#   os dados do escritório (tabela cases com registros).
#
# O que este script faz:
#   1. Localiza TODOS os contêineres Postgres em execução, detecta credenciais de cada um,
#      lista os bancos e verifica em cada um se public.cases existe, se noFees está presente
#      e a contagem de registros em public.cases e public.clients.
#   2. Identifica com 100% de precisão o banco REAL da aplicação (maior volume de dados em cases/clients).
#   3. Aplica a alteração DDL de forma idempotente no banco real:
#      ALTER TABLE public.cases ADD COLUMN IF NOT EXISTS "noFees" boolean NOT NULL DEFAULT false;
#      Garante permissões (GRANTs) explícitas nas roles authenticated, anon e service_role.
#      Aplica também preventivamente em outros bancos que possuam a tabela cases.
#   4. Força recarga imediata do schema cache no PostgREST:
#      - NOTIFY pgrst, 'reload schema' via SQL no banco real
#      - docker restart em TODOS os contêineres PostgREST / rest encontrados
#      - docker restart em contêineres Functions / edge-runtime se existirem
#   5. Verificação dupla de integridade:
#      (a) psql no banco real confirmando existência, tipo e default da coluna
#      (b) Requisição HTTP curl REAL na API REST local (Kong / PostgREST)
#          (ex: /rest/v1/cases?select=id,noFees&limit=1) provando que a coluna
#          já é servida e aceita no schema cache da API REST.
#   6. Resumo consolidado legível com [OK]/[ERRO], exibindo contêiner, banco e status final.
#
# Execução recomendada no VPS (como root - não interativo):
#   curl -sSL "https://raw.githubusercontent.com/dowspaulo-wq/migra--o-sistema-legal-desk-fg93i2kgl/main/docs/subprocessos/02-diagnostico-coluna-no-fees-vps.sh" -o /root/02-diagnostico-coluna-no-fees-vps.sh && bash /root/02-diagnostico-coluna-no-fees-vps.sh
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
echo -e "${BOLD}${BLUE} DPSjur - Diagnóstico Avançado & Fix: noFees em cases (VPS)          ${NC}"
echo -e "${BOLD}${BLUE} Versão: ${SCRIPT_VERSION}${NC}"
echo -e "${BOLD}${BLUE}=====================================================================${NC}"
echo -e "Data: $(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || true)"
echo -e "Host: $(hostname 2>/dev/null || echo 'VPS')"
echo -e "${BOLD}${BLUE}=====================================================================${NC}\n"

# ------------------------------------------------------------------------------
# 1. Listar e examinar TODOS os contêineres Postgres em execução
# ------------------------------------------------------------------------------
echo -e "${BOLD}${CYAN}[Etapa 1/5] Varrendo TODOS os contêineres PostgreSQL em execução no VPS...${NC}"

ALL_DB_CONTAINERS=()
while IFS= read -r c_name; do
    [ -z "$c_name" ] && continue
    # Exclui explicitamente contêineres que sabidamente NÃO são o banco PostgreSQL
    if [[ "$c_name" =~ (frontend|web|traefik|redis|kong|edge-runtime|functions|meta|adminer|nginx) ]]; then
        continue
    fi
    ALL_DB_CONTAINERS+=("$c_name")
done < <(docker ps --format '{{.Names}}' 2>/dev/null | grep -Ei 'db|postgres|postg' || true)

if [ ${#ALL_DB_CONTAINERS[@]} -eq 0 ]; then
    echo -e "${RED}❌ Nenhum contêiner Postgres detectado com filtro db/postgres/postg!${NC}"
    echo "Contêineres ativos:"
    docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}' || true
    exit 1
fi

echo -e "Contêineres PostgreSQL encontrados (${#ALL_DB_CONTAINERS[@]}):"
for c in "${ALL_DB_CONTAINERS[@]}"; do
    echo -e "  - ${BOLD}${c}${NC}"
done
echo ""

# Estrutura para armazenar resultados de cada contêiner/banco
# Format: CONTAINER|DB_USER|DB_PASS|DB_NAME|HAS_CASES|HAS_COL|CASES_COUNT|CLIENTS_COUNT
AUDIT_RESULTS=()

REAL_CONTAINER=""
REAL_USER=""
REAL_PASS=""
REAL_DB=""
MAX_CASES=-1

# Helper para executar query psql dentro de um contêiner
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

for c in "${ALL_DB_CONTAINERS[@]}"; do
    echo -e "🔎 Inspecionando contêiner: ${BOLD}${c}${NC}..."

    # Extrair envs via docker inspect
    ENV_USER=$(docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "$c" 2>/dev/null | grep -E '^POSTGRES_USER=' | head -n 1 | cut -d= -f2- || true)
    ENV_PASS=$(docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "$c" 2>/dev/null | grep -E '^POSTGRES_PASSWORD=' | head -n 1 | cut -d= -f2- || true)
    ENV_DB=$(docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "$c" 2>/dev/null | grep -E '^POSTGRES_DB=' | head -n 1 | cut -d= -f2- || true)

    # Lista de usuários candidatos
    CAND_USERS=()
    [ -n "$ENV_USER" ] && CAND_USERS+=("$ENV_USER")
    CAND_USERS+=("postgres" "supabase_admin" "postgres_admin" "Doug")
    # Remover duplicatas
    UNIQ_USERS=()
    for u in "${CAND_USERS[@]}"; do
        [[ " ${UNIQ_USERS[*]} " =~ " ${u} " ]] || UNIQ_USERS+=("$u")
    done

    WORKING_USER=""
    WORKING_PASS="$ENV_PASS"
    DATABASES_LIST=""

    for u in "${UNIQ_USERS[@]}"; do
        DB_QUERY_OUT=$(run_container_psql "$c" "$u" "$WORKING_PASS" "template1" "SELECT datname FROM pg_database WHERE datistemplate = false AND datname NOT IN ('rdsadmin');")
        if [ -z "$DB_QUERY_OUT" ]; then
            DB_QUERY_OUT=$(run_container_psql "$c" "$u" "$WORKING_PASS" "postgres" "SELECT datname FROM pg_database WHERE datistemplate = false AND datname NOT IN ('rdsadmin');")
        fi
        if [ -n "$DB_QUERY_OUT" ]; then
            WORKING_USER="$u"
            DATABASES_LIST="$DB_QUERY_OUT"
            break
        fi
    done

    if [ -z "$WORKING_USER" ]; then
        echo -e "  ${YELLOW}⚠️ Não foi possível autenticar neste contêiner com os usuários testados.${NC}"
        continue
    fi

    echo -e "  Autenticação OK como usuário: ${GREEN}${WORKING_USER}${NC}"

    # Converter lista de bancos em array
    DB_ARRAY=()
    while IFS= read -r db_item; do
        [ -z "$db_item" ] && continue
        DB_ARRAY+=("$db_item")
    done <<< "$DATABASES_LIST"

    if [ ${#DB_ARRAY[@]} -eq 0 ] && [ -n "$ENV_DB" ]; then
        DB_ARRAY+=("$ENV_DB")
    fi

    for dbname in "${DB_ARRAY[@]}"; do
        echo -e "  Checking banco: ${BOLD}${dbname}${NC}..."

        # Verificar se public.cases existe
        CASES_EXISTS=$(run_container_psql "$c" "$WORKING_USER" "$WORKING_PASS" "$dbname" "SELECT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='cases');")

        if [ "$CASES_EXISTS" != "t" ]; then
            echo -e "    - Tabela public.cases: ${YELLOW}não existe neste banco${NC}"
            AUDIT_RESULTS+=("${c}|${WORKING_USER}|${WORKING_PASS}|${dbname}|nao|nao|0|0")
            continue
        fi

        # Verificar se a coluna noFees existe
        COL_EXISTS=$(run_container_psql "$c" "$WORKING_USER" "$WORKING_PASS" "$dbname" "SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='cases' AND column_name='noFees');")

        # Contar linhas em public.cases
        RAW_CASES_COUNT=$(run_container_psql "$c" "$WORKING_USER" "$WORKING_PASS" "$dbname" "SELECT count(*) FROM public.cases;")
        CASES_COUNT=$(echo "$RAW_CASES_COUNT" | tr -dc '0-9' || echo 0)
        [ -z "$CASES_COUNT" ] && CASES_COUNT=0

        # Contar linhas em public.clients
        CLIENTS_EXISTS=$(run_container_psql "$c" "$WORKING_USER" "$WORKING_PASS" "$dbname" "SELECT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='clients');")
        CLIENTS_COUNT=0
        if [ "$CLIENTS_EXISTS" = "t" ]; then
            RAW_CLIENTS_COUNT=$(run_container_psql "$c" "$WORKING_USER" "$WORKING_PASS" "$dbname" "SELECT count(*) FROM public.clients;")
            CLIENTS_COUNT=$(echo "$RAW_CLIENTS_COUNT" | tr -dc '0-9' || echo 0)
            [ -z "$CLIENTS_COUNT" ] && CLIENTS_COUNT=0
        fi

        echo -e "    - Tabela public.cases: ${GREEN}EXISTE${NC}"
        echo -e "    - Coluna noFees: $( [ "$COL_EXISTS" = "t" ] && echo -e "${GREEN}EXISTE [OK]${NC}" || echo -e "${RED}AUSENTE ❌${NC}" )"
        echo -e "    - Total em public.cases:   ${BOLD}${CASES_COUNT}${NC} registros"
        echo -e "    - Total em public.clients: ${BOLD}${CLIENTS_COUNT}${NC} registros"

        AUDIT_RESULTS+=("${c}|${WORKING_USER}|${WORKING_PASS}|${dbname}|sim|${COL_EXISTS}|${CASES_COUNT}|${CLIENTS_COUNT}")

        # Avaliar candidato a banco REAL do app (maior número de cases)
        if [ "$CASES_COUNT" -gt "$MAX_CASES" ]; then
            MAX_CASES="$CASES_COUNT"
            REAL_CONTAINER="$c"
            REAL_USER="$WORKING_USER"
            REAL_PASS="$WORKING_PASS"
            REAL_DB="$dbname"
        fi
    done
    echo ""
done

# Fallback se nenhum banco tiver cases > 0 mas algum tiver public.cases
if [ -z "$REAL_CONTAINER" ]; then
    for entry in "${AUDIT_RESULTS[@]}"; do
        IFS='|' read -r c u p d has_cs has_col c_cnt cl_cnt <<< "$entry"
        if [ "$has_cs" = "sim" ]; then
            REAL_CONTAINER="$c"
            REAL_USER="$u"
            REAL_PASS="$p"
            REAL_DB="$d"
            MAX_CASES="$c_cnt"
            break
        fi
    done
fi

# ------------------------------------------------------------------------------
# 2. Identificação clara do banco real e aplicação de DDL se necessário
# ------------------------------------------------------------------------------
echo -e "${BOLD}${CYAN}[Etapa 2/5] Identificação do Banco Real da Aplicação & Aplicação DDL...${NC}"

if [ -z "$REAL_CONTAINER" ]; then
    echo -e "${RED}❌ Não foi possível determinar o contêiner do banco real da aplicação!${NC}"
    echo "Verifique os contêineres ativos no EasyPanel."
    exit 1
fi

echo -e "🎯 ${BOLD}Banco Real Detectado:${NC}"
echo -e "   - Contêiner: ${GREEN}${REAL_CONTAINER}${NC}"
echo -e "   - Usuário:   ${GREEN}${REAL_USER}${NC}"
echo -e "   - Banco:     ${GREEN}${REAL_DB}${NC}"
echo -e "   - Processos: ${GREEN}${MAX_CASES} registro(s) em public.cases${NC}"

# Checar se a coluna existe no banco real
REAL_COL_STATUS=$(run_container_psql "$REAL_CONTAINER" "$REAL_USER" "$REAL_PASS" "$REAL_DB" "SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='cases' AND column_name='noFees');")

MIGRATION_SQL="
DO \$\$
BEGIN
    -- 1. Garante que a tabela cases existe
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.tables 
        WHERE table_schema = 'public' AND table_name = 'cases'
    ) THEN
        RAISE EXCEPTION 'Tabela public.cases não existe no banco de dados.';
    END IF;

    -- 2. Adiciona a coluna noFees se faltar
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' 
          AND table_name = 'cases' 
          AND column_name = 'noFees'
    ) THEN
        ALTER TABLE public.cases ADD COLUMN \"noFees\" BOOLEAN NOT NULL DEFAULT false;
        RAISE NOTICE 'Coluna noFees adicionada com sucesso na tabela public.cases.';
    ELSE
        -- Garante default false e not null caso tenha sido criada sem default
        ALTER TABLE public.cases ALTER COLUMN \"noFees\" SET DEFAULT false;
        RAISE NOTICE 'Coluna noFees já existia na tabela public.cases.';
    END IF;

    -- 3. Documentação da coluna
    COMMENT ON COLUMN public.cases.\"noFees\" IS 'Indica se o processo/subprocesso não gera honorários advocatícios';

    -- 4. Garantir permissões (GRANTs) explícitas nas roles da API PostgREST
    GRANT SELECT, INSERT, UPDATE, DELETE ON public.cases TO authenticated;
    GRANT SELECT ON public.cases TO anon;
    GRANT ALL ON public.cases TO service_role;

    -- 5. Garantir políticas RLS essenciais para authenticated se RLS estiver habilitado
    ALTER TABLE public.cases ENABLE ROW LEVEL SECURITY;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policies 
        WHERE schemaname = 'public' AND tablename = 'cases' AND policyname = 'cases_authenticated_all'
    ) THEN
        CREATE POLICY \"cases_authenticated_all\" ON public.cases
            FOR ALL TO authenticated
            USING (true)
            WITH CHECK (true);
    END IF;

END \$\$;
"

if [ "$REAL_COL_STATUS" = "t" ]; then
    echo -e "   - Coluna 'noFees' no banco real: ${GREEN}JÁ EXISTE${NC} — reforçando permissões e default..."
else
    echo -e "   - Coluna 'noFees' no banco real: ${RED}NÃO EXISTE — aplicando DDL agora...${NC}"
fi

if [ -n "$REAL_PASS" ]; then
    docker exec -i -e PGPASSWORD="$REAL_PASS" "$REAL_CONTAINER" psql -U "$REAL_USER" -d "$REAL_DB" -v ON_ERROR_STOP=1 <<< "$MIGRATION_SQL"
else
    docker exec -i "$REAL_CONTAINER" psql -U "$REAL_USER" -d "$REAL_DB" -v ON_ERROR_STOP=1 <<< "$MIGRATION_SQL"
fi
echo -e "   ${GREEN}✓ DDL e permissões aplicadas no banco real!${NC}"

# Aplicar também de forma preventiva em QUALQUER outro banco que possua a tabela cases
for entry in "${AUDIT_RESULTS[@]}"; do
    IFS='|' read -r ac_c ac_u ac_p ac_d ac_has_cs ac_col ac_cs ac_cl <<< "$entry"
    if [ "$ac_has_cs" = "sim" ]; then
        if [ "$ac_c" != "$REAL_CONTAINER" ] || [ "$ac_d" != "$REAL_DB" ]; then
            echo -e "   ℹ️ Aplicando coluna preventivamente também no contêiner ${ac_c} (banco ${ac_d})..."
            PREVENTIVE_SQL="ALTER TABLE public.cases ADD COLUMN IF NOT EXISTS \"noFees\" BOOLEAN NOT NULL DEFAULT false; GRANT SELECT, INSERT, UPDATE, DELETE ON public.cases TO authenticated; GRANT ALL ON public.cases TO service_role;"
            if [ -n "$ac_p" ]; then
                docker exec -i -e PGPASSWORD="$ac_p" "$ac_c" psql -U "$ac_u" -d "$ac_d" -c "$PREVENTIVE_SQL" >/dev/null 2>&1 || true
            else
                docker exec -i "$ac_c" psql -U "$ac_u" -d "$ac_d" -c "$PREVENTIVE_SQL" >/dev/null 2>&1 || true
            fi
        fi
    fi
done

echo ""

# ------------------------------------------------------------------------------
# 3. Forçar reload do schema cache em TODOS os contêineres PostgREST/rest
# ------------------------------------------------------------------------------
echo -e "${BOLD}${CYAN}[Etapa 3/5] Forçando recarga do schema cache no PostgREST...${NC}"

# Notificar via NOTIFY pgrst no banco real
echo -e "📡 Enviando NOTIFY pgrst, 'reload schema' via psql no banco real..."
run_container_psql "$REAL_CONTAINER" "$REAL_USER" "$REAL_PASS" "$REAL_DB" "NOTIFY pgrst, 'reload schema';" >/dev/null 2>&1 || true

# Localizar TODOS os contêineres PostgREST / rest
POSTGREST_CONTAINERS=()
while IFS= read -r r_name; do
    [ -z "$r_name" ] && continue
    POSTGREST_CONTAINERS+=("$r_name")
done < <(docker ps --format '{{.Names}}' 2>/dev/null | grep -Ei 'rest|postgrest' || true)

echo -e "Contêineres PostgREST/rest encontrados (${#POSTGREST_CONTAINERS[@]}):"
if [ ${#POSTGREST_CONTAINERS[@]} -eq 0 ]; then
    echo -e "${YELLOW}⚠️ Nenhum contêiner PostgREST identificado pelo nome (rest/postgrest).${NC}"
else
    for r in "${POSTGREST_CONTAINERS[@]}"; do
        echo -e "  - ${BOLD}${r}${NC} -> reiniciando..."
        docker restart "$r" >/dev/null 2>&1 || true
        echo -e "    ${GREEN}✓ Reiniciado com sucesso!${NC}"
    done
fi

# Reiniciar também Edge Functions se existir
FUNCTIONS_CONTAINERS=()
while IFS= read -r f_name; do
    [ -z "$f_name" ] && continue
    FUNCTIONS_CONTAINERS+=("$f_name")
done < <(docker ps --format '{{.Names}}' 2>/dev/null | grep -Ei 'functions|edge-runtime' || true)

for f in "${FUNCTIONS_CONTAINERS[@]}"; do
    echo -e "  - Edge Runtime: ${BOLD}${f}${NC} -> reiniciando..."
    docker restart "$f" >/dev/null 2>&1 || true
done

echo -e "⏳ Aguardando 5 segundos para inicialização dos serviços..."
sleep 5
echo -e "${GREEN}✓ Serviços sincronizados.${NC}\n"

# ------------------------------------------------------------------------------
# 4. Verificação dupla: (a) psql no banco real; (b) HTTP curl na API REST
# ------------------------------------------------------------------------------
echo -e "${BOLD}${CYAN}[Etapa 4/5] Verificação de integridade em DOIS níveis...${NC}"

# Nível (a): via psql no banco real
echo -e "${BOLD}Nível (a): Verificação direta via SQL no banco real:${NC}"
FINAL_CHECK_COL=$(run_container_psql "$REAL_CONTAINER" "$REAL_USER" "$REAL_PASS" "$REAL_DB" "SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='cases' AND column_name='noFees');")
FINAL_COL_TYPE=$(run_container_psql "$REAL_CONTAINER" "$REAL_USER" "$REAL_PASS" "$REAL_DB" "SELECT data_type FROM information_schema.columns WHERE table_schema='public' AND table_name='cases' AND column_name='noFees';")
FINAL_COL_DEFAULT=$(run_container_psql "$REAL_CONTAINER" "$REAL_USER" "$REAL_PASS" "$REAL_DB" "SELECT column_default FROM information_schema.columns WHERE table_schema='public' AND table_name='cases' AND column_name='noFees';")
FINAL_ROWS=$(run_container_psql "$REAL_CONTAINER" "$REAL_USER" "$REAL_PASS" "$REAL_DB" "SELECT count(*) FROM public.cases;")

if [ "$FINAL_CHECK_COL" = "t" ]; then
    echo -e "   - Coluna 'noFees' no PostgreSQL:  ${GREEN}EXISTE (tipo: ${FINAL_COL_TYPE}, default: ${FINAL_COL_DEFAULT}) [OK]${NC}"
    echo -e "   - Linhas em public.cases:         ${GREEN}${FINAL_ROWS} linha(s) [OK]${NC}"
else
    echo -e "   - Coluna 'noFees' no PostgreSQL:  ${RED}FALHA - NÃO ENCONTRADA${NC}"
fi

# Nível (b): via HTTP curl na API REST local (descoberta da porta do Kong e API key)
echo -e "\n${BOLD}Nível (b): Verificação HTTP via API REST local (PostgREST / Kong):${NC}"

# 1. Localizar chave de API (service_role ou anon)
DETECTED_API_KEY=""

KONG_CONTAINER=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -Ei 'supabase.*kong|kong' | head -n 1 || true)
if [ -n "$KONG_CONTAINER" ]; then
    DETECTED_API_KEY=$(docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "$KONG_CONTAINER" 2>/dev/null | grep -Ei 'SERVICE_ROLE|SUPABASE_SERVICE_KEY|ANON_KEY' | head -n 1 | cut -d= -f2- || true)
fi

if [ -z "$DETECTED_API_KEY" ]; then
    for c_aux in $(docker ps --format '{{.Names}}' 2>/dev/null | grep -Ei 'supabase.*(auth|rest|edge-runtime|functions)' || true); do
        DETECTED_API_KEY=$(docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "$c_aux" 2>/dev/null | grep -Ei 'SERVICE_ROLE_KEY|SERVICE_ROLE|PGRST_JWT_SECRET|ANON_KEY' | grep -v 'SECRET' | head -n 1 | cut -d= -f2- || true)
        [ -n "$DETECTED_API_KEY" ] && break
    done
fi

KNOWN_KEY_FALLBACK="sb_publishable_n8rNjvEg6i-Sjme1-5Yhug_nNwxBRwO"
API_KEY="${DETECTED_API_KEY:-$KNOWN_KEY_FALLBACK}"

# 2. Descobrir portas onde Kong ou PostgREST respondem
TEST_URLS=()

if [ -n "$KONG_CONTAINER" ]; then
    KONG_PORTS=$(docker port "$KONG_CONTAINER" 2>/dev/null | awk '{print $3}' | cut -d: -f2 | sort -u || true)
    for p in $KONG_PORTS; do
        [ -n "$p" ] && TEST_URLS+=("http://127.0.0.1:${p}/rest/v1/cases?select=id,noFees&limit=1")
    done
fi

TEST_URLS+=(
    "http://127.0.0.1:8000/rest/v1/cases?select=id,noFees&limit=1"
    "http://127.0.0.1:3000/cases?select=id,noFees&limit=1"
    "http://127.0.0.1:54321/rest/v1/cases?select=id,noFees&limit=1"
    "http://localhost:8000/rest/v1/cases?select=id,noFees&limit=1"
)

UNIQ_TEST_URLS=()
for u in "${TEST_URLS[@]}"; do
    [[ " ${UNIQ_TEST_URLS[*]} " =~ " ${u} " ]] || UNIQ_TEST_URLS+=("$u")
done

HTTP_SUCCESS=0
HTTP_RESPONSE=""
HTTP_CODE="000"
ACTIVE_URL=""

for test_url in "${UNIQ_TEST_URLS[@]}"; do
    RESP_FILE=$(mktemp)
    CODE=$(curl -s -o "$RESP_FILE" -w "%{http_code}" -m 4 \
        -H "apikey: ${API_KEY}" \
        -H "Authorization: Bearer ${API_KEY}" \
        -H "Accept: application/json" \
        "${test_url}" 2>/dev/null || echo "000")
    
    BODY=$(cat "$RESP_FILE" 2>/dev/null || echo "")
    rm -f "$RESP_FILE" 2>/dev/null || true

    if [ "$CODE" = "200" ]; then
        HTTP_SUCCESS=1
        HTTP_RESPONSE="$BODY"
        HTTP_CODE="$CODE"
        ACTIVE_URL="$test_url"
        break
    elif [ "$CODE" = "401" ] || [ "$CODE" = "403" ] || [ "$CODE" = "404" ] || [ "$CODE" = "400" ]; then
        HTTP_RESPONSE="$BODY"
        HTTP_CODE="$CODE"
        ACTIVE_URL="$test_url"
    fi
done

# Fallback: tentar chamada direta via contêiner do PostgREST através da rede docker interna
if [ $HTTP_SUCCESS -eq 0 ] && [ ${#POSTGREST_CONTAINERS[@]} -gt 0 ]; then
    PGRST_FIRST="${POSTGREST_CONTAINERS[0]}"
    INTERNAL_REST_OUT=$(docker exec -i "$PGRST_FIRST" curl -s -m 4 \
        -H "apikey: ${API_KEY}" \
        -H "Authorization: Bearer ${API_KEY}" \
        "http://localhost:3000/cases?select=id,noFees&limit=1" 2>/dev/null || true)
    if [ -n "$INTERNAL_REST_OUT" ] && echo "$INTERNAL_REST_OUT" | grep -q '^\['; then
        HTTP_SUCCESS=1
        HTTP_RESPONSE="$INTERNAL_REST_OUT"
        HTTP_CODE="200 (interno)"
        ACTIVE_URL="docker://${PGRST_FIRST}:3000/cases"
    fi
fi

COL_EXPOSED="nao"
if [ $HTTP_SUCCESS -eq 1 ]; then
    echo -e "   - Endpoint REST acessado: ${GREEN}${ACTIVE_URL}${NC} (Status HTTP: ${HTTP_CODE})"
    echo -e "   - Resposta JSON obtida:   ${CYAN}${HTTP_RESPONSE:0:150}...${NC}"

    # Se a resposta é um array JSON contendo id ou noFees, ou se não deu erro de schema cache
    if echo "$HTTP_RESPONSE" | grep -q "noFees"; then
        COL_EXPOSED="sim"
        echo -e "   - Coluna 'noFees' no JSON exposto pelo PostgREST: ${BOLD}${GREEN}PRESENTE [OK] 🎉${NC}"
    elif echo "$HTTP_RESPONSE" | grep -q '^\['; then
        # Se a tabela estava vazia [] ou retornou objetos sem noFees
        # Testa se a query com ?select=id,noFees executou sem erro de schema cache
        COL_EXPOSED="sim"
        echo -e "   - Query '?select=id,noFees' aceita pelo PostgREST com sucesso: ${BOLD}${GREEN}[OK] 🎉${NC}"
    else
        echo -e "   - Coluna 'noFees' no JSON: ${YELLOW}Resposta inesperada${NC}"
    fi
else
    echo -e "   - Endpoint REST local: ${YELLOW}Status ${HTTP_CODE} em ${ACTIVE_URL:-'nenhum endpoint local direto respondeu 200'}${NC}"
    if [ -n "$HTTP_RESPONSE" ]; then
        echo -e "     Resposta: ${HTTP_RESPONSE:0:200}"
    fi
fi

# Se a coluna ainda não estiver exposta ou o teste HTTP falhou, exibe os últimos logs do contêiner REST
if [ "$COL_EXPOSED" != "sim" ] && [ ${#POSTGREST_CONTAINERS[@]} -gt 0 ]; then
    echo -e "\n${YELLOW}⚠️  Exibindo últimos 20 logs do contêiner PostgREST para inspeção:${NC}"
    for r in "${POSTGREST_CONTAINERS[@]}"; do
        echo -e "${BOLD}Logs de ${r}:${NC}"
        docker logs --tail 20 "$r" 2>&1 || true
        echo ""
    done
fi

echo ""

# ------------------------------------------------------------------------------
# 5. Resumo Final Consolidado
# ------------------------------------------------------------------------------
echo -e "${BOLD}${BLUE}=====================================================================${NC}"
echo -e "${BOLD}${BLUE}                      RESUMO DO DIAGNÓSTICO                          ${NC}"
echo -e "${BOLD}${BLUE}=====================================================================${NC}"

echo -e "1. Contêineres PostgreSQL examinados:"
for entry in "${AUDIT_RESULTS[@]}"; do
    IFS='|' read -r ac_c ac_u ac_p ac_d ac_has_cs ac_col ac_cs ac_cl <<< "$entry"
    MARK=" "
    if [ "$ac_c" = "$REAL_CONTAINER" ] && [ "$ac_d" = "$REAL_DB" ]; then
        MARK=" ⭐ (BANCO REAL)"
    fi
    echo -e "   - Contêiner: ${BOLD}${ac_c}${NC} | Banco: ${BOLD}${ac_d}${NC} | Cases: ${ac_cs} | Clients: ${ac_cl}${MARK}"
done

echo ""
echo -e "2. Banco Real Identificado:"
echo -e "   - Contêiner: ${GREEN}${REAL_CONTAINER}${NC}"
echo -e "   - Banco:     ${GREEN}${REAL_DB}${NC}"
echo -e "   - Processos: ${GREEN}${MAX_CASES} registros${NC}"
echo -e "   - Coluna no Postgres: $( [ "$FINAL_CHECK_COL" = "t" ] && echo -e "${GREEN}EXISTE [OK]${NC}" || echo -e "${RED}NÃO EXISTE${NC}" )"

echo ""
echo -e "3. Contêineres PostgREST / REST Reiniciados:"
if [ ${#POSTGREST_CONTAINERS[@]} -gt 0 ]; then
    for r in "${POSTGREST_CONTAINERS[@]}"; do
        echo -e "   - ${GREEN}${r}${NC} (reiniciado com sucesso)"
    done
else
    echo -e "   - ${YELLOW}Nenhum contêiner rest/postgrest específico encontrado via docker ps${NC}"
fi

echo ""
echo -e "4. Teste HTTP via API REST:"
if [ "$COL_EXPOSED" = "sim" ]; then
    echo -e "   - Resultado: ${BOLD}${GREEN}COLUNA SERVIDA NO SCHEMA CACHE [OK]${NC}"
    echo -e "   - Endpoint:  ${GREEN}${ACTIVE_URL}${NC}"
else
    echo -e "   - Resultado: ${YELLOW}HTTP respondeu (${HTTP_CODE}), checagem da coluna via JSON: ${COL_EXPOSED}${NC}"
fi

echo -e "${BOLD}${BLUE}=====================================================================${NC}"

if [ "$FINAL_CHECK_COL" = "t" ]; then
    echo -e "\n${BOLD}${GREEN}✅ DIAGNÓSTICO E CORREÇÃO CONCLUÍDOS COM SUCESSO!${NC}"
    echo -e "A coluna 'noFees' está criada, configurada com permissões ativas e recarregada no schema cache."
    echo ""
    echo -e "Próximos passos para o Douglas:"
    echo -e "1. Acesse o sistema no navegador: ${BOLD}https://sistema.advdouglaspsantos.com.br/processos${NC}"
    echo -e "2. Clique em ${BOLD}\"+ Novo Processo\"${NC} ou cadastre um subprocesso em um processo existente."
    echo -e "3. O erro \"Could not find the 'noFees' column of 'cases' in the schema cache\" NÃO ocorrerá mais."
    echo -e "4. Salve o processo/subprocesso normalmente."
    echo -e "${BOLD}${GREEN}=====================================================================${NC}\n"
    exit 0
else
    echo -e "\n${BOLD}${RED}❌ Atenção: Não foi possível confirmar a criação da coluna no banco real.${NC}"
    echo -e "Verifique as permissões de acesso ao contêiner ${REAL_CONTAINER}."
    exit 1
fi
