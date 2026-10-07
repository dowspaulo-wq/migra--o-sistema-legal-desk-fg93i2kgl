#!/usr/bin/env bash
# ==============================================================================
# DPSjur / SBJur - Kit de Migração Asaas para Supabase Self-Hosted no VPS
# Script: 03-aplicar-migracao-asaas.sh
# Versão: v1.0.0
# SCRIPT_VERSION: v1.0.0
# ==============================================================================
# Finalidade:
# Adicionar com segurança e de forma idempotente as colunas "asaasApiKey" e
# "asaasApiUrl" na tabela public.settings no PostgreSQL do Supabase Self-Hosted.
#
# Isso resolve o problema onde o app no VPS não consegue salvar a chave da API
# do Asaas porque as colunas não existiam na tabela settings do banco local.
# ==============================================================================
set -euo pipefail

SCRIPT_VERSION="v1.0.0"

echo "====================================================================="
echo " DPSjur / SBJur - Aplicação de Migração Asaas no PostgreSQL (VPS)"
echo " Versão: $SCRIPT_VERSION"
echo "====================================================================="
echo ""

# ------------------------------------------------------------------------------
# 1. Localização automática do contêiner PostgreSQL do Supabase
# ------------------------------------------------------------------------------
echo "🔍 1. Buscando contêiner PostgreSQL do Supabase no EasyPanel/Docker..."
DB_CONTAINER="${DB_CONTAINER:-${CONTAINER_LOCAL:-}}"

if [ -z "$DB_CONTAINER" ]; then
    DB_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E 'supabase.*db|supabase-db' | head -n 1 || true)
fi

if [ -z "$DB_CONTAINER" ]; then
    # Fallback procurando qualquer contêiner com postgres/db excluindo o app frontend
    DB_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E 'postgres|db' | grep -v -E 'dpsjur-web|web|frontend' | head -n 1 || true)
fi

if [ -z "$DB_CONTAINER" ]; then
    echo "⚠️ Contêiner com padrão 'supabase...db' não identificado automaticamente via 'docker ps'."
    echo "Contêineres em execução atualmente:"
    docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}' || true
    echo ""
    echo "Informe o nome exato do contêiner PostgreSQL do Supabase (ou Ctrl+C para sair):"
    read -r -p "Nome do contêiner: " DB_CONTAINER
fi

if [ -z "$DB_CONTAINER" ]; then
    echo "❌ Erro: Contêiner PostgreSQL não informado. Abortando."
    exit 1
fi

echo "✅ Contêiner PostgreSQL identificado: $DB_CONTAINER"
echo ""

# ------------------------------------------------------------------------------
# 2. Credenciais de acesso ao PostgreSQL dentro do contêiner
# ------------------------------------------------------------------------------
# O Supabase self-hosted aceita conexão direta via usuário postgres ou supabase_admin
DB_USER="${POSTGRES_USER:-postgres}"
DB_NAME="${POSTGRES_DB:-postgres}"
LOCAL_DB_PASSWORD="${POSTGRES_PASSWORD:-${LOCAL_DB_PASSWORD:-}}"

# Testar se conecta direto sem senha (padrão em redes docker internas) ou se precisa de usuário/senha
echo "🔐 2. Testando conectividade com o banco de dados..."
AUTH_MODE=""

# Teste 2.1: com usuário postgres (e senha se fornecida)
set +e
if [ -n "$LOCAL_DB_PASSWORD" ]; then
    TEST_OUT=$(docker exec -i -e PGPASSWORD="$LOCAL_DB_PASSWORD" "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -tAc "SELECT 1;" 2>&1)
    TEST_STATUS=$?
else
    TEST_OUT=$(docker exec -i "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -tAc "SELECT 1;" 2>&1)
    TEST_STATUS=$?
fi
set -e

if [ $TEST_STATUS -eq 0 ]; then
    AUTH_MODE="postgres"
    echo "✅ Conexão bem-sucedida via usuário '$DB_USER'!"
else
    # Teste 2.2: tentar usuário supabase_admin
    set +e
    TEST_OUT_ADMIN=$(docker exec -i "$DB_CONTAINER" psql -U supabase_admin -d "$DB_NAME" -tAc "SELECT 1;" 2>&1)
    TEST_STATUS_ADMIN=$?
    set -e

    if [ $TEST_STATUS_ADMIN -eq 0 ]; then
        AUTH_MODE="supabase_admin"
        DB_USER="supabase_admin"
        echo "✅ Conexão bem-sucedida via usuário 'supabase_admin'!"
    else
        echo "⚠️ Conexão direta padrão falhou. Solicitando senha do PostgreSQL..."
        echo "Detalhe: $TEST_OUT"
        echo ""
        read -s -r -p "Digite a senha do POSTGRES_PASSWORD (do EasyPanel): " LOCAL_DB_PASSWORD
        echo ""

        set +e
        TEST_OUT=$(docker exec -i -e PGPASSWORD="$LOCAL_DB_PASSWORD" "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -tAc "SELECT 1;" 2>&1)
        TEST_STATUS=$?
        set -e

        if [ $TEST_STATUS -ne 0 ]; then
            echo "❌ Erro: Não foi possível autenticar no PostgreSQL!"
            echo "$TEST_OUT"
            exit 1
        fi
        AUTH_MODE="postgres"
        echo "✅ Conexão autenticada com sucesso!"
    fi
fi
echo ""

# Helper para executar comandos SQL via psql
run_sql() {
    local sql_query="$1"
    if [ -n "$LOCAL_DB_PASSWORD" ]; then
        docker exec -i -e PGPASSWORD="$LOCAL_DB_PASSWORD" "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 <<< "$sql_query"
    else
        docker exec -i "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 <<< "$sql_query"
    fi
}

run_sql_query_silent() {
    local sql_query="$1"
    if [ -n "$LOCAL_DB_PASSWORD" ]; then
        docker exec -i -e PGPASSWORD="$LOCAL_DB_PASSWORD" "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -tAc "$sql_query" 2>&1
    else
        docker exec -i "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -tAc "$sql_query" 2>&1
    fi
}

# ------------------------------------------------------------------------------
# 3. Verificação do estado atual da tabela public.settings
# ------------------------------------------------------------------------------
echo "📊 3. Verificando estrutura atual da tabela public.settings..."

SETTINGS_EXISTS=$(run_sql_query_silent "SELECT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='settings');")
if [ "$SETTINGS_EXISTS" != "t" ]; then
    echo "❌ Erro: A tabela 'public.settings' não foi encontrada no banco!"
    echo "Certifique-se de que a Fase 4 da migração (schema DDL) foi concluída."
    exit 1
fi

HAS_KEY_COL=$(run_sql_query_silent "SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='settings' AND column_name='asaasApiKey');")
HAS_URL_COL=$(run_sql_query_silent "SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='settings' AND column_name='asaasApiUrl');")

echo "   - Coluna 'asaasApiKey': $( [ "$HAS_KEY_COL" = "t" ] && echo "Presente ✅" || echo "Ausente ❌" )"
echo "   - Coluna 'asaasApiUrl': $( [ "$HAS_URL_COL" = "t" ] && echo "Presente ✅" || echo "Ausente ❌" )"
echo ""

# ------------------------------------------------------------------------------
# 4. Aplicação do DDL (ALTER TABLE ADD COLUMN IF NOT EXISTS)
# ------------------------------------------------------------------------------
echo "🚀 4. Aplicando comandos SQL DDL na tabela public.settings..."

DDL_SQL="
BEGIN;

-- Adiciona a coluna da chave de API do Asaas (se não existir)
ALTER TABLE public.settings
    ADD COLUMN IF NOT EXISTS \"asaasApiKey\" text;

-- Adiciona a coluna da URL base da API do Asaas com default oficial de produção
ALTER TABLE public.settings
    ADD COLUMN IF NOT EXISTS \"asaasApiUrl\" text DEFAULT 'https://api.asaas.com/v3';

-- Preenche default em registros existentes onde a URL estiver nula
UPDATE public.settings
    SET \"asaasApiUrl\" = 'https://api.asaas.com/v3'
    WHERE \"asaasApiUrl\" IS NULL;

-- Garante que exista pelo menos um registro em settings para ser atualizado pelo app
DO \$\$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.settings LIMIT 1) THEN
        INSERT INTO public.settings (id, \"showFinanceDashboard\", \"themeColor\", created_at, \"asaasApiUrl\")
        VALUES (gen_random_uuid(), true, 'blue', NOW(), 'https://api.asaas.com/v3');
    END IF;
END
\$\$;

COMMIT;
"

run_sql "$DDL_SQL"
echo "✅ Comandos DDL executados com sucesso!"
echo ""

# ------------------------------------------------------------------------------
# 5. Validação rigorosa pós-migração
# ------------------------------------------------------------------------------
echo "🔎 5. Verificando se as colunas foram criadas corretamente..."

COLUMNS_CHECK=$(run_sql_query_silent "
    SELECT column_name, data_type, column_default
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'settings'
      AND column_name IN ('asaasApiKey', 'asaasApiUrl')
    ORDER BY column_name;
")

echo "Colunas encontradas em public.settings:"
echo "$COLUMNS_CHECK"
echo ""

RECHECK_KEY=$(run_sql_query_silent "SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='settings' AND column_name='asaasApiKey');")
RECHECK_URL=$(run_sql_query_silent "SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='settings' AND column_name='asaasApiUrl');")

if [ "$RECHECK_KEY" = "t" ] && [ "$RECHECK_URL" = "t" ]; then
    echo "====================================================================="
    echo "🎉 MIGRAÇÃO CONCLUÍDA COM SUCESSO!"
    echo "====================================================================="
    echo "✅ As gavetas 'asaasApiKey' e 'asaasApiUrl' agora existem no banco do VPS."
    echo ""
    echo "Próximos passos para o Douglas:"
    echo "1. Abra o app no navegador: https://sistema.advdouglaspsantos.com.br"
    echo "2. Acesse 'Configurações' → aba 'Integrações'"
    echo "3. Cole sua chave da API do Asaas (\$aact_...)"
    echo "4. Clique no botão azul 'Salvar Configurações do Asaas'"
    echo "5. O badge mudará para 'Configurada' e o valor permanecerá salvo permanentemente! ✅"
    echo "====================================================================="
else
    echo "====================================================================="
    echo "⚠️ ATENÇÃO: As colunas não puderam ser verificadas após a execução."
    echo "Verifique as mensagens acima ou execute 'docker logs $DB_CONTAINER'."
    echo "====================================================================="
    exit 1
fi
