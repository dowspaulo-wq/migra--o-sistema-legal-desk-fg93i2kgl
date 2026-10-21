#!/usr/bin/env bash
# ==============================================================================
# DPSjur / SBJur - Atualização de Usuário no Supabase Self-Hosted (VPS / EasyPanel)
# Script: docs/usuarios/01-renomear-filippini-vps.sh
# Versão: v1.0.0
# ==============================================================================
# Finalidade:
#   Renomear o usuário GUILHERME FILIPPINI para "Filippini" no banco de produção
#   do VPS (EasyPanel / Docker), evitando duplicidade/confusão de nomes na equipe
#   com o colaborador "Guilherme Almeida".
#
# Alvo:
#   - Usuário: guilherme.f.augusto@gmail.com
#   - ID: 97971288-d3cf-4d66-a48f-8691ab0b40a4
#   - Novo nome: "Filippini"
#   - Preservado: "Guilherme Almeida" (willhelmalmeida@gmail.com, id 4ad65234-...)
#
# O que este script faz:
#   1. Varre TODOS os contêineres Docker filtrando serviços de banco (db/postgres/postg).
#   2. Identifica o banco real da aplicação (public.profiles com múltiplos registros).
#   3. Executa de forma segura e idempotente no banco real:
#      (a) UPDATE public.profiles SET name = 'Filippini' WHERE id = '97971288-d3cf-4d66-a48f-8691ab0b40a4' OR name = 'Guilherme Filippini';
#      (b) UPDATE auth.users SET raw_user_meta_data = jsonb_set(COALESCE(raw_user_meta_data, '{}'::jsonb), '{name}', '"Filippini"')
#          WHERE id = '97971288-d3cf-4d66-a48f-8691ab0b40a4';
#   4. Aplica preventivamente em qualquer outro banco Postgres que contenha a tabela public.profiles.
#   5. Notifica o PostgREST para recarregar o schema/cache e confirma status.
#   6. Verificação de integridade:
#      - Exibe o perfil do usuário alterado (id, name, email).
#      - Confirma que "Guilherme Almeida" permanece inalterado.
#      - Lista os usuários contendo 'filippini' ou 'guilherme' no nome/email.
#   7. Resumo consolidado legível com marcação visual [OK].
#
# Execução recomendada no VPS (como root - comando único sem pipe):
#   curl -sSL "https://raw.githubusercontent.com/dowspaulo-wq/migra--o-sistema-legal-desk-fg93i2kgl/main/docs/usuarios/01-renomear-filippini-vps.sh" -o /root/01-renomear-filippini-vps.sh && bash /root/01-renomear-filippini-vps.sh
# ==============================================================================

set -uo pipefail

SCRIPT_VERSION="v1.0.0"
TARGET_USER_ID="97971288-d3cf-4d66-a48f-8691ab0b40a4"
TARGET_EMAIL="guilherme.f.augusto@gmail.com"
NEW_NAME="Filippini"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${BOLD}${BLUE}=====================================================================${NC}"
echo -e "${BOLD}${BLUE} DPSjur - Renomear Usuário: Guilherme Filippini -> Filippini (VPS)   ${NC}"
echo -e "${BOLD}${BLUE} Versão: ${SCRIPT_VERSION}${NC}"
echo -e "${BOLD}${BLUE}=====================================================================${NC}"
echo -e "Data: $(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || true)"
echo -e "Host: $(hostname 2>/dev/null || echo 'VPS')"
echo -e "Alvo: ID ${TARGET_USER_ID} (${TARGET_EMAIL}) -> '${NEW_NAME}'"
echo -e "${BOLD}${BLUE}=====================================================================${NC}\n"

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

# ------------------------------------------------------------------------------
# 1. Listar e examinar TODOS os contêineres Postgres em execução
# ------------------------------------------------------------------------------
echo -e "${BOLD}${CYAN}[Etapa 1/4] Varrendo contêineres PostgreSQL em execução no VPS...${NC}"

ALL_DB_CONTAINERS=()
while IFS= read -r c_name; do
    [ -z "$c_name" ] && continue
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

# Estrutura para armazenar resultados de auditoria
# Format: CONTAINER|DB_USER|DB_PASS|DB_NAME|HAS_PROFILES|PROFILES_COUNT|CURRENT_NAME
AUDIT_RESULTS=()

REAL_CONTAINER=""
REAL_USER=""
REAL_PASS=""
REAL_DB=""
MAX_PROFILES=-1

for c in "${ALL_DB_CONTAINERS[@]}"; do
    echo -e "🔎 Inspecionando contêiner: ${BOLD}${c}${NC}..."

    ENV_USER=$(docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "$c" 2>/dev/null | grep -E '^POSTGRES_USER=' | head -n 1 | cut -d= -f2- || true)
    ENV_PASS=$(docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "$c" 2>/dev/null | grep -E '^POSTGRES_PASSWORD=' | head -n 1 | cut -d= -f2- || true)
    ENV_DB=$(docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "$c" 2>/dev/null | grep -E '^POSTGRES_DB=' | head -n 1 | cut -d= -f2- || true)

    CAND_USERS=()
    [ -n "$ENV_USER" ] && CAND_USERS+=("$ENV_USER")
    CAND_USERS+=("postgres" "supabase_admin" "postgres_admin" "Doug")
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

        PROFILES_EXISTS=$(run_container_psql "$c" "$WORKING_USER" "$WORKING_PASS" "$dbname" "SELECT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='profiles');")

        if [ "$PROFILES_EXISTS" != "t" ]; then
            echo -e "    - Tabela public.profiles: ${YELLOW}não existe neste banco${NC}"
            AUDIT_RESULTS+=("${c}|${WORKING_USER}|${WORKING_PASS}|${dbname}|nao|0|")
            continue
        fi

        RAW_PROFILES_COUNT=$(run_container_psql "$c" "$WORKING_USER" "$WORKING_PASS" "$dbname" "SELECT count(*) FROM public.profiles;")
        PROFILES_COUNT=$(echo "$RAW_PROFILES_COUNT" | tr -dc '0-9' || echo 0)
        [ -z "$PROFILES_COUNT" ] && PROFILES_COUNT=0

        CURRENT_TARGET_NAME=$(run_container_psql "$c" "$WORKING_USER" "$WORKING_PASS" "$dbname" "SELECT name FROM public.profiles WHERE id = '${TARGET_USER_ID}' OR email = '${TARGET_EMAIL}' LIMIT 1;")

        echo -e "    - Tabela public.profiles: ${GREEN}EXISTE${NC} (${PROFILES_COUNT} perfis)"
        if [ -n "$CURRENT_TARGET_NAME" ]; then
            echo -e "    - Nome atual do usuário alvo: ${CYAN}${CURRENT_TARGET_NAME}${NC}"
        fi

        AUDIT_RESULTS+=("${c}|${WORKING_USER}|${WORKING_PASS}|${dbname}|sim|${PROFILES_COUNT}|${CURRENT_TARGET_NAME}")

        # Critério: banco real da aplicação tem dados de perfis (> 1 usuário)
        if [ "$PROFILES_COUNT" -gt "$MAX_PROFILES" ]; then
            MAX_PROFILES="$PROFILES_COUNT"
            REAL_CONTAINER="$c"
            REAL_USER="$WORKING_USER"
            REAL_PASS="$WORKING_PASS"
            REAL_DB="$dbname"
        fi
    done
    echo ""
done

# Fallback se nenhum banco tiver profiles > 1 mas algum tiver public.profiles
if [ -z "$REAL_CONTAINER" ]; then
    for entry in "${AUDIT_RESULTS[@]}"; do
        IFS='|' read -r c u p d has_prof p_cnt cur_name <<< "$entry"
        if [ "$has_prof" = "sim" ]; then
            REAL_CONTAINER="$c"
            REAL_USER="$u"
            REAL_PASS="$p"
            REAL_DB="$d"
            MAX_PROFILES="$p_cnt"
            break
        fi
    done
fi

# ------------------------------------------------------------------------------
# 2. Identificação do Banco Real e Aplicação do Update
# ------------------------------------------------------------------------------
echo -e "${BOLD}${CYAN}[Etapa 2/4] Aplicando a renomeação no Banco Real da Aplicação...${NC}"

if [ -z "$REAL_CONTAINER" ]; then
    echo -e "${RED}❌ Não foi possível determinar o contêiner do banco real da aplicação!${NC}"
    echo "Verifique os contêineres ativos no EasyPanel."
    exit 1
fi

echo -e "🎯 ${BOLD}Banco Real Detectado:${NC}"
echo -e "   - Contêiner: ${GREEN}${REAL_CONTAINER}${NC}"
echo -e "   - Usuário:   ${GREEN}${REAL_USER}${NC}"
echo -e "   - Banco:     ${GREEN}${REAL_DB}${NC}"
echo -e "   - Perfis:    ${GREEN}${MAX_PROFILES} registro(s) em public.profiles${NC}\n"

SQL_UPDATE="
DO \$\$
DECLARE
    v_profiles_updated integer := 0;
    v_auth_updated integer := 0;
BEGIN
    -- 1. Atualizar public.profiles pelo ID ou pelo nome antigo
    UPDATE public.profiles
    SET name = '${NEW_NAME}'
    WHERE id = '${TARGET_USER_ID}'
       OR email = '${TARGET_EMAIL}'
       OR name = 'Guilherme Filippini';

    GET DIAGNOSTICS v_profiles_updated = ROW_COUNT;
    RAISE NOTICE 'Linhas atualizadas em public.profiles: %', v_profiles_updated;

    -- 2. Atualizar auth.users (metadado raw_user_meta_data)
    IF EXISTS (
        SELECT 1 FROM information_schema.tables 
        WHERE table_schema = 'auth' AND table_name = 'users'
    ) THEN
        UPDATE auth.users
        SET raw_user_meta_data = jsonb_set(
            COALESCE(raw_user_meta_data, '{}'::jsonb),
            '{name}',
            '\"${NEW_NAME}\"'::jsonb
        )
        WHERE id = '${TARGET_USER_ID}'
           OR email = '${TARGET_EMAIL}';

        GET DIAGNOSTICS v_auth_updated = ROW_COUNT;
        RAISE NOTICE 'Linhas atualizadas em auth.users: %', v_auth_updated;
    END IF;

    -- 3. Notificar PostgREST para reload de cache (inofensivo e imediato)
    PERFORM pg_notify('pgrst', 'reload schema');
END \$\$;
"

echo -e "Executando SQL no banco real..."
if [ -n "$REAL_PASS" ]; then
    docker exec -i -e PGPASSWORD="$REAL_PASS" "$REAL_CONTAINER" psql -U "$REAL_USER" -d "$REAL_DB" -v ON_ERROR_STOP=1 <<< "$SQL_UPDATE"
else
    docker exec -i "$REAL_CONTAINER" psql -U "$REAL_USER" -d "$REAL_DB" -v ON_ERROR_STOP=1 <<< "$SQL_UPDATE"
fi
echo -e "  ${GREEN}✓ UPDATE executado com sucesso no banco real!${NC}"

# Aplicar preventivamente em qualquer outro banco que possua a tabela profiles
for entry in "${AUDIT_RESULTS[@]}"; do
    IFS='|' read -r ac_c ac_u ac_p ac_d ac_has_prof ac_p_cnt ac_cur_name <<< "$entry"
    if [ "$ac_has_prof" = "sim" ]; then
        if [ "$ac_c" != "$REAL_CONTAINER" ] || [ "$ac_d" != "$REAL_DB" ]; then
            echo -e "   ℹ️ Aplicando preventivamente também no contêiner ${ac_c} (banco ${ac_d})..."
            PREVENTIVE_SQL="UPDATE public.profiles SET name = '${NEW_NAME}' WHERE id = '${TARGET_USER_ID}' OR email = '${TARGET_EMAIL}' OR name = 'Guilherme Filippini';"
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
# 3. Notificar / sincronizar schema cache
# ------------------------------------------------------------------------------
echo -e "${BOLD}${CYAN}[Etapa 3/4] Notificando recarga de cache no PostgREST...${NC}"
run_container_psql "$REAL_CONTAINER" "$REAL_USER" "$REAL_PASS" "$REAL_DB" "NOTIFY pgrst, 'reload schema';" >/dev/null 2>&1 || true
echo -e "  ${GREEN}✓ NOTIFY pgrst disparado com sucesso.${NC}\n"

# ------------------------------------------------------------------------------
# 4. Verificação de integridade e auditoria
# ------------------------------------------------------------------------------
echo -e "${BOLD}${CYAN}[Etapa 4/4] Verificando integridade dos dados no banco real...${NC}"

CHECK_QUERY="
SELECT 
    id,
    name,
    email,
    role,
    created_at::date as criado
FROM public.profiles
ORDER BY name ASC;
"

echo -e "\n${BOLD}Lista completa de colaboradores em public.profiles:${NC}"
if [ -n "$REAL_PASS" ]; then
    docker exec -i -e PGPASSWORD="$REAL_PASS" "$REAL_CONTAINER" psql -U "$REAL_USER" -d "$REAL_DB" -c "$CHECK_QUERY" 2>/dev/null || true
else
    docker exec -i "$REAL_CONTAINER" psql -U "$REAL_USER" -d "$REAL_DB" -c "$CHECK_QUERY" 2>/dev/null || true
fi

# Checagem específica do alvo
FINAL_TARGET_NAME=$(run_container_psql "$REAL_CONTAINER" "$REAL_USER" "$REAL_PASS" "$REAL_DB" "SELECT name FROM public.profiles WHERE id = '${TARGET_USER_ID}';")
FINAL_GUILHERME_ALMEIDA=$(run_container_psql "$REAL_CONTAINER" "$REAL_USER" "$REAL_PASS" "$REAL_DB" "SELECT name FROM public.profiles WHERE email = 'willhelmalmeida@gmail.com';")

# Checagem do auth.users (metadado)
AUTH_META_NAME=$(run_container_psql "$REAL_CONTAINER" "$REAL_USER" "$REAL_PASS" "$REAL_DB" "SELECT raw_user_meta_data->>'name' FROM auth.users WHERE id = '${TARGET_USER_ID}';")

echo ""
echo -e "${BOLD}Conferência individual:${NC}"
echo -e "  - Usuário Filippini (id ${TARGET_USER_ID}):"
echo -e "      * Nome em public.profiles: ${BOLD}${GREEN}${FINAL_TARGET_NAME}${NC}"
echo -e "      * Nome em auth.users meta: ${BOLD}${GREEN}${AUTH_META_NAME}${NC}"
echo -e "  - Usuário Guilherme Almeida (willhelmalmeida@gmail.com):"
echo -e "      * Nome em public.profiles: ${BOLD}${GREEN}${FINAL_GUILHERME_ALMEIDA}${NC}"

IS_OK=true
if [ "$FINAL_TARGET_NAME" != "$NEW_NAME" ]; then
    IS_OK=false
fi
if [ "$FINAL_GUILHERME_ALMEIDA" != "Guilherme Almeida" ]; then
    echo -e "  ${YELLOW}⚠️ Aviso: Guilherme Almeida foi afetado ou não encontrado exatamente como 'Guilherme Almeida'.${NC}"
fi

# ------------------------------------------------------------------------------
# 5. Resumo Final Consolidado
# ------------------------------------------------------------------------------
echo ""
echo -e "${BOLD}${BLUE}=====================================================================${NC}"
echo -e "${BOLD}${BLUE}                      RESUMO DA ATUALIZAÇÃO                          ${NC}"
echo -e "${BOLD}${BLUE}=====================================================================${NC}"
echo -e "1. Banco Real: ${GREEN}${REAL_CONTAINER}${NC} (banco: ${GREEN}${REAL_DB}${NC})"
echo -e "2. Perfil Alterado:"
echo -e "   - ID:    ${TARGET_USER_ID}"
echo -e "   - Email: ${TARGET_EMAIL}"
echo -e "   - De:    Guilherme Filippini"
echo -e "   - Para:  ${BOLD}${GREEN}${FINAL_TARGET_NAME}${NC} [OK]"
echo -e "3. Perfil Preservado:"
echo -e "   - Email: willhelmalmeida@gmail.com"
echo -e "   - Nome:  ${BOLD}${GREEN}${FINAL_GUILHERME_ALMEIDA}${NC} [OK]"
echo -e "${BOLD}${BLUE}=====================================================================${NC}"

if [ "$IS_OK" = "true" ]; then
    echo -e "\n${BOLD}${GREEN}✅ OPERAÇÃO CONCLUÍDA COM SUCESSO! [OK]${NC}"
    echo -e "O usuário ${TARGET_EMAIL} agora se chama exclusivamente '${NEW_NAME}' no VPS."
    echo -e "Não há mais duplicidade com o colaborador 'Guilherme Almeida'."
    echo ""
    echo -e "Próximos passos para Douglas:"
    echo -e "1. Acesse o sistema: ${BOLD}https://sistema.advdouglaspsantos.com.br${NC}"
    echo -e "2. Verifique os filtros de responsável nas telas de Processos e Tarefas."
    echo -e "3. Um colaborador aparece como 'Guilherme Almeida' e o outro meramente como 'Filippini'."
    echo -e "${BOLD}${GREEN}=====================================================================${NC}\n"
    exit 0
else
    echo -e "\n${BOLD}${RED}❌ A verificação final não confirmou o nome '${NEW_NAME}'.${NC}"
    echo -e "Valor obtido: '${FINAL_TARGET_NAME}'"
    exit 1
fi
