#!/usr/bin/env bash
# ==============================================================================
# DPSjur / SBJur - Kit Pós-Migração VPS (Hostinger KVM 1 - IP 2.25.181.69)
# Script: docs/pos-migracao/05-executar-04-recriar-processos.sh
# Versão: v0.0.524
# ==============================================================================
# Finalidade:
# Localizar automaticamente o contêiner PostgreSQL do Supabase Self-Hosted
# no VPS (EasyPanel/Docker), baixar e aplicar de forma idempotente o script
# SQL '04-recriar-processos-guilherme.sql', restaurando os 3 processos criados
# por Guilherme Almeida e registrando os respectivos logs de auditoria.
#
# Execução recomendada no VPS:
# curl -sSf -L -H "Accept: application/vnd.github.v3.raw" \
#   "https://api.github.com/repos/dowspaulo-wq/migra--o-sistema-legal-desk-fg93i2kgl/contents/docs/pos-migracao/05-executar-04-recriar-processos.sh?ref=main" \
#   | bash
# ==============================================================================
set -euo pipefail

# Garante que terminal restaure echo em caso de interrupção
trap 'stty echo 2>/dev/null || true' EXIT INT TERM

SCRIPT_VERSION="v0.0.525"
# Quando executado via pipe (curl | bash), BASH_SOURCE[0] vem vazio sob `set -u`
SCRIPT_ENTRY="${BASH_SOURCE[0]:-$0}"
SCRIPT_DIR="$(cd "$(dirname "${SCRIPT_ENTRY}")" 2>/dev/null && pwd || echo "/root/sbjur-pos-migracao")"
WORK_DIR="/root/sbjur-pos-migracao"
SQL_FILE_NAME="04-recriar-processos-guilherme.sql"
SQL_FILE_PATH="${SCRIPT_DIR}/${SQL_FILE_NAME}"

GITHUB_API_SQL_URL="https://api.github.com/repos/dowspaulo-wq/migra--o-sistema-legal-desk-fg93i2kgl/contents/docs/pos-migracao/${SQL_FILE_NAME}?ref=main"
GITHUB_RAW_SQL_URL="https://raw.githubusercontent.com/dowspaulo-wq/migra--o-sistema-legal-desk-fg93i2kgl/main/docs/pos-migracao/${SQL_FILE_NAME}"

echo "====================================================================="
echo " DPSjur / SBJur - Recriação de Processos no VPS (Guilherme Almeida)  "
echo " Versão: $SCRIPT_VERSION"
echo "====================================================================="
echo "Data: $(date '+%Y-%m-%d %H:%M:%S')"
echo "Host: $(hostname 2>/dev/null || echo 'VPS')"
echo ""

# ------------------------------------------------------------------------------
# 1. LOCALIZAÇÃO DO ARQUIVO SQL (LOCAL OU DOWNLOAD VIA GITHUB API/RAW)
# ------------------------------------------------------------------------------
echo "📁 1. Verificando disponibilidade do arquivo SQL (${SQL_FILE_NAME})..."

if [ ! -f "$SQL_FILE_PATH" ]; then
    mkdir -p "$WORK_DIR"
    SQL_FILE_PATH="${WORK_DIR}/${SQL_FILE_NAME}"
    echo "⏳ Arquivo local não encontrado. Baixando do repositório GitHub..."

    set +e
    curl -sSf -L \
         -H "Accept: application/vnd.github.v3.raw" \
         -H "User-Agent: DPSjur-PosMigracao" \
         "$GITHUB_API_SQL_URL" \
         -o "$SQL_FILE_PATH" 2>/dev/null
    CURL_STATUS=$?
    set -e

    if [ $CURL_STATUS -ne 0 ] || [ ! -s "$SQL_FILE_PATH" ]; then
        echo "ℹ️  Tentando via raw.githubusercontent.com com anti-cache..."
        CACHE_BUST=$(date +%s)
        set +e
        curl -sSf -L \
             -H "Cache-Control: no-cache, no-store, must-revalidate" \
             -H "Pragma: no-cache" \
             "${GITHUB_RAW_SQL_URL}?ts=${CACHE_BUST}" \
             -o "$SQL_FILE_PATH" 2>/dev/null
        CURL_STATUS=$?
        set -e
    fi
fi

if [ ! -f "$SQL_FILE_PATH" ] || [ ! -s "$SQL_FILE_PATH" ]; then
    echo "❌ Erro fatal: Não foi possível obter o arquivo ${SQL_FILE_NAME}!"
    echo "Execute manualmente:"
    echo "  mkdir -p ${WORK_DIR} && cd ${WORK_DIR}"
    echo "  curl -sSf -L -H 'Accept: application/vnd.github.v3.raw' '${GITHUB_API_SQL_URL}' -o ${SQL_FILE_NAME}"
    exit 1
fi

echo "✅ Arquivo SQL pronto: ${SQL_FILE_PATH}"
echo ""

# ------------------------------------------------------------------------------
# 2. LOCALIZAÇÃO DO CONTÊINER POSTGRESQL DO SUPABASE NO DOCKER / EASYPANEL
# ------------------------------------------------------------------------------
echo "🔍 2. Localizando contêiner PostgreSQL do Supabase no VPS..."
DB_CONTAINER="${DB_CONTAINER:-${CONTAINER_LOCAL:-}}"

if [ -z "$DB_CONTAINER" ]; then
    # 1. Busca contêiner que contenha 'supabase' e 'db' no nome
    DB_CONTAINER=$(docker ps --format '{{.Names}}' | grep -i -- 'supabase' | grep -i -- 'db' | head -n 1 || true)
fi

if [ -z "$DB_CONTAINER" ]; then
    # 2. Busca padrão regex clássico
    DB_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E -- 'supabase.*db|supabase-db' | head -n 1 || true)
fi

if [ -z "$DB_CONTAINER" ]; then
    # 3. Fallback: qualquer contêiner com postgres/db excluindo frontends
    DB_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E -- 'postgres|db' | grep -v -E -- 'dpsjur-web|web|frontend' | head -n 1 || true)
fi

if [ -z "$DB_CONTAINER" ]; then
    echo "❌ Erro: Não foi possível localizar automaticamente o contêiner do PostgreSQL!"
    echo "Contêineres em execução:"
    docker ps --format 'table {{.Names}}\t{{.Status}}' || true
    echo ""
    echo "Informe manualmente executando:"
    echo "  DB_CONTAINER=nome_do_conteiner bash $0"
    exit 1
fi

echo "✅ Contêiner PostgreSQL localizado: $DB_CONTAINER"
echo ""

# ------------------------------------------------------------------------------
# 3. TESTE DE CONECTIVIDADE E DETERMINAÇÃO DE USUÁRIO / SENHA
# ------------------------------------------------------------------------------
echo "🔐 3. Testando conectividade com o banco de dados PostgreSQL..."

DB_USER="${POSTGRES_USER:-postgres}"
DB_NAME="${POSTGRES_DB:-postgres}"
LOCAL_DB_PASSWORD="${POSTGRES_PASSWORD:-${LOCAL_DB_PASSWORD:-}}"

# Função auxiliar para testar conexão com usuário e senha específicos
test_db_connection() {
    local u="$1"
    local p="$2"
    if [ -n "$p" ]; then
        docker exec -i -e PGPASSWORD="$p" "$DB_CONTAINER" psql -U "$u" -d "$DB_NAME" -tAc "SELECT 1;" 2>&1
    else
        docker exec -i "$DB_CONTAINER" psql -U "$u" -d "$DB_NAME" -tAc "SELECT 1;" 2>&1
    fi
}

CONN_OK=0

# Teste 3.1: Testar com usuário postgres e senha existente (se já fornecida em env) ou sem senha
set +e
TEST_OUT=$(test_db_connection "$DB_USER" "$LOCAL_DB_PASSWORD")
TEST_STATUS=$?
set -e

if [ $TEST_STATUS -eq 0 ] && [ "${TEST_OUT//[$'\t\r\n ']/}" = "1" ]; then
    CONN_OK=1
    echo "✅ Conexão bem-sucedida via usuário '$DB_USER'!"
else
    # Teste 3.2: Tentar supabase_admin
    set +e
    TEST_OUT_ADMIN=$(test_db_connection "supabase_admin" "$LOCAL_DB_PASSWORD")
    TEST_STATUS_ADMIN=$?
    set -e

    if [ $TEST_STATUS_ADMIN -eq 0 ] && [ "${TEST_OUT_ADMIN//[$'\t\r\n ']/}" = "1" ]; then
        DB_USER="supabase_admin"
        CONN_OK=1
        echo "✅ Conexão bem-sucedida via usuário 'supabase_admin'!"
    fi
fi

# Se não conectou direto, solicitar senha via prompt seguro (lendo do tty para suportar curl | bash)
if [ $CONN_OK -eq 0 ]; then
    echo "ℹ️  Conexão sem senha falhou ou exigiu autenticação."
    if [ -n "$TEST_OUT" ]; then
        echo "   [Diagnóstico 'postgres']: $(echo "$TEST_OUT" | tr '\n' ' ' | head -c 200)"
    fi
    if [ -n "${TEST_OUT_ADMIN:-}" ]; then
        echo "   [Diagnóstico 'supabase_admin']: $(echo "$TEST_OUT_ADMIN" | tr '\n' ' ' | head -c 200)"
    fi
    echo ""
    echo "🔑 Solicitando POSTGRES_PASSWORD do Supabase local (EasyPanel)..."

    # Abre descritor para leitura interativa do terminal mesmo quando stdin for pipe (curl | bash)
    TTY_IN="/dev/tty"
    if [ ! -r "$TTY_IN" ]; then
        TTY_IN="/dev/stdin"
    fi

    printf "👉 Digite a senha POSTGRES_PASSWORD do Supabase (EasyPanel): "
    stty -echo < "$TTY_IN" 2>/dev/null || true
    read -r LOCAL_DB_PASSWORD < "$TTY_IN"
    stty echo < "$TTY_IN" 2>/dev/null || true
    echo ""

    if [ -z "$LOCAL_DB_PASSWORD" ]; then
        echo "❌ Erro: Senha fornecida está vazia!"
        exit 1
    fi

    # Tenta com postgres + senha
    set +e
    TEST_OUT_PW=$(test_db_connection "postgres" "$LOCAL_DB_PASSWORD")
    TEST_STATUS_PW=$?
    set -e

    if [ $TEST_STATUS_PW -eq 0 ] && [ "${TEST_OUT_PW//[$'\t\r\n ']/}" = "1" ]; then
        DB_USER="postgres"
        CONN_OK=1
        echo "✅ Conexão autenticada com sucesso via usuário 'postgres'!"
    else
        # Tenta com supabase_admin + senha
        set +e
        TEST_OUT_ADMIN_PW=$(test_db_connection "supabase_admin" "$LOCAL_DB_PASSWORD")
        TEST_STATUS_ADMIN_PW=$?
        set -e

        if [ $TEST_STATUS_ADMIN_PW -eq 0 ] && [ "${TEST_OUT_ADMIN_PW//[$'\t\r\n ']/}" = "1" ]; then
            DB_USER="supabase_admin"
            CONN_OK=1
            echo "✅ Conexão autenticada com sucesso via usuário 'supabase_admin'!"
        else
            echo "❌ Erro fatal: Não foi possível autenticar no PostgreSQL com a senha fornecida!"
            echo "Detalhes do erro com 'postgres':"
            echo "$TEST_OUT_PW"
            echo "Detalhes do erro com 'supabase_admin':"
            echo "$TEST_OUT_ADMIN_PW"
            echo ""
            echo "Verifique no EasyPanel a variável POSTGRES_PASSWORD do serviço Supabase."
            exit 1
        fi
    fi
fi
echo ""

# ------------------------------------------------------------------------------
# 4. APLICAÇÃO DO SCRIPT SQL NO POSTGRESQL LOCAL
# ------------------------------------------------------------------------------
echo "🚀 4. Executando ${SQL_FILE_NAME} no PostgreSQL..."
echo "---------------------------------------------------------------------"

set +e
if [ -n "$LOCAL_DB_PASSWORD" ]; then
    docker exec -i -e PGPASSWORD="$LOCAL_DB_PASSWORD" "$DB_CONTAINER" \
        psql -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 < "$SQL_FILE_PATH"
    APPLY_STATUS=$?
else
    docker exec -i "$DB_CONTAINER" \
        psql -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 < "$SQL_FILE_PATH"
    APPLY_STATUS=$?
fi
set -e

echo "---------------------------------------------------------------------"
if [ $APPLY_STATUS -ne 0 ]; then
    echo "❌ Erro: Falha durante a execução do script SQL!"
    exit $APPLY_STATUS
fi

echo "✅ Script SQL executado com sucesso!"
echo ""

# ------------------------------------------------------------------------------
# 5. AUDITORIA FINAL DE CONFERÊNCIA
# ------------------------------------------------------------------------------
echo "📊 5. Conferência dos processos recriados no VPS..."

QUERY_VERIFICACAO="
SELECT 
    c.number AS processo,
    cl.name AS cliente,
    p.name AS responsavel,
    c.status,
    c.created_at::date AS data_criacao
FROM public.cases c
JOIN public.clients cl ON cl.id = c.\"clientId\"
LEFT JOIN public.profiles p ON p.id = c.\"responsibleId\"
WHERE c.number IN (
    'Adílio x Kasa Bella (indenizatória)',
    'Indenizatória contra a WX',
    'Indenizatória contra Zurich'
)
ORDER BY c.created_at;
"

if [ -n "$LOCAL_DB_PASSWORD" ]; then
    docker exec -i -e PGPASSWORD="$LOCAL_DB_PASSWORD" "$DB_CONTAINER" \
        psql -U "$DB_USER" -d "$DB_NAME" -c "$QUERY_VERIFICACAO"
else
    docker exec -i "$DB_CONTAINER" \
        psql -U "$DB_USER" -d "$DB_NAME" -c "$QUERY_VERIFICACAO"
fi

echo ""
echo "====================================================================="
echo "🎉 Recriação concluída com sucesso no VPS oficial!"
echo "   Os 3 processos agora estão visíveis no sistema:"
echo "   👉 https://sistema.advdouglaspsantos.com.br"
echo "====================================================================="
