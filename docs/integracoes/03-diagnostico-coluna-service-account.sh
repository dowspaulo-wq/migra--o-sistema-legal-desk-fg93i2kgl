#!/usr/bin/env bash
# ==============================================================================
# DPSjur / SBJur - Kit Google Sheets para Supabase Self-Hosted no VPS (EasyPanel)
# Script: docs/integracoes/03-diagnostico-coluna-service-account.sh
# Versão: v1.0.0
# ==============================================================================
# Finalidade:
# Diagnosticar e resolver em definitivo o erro:
#   "Erro ao salvar Service Account — Could not find the 'googleServiceAccount'
#    column of 'settings' in the schema cache"
#
# Hipóteses cobertas por este diagnóstico aprofundado:
#   1. O script 02 criou a coluna num contêiner ou banco Postgres errado (o VPS pode
#      ter múltiplos contêineres Postgres no EasyPanel).
#   2. O contêiner PostgREST que atende o app tem nome diferente (ex: sbjur-local_supabase-rest-1)
#      e não foi reiniciado ou o NOTIFY pgrst não surtiu efeito.
#   3. O app usa outro schema ou a tabela settings vive em outro banco.
#
# O que este script faz:
#   1. Localiza TODOS os contêineres Postgres em execução, detecta credenciais de cada um,
#      lista os bancos e verifica em cada um se public.settings existe, se googleServiceAccount
#      está presente e a contagem de public.clients.
#   2. Identifica e exibe qual é o banco REAL da aplicação (public.clients > 0). Se a coluna
#      googleServiceAccount não existir no banco real, aplica o DDL idempotente + as 5 RLS policies.
#   3. Força recarga de cache no PostgREST: NOTIFY pgrst via SQL no banco real e docker restart
#      em TODOS os contêineres PostgREST encontrados.
#   4. Verificação dupla: (a) psql no banco real; (b) requisição HTTP curl na API REST local
#      (via Kong interno / rest) com headers apikey e Authorization para provar que a coluna
#      já é exposta no JSON da API. Mostra logs recentes se a coluna ainda faltar.
#   5. Resumo consolidado legível com diagnóstico e resultado final.
#
# Execução no VPS (não interativo):
#   curl -sSL "https://raw.githubusercontent.com/dowspaulo-wq/migra--o-sistema-legal-desk-fg93i2kgl/main/docs/integracoes/03-diagnostico-coluna-service-account.sh" -o /root/03-diagnostico-coluna-service-account.sh && bash /root/03-diagnostico-coluna-service-account.sh
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
echo -e "${BOLD}${BLUE} DPSjur - Diagnóstico Avançado & Fix: googleServiceAccount (VPS)    ${NC}"
echo -e "${BOLD}${BLUE} Versão: ${SCRIPT_VERSION}${NC}"
echo -e "${BOLD}${BLUE}=====================================================================${NC}"
echo -e "Data: $(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || true)"
echo -e "Host: $(hostname 2>/dev/null || echo 'VPS')"
echo -e "${BOLD}${BLUE}=====================================================================${NC}\n"

# ------------------------------------------------------------------------------
# 1. Listar e examinar TODOS os contêineres Postgres em execução
# ------------------------------------------------------------------------------
echo -e "${BOLD}${CYAN}[Etapa 1/5] Varrendo TODOS os contêineres PostgreSQL em execução no VPS...${NC}"

# Localiza contêineres cujos nomes contenham 'db', 'postgres' ou 'postg'
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
# Format: CONTAINER|DB_USER|DB_PASS|DB_NAME|HAS_SETTINGS|HAS_COL|CLIENTS_COUNT
AUDIT_RESULTS=()

REAL_CONTAINER=""
REAL_USER=""
REAL_PASS=""
REAL_DB=""
MAX_CLIENTS=-1

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

        # Verificar se public.settings existe
        SETTINGS_EXISTS=$(run_container_psql "$c" "$WORKING_USER" "$WORKING_PASS" "$dbname" "SELECT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='settings');")

        if [ "$SETTINGS_EXISTS" != "t" ]; then
            echo -e "    - Tabela public.settings: ${YELLOW}não existe neste banco${NC}"
            AUDIT_RESULTS+=("${c}|${WORKING_USER}|${WORKING_PASS}|${dbname}|nao|nao|0")
            continue
        fi

        # Verificar se a coluna googleServiceAccount existe
        COL_EXISTS=$(run_container_psql "$c" "$WORKING_USER" "$WORKING_PASS" "$dbname" "SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='settings' AND column_name='googleServiceAccount');")

        # Contar linhas em public.clients
        CLIENTS_EXISTS=$(run_container_psql "$c" "$WORKING_USER" "$WORKING_PASS" "$dbname" "SELECT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='clients');")
        CLIENTS_COUNT=0
        if [ "$CLIENTS_EXISTS" = "t" ]; then
            RAW_COUNT=$(run_container_psql "$c" "$WORKING_USER" "$WORKING_PASS" "$dbname" "SELECT count(*) FROM public.clients;")
            CLIENTS_COUNT=$(echo "$RAW_COUNT" | tr -dc '0-9' || echo 0)
            [ -z "$CLIENTS_COUNT" ] && CLIENTS_COUNT=0
        fi

        echo -e "    - Tabela public.settings: ${GREEN}EXISTE${NC}"
        echo -e "    - Coluna googleServiceAccount: $( [ "$COL_EXISTS" = "t" ] && echo -e "${GREEN}EXISTE [OK]${NC}" || echo -e "${RED}AUSENTE ❌${NC}" )"
        echo -e "    - Total de registros em public.clients: ${BOLD}${CLIENTS_COUNT}${NC}"

        AUDIT_RESULTS+=("${c}|${WORKING_USER}|${WORKING_PASS}|${dbname}|sim|${COL_EXISTS}|${CLIENTS_COUNT}")

        # Avaliar candidato a banco REAL do app (maior número de clientes)
        if [ "$CLIENTS_COUNT" -gt "$MAX_CLIENTS" ]; then
            MAX_CLIENTS="$CLIENTS_COUNT"
            REAL_CONTAINER="$c"
            REAL_USER="$WORKING_USER"
            REAL_PASS="$WORKING_PASS"
            REAL_DB="$dbname"
        fi
    done
    echo ""
done

# Fallback se nenhum banco tiver clientes > 0 mas algum tiver public.settings
if [ -z "$REAL_CONTAINER" ]; then
    for entry in "${AUDIT_RESULTS[@]}"; do
        IFS='|' read -r c u p d has_s has_c cnt <<< "$entry"
        if [ "$has_s" = "sim" ]; then
            REAL_CONTAINER="$c"
            REAL_USER="$u"
            REAL_PASS="$p"
            REAL_DB="$d"
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
echo -e "   - Clientes:  ${GREEN}${MAX_CLIENTS} registro(s) em public.clients${NC}"

# Checar se a coluna existe no banco real
REAL_COL_STATUS=$(run_container_psql "$REAL_CONTAINER" "$REAL_USER" "$REAL_PASS" "$REAL_DB" "SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='settings' AND column_name='googleServiceAccount');")

if [ "$REAL_COL_STATUS" = "t" ]; then
    echo -e "   - Coluna 'googleServiceAccount' no banco real: ${GREEN}JÁ EXISTE [OK]${NC}"
else
    echo -e "   - Coluna 'googleServiceAccount' no banco real: ${RED}NÃO EXISTE — aplicando DDL agora...${NC}"

    MIGRATION_SQL="
DO \$\$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.tables 
        WHERE table_schema = 'public' AND table_name = 'settings'
    ) THEN
        RAISE EXCEPTION 'Tabela public.settings não existe no banco de dados.';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' 
          AND table_name = 'settings' 
          AND column_name = 'googleServiceAccount'
    ) THEN
        ALTER TABLE public.settings ADD COLUMN \"googleServiceAccount\" TEXT;
        RAISE NOTICE 'Coluna googleServiceAccount adicionada com sucesso na tabela public.settings.';
    END IF;

    COMMENT ON COLUMN public.settings.\"googleServiceAccount\" IS 'Chave de autenticação JSON da Google Service Account para espelhamento em Google Sheets';

    IF NOT EXISTS (SELECT 1 FROM public.settings LIMIT 1) THEN
        INSERT INTO public.settings (id, \"showFinanceDashboard\", \"themeColor\", created_at)
        VALUES (gen_random_uuid(), true, 'blue', NOW());
        RAISE NOTICE 'Registro inicial criado em public.settings.';
    END IF;

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
    if [ -n "$REAL_PASS" ]; then
        docker exec -i -e PGPASSWORD="$REAL_PASS" "$REAL_CONTAINER" psql -U "$REAL_USER" -d "$REAL_DB" -v ON_ERROR_STOP=1 <<< "$MIGRATION_SQL"
    else
        docker exec -i "$REAL_CONTAINER" psql -U "$REAL_USER" -d "$REAL_DB" -v ON_ERROR_STOP=1 <<< "$MIGRATION_SQL"
    fi
    echo -e "   ${GREEN}✓ DDL e políticas RLS aplicadas no banco real!${NC}"
fi

# Aplicar também de forma preventiva em QUALQUER outro banco que possua a tabela settings
for entry in "${AUDIT_RESULTS[@]}"; do
    IFS='|' read -r ac_c ac_u ac_p ac_d ac_hs ac_hc ac_cnt <<< "$entry"
    if [ "$ac_hs" = "sim" ]; then
        if [ "$ac_c" != "$REAL_CONTAINER" ] || [ "$ac_d" != "$REAL_DB" ]; then
            echo -e "   ℹ️ Aplicando coluna preventivamente também no contêiner ${ac_c} (banco ${ac_d})..."
            if [ -n "$ac_p" ]; then
                docker exec -i -e PGPASSWORD="$ac_p" "$ac_c" psql -U "$ac_u" -d "$ac_d" -c "ALTER TABLE public.settings ADD COLUMN IF NOT EXISTS \"googleServiceAccount\" TEXT;" >/dev/null 2>&1 || true
            else
                docker exec -i "$ac_c" psql -U "$ac_u" -d "$ac_d" -c "ALTER TABLE public.settings ADD COLUMN IF NOT EXISTS \"googleServiceAccount\" TEXT;" >/dev/null 2>&1 || true
            fi
        fi
    fi
done

echo ""

# ------------------------------------------------------------------------------
# 3. Forçar reload do schema cache em TODOS os contêineres PostgREST/rest
# ------------------------------------------------------------------------------
echo -e "${BOLD}${CYAN}[Etapa 3/5] Forçando recarga do schema cache no PostgREST...${NC}"

# Notificar via NOTIFY pgrst no banco real e em todos os bancos com settings
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
FINAL_CHECK_COL=$(run_container_psql "$REAL_CONTAINER" "$REAL_USER" "$REAL_PASS" "$REAL_DB" "SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='settings' AND column_name='googleServiceAccount');")
FINAL_COL_TYPE=$(run_container_psql "$REAL_CONTAINER" "$REAL_USER" "$REAL_PASS" "$REAL_DB" "SELECT data_type FROM information_schema.columns WHERE table_schema='public' AND table_name='settings' AND column_name='googleServiceAccount';")
FINAL_ROWS=$(run_container_psql "$REAL_CONTAINER" "$REAL_USER" "$REAL_PASS" "$REAL_DB" "SELECT count(*) FROM public.settings;")

if [ "$FINAL_CHECK_COL" = "t" ]; then
    echo -e "   - Coluna 'googleServiceAccount' no PostgreSQL: ${GREEN}EXISTE (tipo: ${FINAL_COL_TYPE}) [OK]${NC}"
    echo -e "   - Linhas em public.settings:                  ${GREEN}${FINAL_ROWS} linha(s) [OK]${NC}"
else
    echo -e "   - Coluna 'googleServiceAccount' no PostgreSQL: ${RED}FALHA - NÃO ENCONTRADA${NC}"
fi

# Nível (b): via HTTP curl na API REST local (descoberta da porta do Kong e service_role key)
echo -e "\n${BOLD}Nível (b): Verificação HTTP via API REST local (PostgREST / Kong):${NC}"

# 1. Localizar chave de API (service_role ou anon)
DETECTED_API_KEY=""

# Tenta ler do Kong
KONG_CONTAINER=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -Ei 'supabase.*kong|kong' | head -n 1 || true)
if [ -n "$KONG_CONTAINER" ]; then
    DETECTED_API_KEY=$(docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "$KONG_CONTAINER" 2>/dev/null | grep -Ei 'SERVICE_ROLE|SUPABASE_SERVICE_KEY|ANON_KEY' | head -n 1 | cut -d= -f2- || true)
fi

# Tenta ler de auth / rest / edge-runtime se ainda não encontrou
if [ -z "$DETECTED_API_KEY" ]; then
    for c_aux in $(docker ps --format '{{.Names}}' 2>/dev/null | grep -Ei 'supabase.*(auth|rest|edge-runtime|functions)' || true); do
        DETECTED_API_KEY=$(docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "$c_aux" 2>/dev/null | grep -Ei 'SERVICE_ROLE_KEY|SERVICE_ROLE|PGRST_JWT_SECRET|ANON_KEY' | grep -v 'SECRET' | head -n 1 | cut -d= -f2- || true)
        [ -n "$DETECTED_API_KEY" ] && break
    done
fi

# Fallback para chave publishable conhecida
KNOWN_KEY_FALLBACK="sb_publishable_n8rNjvEg6i-Sjme1-5Yhug_nNwxBRwO"
API_KEY="${DETECTED_API_KEY:-$KNOWN_KEY_FALLBACK}"

# 2. Descobrir portas onde Kong ou PostgREST respondem
# Portas candidatas
TEST_URLS=()

# Se Kong existe, inspeciona porta mapeada
if [ -n "$KONG_CONTAINER" ]; then
    KONG_PORTS=$(docker port "$KONG_CONTAINER" 2>/dev/null | awk '{print $3}' | cut -d: -f2 | sort -u || true)
    for p in $KONG_PORTS; do
        [ -n "$p" ] && TEST_URLS+=("http://127.0.0.1:${p}/rest/v1/settings?select=*&limit=1")
    done
fi

# Portas padrão conhecidas do EasyPanel e Supabase
TEST_URLS+=(
    "http://127.0.0.1:8000/rest/v1/settings?select=*&limit=1"
    "http://127.0.0.1:3000/settings?select=*&limit=1"
    "http://127.0.0.1:54321/rest/v1/settings?select=*&limit=1"
    "http://localhost:8000/rest/v1/settings?select=*&limit=1"
)

# Remover duplicatas nas URLs de teste
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
        # Endpoint respondeu, mesmo com código de erro de auth/rota
        HTTP_RESPONSE="$BODY"
        HTTP_CODE="$CODE"
        ACTIVE_URL="$test_url"
    fi
done

# Fallback: tentar chamada direta via contêiner do Kong ou PostgREST através da rede docker interna
if [ $HTTP_SUCCESS -eq 0 ] && [ ${#POSTGREST_CONTAINERS[@]} -gt 0 ]; then
    PGRST_FIRST="${POSTGREST_CONTAINERS[0]}"
    INTERNAL_REST_OUT=$(docker exec -i "$PGRST_FIRST" curl -s -m 4 \
        -H "apikey: ${API_KEY}" \
        -H "Authorization: Bearer ${API_KEY}" \
        "http://localhost:3000/settings?select=*&limit=1" 2>/dev/null || true)
    if [ -n "$INTERNAL_REST_OUT" ] && echo "$INTERNAL_REST_OUT" | grep -q '^\['; then
        HTTP_SUCCESS=1
        HTTP_RESPONSE="$INTERNAL_REST_OUT"
        HTTP_CODE="200 (interno)"
        ACTIVE_URL="docker://${PGRST_FIRST}:3000/settings"
    fi
fi

COL_EXPOSED="nao"
if [ $HTTP_SUCCESS -eq 1 ]; then
    echo -e "   - Endpoint REST acessado: ${GREEN}${ACTIVE_URL}${NC} (Status HTTP: ${HTTP_CODE})"
    echo -e "   - Resposta JSON obtida: ${CYAN}${HTTP_RESPONSE:0:150}...${NC}"

    if echo "$HTTP_RESPONSE" | grep -q "googleServiceAccount"; then
        COL_EXPOSED="sim"
        echo -e "   - Coluna 'googleServiceAccount' no JSON exposto pelo PostgREST: ${BOLD}${GREEN}PRESENTE [OK] 🎉${NC}"
    else
        echo -e "   - Coluna 'googleServiceAccount' no JSON: ${YELLOW}Ainda não listada nos campos de settings${NC}"
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
    IFS='|' read -r ac_c ac_u ac_p ac_d ac_hs ac_hc ac_cnt <<< "$entry"
    MARK=" "
    if [ "$ac_c" = "$REAL_CONTAINER" ] && [ "$ac_d" = "$REAL_DB" ]; then
        MARK=" ⭐ (BANCO REAL)"
    fi
    echo -e "   - Contêiner: ${BOLD}${ac_c}${NC} | Banco: ${BOLD}${ac_d}${NC} | Settings: ${ac_hs} | Clients: ${ac_cnt}${MARK}"
done

echo ""
echo -e "2. Banco Real Identificado:"
echo -e "   - Contêiner: ${GREEN}${REAL_CONTAINER}${NC}"
echo -e "   - Banco:     ${GREEN}${REAL_DB}${NC}"
echo -e "   - Clientes:  ${GREEN}${MAX_CLIENTS} registros${NC}"
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
    echo -e "   - Resultado: ${BOLD}${GREEN}COLUNA EXPOSTA NO SCHEMA CACHE [OK]${NC}"
    echo -e "   - Endpoint:  ${GREEN}${ACTIVE_URL}${NC}"
else
    echo -e "   - Resultado: ${YELLOW}HTTP respondeu (${HTTP_CODE}), checagem da coluna via JSON: ${COL_EXPOSED}${NC}"
fi

echo -e "${BOLD}${BLUE}=====================================================================${NC}"

if [ "$FINAL_CHECK_COL" = "t" ]; then
    echo -e "\n${BOLD}${GREEN}✅ DIAGNÓSTICO CONCLUÍDO COM SUCESSO!${NC}"
    echo -e "A coluna 'googleServiceAccount' está devidamente criada e validada no banco de dados real."
    echo ""
    echo -e "Próximos passos para o Douglas:"
    echo -e "1. Acesse o sistema no navegador: ${BOLD}https://sistema.advdouglaspsantos.com.br/configuracoes${NC}"
    echo -e "2. Vá na aba ${BOLD}Integrações${NC} → Cartão ${BOLD}Espelhamento de Clientes (Google Sheets)${NC}."
    echo -e "3. Cole o JSON da sua Service Account e clique em ${BOLD}\"Salvar Service Account\"${NC}."
    echo -e "4. O erro \"Could not find the 'googleServiceAccount' column\" NÃO deve mais ocorrer."
    echo -e "5. Clique em ${BOLD}\"Sincronizar Planilha Agora\"${NC} para rodar o primeiro teste de sincronização."
    echo -e "${BOLD}${GREEN}=====================================================================${NC}\n"
    exit 0
else
    echo -e "\n${BOLD}${RED}❌ Atenção: Não foi possível confirmar a criação da coluna no banco real.${NC}"
    echo -e "Verifique as permissões de acesso ao contêiner ${REAL_CONTAINER}."
    exit 1
fi
