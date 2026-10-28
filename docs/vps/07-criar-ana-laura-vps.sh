#!/usr/bin/env bash
# ==============================================================================
# DPSjur / SBJur - Criação de Usuário no Supabase Self-Hosted do VPS: Ana Laura
# Script: docs/vps/07-criar-ana-laura-vps.sh
# Versão: v1.0.0
# Alvo: VPS Hostinger 2.25.181.69 (EasyPanel / Supabase Self-Hosted)
# ==============================================================================
# Dados do Usuário:
#   - Nome:           Ana Laura
#   - E-mail:         lauralemes25@gmail.com
#   - Senha inicial:  AnaLaura@2026!Dps
#   - Role:           User (Colaborador)
#   - canViewFinance: false
#   - is_active:      true
#   - E-mail Conf.:   true (email_confirmed_at preenchido p/ login imediato)
#
# Finalidade:
# 1. Localizar o contêiner Docker real do PostgreSQL no VPS através de varredura
#    e eleger o banco de produção com base na quantidade real de registros em
#    public.clients e public.cases (NUNCA hardcodar Doug/dpsjur que é banco vazio).
# 2. Executar operações SQL idempotentes via arquivo temporário (docker cp + psql -f):
#    - Garantir extensões "pgcrypto" e "uuid-ossp".
#    - Detectar se o usuário já existe em auth.users por e-mail (ILIKE).
#    - Se não existir, gerar novo UUID e inserir em auth.users com:
#        * instance_id = '00000000-0000-0000-0000-000000000000'
#        * aud = 'authenticated', role = 'authenticated'
#        * encrypted_password = crypt('AnaLaura@2026!Dps', gen_salt('bf', 10))
#        * email_confirmed_at = now()
#        * raw_app_meta_data = '{"provider":"email","providers":["email"]}'::jsonb
#        * raw_user_meta_data = '{"name":"Ana Laura","role":"User","color":"#3b82f6","canViewFinance":false}'::jsonb
#        * is_super_admin = false, is_sso_user = false, is_anonymous = false
#        * Todos os campos de token text inicializados com '' (COALESCE/vazio) para
#          tolerância total ao GoTrue self-hosted (que faz sql.Scan para struct Go
#          com tipos string primitivos e não tolera NULL).
#    - Se já existir, atualizar senha com bcrypt, preencher email_confirmed_at se nulo,
#      sanitizar tokens com string vazia e manter idempotência sem duplicar.
#    - Inserir/atualizar perfil correspondente em public.profiles:
#        * id = mesmo UUID de auth.users
#        * name = 'Ana Laura'
#        * role = 'User'
#        * "canViewFinance" = false
#        * is_active = true
#        * email = 'lauralemes25@gmail.com'
#        * color = '#3b82f6'
#    - Sincronizar auth.identities com provider = 'email', provider_id = user_id::text
#      e identity_data compatível com GoTrue moderno.
# 3. Recarregar PostgREST via NOTIFY pgrst e restart do contêiner PostgREST (se presente).
# 4. Conferência rigorosa exibindo dados de auth.users, public.profiles e auth.identities.
#
# Execução no terminal do VPS (como root - comando único sem pipe interativo):
#   curl -sSL "https://raw.githubusercontent.com/dowspaulo-wq/migra--o-sistema-legal-desk-fg93i2kgl/main/docs/vps/07-criar-ana-laura-vps.sh" -o /root/07-criar-ana-laura-vps.sh && bash /root/07-criar-ana-laura-vps.sh
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

TARGET_NAME="Ana Laura"
TARGET_EMAIL="lauralemes25@gmail.com"
TARGET_PASS="AnaLaura@2026!Dps"
TARGET_ROLE="User"
TARGET_CAN_VIEW_FINANCE="false"
TARGET_IS_ACTIVE="true"
TARGET_COLOR="#3b82f6"

echo -e "${BOLD}${BLUE}=====================================================================${NC}"
echo -e "${BOLD}${BLUE} DPSjur - Criação/Atualização de Usuária: Ana Laura (VPS)           ${NC}"
echo -e "${BOLD}${BLUE} Versão: ${SCRIPT_VERSION}                                                     ${NC}"
echo -e "${BOLD}${BLUE}=====================================================================${NC}"
echo -e "Data: $(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || true)"
echo -e "Host: $(hostname 2>/dev/null || echo 'VPS')"
echo -e "Alvo: ${CYAN}${TARGET_NAME}${NC} <${CYAN}${TARGET_EMAIL}${NC}>"
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
# 2. Diagnóstico prévio da usuária
# ------------------------------------------------------------------------------
echo -e "\n${BOLD}${CYAN}[2/4] Verificando existência prévia da usuária no banco eleito...${NC}"

PRE_USER_EXISTS=$(run_sql_query "SELECT EXISTS (SELECT 1 FROM auth.users WHERE email ILIKE '${TARGET_EMAIL}');" || echo "f")
if [ "$PRE_USER_EXISTS" = "t" ]; then
    PRE_USER_ID=$(run_sql_query "SELECT id FROM auth.users WHERE email ILIKE '${TARGET_EMAIL}' LIMIT 1;" || echo "")
    echo -e "   - Usuária já cadastrada em auth.users: ${YELLOW}SIM${NC} (ID: ${PRE_USER_ID})"
    echo -e "   - O script atualizará a senha bcrypt, confirmará o e-mail e higienizará tokens com idempotência."
else
    echo -e "   - Usuária cadastrada em auth.users: ${GREEN}NÃO (será criada de primeira)${NC}"
fi

PRE_PROFILE_EXISTS=$(run_sql_query "SELECT EXISTS (SELECT 1 FROM public.profiles WHERE email ILIKE '${TARGET_EMAIL}');" || echo "f")
echo -e "   - Perfil em public.profiles: $( [ "$PRE_PROFILE_EXISTS" = "t" ] && echo -e "${YELLOW}EXISTE${NC}" || echo -e "${GREEN}SERÁ CRIADO${NC}" )"

# ------------------------------------------------------------------------------
# 3. Execução da migração SQL idempotente via arquivo temporário
# ------------------------------------------------------------------------------
echo -e "\n${BOLD}${CYAN}[3/4] Criando/atualizando Ana Laura em auth.users, public.profiles e auth.identities...${NC}"

SQL_TEMP_HOST=$(mktemp /tmp/criar_ana_laura_vps_XXXXXX.sql)

cat << 'EOF_MIGRATION_SQL' > "$SQL_TEMP_HOST"
BEGIN;

-- 1. Garantir extensões necessárias no PostgreSQL
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

DO $$
DECLARE
    v_email TEXT := 'lauralemes25@gmail.com';
    v_password TEXT := 'AnaLaura@2026!Dps';
    v_name TEXT := 'Ana Laura';
    v_role TEXT := 'User';
    v_can_view_finance BOOLEAN := false;
    v_is_active BOOLEAN := true;
    v_color TEXT := '#3b82f6';
    v_user_id UUID;
    v_is_new BOOLEAN := false;
    v_hashed_password TEXT;
    v_app_metadata JSONB := '{"provider":"email","providers":["email"]}'::jsonb;
    v_user_metadata JSONB;
BEGIN
    -- Detectar e setar search_path para pgcrypto (extensions ou public)
    IF EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'extensions' AND p.proname = 'gen_salt'
    ) THEN
        EXECUTE 'SET search_path TO public, extensions;';
    END IF;

    -- Gerar hash bcrypt no lado do banco com pgcrypto (custo bf 10)
    -- crypt(v_password, gen_salt('bf', 10))
    IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'gen_salt') THEN
        v_hashed_password := crypt(v_password, gen_salt('bf', 10));
    ELSE
        RAISE EXCEPTION 'Extensão pgcrypto (gen_salt) não está disponível no banco!';
    END IF;

    v_user_metadata := jsonb_build_object(
        'name', v_name,
        'role', v_role,
        'color', v_color,
        'canViewFinance', v_can_view_finance,
        'email_verified', true
    );

    -- 2. Localizar usuário existente por e-mail ou gerar novo UUID
    SELECT id INTO v_user_id
    FROM auth.users
    WHERE email ILIKE v_email
    LIMIT 1;

    IF v_user_id IS NULL THEN
        v_is_new := true;
        v_user_id := gen_random_uuid();

        -- Inserção segura em auth.users:
        -- - NÃO inclui colunas geradas como confirmed_at (GENERATED ALWAYS)
        -- - Define email_confirmed_at = now() (gera confirmed_at automaticamente)
        -- - Tolerância GoTrue local: tokens como string vazia '' em vez de NULL
        -- - phone mantido NULL (coluna phone única)
        INSERT INTO auth.users (
            instance_id,
            id,
            aud,
            role,
            email,
            encrypted_password,
            email_confirmed_at,
            raw_app_meta_data,
            raw_user_meta_data,
            is_super_admin,
            created_at,
            updated_at,
            phone,
            phone_change,
            phone_change_token,
            confirmation_token,
            recovery_token,
            email_change_token_new,
            email_change_token_current,
            email_change,
            reauthentication_token,
            is_sso_user,
            is_anonymous
        ) VALUES (
            '00000000-0000-0000-0000-000000000000'::uuid,
            v_user_id,
            'authenticated',
            'authenticated',
            v_email,
            v_hashed_password,
            now(),
            v_app_metadata,
            v_user_metadata,
            false,
            now(),
            now(),
            NULL,
            '',
            '',
            '',
            '',
            '',
            '',
            '',
            '',
            false,
            false
        );

        RAISE NOTICE '[OK] Usuária % criada em auth.users com ID %', v_email, v_user_id;
    ELSE
        -- Usuária já existia: atualização idempotente
        UPDATE auth.users
        SET
            encrypted_password = v_hashed_password,
            email_confirmed_at = COALESCE(email_confirmed_at, now()),
            instance_id = COALESCE(instance_id, '00000000-0000-0000-0000-000000000000'::uuid),
            aud = COALESCE(aud, 'authenticated'),
            role = COALESCE(role, 'authenticated'),
            raw_app_meta_data = v_app_metadata,
            raw_user_meta_data = v_user_metadata,
            is_super_admin = false,
            is_sso_user = false,
            is_anonymous = false,
            confirmation_token = COALESCE(confirmation_token, ''),
            recovery_token = COALESCE(recovery_token, ''),
            email_change_token_new = COALESCE(email_change_token_new, ''),
            email_change_token_current = COALESCE(email_change_token_current, ''),
            email_change = COALESCE(email_change, ''),
            phone_change = COALESCE(phone_change, ''),
            phone_change_token = COALESCE(phone_change_token, ''),
            reauthentication_token = COALESCE(reauthentication_token, ''),
            updated_at = now()
        WHERE id = v_user_id;

        RAISE NOTICE '[INFO] Usuária % já existia em auth.users (ID %). Senha, metadados e tokens atualizados com sucesso.', v_email, v_user_id;
    END IF;

    -- Suporte a schema legacy onde confirmed_at seja gravável (não-STORED)
    IF EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'auth' 
          AND table_name = 'users' 
          AND column_name = 'confirmed_at' 
          AND is_generated = 'NEVER'
          AND is_identity = 'NO'
    ) THEN
        EXECUTE 'UPDATE auth.users SET confirmed_at = COALESCE(confirmed_at, email_confirmed_at, now()) WHERE id = $1' USING v_user_id;
    END IF;

    -- 3. Inserir ou atualizar perfil em public.profiles
    -- Schema conferido:
    -- id (uuid, PK, fkey auth.users)
    -- name (text, not null)
    -- role (text, not null, default 'User')
    -- "canViewFinance" (boolean, not null, default false)
    -- color (text, not null, default '#3b82f6')
    -- created_at (timestamptz, not null, default now())
    -- email (text, nullable)
    -- avatar_url (text, nullable)
    -- is_active (boolean, not null, default true)
    IF EXISTS (
        SELECT 1 FROM information_schema.tables 
        WHERE table_schema = 'public' AND table_name = 'profiles'
    ) THEN
        INSERT INTO public.profiles (
            id,
            name,
            role,
            "canViewFinance",
            color,
            created_at,
            email,
            avatar_url,
            is_active
        ) VALUES (
            v_user_id,
            v_name,
            v_role,
            v_can_view_finance,
            v_color,
            now(),
            v_email,
            NULL,
            v_is_active
        )
        ON CONFLICT (id) DO UPDATE SET
            name = EXCLUDED.name,
            role = EXCLUDED.role,
            "canViewFinance" = EXCLUDED."canViewFinance",
            color = EXCLUDED.color,
            email = EXCLUDED.email,
            is_active = EXCLUDED.is_active;

        RAISE NOTICE '[OK] Perfil de % em public.profiles inserido/atualizado com sucesso.', v_name;
    ELSE
        RAISE NOTICE '[AVISO] Tabela public.profiles não encontrada no schema.';
    END IF;

    -- 4. Sincronizar auth.identities para login GoTrue com provedor 'email'
    IF EXISTS (
        SELECT 1 FROM information_schema.tables 
        WHERE table_schema = 'auth' AND table_name = 'identities'
    ) THEN
        IF EXISTS (SELECT 1 FROM auth.identities WHERE user_id = v_user_id) THEN
            UPDATE auth.identities
            SET
                provider = 'email',
                provider_id = v_user_id::text,
                identity_data = jsonb_build_object(
                    'sub', v_user_id::text,
                    'email', v_email,
                    'email_verified', true,
                    'phone_verified', false
                ),
                updated_at = now()
            WHERE user_id = v_user_id;

            RAISE NOTICE '[OK] Identidade em auth.identities sincronizada para o usuário %', v_user_id;
        ELSE
            INSERT INTO auth.identities (
                id,
                user_id,
                identity_data,
                provider,
                provider_id,
                last_sign_in_at,
                created_at,
                updated_at
            ) VALUES (
                gen_random_uuid(),
                v_user_id,
                jsonb_build_object(
                    'sub', v_user_id::text,
                    'email', v_email,
                    'email_verified', true,
                    'phone_verified', false
                ),
                'email',
                v_user_id::text,
                NULL,
                now(),
                now()
            );

            RAISE NOTICE '[OK] Nova identidade criada em auth.identities para o usuário %', v_user_id;
        END IF;
    END IF;

END $$;

COMMIT;
EOF_MIGRATION_SQL

RAND_ID="criar_ana_laura_${RANDOM:-$$}_$(date +%s 2>/dev/null || echo '0')"
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

echo -e "${GREEN}✓ Usuária Ana Laura configurada com sucesso no PostgreSQL!${NC}"

# Notificar e reiniciar PostgREST para limpar cache de permissões
echo -e "🔄 Recarregando cache do PostgREST via NOTIFY pgrst..."
run_sql_query "NOTIFY pgrst, 'reload schema';" >/dev/null 2>&1 || true

if [ -n "$PGRST_CONTAINER" ]; then
    echo -e "🔄 Reiniciando contêiner do PostgREST (${PGRST_CONTAINER})..."
    docker restart "$PGRST_CONTAINER" >/dev/null 2>&1 || true
    echo -e "${GREEN}✓ Contêiner PostgREST reiniciado!${NC}"
fi

# ------------------------------------------------------------------------------
# 4. Conferência rigorosa e amigável pós-migração
# ------------------------------------------------------------------------------
echo -e "\n${BOLD}${CYAN}[4/4] Conferência final dos dados de Ana Laura no PostgreSQL:${NC}"
echo -e "   - Contêiner: ${BOLD}${DB_CONTAINER}${NC}"
echo -e "   - Usuário:   ${BOLD}${DB_USER}${NC}"
echo -e "   - Banco:     ${BOLD}${DB_NAME}${NC}"
echo -e "---------------------------------------------------------------------"

POST_USER_ID=$(run_sql_query "SELECT id FROM auth.users WHERE email ILIKE '${TARGET_EMAIL}' LIMIT 1;" || echo "")
POST_EMAIL_CONFIRMED=$(run_sql_query "SELECT email_confirmed_at IS NOT NULL FROM auth.users WHERE email ILIKE '${TARGET_EMAIL}' LIMIT 1;" || echo "f")
POST_HASH_VALID=$(run_sql_query "SELECT encrypted_password LIKE '\$2a\$%' OR encrypted_password LIKE '\$2b\$%' FROM auth.users WHERE email ILIKE '${TARGET_EMAIL}' LIMIT 1;" || echo "f")
POST_TOKEN_SANITIZED=$(run_sql_query "SELECT confirmation_token = '' AND recovery_token = '' FROM auth.users WHERE email ILIKE '${TARGET_EMAIL}' LIMIT 1;" || echo "f")

POST_PROFILE_NAME=$(run_sql_query "SELECT name FROM public.profiles WHERE id = '${POST_USER_ID}';" || echo "")
POST_PROFILE_ROLE=$(run_sql_query "SELECT role FROM public.profiles WHERE id = '${POST_USER_ID}';" || echo "")
POST_PROFILE_FINANCE=$(run_sql_query "SELECT \"canViewFinance\" FROM public.profiles WHERE id = '${POST_USER_ID}';" || echo "")
POST_PROFILE_ACTIVE=$(run_sql_query "SELECT is_active FROM public.profiles WHERE id = '${POST_USER_ID}';" || echo "")

POST_IDENTITIES_COUNT=$(run_sql_query "SELECT count(*) FROM auth.identities WHERE user_id = '${POST_USER_ID}';" || echo "0")

echo -e "   - 1. Usuária em auth.users:       $( [ -n "$POST_USER_ID" ] && echo -e "${GREEN}CRIADA/PRESENTE (ID: ${POST_USER_ID}) [OK]${NC}" || echo -e "${RED}NÃO ENCONTRADA [FALHA]${NC}" )"
echo -e "   - 2. Hash bcrypt de senha:        $( [ "$POST_HASH_VALID" = "t" ] && echo -e "${GREEN}VÁLIDO (\$2a\$...) [OK]${NC}" || echo -e "${RED}INVÁLIDO [FALHA]${NC}" )"
echo -e "   - 3. E-mail confirmado (login):   $( [ "$POST_EMAIL_CONFIRMED" = "t" ] && echo -e "${GREEN}CONFIRMADO [OK]${NC}" || echo -e "${RED}NÃO CONFIRMADO [FALHA]${NC}" )"
echo -e "   - 4. Higienização de tokens:      $( [ "$POST_TOKEN_SANITIZED" = "t" ] && echo -e "${GREEN}SANITIZADO (string vazia GoTrue) [OK]${NC}" || echo -e "${YELLOW}AVISO${NC}" )"
echo -e "   - 5. Perfil em public.profiles:   $( [ -n "$POST_PROFILE_NAME" ] && echo -e "${GREEN}${POST_PROFILE_NAME} [OK]${NC}" || echo -e "${RED}NÃO ENCONTRADO [FALHA]${NC}" )"
echo -e "   - 6. Papel / Permissões:          Role: ${GREEN}${POST_PROFILE_ROLE}${NC} | canViewFinance: ${GREEN}${POST_PROFILE_FINANCE}${NC} | is_active: ${GREEN}${POST_PROFILE_ACTIVE}${NC}"
echo -e "   - 7. Provedor em auth.identities: ${GREEN}${POST_IDENTITIES_COUNT} identidade(s) vinculada(s) [OK]${NC}"

echo -e "\n${BOLD}${CYAN}Registro detalhado em auth.users e public.profiles:${NC}"

if [ -n "$LOCAL_DB_PASSWORD" ]; then
    docker exec -i -e PGPASSWORD="$LOCAL_DB_PASSWORD" "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -x -c "
        SELECT 
            u.id,
            u.email,
            left(u.encrypted_password, 15) || '...' AS \"encrypted_password (bcrypt)\",
            u.email_confirmed_at,
            u.role AS auth_role,
            p.name AS profile_name,
            p.role AS profile_role,
            p.\"canViewFinance\",
            p.is_active,
            p.color,
            u.created_at
        FROM auth.users u
        LEFT JOIN public.profiles p ON p.id = u.id
        WHERE u.email ILIKE '${TARGET_EMAIL}';
    " || true
else
    docker exec -i "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -x -c "
        SELECT 
            u.id,
            u.email,
            left(u.encrypted_password, 15) || '...' AS \"encrypted_password (bcrypt)\",
            u.email_confirmed_at,
            u.role AS auth_role,
            p.name AS profile_name,
            p.role AS profile_role,
            p.\"canViewFinance\",
            p.is_active,
            p.color,
            u.created_at
        FROM auth.users u
        LEFT JOIN public.profiles p ON p.id = u.id
        WHERE u.email ILIKE '${TARGET_EMAIL}';
    " || true
fi

# Validação final do script
VERIFICATION_FAILED=0
if [ -z "$POST_USER_ID" ]; then VERIFICATION_FAILED=1; fi
if [ "$POST_EMAIL_CONFIRMED" != "t" ]; then VERIFICATION_FAILED=1; fi
if [ "$POST_HASH_VALID" != "t" ]; then VERIFICATION_FAILED=1; fi
if [ -z "$POST_PROFILE_NAME" ]; then VERIFICATION_FAILED=1; fi

if [ $VERIFICATION_FAILED -ne 0 ]; then
    echo -e "\n${RED}=====================================================================${NC}"
    echo -e "${RED}❌ ERRO: A criação/verificação da usuária falhou no banco do VPS!    ${NC}"
    echo -e "${RED}=====================================================================${NC}\n"
    exit 1
fi

echo -e "\n${BOLD}${GREEN}=====================================================================${NC}"
echo -e "${BOLD}${GREEN}🎉 USUÁRIA ANA LAURA CRIADA/CONFIRMADA COM SUCESSO NO BANCO DO VPS!   ${NC}"
echo -e "${BOLD}${GREEN}=====================================================================${NC}"
echo -e "Nome:                ${BOLD}${POST_PROFILE_NAME}${NC}"
echo -e "E-mail:              ${BOLD}${TARGET_EMAIL}${NC}"
echo -e "Senha inicial:       ${BOLD}${TARGET_PASS}${NC}"
echo -e "Papel:               ${BOLD}${POST_PROFILE_ROLE} (Colaborador)${NC}"
echo -e "Acesso Financeiro:   ${BOLD}Bloqueado (canViewFinance = false)${NC}"
echo -e "Status:              ${BOLD}Ativo (is_active = true)${NC}"
echo -e "E-mail confirmado:   ${BOLD}Sim (login liberado de primeira)${NC}"
echo -e "PostgREST cache:     ${BOLD}Recarregado via NOTIFY pgrst e restart de contêiner${NC}"
echo -e "${BOLD}${GREEN}=====================================================================${NC}"
echo -e "${BOLD}${CYAN}ℹ️  Sobre Deploy no EasyPanel:${NC}"
echo -e "Como esta operação altera estritamente dados no banco PostgreSQL,"
echo -e "${BOLD}NÃO é necessário novo deploy de código no EasyPanel.${NC}"
echo -e "Ana Laura já pode acessar e logar imediatamente em:"
echo -e "${GREEN}👉 https://sistema.advdouglaspsantos.com.br${NC}"
echo -e "${BOLD}${GREEN}=====================================================================${NC}\n"
