#!/usr/bin/env bash
# ==============================================================================
# DPSjur / SBJur - Kit Pós-Migração VPS (Hostinger KVM 1 - IP 2.25.181.69)
# Script: docs/pos-migracao/09-redefinir-senha-usuario.sh
# Versão: v0.0.536
# ==============================================================================
# Execução direta no terminal do VPS:
#   bash docs/pos-migracao/09-redefinir-senha-usuario.sh "<email>" "<nova_senha>"
#
# Execução remota via curl (sem clonar o repositório):
#   curl -sSf -L -H "Accept: application/vnd.github.v3.raw" \
#     "https://api.github.com/repos/dowspaulo-wq/migra--o-sistema-legal-desk-fg93i2kgl/contents/docs/pos-migracao/09-redefinir-senha-usuario.sh?ref=main" \
#     | bash -s -- "<email>" "<nova_senha>"
#
# Ou passando via variáveis de ambiente:
#   USUARIO_EMAIL="<email>" NOVA_SENHA="<nova_senha>" curl -sSf -L ... | bash
# ==============================================================================

SCRIPT_VERSION="v0.0.536"

# (1) Banner no padrão dos scripts anteriores
echo "====================================================================="
echo " SBJur — Redefinição direta de senha de usuário                      "
echo " Versão: ${SCRIPT_VERSION}"
echo "====================================================================="
echo "Data: $(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || true)"
echo "Host: $(hostname 2>/dev/null || echo 'VPS')"
echo "====================================================================="
echo ""

# (2) Receber do operador: e-mail e nova senha (argumentos ou env vars)
TARGET_EMAIL="${1:-${USUARIO_EMAIL:-}}"
NEW_PASSWORD="${2:-${NOVA_SENHA:-}}"

if [ -z "${TARGET_EMAIL}" ] || [ -z "${NEW_PASSWORD}" ]; then
    echo "❌ Erro: Parâmetros incompletos!"
    echo ""
    echo "Uso correto:"
    echo "  1) Passando argumentos diretamente:"
    echo "     bash docs/pos-migracao/09-redefinir-senha-usuario.sh \"usuario@email.com\" \"NovaSenhaForte123!\""
    echo ""
    echo "  2) Via curl (one-liner recomendado no VPS):"
    echo "     curl -sSf -L -H \"Accept: application/vnd.github.v3.raw\" \\"
    echo "       \"https://api.github.com/repos/dowspaulo-wq/migra--o-sistema-legal-desk-fg93i2kgl/contents/docs/pos-migracao/09-redefinir-senha-usuario.sh?ref=main\" \\"
    echo "       | bash -s -- \"usuario@email.com\" \"NovaSenhaForte123!\""
    echo ""
    echo "  3) Via variáveis de ambiente:"
    echo "     USUARIO_EMAIL=\"usuario@email.com\" NOVA_SENHA=\"NovaSenhaForte123!\" \\"
    echo "     curl -sSf -L -H \"Accept: application/vnd.github.v3.raw\" \\"
    echo "       \"https://api.github.com/repos/dowspaulo-wq/migra--o-sistema-legal-desk-fg93i2kgl/contents/docs/pos-migracao/09-redefinir-senha-usuario.sh?ref=main\" \\"
    echo "       | bash"
    echo ""
    exit 1
fi

echo "🎯 Alvo: ${TARGET_EMAIL}"
echo ""

# (3) Localizar contêiner PostgreSQL via docker ps
echo "🔍 1. Localizando contêiner PostgreSQL do Supabase..."
DB_CONTAINER="${DB_CONTAINER:-}"

if [ -z "${DB_CONTAINER}" ]; then
    DB_CONTAINER=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -E 'supa?base.*db|supa?base-db' | head -n 1 || true)
fi

if [ -z "${DB_CONTAINER}" ]; then
    DB_CONTAINER=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -E 'postgres|db' | grep -v -E 'dpsjur-web|web|frontend|traefik|redis' | head -n 1 || true)
fi

if [ -z "${DB_CONTAINER}" ]; then
    echo "❌ Erro: Não foi possível localizar o contêiner do PostgreSQL via docker ps!"
    echo "Contêineres em execução:"
    docker ps --format 'table {{.Names}}\t{{.Status}}' 2>/dev/null || true
    echo ""
    echo "Você pode informar manualmente executando:"
    echo "  DB_CONTAINER=nome_do_conteiner bash ..."
    exit 1
fi
echo "✅ Contêiner localizado: ${DB_CONTAINER}"
echo ""

# (4) Teste de conexão direta via socket local
echo "🔐 2. Testando conectividade com o banco de dados..."
if docker exec "${DB_CONTAINER}" psql -U postgres -d postgres -tAc "SELECT 1;" >/dev/null 2>&1; then
    echo "✅ Conexão direta bem-sucedida via usuário 'postgres' (local socket)!"
else
    echo "❌ Erro: Falha ao conectar ao banco de dados no contêiner '${DB_CONTAINER}' com usuário 'postgres'."
    echo "Verifique se o contêiner está pronto ou se o serviço do banco está ativo."
    exit 1
fi
echo ""

# (5) Validar se o usuário existe em auth.users
echo "🔎 3. Verificando existência do usuário ${TARGET_EMAIL}..."
USER_CHECK_COUNT=$(docker exec -i -e TARGET_EMAIL="${TARGET_EMAIL}" "${DB_CONTAINER}" psql -U postgres -d postgres -tAc "SELECT count(*) FROM auth.users WHERE email ILIKE current_setting('target.email', true);" -c "SET target.email = '${TARGET_EMAIL}';" 2>/dev/null || true)

# Validação alternativa sem mexer em settings caso venha vazio ou falhe:
if [ -z "${USER_CHECK_COUNT}" ]; then
    USER_CHECK_COUNT=$(docker exec -i -e TARGET_EMAIL="${TARGET_EMAIL}" "${DB_CONTAINER}" \
        psql -U postgres -d postgres -v "target_email=${TARGET_EMAIL}" -tAc \
        "SELECT count(*) FROM auth.users WHERE email ILIKE :'target_email';" 2>/dev/null || echo "0")
fi

if [ "${USER_CHECK_COUNT}" = "0" ] || [ -z "${USER_CHECK_COUNT}" ]; then
    echo "❌ Usuário não encontrado em auth.users com o e-mail: '${TARGET_EMAIL}'"
    echo ""
    echo "Nenhuma alteração foi realizada."
    echo "Lista de usuários cadastrados no banco para conferência:"
    docker exec -i "${DB_CONTAINER}" psql -U postgres -d postgres -c "
        SELECT id, email, created_at, email_confirmed_at IS NOT NULL AS confirmado 
        FROM auth.users 
        ORDER BY email;
    " 2>/dev/null || true
    exit 1
fi

echo "✅ Usuário encontrado no banco de dados! Prosseguindo com a redefinição de senha..."
echo ""

# (6) Redefinir a senha com pgcrypto e limpar tokens pendentes
# Passamos TARGET_EMAIL e NEW_PASSWORD com segurança via docker exec -e
# Usamos extensões do PostgreSQL de forma resiliente: pgcrypto (crypt + gen_salt('bf', 10))
# IMPORTANTE:
# - confirmed_at e email são colunas GENERATED e NUNCA devem ser atualizadas diretamente.
# - email_confirmed_at é coluna normal: preenchemos COALESCE(email_confirmed_at, now()).
# - Limpamos tokens pendentes: confirmation_token = NULL, recovery_token = NULL, email_change_token_new = NULL, email_change = NULL.
# - Atualizamos auth.identities para garantir que identity_data reflita email e email_verified.
echo "🚀 4. Atualizando senha e higienizando tokens no auth.users..."
echo "---------------------------------------------------------------------"
docker exec -i \
    -e TARGET_EMAIL="${TARGET_EMAIL}" \
    -e NEW_PASSWORD="${NEW_PASSWORD}" \
    "${DB_CONTAINER}" \
    psql -U postgres -d postgres -v ON_ERROR_STOP=1 \
    -v "target_email=${TARGET_EMAIL}" \
    -v "new_pass=${NEW_PASSWORD}" << 'EOSQL'
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

DO $$
DECLARE
    v_crypt_func text;
    v_target_email text := :'target_email';
    v_new_password text := :'new_pass';
    v_user_id uuid;
    v_user_email text;
    v_has_identities boolean := false;
BEGIN
    -- Obter ID e email exato do usuário
    SELECT id, email INTO v_user_id, v_user_email
    FROM auth.users
    WHERE email ILIKE v_target_email
    LIMIT 1;

    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Usuário % não encontrado!', v_target_email;
    END IF;

    -- Detectar schema onde pgcrypto reside (extensions ou public)
    IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'extensions' AND p.proname = 'gen_salt') THEN
        EXECUTE 'SET search_path TO public, extensions;';
    END IF;

    -- 1. Atualizar auth.users:
    -- - encrypted_password gerado com bcrypt (gen_salt bf 10)
    -- - email_confirmed_at preenchido se estava nulo (ativa confirmed_at gerado automaticamente)
    -- - tokens pendentes limpos para que GoTrue não fique travado
    -- - updated_at atualizado
    UPDATE auth.users
    SET 
        encrypted_password = crypt(v_new_password, gen_salt('bf', 10)),
        email_confirmed_at = COALESCE(email_confirmed_at, now()),
        confirmation_token = NULL,
        recovery_token = NULL,
        email_change_token_new = NULL,
        email_change = NULL,
        updated_at = now()
    WHERE id = v_user_id;

    -- 2. Atualizar ou inserir em auth.identities (se a tabela existir)
    -- Garante que o provedor 'email' esteja vinculado ao usuário com identity_data correto
    IF EXISTS (
        SELECT 1 FROM information_schema.tables 
        WHERE table_schema = 'auth' AND table_name = 'identities'
    ) THEN
        -- Se já existir identidade para esse usuário, apenas atualiza updated_at e flags
        IF EXISTS (SELECT 1 FROM auth.identities WHERE user_id = v_user_id) THEN
            UPDATE auth.identities
            SET 
                identity_data = jsonb_set(
                    jsonb_set(COALESCE(identity_data, '{}'::jsonb), '{email_verified}', 'true'::jsonb),
                    '{email}', to_jsonb(v_user_email)
                ),
                updated_at = now()
            WHERE user_id = v_user_id;
        ELSE
            -- Se não existir identidade cadastrada, cria para garantir compatibilidade com GoTrue
            INSERT INTO auth.identities (
                id,
                user_id,
                identity_data,
                provider,
                provider_id,
                created_at,
                updated_at
            ) VALUES (
                gen_random_uuid(),
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
END $$;
EOSQL
rc=$?
echo "---------------------------------------------------------------------"

if [ $rc -ne 0 ]; then
    echo "❌ Erro fatal: O comando psql encerrou com código de erro ${rc}!"
    echo "A senha NÃO foi alterada."
    exit $rc
fi

echo "✅ Hash bcrypt gerado e salvo com sucesso no banco de dados!"
echo ""

# (7) Conferência final
echo "📊 5. Conferência dos dados no banco..."
echo ""

echo ">> Registro do usuário atualizado em auth.users:"
docker exec -i "${DB_CONTAINER}" psql -U postgres -d postgres -v "target_email=${TARGET_EMAIL}" -c "
SELECT 
    id, 
    email, 
    length(encrypted_password) AS tamanho_hash, 
    left(encrypted_password, 7) AS prefixo_hash, 
    email_confirmed_at IS NOT NULL AS confirmado,
    updated_at
FROM auth.users 
WHERE email ILIKE :'target_email';
" || {
    echo "⚠️  Aviso: Consulta de conferência do usuário falhou."
}
echo ""

echo ">> Sessões ativas em auth.sessions (informativo):"
docker exec -i "${DB_CONTAINER}" psql -U postgres -d postgres -v "target_email=${TARGET_EMAIL}" -c "
SELECT 
    count(*) AS sessoes_ativas 
FROM auth.sessions 
WHERE user_id IN (SELECT id FROM auth.users WHERE email ILIKE :'target_email');
" || {
    echo "⚠️  Aviso: Consulta de conferência de sessões falhou."
}
echo ""

# (8) Mensagem final clara
echo "====================================================================="
echo "🎉 Senha redefinida com sucesso para ${TARGET_EMAIL}."
echo "   O usuário já pode entrar em https://sistema.advdouglaspsantos.com.br com a nova senha."
echo "====================================================================="
exit 0
