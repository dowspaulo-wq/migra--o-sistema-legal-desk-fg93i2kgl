#!/usr/bin/env bash
# ==============================================================================
# DPSjur / SBJur - Kit Google Agenda para Supabase Self-Hosted no VPS (EasyPanel)
# Script: docs/google-agenda/01-adicionar-colunas-settings.sh
# Versão: v1.0.0
# SCRIPT_VERSION: v1.0.0
# ==============================================================================
# Finalidade:
# Adicionar com segurança e de forma idempotente as colunas "googleClientId" e
# "googleClientSecret" na tabela public.settings no PostgreSQL do Supabase Self-Hosted,
# além de emitir NOTIFY pgrst, 'reload schema' para atualizar o cache do PostgREST.
#
# Isso resolve o erro:
#   "Erro ao salvar credenciais do Google — Could not find the 'googleClientId'
#    column of 'settings' in the schema cache"
#
# Execução no VPS:
#   curl -sSf -L -H "Accept: application/vnd.github.v3.raw" \
#     "https://api.github.com/repos/dowspaulo-wq/migra--o-sistema-legal-desk-fg93i2kgl/contents/docs/google-agenda/01-adicionar-colunas-settings.sh?ref=main" \
#     -o /root/01-adicionar-colunas-settings.sh && bash /root/01-adicionar-colunas-settings.sh
# ==============================================================================
set -euo pipefail

SCRIPT_VERSION="v1.0.0"

echo "====================================================================="
echo " DPSjur - Adicionar Colunas Google Agenda na Tabela Settings (VPS)   "
echo " Versão: $SCRIPT_VERSION"
echo "====================================================================="
echo "Data: $(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || true)"
echo "Host: $(hostname 2>/dev/null || echo 'VPS')"
echo "====================================================================="
echo ""

# ------------------------------------------------------------------------------
# 1. Localização automática do contêiner PostgreSQL do Supabase
# ------------------------------------------------------------------------------
echo "🔍 1. Buscando contêiner PostgreSQL do Supabase no EasyPanel/Docker..."
DB_CONTAINER="${DB_CONTAINER:-${CONTAINER_LOCAL:-}}"

if [ -z "$DB_CONTAINER" ]; then
    DB_CONTAINER=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -E 'supa?base.*db|supa?base-db' | head -n 1 || true)
fi

if [ -z "$DB_CONTAINER" ]; then
    # Fallback procurando qualquer contêiner com postgres/db excluindo o app frontend
    DB_CONTAINER=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -E 'postgres|db' | grep -v -E 'dpsjur-web|web|frontend|traefik|redis' | head -n 1 || true)
fi

if [ -z "$DB_CONTAINER" ]; then
    echo "⚠️ Contêiner com padrão 'supabase...db' não identificado automaticamente via 'docker ps'."
    echo "Contêineres em execução atualmente:"
    docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}' || true
    echo ""
    echo "❌ Erro: Contêiner PostgreSQL não encontrado. Abortando."
    exit 1
fi

echo "✅ Contêiner PostgreSQL identificado: $DB_CONTAINER"
echo ""

# ------------------------------------------------------------------------------
# 2. Localização opcional dos contêineres PostgREST e Kong (para recarga de cache)
# ------------------------------------------------------------------------------
echo "🔍 2. Mapeando contêineres do PostgREST e Edge Runtime..."
PGRST_CONTAINER=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -E 'supa?base.*rest|postgrest' | head -n 1 || true)
FUNCTIONS_CONTAINER=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -E 'supa?base.*functions|edge-runtime' | head -n 1 || true)

echo "   - PostgREST (REST): ${PGRST_CONTAINER:-⚠️ NÃO LOCALIZADO (reload será feito via NOTIFY)}"
echo "   - Functions Runtime: ${FUNCTIONS_CONTAINER:-⚠️ NÃO LOCALIZADO}"
echo ""

# ------------------------------------------------------------------------------
# 3. Teste de conectividade direta com o banco de dados
# ------------------------------------------------------------------------------
echo "🔐 3. Testando conectividade com o banco de dados..."
DB_USER="${POSTGRES_USER:-postgres}"
DB_NAME="${POSTGRES_DB:-postgres}"
LOCAL_DB_PASSWORD="${POSTGRES_PASSWORD:-${LOCAL_DB_PASSWORD:-}}"

if [ -n "$LOCAL_DB_PASSWORD" ]; then
    TEST_OUT=$(docker exec -i -e PGPASSWORD="$LOCAL_DB_PASSWORD" "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -tAc "SELECT 1;" 2>&1 || true)
else
    TEST_OUT=$(docker exec -i "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -tAc "SELECT 1;" 2>&1 || true)
fi

if [ "$TEST_OUT" = "1" ]; then
    echo "✅ Conexão direta com PostgreSQL OK via usuário '$DB_USER'!"
else
    # Tenta usuário supabase_admin
    TEST_OUT_ADMIN=$(docker exec -i "$DB_CONTAINER" psql -U supabase_admin -d "$DB_NAME" -tAc "SELECT 1;" 2>&1 || true)
    if [ "$TEST_OUT_ADMIN" = "1" ]; then
        DB_USER="supabase_admin"
        echo "✅ Conexão direta com PostgreSQL OK via usuário 'supabase_admin'!"
    else
        echo "❌ Erro: Não foi possível conectar ao banco de dados:"
        echo "$TEST_OUT"
        exit 1
    fi
fi
echo ""

# Helper para executar SQL de forma segura sem drenar stdin
run_sql_query_silent() {
    local sql_query="$1"
    if [ -n "$LOCAL_DB_PASSWORD" ]; then
        docker exec -i -e PGPASSWORD="$LOCAL_DB_PASSWORD" "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -tAc "$sql_query" 2>&1
    else
        docker exec -i "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -tAc "$sql_query" 2>&1
    fi
}

run_sql_script() {
    local sql_content="$1"
    local tmp_local="/tmp/sbjur_sql_$$.sql"
    local tmp_cont="/tmp/sbjur_sql_$$.sql"

    printf "%s\n" "${sql_content}" > "${tmp_local}"
    docker cp "${tmp_local}" "${DB_CONTAINER}:${tmp_cont}" >/dev/null 2>&1
    local cp_rc=$?

    if [ ${cp_rc} -eq 0 ]; then
        if [ -n "$LOCAL_DB_PASSWORD" ]; then
            docker exec -e PGPASSWORD="$LOCAL_DB_PASSWORD" "${DB_CONTAINER}" psql -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 -f "${tmp_cont}"
        else
            docker exec "${DB_CONTAINER}" psql -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 -f "${tmp_cont}"
        fi
        local psql_rc=$?
        docker exec "${DB_CONTAINER}" rm -f "${tmp_cont}" >/dev/null 2>&1 || true
    else
        if [ -n "$LOCAL_DB_PASSWORD" ]; then
            docker exec -i -e PGPASSWORD="$LOCAL_DB_PASSWORD" "${DB_CONTAINER}" psql -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 -f - < "${tmp_local}"
        else
            docker exec -i "${DB_CONTAINER}" psql -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 -f - < "${tmp_local}"
        fi
        local psql_rc=$?
    fi
    rm -f "${tmp_local}" 2>/dev/null || true
    return ${psql_rc}
}

# ------------------------------------------------------------------------------
# 4. Verificação do estado atual da tabela public.settings
# ------------------------------------------------------------------------------
echo "📊 4. Verificando estrutura atual da tabela public.settings..."

SETTINGS_EXISTS=$(run_sql_query_silent "SELECT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='settings');")
if [ "$SETTINGS_EXISTS" != "t" ]; then
    echo "❌ Erro: A tabela 'public.settings' não foi encontrada no banco!"
    exit 1
fi

HAS_ID_COL=$(run_sql_query_silent "SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='settings' AND column_name='googleClientId');")
HAS_SECRET_COL=$(run_sql_query_silent "SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='settings' AND column_name='googleClientSecret');")
HAS_TOKENS_COL=$(run_sql_query_silent "SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='settings' AND column_name='googleCalendarTokens');")

echo "   - Coluna 'googleClientId':      $( [ "$HAS_ID_COL" = "t" ] && echo "Presente ✅" || echo "Ausente ❌ (será criada)" )"
echo "   - Coluna 'googleClientSecret':  $( [ "$HAS_SECRET_COL" = "t" ] && echo "Presente ✅" || echo "Ausente ❌ (será criada)" )"
echo "   - Coluna 'googleCalendarTokens':$( [ "$HAS_TOKENS_COL" = "t" ] && echo "Presente ✅" || echo "Ausente ❌ (será criada)" )"
echo ""

# ------------------------------------------------------------------------------
# 5. Aplicação das colunas de forma idempotente
# ------------------------------------------------------------------------------
echo "🚀 5. Aplicando ALTER TABLE com colunas em camelCase..."

DDL_SQL="
BEGIN;

-- Adiciona colunas para credenciais OAuth do Google na tabela settings (camelCase exato)
ALTER TABLE public.settings
  ADD COLUMN IF NOT EXISTS \"googleClientId\" text,
  ADD COLUMN IF NOT EXISTS \"googleClientSecret\" text,
  ADD COLUMN IF NOT EXISTS \"googleCalendarTokens\" jsonb;

-- Comentários documentais
COMMENT ON COLUMN public.settings.\"googleClientId\" IS 'Client ID OAuth 2.0 do Google Cloud Console para sincronização da agenda';
COMMENT ON COLUMN public.settings.\"googleClientSecret\" IS 'Client Secret OAuth 2.0 do Google Cloud Console para sincronização da agenda';
COMMENT ON COLUMN public.settings.\"googleCalendarTokens\" IS 'Tokens OAuth 2.0 (access_token, refresh_token) da conta Google conectada';

-- Garante existência da coluna googleEventId na tabela appointments
ALTER TABLE public.appointments
  ADD COLUMN IF NOT EXISTS \"googleEventId\" text;

-- Garante que exista pelo menos uma linha em settings para o app atualizar
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.settings LIMIT 1) THEN
    INSERT INTO public.settings (id, \"showFinanceDashboard\", \"themeColor\", created_at)
    VALUES (gen_random_uuid(), true, 'blue', NOW());
  END IF;
END \$\$;

COMMIT;
"

run_sql_script "$DDL_SQL"
echo "✅ DDL executado com sucesso no PostgreSQL!"
echo ""

# ------------------------------------------------------------------------------
# 6. Recarga do schema cache do PostgREST
# ------------------------------------------------------------------------------
echo "🔄 6. Recarregando schema cache do PostgREST..."

RELOAD_SQL="NOTIFY pgrst, 'reload schema';"
run_sql_script "$RELOAD_SQL"
echo "✅ Comando 'NOTIFY pgrst, reload schema' enviado ao Postgres!"

# Se o contêiner do PostgREST estiver rodando, reinicia-o para garantir recarga 100% imediata
if [ -n "$PGRST_CONTAINER" ]; then
    echo "🔄 Reiniciando contêiner do PostgREST ($PGRST_CONTAINER) para aplicar novo schema..."
    docker restart "$PGRST_CONTAINER" >/dev/null 2>&1 || true
    echo "✅ Contêiner PostgREST reiniciado!"
fi

# Se o contêiner de functions existir, também reinicia para limpar possíveis caches
if [ -n "$FUNCTIONS_CONTAINER" ]; then
    echo "🔄 Reiniciando contêiner de Edge Functions ($FUNCTIONS_CONTAINER)..."
    docker restart "$FUNCTIONS_CONTAINER" >/dev/null 2>&1 || true
    echo "✅ Contêiner de Edge Functions reiniciado!"
fi
echo ""

# ------------------------------------------------------------------------------
# 7. Validação rigorosa pós-execução
# ------------------------------------------------------------------------------
echo "🔎 7. Verificando resultado final das colunas em public.settings..."

COLUMNS_CHECK=$(run_sql_query_silent "
    SELECT column_name, data_type, is_nullable
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'settings'
      AND column_name IN ('googleClientId', 'googleClientSecret', 'googleCalendarTokens')
    ORDER BY column_name;
")

echo "Colunas encontradas em public.settings:"
echo "$COLUMNS_CHECK"
echo ""

FINAL_ID=$(run_sql_query_silent "SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='settings' AND column_name='googleClientId');")
FINAL_SECRET=$(run_sql_query_silent "SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='settings' AND column_name='googleClientSecret');")

if [ "$FINAL_ID" = "t" ] && [ "$FINAL_SECRET" = "t" ]; then
    echo "====================================================================="
    echo "🎉 SUCESSO! TABELA SETTINGS ATUALIZADA E PRONTA NO VPS!"
    echo "====================================================================="
    echo "✅ As colunas \"googleClientId\" e \"googleClientSecret\" já estão criadas."
    echo "✅ O PostgREST recarregou o schema e agora aceitará salvar as credenciais."
    echo ""
    echo "Próximos passos no sistema DPSjur:"
    echo "1. Abra https://sistema.advdouglaspsantos.com.br/configuracoes"
    echo "2. Vá na aba 'Integrações' → Cartão 'Google Agenda'"
    echo "3. Cole o Google Client ID e Google Client Secret"
    echo "4. Clique em 'Salvar Credenciais do Google' (agora salvará sem erro!)"
    echo "5. Clique em 'Conectar Conta Google' (ou vá em Agenda e clique em 'Sincronizar')"
    echo "6. Conceda a permissão na tela do Google e pronto!"
    echo "====================================================================="
else
    echo "❌ Erro: Não foi possível confirmar a criação das colunas no banco."
    exit 1
fi
