#!/usr/bin/env bash
# ==============================================================================
# DPSjur / SBJur - Kit Pós-Migração VPS (Hostinger KVM 1 - IP 2.25.181.69)
# Script: docs/pos-migracao/11-corrigir-login-gotrue.sh
# Versão: v0.0.541
# ==============================================================================
# Execução direta no terminal do VPS:
#   bash docs/pos-migracao/11-corrigir-login-gotrue.sh ["<email>"] ["<nova_senha_opcional>"]
#
# Execução remota via curl (sem clonar o repositório):
#   curl -sSf -L -H "Accept: application/vnd.github.v3.raw" \
#     "https://api.github.com/repos/dowspaulo-wq/migra--o-sistema-legal-desk-fg93i2kgl/contents/docs/pos-migracao/11-corrigir-login-gotrue.sh?ref=main" \
#     | bash -s -- "heitorpaulodossantos@gmail.com"
#
# Se omitido o e-mail, o alvo padrão é heitorpaulodossantos@gmail.com.
# Se informada uma senha, ela é regravada em bcrypt; se omitida, o hash
# existente é mantido intacto.
#
# Por que este script é necessário?
# O GoTrue (Supabase Auth em Go) faz `sql.Scan` de todas as colunas de auth.users
# ao buscar o usuário por email. Na struct Go `models.User`, os campos de token:
#   confirmation_token, recovery_token, email_change, email_change_token_new,
#   email_change_token_current, phone_change, phone_change_token, reauthentication_token
# são mapeados para tipos `string` primitivos do Go (NÃO sql.NullString).
# Quando qualquer uma dessas colunas está com valor SQL NULL no banco, o driver
# falha com:
#   "500: Database error querying schema - error finding user: sql: Scan error:
#    converting NULL to string is unsupported"
#
# A correção consiste em:
# 1. Aplicar COALESCE para string vazia '' em todas as colunas de texto/tokens de auth.users.
# 2. Garantir instance_id = '00000000-0000-0000-0000-000000000000', aud = 'authenticated', role = 'authenticated'.
# 3. Garantir is_super_admin = false, is_sso_user = false, is_anonymous = false.
# 4. Sincronizar auth.identities com provider = 'email', provider_id = user_id e identity_data válido.
# 5. Se fornecida nova senha, atualizar encrypted_password com crypt/gen_salt('bf', 10).
# ==============================================================================

SCRIPT_VERSION="v0.0.541"
TARGET_EMAIL="${1:-${USUARIO_EMAIL:-heitorpaulodossantos@gmail.com}}"
OPTIONAL_NEW_PASSWORD="${2:-${NOVA_SENHA:-}}"

echo "====================================================================="
echo " SBJur — Correção de Incompatibilidade de Schema GoTrue (auth.users)"
echo " Versão: ${SCRIPT_VERSION}"
echo "====================================================================="
echo "Data: $(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || true)"
echo "Host: $(hostname 2>/dev/null || echo 'VPS')"
echo "Alvo: ${TARGET_EMAIL}"
if [ -n "${OPTIONAL_NEW_PASSWORD}" ]; then
    echo "Ação: Higienização de tokens + redefinição de senha"
else
    echo "Ação: Higienização de tokens (preservando o hash de senha atual)"
fi
echo "====================================================================="
echo ""

ESCAPED_EMAIL="${TARGET_EMAIL//\'/\'\'}"
ESCAPED_PASSWORD="${OPTIONAL_NEW_PASSWORD//\'/\'\'}"

# (1) Localizar contêiner PostgreSQL
echo "🔍 1. Localizando contêiner PostgreSQL..."
DB_CONTAINER="${DB_CONTAINER:-}"
if [ -z "${DB_CONTAINER}" ]; then
    DB_CONTAINER=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -E 'supa?base.*db|supa?base-db' | head -n 1 || true)
fi
if [ -z "${DB_CONTAINER}" ]; then
    DB_CONTAINER=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -E 'postgres|db' | grep -v -E 'dpsjur-web|web|frontend|traefik|redis' | head -n 1 || true)
fi

if [ -z "${DB_CONTAINER}" ]; then
    echo "❌ Erro: Não foi possível localizar o contêiner do PostgreSQL via docker ps!"
    docker ps --format 'table {{.Names}}\t{{.Status}}' 2>/dev/null || true
    exit 1
fi
echo "✅ Contêiner localizado: ${DB_CONTAINER}"
echo ""

# (2) Teste de conexão
echo "🔐 2. Testando conectividade com o banco de dados..."
if docker exec "${DB_CONTAINER}" psql -U postgres -d postgres -tAc "SELECT 1;" >/dev/null 2>&1; then
    echo "✅ Conexão direta com PostgreSQL OK!"
else
    echo "❌ Falha ao conectar ao banco de dados no contêiner '${DB_CONTAINER}'."
    exit 1
fi
echo ""

# (3) Verificar existência do usuário
echo "🔎 3. Verificando existência do usuário ${TARGET_EMAIL}..."
CHECK_COUNT=$(docker exec "${DB_CONTAINER}" psql -U postgres -d postgres -t -A -c "SELECT count(*) FROM auth.users WHERE email ILIKE '${ESCAPED_EMAIL}';" 2>&1)
rc_check=$?

if [ ${rc_check} -ne 0 ]; then
    echo "❌ Erro ao consultar o banco (rc=${rc_check}): ${CHECK_COUNT}"
    exit ${rc_check}
fi

USER_COUNT=$(echo "${CHECK_COUNT}" | grep -E '^[0-9]+$' | tr -d '[:space:]' || true)
if [ "${USER_COUNT}" != "1" ]; then
    echo "❌ Usuário NÃO encontrado em auth.users (encontrados: '${USER_COUNT}') para o email: ${TARGET_EMAIL}"
    exit 1
fi
echo "✅ Usuário encontrado no banco de dados! Prosseguindo com a correção..."
echo ""

# (4) Executar correção via docker cp + psql -f (anti-pipe drain)
echo "🚀 4. Aplicando correção estrutural e sanitização de tokens..."
echo "---------------------------------------------------------------------"

TMP_LOCAL_SQL="/tmp/sbjur_fix_tokens_$$.sql"
TMP_CONT_SQL="/tmp/sbjur_fix_tokens_$$.sql"

cat << EOSQL > "${TMP_LOCAL_SQL}"
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

DO \$\$
DECLARE
    v_target_email text := '${ESCAPED_EMAIL}';
    v_new_password text := '${ESCAPED_PASSWORD}';
    v_user_id uuid;
    v_user_email text;
    v_has_new_pass boolean := (v_new_password IS NOT NULL AND length(v_new_password) > 0);
BEGIN
    SELECT id, email INTO v_user_id, v_user_email
    FROM auth.users
    WHERE email ILIKE v_target_email
    LIMIT 1;

    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Usuário % não encontrado!', v_target_email;
    END IF;

    -- Detectar search_path para pgcrypto caso fornecida nova senha
    IF v_has_new_pass THEN
        IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'extensions' AND p.proname = 'gen_salt') THEN
            EXECUTE 'SET search_path TO public, extensions;';
        END IF;
    END IF;

    -- 1. Atualização e higienização em auth.users
    -- GoTrue exige string vazia '' (e NUNCA NULL) para os campos de tokens
    UPDATE auth.users
    SET
        encrypted_password = CASE 
            WHEN v_has_new_pass THEN crypt(v_new_password, gen_salt('bf', 10))
            ELSE encrypted_password 
        END,
        email_confirmed_at = COALESCE(email_confirmed_at, now()),
        instance_id = COALESCE(instance_id, '00000000-0000-0000-0000-000000000000'::uuid),
        aud = COALESCE(aud, 'authenticated'),
        role = COALESCE(role, 'authenticated'),
        raw_app_meta_data = COALESCE(raw_app_meta_data, '{"provider":"email","providers":["email"]}'::jsonb),
        raw_user_meta_data = COALESCE(raw_user_meta_data, '{}'::jsonb),
        is_super_admin = COALESCE(is_super_admin, false),
        is_sso_user = COALESCE(is_sso_user, false),
        is_anonymous = COALESCE(is_anonymous, false),
        -- OBRIGATÓRIO PARA GOTRUE: tokens como string vazia '' em vez de NULL
        confirmation_token = '',
        recovery_token = '',
        email_change_token_new = '',
        email_change_token_current = '',
        email_change = '',
        phone_change = '',
        phone_change_token = '',
        reauthentication_token = '',
        updated_at = now()
    WHERE id = v_user_id;

    -- 2. Também higienizar TODOS os outros usuários para evitar o mesmo erro caso algum token esteja NULL
    UPDATE auth.users
    SET
        confirmation_token = COALESCE(confirmation_token, ''),
        recovery_token = COALESCE(recovery_token, ''),
        email_change_token_new = COALESCE(email_change_token_new, ''),
        email_change_token_current = COALESCE(email_change_token_current, ''),
        email_change = COALESCE(email_change, ''),
        phone_change = COALESCE(phone_change, ''),
        phone_change_token = COALESCE(phone_change_token, ''),
        reauthentication_token = COALESCE(reauthentication_token, ''),
        instance_id = COALESCE(instance_id, '00000000-0000-0000-0000-000000000000'::uuid),
        aud = COALESCE(aud, 'authenticated'),
        role = COALESCE(role, 'authenticated'),
        is_super_admin = COALESCE(is_super_admin, false),
        is_sso_user = COALESCE(is_sso_user, false),
        is_anonymous = COALESCE(is_anonymous, false)
    WHERE confirmation_token IS NULL
       OR recovery_token IS NULL
       OR email_change_token_new IS NULL
       OR email_change_token_current IS NULL
       OR email_change IS NULL
       OR phone_change IS NULL
       OR phone_change_token IS NULL
       OR reauthentication_token IS NULL;

    -- 3. Sincronizar auth.identities
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
                    'email', v_user_email,
                    'email_verified', true,
                    'phone_verified', false
                ),
                updated_at = now()
            WHERE user_id = v_user_id;
        ELSE
            INSERT INTO auth.identities (
                id,
                user_id,
                identity_data,
                provider,
                provider_id,
                created_at,
                updated_at
            ) VALUES (
                v_user_id,
                v_user_id,
                jsonb_build_object(
                    'sub', v_user_id::text,
                    'email', v_user_email,
                    'email_verified', true,
                    'phone_verified', false
                ),
                'email',
                v_user_id::text,
                now(),
                now()
            );
        END IF;
    END IF;

    RAISE NOTICE 'Higienização de auth.users e auth.identities concluída com sucesso para %', v_target_email;
END \$\$;
EOSQL

docker cp "${TMP_LOCAL_SQL}" "${DB_CONTAINER}:${TMP_CONT_SQL}" >/dev/null 2>&1
cp_rc=$?

if [ ${cp_rc} -eq 0 ]; then
    docker exec "${DB_CONTAINER}" \
        psql -U postgres -d postgres -v ON_ERROR_STOP=1 \
        -f "${TMP_CONT_SQL}"
    rc=$?
    docker exec "${DB_CONTAINER}" rm -f "${TMP_CONT_SQL}" >/dev/null 2>&1 || true
else
    docker exec -i "${DB_CONTAINER}" \
        psql -U postgres -d postgres -v ON_ERROR_STOP=1 \
        -f - < "${TMP_LOCAL_SQL}"
    rc=$?
fi
rm -f "${TMP_LOCAL_SQL}" 2>/dev/null || true

echo "---------------------------------------------------------------------"
if [ ${rc} -ne 0 ]; then
    echo "❌ Erro ao aplicar correção no banco de dados (código ${rc})!"
    exit ${rc}
fi
echo "✅ Banco atualizado com sucesso!"
echo ""

# (5) Conferência final
echo "📊 5. Conferência final do usuário corrigido:"
echo ""
docker exec "${DB_CONTAINER}" psql -U postgres -d postgres -c "
SELECT 
    id,
    email,
    length(encrypted_password) AS pass_len,
    left(encrypted_password, 7) AS pass_prefix,
    email_confirmed_at IS NOT NULL AS confirmado,
    confirmation_token = '' AS conf_tok_ok,
    recovery_token = '' AS rec_tok_ok,
    email_change = '' AS emch_ok,
    email_change_token_new = '' AS emch_tok_ok,
    updated_at
FROM auth.users
WHERE email ILIKE '${ESCAPED_EMAIL}';
" || true

echo ""
echo ">> Identidade associada em auth.identities:"
docker exec "${DB_CONTAINER}" psql -U postgres -d postgres -c "
SELECT id, user_id, provider, provider_id, updated_at
FROM auth.identities
WHERE user_id IN (SELECT id FROM auth.users WHERE email ILIKE '${ESCAPED_EMAIL}');
" || true

echo ""
echo "====================================================================="
echo "🎉 Correção concluída com sucesso para ${TARGET_EMAIL}!"
echo "   Os campos de token foram sanitizados para string vazia (''),"
echo "   eliminando o erro 'converting NULL to string is unsupported' no GoTrue."
echo "   👉 O usuário já pode logar em https://sistema.advdouglaspsantos.com.br"
echo "====================================================================="
exit 0
