#!/usr/bin/env bash
# ==============================================================================
# DPSjur / SBJur - Kit Pós-Migração VPS (Hostinger KVM 1 - IP 2.25.181.69)
# Script: docs/pos-migracao/05-executar-04-recriar-processos.sh
# Versão: v0.0.526
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

SCRIPT_VERSION="v0.0.526"
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

# Função auxiliar segura para testar conexão com usuário e senha específicos.
# NUNCA deixa o shell abortar via set -e ou pipefail; retorna o exit code real do psql.
# A saída combinada (stdout + stderr) é gravada na variável global TEST_OUT_RAW.
TEST_OUT_RAW=""
test_db_connection() {
    local u="$1"
    local p="$2"
    local code=0

    TEST_OUT_RAW=""
    if [ -n "$p" ]; then
        TEST_OUT_RAW=$(docker exec -i -e PGPASSWORD="$p" "$DB_CONTAINER" psql -U "$u" -d "$DB_NAME" -tAc "SELECT 1;" 2>&1) || code=$?
    else
        TEST_OUT_RAW=$(docker exec -i "$DB_CONTAINER" psql -U "$u" -d "$DB_NAME" -tAc "SELECT 1;" 2>&1) || code=$?
    fi
    return $code
}

# 3.0: Tentar extrair POSTGRES_PASSWORD do ambiente interno do próprio contêiner
# No EasyPanel / Supabase Docker Compose, a senha frequentemente reside nas env vars do contêiner db
if [ -z "$LOCAL_DB_PASSWORD" ]; then
    echo "   🔎 Verificando se POSTGRES_PASSWORD está configurada no ambiente do contêiner..."
    DETECTED_CONTAINER_PW=""
    set +e
    DETECTED_CONTAINER_PW=$(docker exec "$DB_CONTAINER" printenv POSTGRES_PASSWORD 2>/dev/null || true)
    if [ -z "$DETECTED_CONTAINER_PW" ]; then
        DETECTED_CONTAINER_PW=$(docker exec "$DB_CONTAINER" env 2>/dev/null | grep -E '^POSTGRES_PASSWORD=' | head -n 1 | cut -d '=' -f 2- || true)
    fi
    set -e

    if [ -n "$DETECTED_CONTAINER_PW" ]; then
        echo "   ℹ️  POSTGRES_PASSWORD detectada no contêiner. Testando autenticação..."
        if test_db_connection "$DB_USER" "$DETECTED_CONTAINER_PW"; then
            if [ "${TEST_OUT_RAW//[$'\t\r\n ']/}" = "1" ]; then
                LOCAL_DB_PASSWORD="$DETECTED_CONTAINER_PW"
                echo "   ✅ Autenticação bem-sucedida usando POSTGRES_PASSWORD do contêiner!"
            fi
        elif test_db_connection "supabase_admin" "$DETECTED_CONTAINER_PW"; then
            if [ "${TEST_OUT_RAW//[$'\t\r\n ']/}" = "1" ]; then
                DB_USER="supabase_admin"
                LOCAL_DB_PASSWORD="$DETECTED_CONTAINER_PW"
                echo "   ✅ Autenticação bem-sucedida usando usuário 'supabase_admin' e POSTGRES_PASSWORD do contêiner!"
            fi
        fi
    fi
fi

CONN_OK=0

# Se já conectou com a senha detectada do contêiner ou se já temos credencial funcional:
if [ -n "$LOCAL_DB_PASSWORD" ]; then
    if test_db_connection "$DB_USER" "$LOCAL_DB_PASSWORD" && [ "${TEST_OUT_RAW//[$'\t\r\n ']/}" = "1" ]; then
        CONN_OK=1
        echo "✅ Conexão bem-sucedida via usuário '$DB_USER'!"
    elif test_db_connection "supabase_admin" "$LOCAL_DB_PASSWORD" && [ "${TEST_OUT_RAW//[$'\t\r\n ']/}" = "1" ]; then
        DB_USER="supabase_admin"
        CONN_OK=1
        echo "✅ Conexão bem-sucedida via usuário 'supabase_admin'!"
    fi
fi

# Teste 3.1: Testar com usuário postgres sem senha (trust ou socket local) caso ainda não conectado
DIAG_POSTGRES=""
if [ $CONN_OK -eq 0 ]; then
    echo "   Tentando conexão direta com usuário '$DB_USER'..."
    if test_db_connection "$DB_USER" ""; then
        if [ "${TEST_OUT_RAW//[$'\t\r\n ']/}" = "1" ]; then
            CONN_OK=1
            echo "✅ Conexão direta bem-sucedida via usuário '$DB_USER'!"
        else
            DIAG_POSTGRES="$TEST_OUT_RAW"
        fi
    else
        DIAG_POSTGRES="$TEST_OUT_RAW"
    fi
fi

# Teste 3.2: Tentar supabase_admin sem senha caso ainda não conectado
DIAG_ADMIN=""
if [ $CONN_OK -eq 0 ]; then
    echo "   Tentando conexão direta com usuário 'supabase_admin'..."
    if test_db_connection "supabase_admin" ""; then
        if [ "${TEST_OUT_RAW//[$'\t\r\n ']/}" = "1" ]; then
            DB_USER="supabase_admin"
            CONN_OK=1
            echo "✅ Conexão direta bem-sucedida via usuário 'supabase_admin'!"
        else
            DIAG_ADMIN="$TEST_OUT_RAW"
        fi
    else
        DIAG_ADMIN="$TEST_OUT_RAW"
    fi
fi

# Se não conectou sem senha, solicitar interativamente ou emitir diagnóstico detalhado
if [ $CONN_OK -eq 0 ]; then
    echo ""
    echo "⚠️  Conexão inicial sem senha não foi aceita pelo PostgreSQL:"
    if [ -n "$DIAG_POSTGRES" ]; then
        echo "   [Diagnóstico 'postgres']:"
        echo "$DIAG_POSTGRES" | sed 's/^/      /'
    fi
    if [ -n "$DIAG_ADMIN" ]; then
        echo "   [Diagnóstico 'supabase_admin']:"
        echo "$DIAG_ADMIN" | sed 's/^/      /'
    fi
    echo ""

    # Determina se há terminal interativo disponível para digitação de senha
    CAN_READ_INTERACTIVE=0
    TTY_DEV=""
    if [ -t 0 ]; then
        CAN_READ_INTERACTIVE=1
        TTY_DEV="/dev/stdin"
    elif [ -r "/dev/tty" ] && [ -w "/dev/tty" ]; then
        CAN_READ_INTERACTIVE=1
        TTY_DEV="/dev/tty"
    fi

    if [ $CAN_READ_INTERACTIVE -eq 1 ] && [ -n "$TTY_DEV" ]; then
        echo "🔑 Solicitando POSTGRES_PASSWORD do Supabase local (EasyPanel)..."
        printf "👉 Digite a senha POSTGRES_PASSWORD do Supabase (EasyPanel): "
        stty -echo < "$TTY_DEV" 2>/dev/null || true
        PROMPT_PW=""
        read -r PROMPT_PW < "$TTY_DEV" 2>/dev/null || PROMPT_PW=""
        stty echo < "$TTY_DEV" 2>/dev/null || true
        echo ""

        if [ -n "$PROMPT_PW" ]; then
            LOCAL_DB_PASSWORD="$PROMPT_PW"

            # Tenta com postgres + senha
            if test_db_connection "postgres" "$LOCAL_DB_PASSWORD" && [ "${TEST_OUT_RAW//[$'\t\r\n ']/}" = "1" ]; then
                DB_USER="postgres"
                CONN_OK=1
                echo "✅ Conexão autenticada com sucesso via usuário 'postgres'!"
            elif test_db_connection "supabase_admin" "$LOCAL_DB_PASSWORD" && [ "${TEST_OUT_RAW//[$'\t\r\n ']/}" = "1" ]; then
                DB_USER="supabase_admin"
                CONN_OK=1
                echo "✅ Conexão autenticada com sucesso via usuário 'supabase_admin'!"
            else
                echo "❌ Erro: Não foi possível autenticar no PostgreSQL com a senha digitada!"
                echo "Saída do psql:"
                echo "$TEST_OUT_RAW" | sed 's/^/   /'
                echo ""
            fi
        else
            echo "⚠️  Nenhuma senha digitada no prompt interativo."
        fi
    fi

    # Se ainda assim não conectou, encerra com instruções cristalinas e nunca em silêncio
    if [ $CONN_OK -eq 0 ]; then
        echo "====================================================================="
        echo "❌ ERRO DE AUTENTICAÇÃO NO POSTGRESQL (Supabase local)"
        echo "====================================================================="
        echo "O banco de dados do contêiner '$DB_CONTAINER' exige senha."
        if [ $CAN_READ_INTERACTIVE -eq 0 ]; then
            echo "Aviso: Como o script foi executado via pipe ('curl | bash'), o terminal"
            echo "não estava em modo interativo direto para captura segura de senha."
        fi
        echo ""
        echo "Como resolver em 1 passo:"
        echo "  Exporte a senha do Supabase do EasyPanel antes de rodar o comando:"
        echo ""
        echo "  export POSTGRES_PASSWORD=\"sua_senha_aqui\""
        echo "  curl -sSf -L -H \"Accept: application/vnd.github.v3.raw\" \\"
        echo "    \"https://api.github.com/repos/dowspaulo-wq/migra--o-sistema-legal-desk-fg93i2kgl/contents/docs/pos-migracao/05-executar-04-recriar-processos.sh?ref=main\" \\"
        echo "    | bash"
        echo ""
        echo "Ou defina diretamente na mesma linha:"
        echo "  POSTGRES_PASSWORD=\"sua_senha_aqui\" bash -c '\$(curl -sSf -L -H \"Accept: application/vnd.github.v3.raw\" \"https://api.github.com/repos/dowspaulo-wq/migra--o-sistema-legal-desk-fg93i2kgl/contents/docs/pos-migracao/05-executar-04-recriar-processos.sh?ref=main\")'"
        echo ""
        echo "Onde encontrar a senha:"
        echo "  1. Acesse o EasyPanel no navegador (https://2.25.181.69:3000 ou domínio configurado)"
        echo "  2. Abra o projeto do Supabase -> Serviço 'supabase' (ou 'supabase-db')"
        echo "  3. Veja a variável 'POSTGRES_PASSWORD' na aba 'Environment'"
        echo "====================================================================="
        exit 1
    fi
fi
echo ""

# ------------------------------------------------------------------------------
# 4. APLICAÇÃO DO SCRIPT SQL NO POSTGRESQL LOCAL
# ------------------------------------------------------------------------------
echo "🚀 4. Executando ${SQL_FILE_NAME} no PostgreSQL..."
echo "---------------------------------------------------------------------"

APPLY_STATUS=0
if [ -n "$LOCAL_DB_PASSWORD" ]; then
    docker exec -i -e PGPASSWORD="$LOCAL_DB_PASSWORD" "$DB_CONTAINER" \
        psql -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 < "$SQL_FILE_PATH" || APPLY_STATUS=$?
else
    docker exec -i "$DB_CONTAINER" \
        psql -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 < "$SQL_FILE_PATH" || APPLY_STATUS=$?
fi

echo "---------------------------------------------------------------------"
if [ $APPLY_STATUS -ne 0 ]; then
    echo "❌ Erro: Falha durante a execução do script SQL (código de saída: $APPLY_STATUS)!"
    echo "Revise as mensagens acima emitidas pelo PostgreSQL para identificar o motivo."
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

set +e
if [ -n "$LOCAL_DB_PASSWORD" ]; then
    docker exec -i -e PGPASSWORD="$LOCAL_DB_PASSWORD" "$DB_CONTAINER" \
        psql -U "$DB_USER" -d "$DB_NAME" -c "$QUERY_VERIFICACAO"
    CONFIRM_STATUS=$?
else
    docker exec -i "$DB_CONTAINER" \
        psql -U "$DB_USER" -d "$DB_NAME" -c "$QUERY_VERIFICACAO"
    CONFIRM_STATUS=$?
fi
set -e

if [ $CONFIRM_STATUS -ne 0 ]; then
    echo "⚠️  Aviso: Consulta de conferência final retornou código $CONFIRM_STATUS."
fi

echo ""
echo "====================================================================="
echo "🎉 Recriação concluída com sucesso no VPS oficial!"
echo "   Os 3 processos agora estão visíveis no sistema:"
echo "   👉 https://sistema.advdouglaspsantos.com.br"
echo "====================================================================="
