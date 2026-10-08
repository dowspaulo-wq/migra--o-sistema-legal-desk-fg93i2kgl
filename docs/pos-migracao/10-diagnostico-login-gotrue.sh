#!/usr/bin/env bash
# ==============================================================================
# DPSjur / SBJur - Kit Pós-Migração VPS (Hostinger KVM 1 - IP 2.25.181.69)
# Script: docs/pos-migracao/10-diagnostico-login-gotrue.sh
# Versão: v0.0.541
# ==============================================================================
# Execução direta no terminal do VPS:
#   bash docs/pos-migracao/10-diagnostico-login-gotrue.sh ["<email>"] ["<senha>"]
#
# Execução remota via curl (sem clonar o repositório):
#   curl -sSf -L -H "Accept: application/vnd.github.v3.raw" \
#     "https://api.github.com/repos/dowspaulo-wq/migra--o-sistema-legal-desk-fg93i2kgl/contents/docs/pos-migracao/10-diagnostico-login-gotrue.sh?ref=main" \
#     | bash -s -- "heitorpaulodossantos@gmail.com" "<senha_opcional>"
#
# Padrões obrigatórios:
# - Não usa docker exec -i para comandos SQL (evita consumo de stdin do pipe curl)
# - Todos os scripts SQL são gravados localmente, enviados via docker cp e rodados com psql -f
# - Sem interpolação :'var' do psql (literais SQL escapados com aspas simples)
# - Nenhuma saída mascarada com 2>/dev/null em verificações críticas
# - Mensagens claras antes e depois de cada etapa
# ==============================================================================

SCRIPT_VERSION="v0.0.541"
TARGET_EMAIL="${1:-${USUARIO_EMAIL:-heitorpaulodossantos@gmail.com}}"
TEST_PASSWORD="${2:-${TESTE_SENHA:-}}"

echo "====================================================================="
echo " SBJur — Diagnóstico Completo de Login GoTrue / Auth                "
echo " Versão: ${SCRIPT_VERSION}"
echo "====================================================================="
echo "Data: $(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || true)"
echo "Host: $(hostname 2>/dev/null || echo 'VPS')"
echo "Alvo: ${TARGET_EMAIL}"
echo "====================================================================="
echo ""

# Escape seguro de aspas simples para literais SQL
ESCAPED_EMAIL="${TARGET_EMAIL//\'/\'\'}"

# ------------------------------------------------------------------------------
# 1. Localizar contêineres Docker (DB, GoTrue/Auth, Kong)
# ------------------------------------------------------------------------------
echo "🔍 1. Mapeando contêineres Docker do Supabase no EasyPanel..."

DB_CONTAINER="${DB_CONTAINER:-}"
if [ -z "${DB_CONTAINER}" ]; then
    DB_CONTAINER=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -E 'supa?base.*db|supa?base-db' | head -n 1 || true)
fi
if [ -z "${DB_CONTAINER}" ]; then
    DB_CONTAINER=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -E 'postgres|db' | grep -v -E 'dpsjur-web|web|frontend|traefik|redis' | head -n 1 || true)
fi

AUTH_CONTAINER="${AUTH_CONTAINER:-}"
if [ -z "${AUTH_CONTAINER}" ]; then
    AUTH_CONTAINER=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -E 'supa?base.*auth|gotrue' | head -n 1 || true)
fi

KONG_CONTAINER="${KONG_CONTAINER:-}"
if [ -z "${KONG_CONTAINER}" ]; then
    KONG_CONTAINER=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -E 'supa?base.*kong|kong' | head -n 1 || true)
fi

echo "   - Banco (PostgreSQL): ${DB_CONTAINER:-❌ NÃO LOCALIZADO}"
echo "   - Auth (GoTrue):     ${AUTH_CONTAINER:-⚠️ NÃO LOCALIZADO (ver logs manuais)}"
echo "   - Gateway (Kong):    ${KONG_CONTAINER:-⚠️ NÃO LOCALIZADO}"
echo ""

if [ -z "${DB_CONTAINER}" ]; then
    echo "❌ Erro: Contêiner do PostgreSQL não encontrado via docker ps!"
    docker ps --format 'table {{.Names}}\t{{.Status}}' 2>/dev/null || true
    exit 1
fi

echo "🔐 Testando conectividade direta com o banco..."
if docker exec "${DB_CONTAINER}" psql -U postgres -d postgres -tAc "SELECT 1;" >/dev/null 2>&1; then
    echo "✅ Conexão direta com PostgreSQL OK!"
else
    echo "❌ Erro ao conectar ao PostgreSQL com usuário postgres."
    exit 1
fi
echo ""

# Helper para rodar SQL via docker cp + psql -f (anti-pipe drain)
run_sql_script() {
    local sql_content="$1"
    local tmp_local="/tmp/sbjur_diag_$$.sql"
    local tmp_cont="/tmp/sbjur_diag_$$.sql"

    printf "%s\n" "${sql_content}" > "${tmp_local}"
    docker cp "${tmp_local}" "${DB_CONTAINER}:${tmp_cont}" >/dev/null 2>&1
    local cp_rc=$?

    if [ ${cp_rc} -eq 0 ]; then
        docker exec "${DB_CONTAINER}" psql -U postgres -d postgres -v ON_ERROR_STOP=0 -f "${tmp_cont}"
        local psql_rc=$?
        docker exec "${DB_CONTAINER}" rm -f "${tmp_cont}" >/dev/null 2>&1 || true
    else
        docker exec -i "${DB_CONTAINER}" psql -U postgres -d postgres -v ON_ERROR_STOP=0 -f - < "${tmp_local}"
        local psql_rc=$?
    fi
    rm -f "${tmp_local}" 2>/dev/null || true
    return ${psql_rc}
}

# ------------------------------------------------------------------------------
# 2. SELECT completo da linha do usuário em auth.users com auditoria de colunas
# ------------------------------------------------------------------------------
echo "====================================================================="
echo "📋 2. Inspeção detalhada de auth.users para ${TARGET_EMAIL}"
echo "====================================================================="

SQL_INSPECT_USER="
\x auto
SELECT 
    id,
    instance_id,
    email,
    role,
    aud,
    length(encrypted_password) AS pass_len,
    left(encrypted_password, 7) AS pass_prefix,
    email_confirmed_at,
    confirmed_at,
    last_sign_in_at,
    is_super_admin,
    is_sso_user,
    is_anonymous,
    phone,
    phone_confirmed_at,
    created_at,
    updated_at
FROM auth.users
WHERE email ILIKE '${ESCAPED_EMAIL}';

\echo '>> Tokens em auth.users (GoTrue exige string vazia \"\" para não disparar Scan error com NULL):'
SELECT 
    id,
    confirmation_token IS NULL AS conf_tok_is_null,
    confirmation_token = '' AS conf_tok_is_empty,
    length(confirmation_token) AS conf_tok_len,
    recovery_token IS NULL AS rec_tok_is_null,
    recovery_token = '' AS rec_tok_is_empty,
    length(recovery_token) AS rec_tok_len,
    email_change_token_new IS NULL AS emch_tok_new_is_null,
    email_change_token_new = '' AS emch_tok_new_is_empty,
    email_change_token_current IS NULL AS emch_tok_cur_is_null,
    email_change IS NULL AS emch_is_null,
    phone_change IS NULL AS phch_is_null,
    phone_change_token IS NULL AS phch_tok_is_null,
    reauthentication_token IS NULL AS reauth_tok_is_null
FROM auth.users
WHERE email ILIKE '${ESCAPED_EMAIL}';
"

run_sql_script "${SQL_INSPECT_USER}"
echo ""

# ------------------------------------------------------------------------------
# 3. Conferência em auth.identities e public.profiles
# ------------------------------------------------------------------------------
echo "====================================================================="
echo "👥 3. Conferência em auth.identities e public.profiles"
echo "====================================================================="

SQL_INSPECT_ID_PROFILE="
\echo '>> Registro(s) em auth.identities:'
SELECT 
    id,
    user_id,
    provider,
    provider_id,
    identity_data,
    last_sign_in_at,
    created_at,
    updated_at
FROM auth.identities
WHERE user_id IN (SELECT id FROM auth.users WHERE email ILIKE '${ESCAPED_EMAIL}');

\echo '>> Registro em public.profiles:'
SELECT 
    id,
    name,
    email,
    role,
    \"canViewFinance\",
    color,
    is_active,
    created_at
FROM public.profiles
WHERE email ILIKE '${ESCAPED_EMAIL}'
   OR id IN (SELECT id FROM auth.users WHERE email ILIKE '${ESCAPED_EMAIL}');
"

run_sql_script "${SQL_INSPECT_ID_PROFILE}"
echo ""

# ------------------------------------------------------------------------------
# 4. Triggers sobre auth.users e teste de UPDATE em transação revertida
# ------------------------------------------------------------------------------
echo "====================================================================="
echo "⚡ 4. Triggers em auth.users e teste de UPDATE simulado (ROLLBACK)"
echo "====================================================================="

SQL_INSPECT_TRIGGERS="
\echo '>> Triggers cadastrados sobre auth.users:'
SELECT 
    t.tgname AS trigger_name,
    CASE 
        WHEN t.tgtype & 2 = 2 THEN 'BEFORE'
        WHEN t.tgtype & 64 = 64 THEN 'INSTEAD OF'
        ELSE 'AFTER'
    END AS timing,
    CASE 
        WHEN t.tgtype & 4 = 4 THEN 'INSERT '
        ELSE ''
    END ||
    CASE 
        WHEN t.tgtype & 8 = 8 THEN 'DELETE '
        ELSE ''
    END ||
    CASE 
        WHEN t.tgtype & 16 = 16 THEN 'UPDATE '
        ELSE ''
    END AS event,
    p.proname AS function_name,
    n.nspname AS function_schema,
    CASE WHEN t.tgenabled = 'O' THEN 'HABILITADO' ELSE 'DESABILITADO' END AS status
FROM pg_trigger t
JOIN pg_class c ON c.oid = t.tgrelid
JOIN pg_namespace ns ON ns.oid = c.relnamespace
JOIN pg_proc p ON p.oid = t.tgfoid
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE ns.nspname = 'auth'
  AND c.relname = 'users'
  AND NOT t.tgisinternal
ORDER BY t.tgname;

\echo '>> Testando execução de UPDATE em transação revertida (testa se triggers quebram):'
DO \$\$
DECLARE
    v_uid uuid;
BEGIN
    SELECT id INTO v_uid FROM auth.users WHERE email ILIKE '${ESCAPED_EMAIL}' LIMIT 1;
    IF v_uid IS NULL THEN
        RAISE NOTICE 'Usuário não encontrado para teste de trigger.';
    ELSE
        -- Simula o tipo de UPDATE que o GoTrue faz no login (last_sign_in_at, updated_at)
        UPDATE auth.users 
        SET updated_at = now() 
        WHERE id = v_uid;
        RAISE NOTICE 'SUCESSO: UPDATE em auth.users executado sem erros de trigger!';
    END IF;
EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'FALHA DE TRIGGER EM auth.users: % (SQLSTATE: %)', SQLERRM, SQLSTATE;
END \$\$;
"

run_sql_script "${SQL_INSPECT_TRIGGERS}"
echo ""

# ------------------------------------------------------------------------------
# 5. Teste direto do endpoint de token do GoTrue (localhost:8000 via Kong / local GoTrue)
# ------------------------------------------------------------------------------
echo "====================================================================="
echo "🌐 5. Teste direto de requisição POST /auth/v1/token?grant_type=password"
echo "====================================================================="

TEST_PASS_ACTUAL="${TEST_PASSWORD:-DPSjur@2026}"

echo ">> Testando chamada HTTP direta ao Kong local (http://127.0.0.1:8000/auth/v1/token)..."
# Tenta obter a anon key ou service_role key do ambiente para incluir no header apikey
ANON_KEY=$(docker exec "${KONG_CONTAINER:-supabase-kong}" env 2>/dev/null | grep -E '^ANON_KEY=' | cut -d'=' -f2- || true)
if [ -z "${ANON_KEY}" ] && [ -n "${AUTH_CONTAINER}" ]; then
    ANON_KEY=$(docker exec "${AUTH_CONTAINER}" env 2>/dev/null | grep -E '^ANON_KEY=|^GOTRUE_JWT_SECRET=' | head -n 1 | cut -d'=' -f2- || true)
fi

# Teste 1: Kong interno (porta 8000)
KONG_RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST "http://127.0.0.1:8000/auth/v1/token?grant_type=password" \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"${TARGET_EMAIL}\",\"password\":\"${TEST_PASS_ACTUAL}\"}" 2>&1 || true)

echo "Resposta do Kong (http://127.0.0.1:8000):"
echo "${KONG_RESPONSE}"
echo ""

# Teste 2: Se GoTrue estiver ouvindo na porta 9999 direta (padrão GoTrue)
echo ">> Testando porta interna direta do GoTrue (9999)..."
GOTRUE_DIRECT=$(curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST "http://127.0.0.1:9999/token?grant_type=password" \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"${TARGET_EMAIL}\",\"password\":\"${TEST_PASS_ACTUAL}\"}" 2>&1 || true)
echo "Resposta GoTrue direto (9999):"
echo "${GOTRUE_DIRECT}"
echo ""

# ------------------------------------------------------------------------------
# 6. Últimas linhas de log do contêiner GoTrue / Auth
# ------------------------------------------------------------------------------
echo "====================================================================="
echo "📜 6. Últimas linhas dos logs do contêiner GoTrue / Auth (docker logs)"
echo "====================================================================="

if [ -n "${AUTH_CONTAINER}" ]; then
    echo ">> Logs recentes do contêiner '${AUTH_CONTAINER}':"
    docker logs --tail 40 "${AUTH_CONTAINER}" 2>&1 || true
else
    echo "⚠️ Contêiner do GoTrue não detectado automaticamente. Listando contêineres ativos:"
    docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' 2>/dev/null || true
fi
echo ""

echo "====================================================================="
echo "🏁 Diagnóstico concluído com sucesso!"
echo "   Analise os blocos acima para verificar valores NULL em colunas text"
echo "   (confirmation_token, recovery_token, email_change, etc.), retorno HTTP"
echo "   e logs do GoTrue que mostram a linha de 'Scan error'."
echo "====================================================================="
exit 0
