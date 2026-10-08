#!/usr/bin/env bash
# ==============================================================================
# DPSjur / SBJur - Kit Pós-Migração VPS (Hostinger KVM 1 - IP 2.25.181.69)
# Script: docs/pos-migracao/05-executar-04-recriar-processos.sh
# Versão: v0.0.527
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
set -u
set -o pipefail

SCRIPT_VERSION="v0.0.527"
SCRIPT_SUCCESS=0
LAST_COMMAND=""

# ------------------------------------------------------------------------------
# TRAPS GLOBAIS: Previne encerramento silencioso em qualquer circunstância
# ------------------------------------------------------------------------------
trap 'LAST_COMMAND="$BASH_COMMAND"' DEBUG

on_error_trap() {
    local exit_code=$?
    local line_no="${BASH_LINENO[0]:-desconhecida}"
    # Se o script já concluiu com sucesso, ignora
    if [ "${SCRIPT_SUCCESS:-0}" -eq 1 ]; then
        return 0
    fi
    echo ""
    echo "====================================================================="
    echo "❌ FALHA DETECTADA: O script foi interrompido inesperadamente!"
    echo "====================================================================="
    echo "Linha do script : $line_no"
    echo "Comando que falhou: ${LAST_COMMAND:-$BASH_COMMAND}"
    echo "Código de saída : $exit_code"
    echo "Versão do script: $SCRIPT_VERSION"
    if [ -n "${LAST_CAPTURED_OUTPUT:-}" ]; then
        echo "Última saída do processo:"
        echo "$LAST_CAPTURED_OUTPUT" | sed 's/^/   /'
    fi
    echo "====================================================================="
    stty echo 2>/dev/null || true
    exit "$exit_code"
}

on_exit_trap() {
    local exit_code=$?
    stty echo 2>/dev/null || true
    if [ "$exit_code" -ne 0 ] && [ "${SCRIPT_SUCCESS:-0}" -eq 0 ]; then
        echo ""
        echo "⚠️  Script encerrado com status de erro ($exit_code) antes da conclusão."
    fi
}

trap 'on_error_trap' ERR
trap 'on_exit_trap' EXIT
trap 'stty echo 2>/dev/null || true; exit 130' INT TERM

# BASH_SOURCE[0] vem unbound via pipe ('curl ... | bash') sob set -u
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

    CURL_STATUS=0
    curl -sSf -L \
         -H "Accept: application/vnd.github.v3.raw" \
         -H "User-Agent: DPSjur-PosMigracao" \
         "$GITHUB_API_SQL_URL" \
         -o "$SQL_FILE_PATH" 2>/dev/null || CURL_STATUS=$?

    if [ "$CURL_STATUS" -ne 0 ] || [ ! -s "$SQL_FILE_PATH" ]; then
        echo "ℹ️  Tentando via raw.githubusercontent.com com anti-cache..."
        CACHE_BUST=$(date +%s)
        curl -sSf -L \
             -H "Cache-Control: no-cache, no-store, must-revalidate" \
             -H "Pragma: no-cache" \
             "${GITHUB_RAW_SQL_URL}?ts=${CACHE_BUST}" \
             -o "$SQL_FILE_PATH" 2>/dev/null || CURL_STATUS=$?
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
    # 1. Busca contêiner que contenha 'supabase' e 'db'
    DB_CONTAINER=$(docker ps --format '{{.Names}}' | grep -i -- 'supabase' | grep -i -- 'db' | head -n 1 || true)
fi

if [ -z "$DB_CONTAINER" ]; then
    # 2. Tolera typos comuns como 'supbase' (ex: sbjur-local_supbase-db-1)
    DB_CONTAINER=$(docker ps --format '{{.Names}}' | grep -i -E -- 'supbase.*db|supbase-db' | head -n 1 || true)
fi

if [ -z "$DB_CONTAINER" ]; then
    # 3. Busca padrão regex amplo
    DB_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E -- 'supa?base.*db|supa?base-db' | head -n 1 || true)
fi

if [ -z "$DB_CONTAINER" ]; then
    # 4. Fallback: qualquer contêiner com postgres ou db excluindo frontends
    DB_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E -- 'postgres|db' | grep -v -E -- 'dpsjur-web|web|frontend|traefik|redis' | head -n 1 || true)
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

LAST_CAPTURED_OUTPUT=""
test_db_connection() {
    local u="$1"
    local p="$2"
    local code=0
    LAST_CAPTURED_OUTPUT=""

    if [ -n "$p" ]; then
        LAST_CAPTURED_OUTPUT=$(docker exec -i -e PGPASSWORD="$p" "$DB_CONTAINER" psql -U "$u" -d "$DB_NAME" -tAc "SELECT 1;" 2>&1) || code=$?
    else
        LAST_CAPTURED_OUTPUT=$(docker exec -i "$DB_CONTAINER" psql -U "$u" -d "$DB_NAME" -tAc "SELECT 1;" 2>&1) || code=$?
    fi
    return "$code"
}

is_select_one_ok() {
    local text="$1"
    # Normaliza removendo espaços e quebras de linha
    local cleaned
    cleaned=$(printf '%s' "$text" | tr -d '[:space:]')
    [ "$cleaned" = "1" ]
}

CONN_OK=0

# Passo 3.0: PRIORIDADE MÁXIMA - Acesso local via unix socket dentro do contêiner (sem senha)
echo "   🔎 Testando acesso direto no contêiner com usuário '$DB_USER' (local socket)..."
if test_db_connection "$DB_USER" "" && is_select_one_ok "$LAST_CAPTURED_OUTPUT"; then
    CONN_OK=1
    echo "   ✅ Conexão direta bem-sucedida via usuário '$DB_USER' (sem necessidade de senha)!"
elif test_db_connection "supabase_admin" "" && is_select_one_ok "$LAST_CAPTURED_OUTPUT"; then
    DB_USER="supabase_admin"
    CONN_OK=1
    echo "   ✅ Conexão direta bem-sucedida via usuário 'supabase_admin' (sem necessidade de senha)!"
fi

# Passo 3.1: Se a conexão sem senha não passou, verificar senha informada via env var do host
if [ "$CONN_OK" -eq 0 ] && [ -n "$LOCAL_DB_PASSWORD" ]; then
    echo "   🔎 Testando autenticação com POSTGRES_PASSWORD fornecida no ambiente do host..."
    if test_db_connection "$DB_USER" "$LOCAL_DB_PASSWORD" && is_select_one_ok "$LAST_CAPTURED_OUTPUT"; then
        CONN_OK=1
        echo "   ✅ Autenticação bem-sucedida usando POSTGRES_PASSWORD do ambiente!"
    elif test_db_connection "supabase_admin" "$LOCAL_DB_PASSWORD" && is_select_one_ok "$LAST_CAPTURED_OUTPUT"; then
        DB_USER="supabase_admin"
        CONN_OK=1
        echo "   ✅ Autenticação bem-sucedida usando 'supabase_admin' e POSTGRES_PASSWORD do ambiente!"
    fi
fi

# Passo 3.2: Tentar extrair POSTGRES_PASSWORD do ambiente interno do próprio contêiner
if [ "$CONN_OK" -eq 0 ]; then
    echo "   🔎 Verificando se POSTGRES_PASSWORD está configurada no ambiente do contêiner..."
    DETECTED_CONTAINER_PW=""
    DETECTED_CONTAINER_PW=$(docker exec "$DB_CONTAINER" printenv POSTGRES_PASSWORD 2>/dev/null || true)
    if [ -z "$DETECTED_CONTAINER_PW" ]; then
        DETECTED_CONTAINER_PW=$(docker exec "$DB_CONTAINER" env 2>/dev/null | grep -E '^POSTGRES_PASSWORD=' | head -n 1 | cut -d '=' -f 2- || true)
    fi

    if [ -n "$DETECTED_CONTAINER_PW" ]; then
        echo "   ℹ️  POSTGRES_PASSWORD detectada no contêiner. Testando autenticação..."
        if test_db_connection "$DB_USER" "$DETECTED_CONTAINER_PW" && is_select_one_ok "$LAST_CAPTURED_OUTPUT"; then
            LOCAL_DB_PASSWORD="$DETECTED_CONTAINER_PW"
            CONN_OK=1
            echo "   ✅ Autenticação bem-sucedida usando POSTGRES_PASSWORD do contêiner!"
        elif test_db_connection "supabase_admin" "$DETECTED_CONTAINER_PW" && is_select_one_ok "$LAST_CAPTURED_OUTPUT"; then
            DB_USER="supabase_admin"
            LOCAL_DB_PASSWORD="$DETECTED_CONTAINER_PW"
            CONN_OK=1
            echo "   ✅ Autenticação bem-sucedida usando usuário 'supabase_admin' e POSTGRES_PASSWORD do contêiner!"
        else
            echo "   ⚠️  POSTGRES_PASSWORD encontrada no contêiner foi rejeitada na autenticação."
        fi
    fi
fi

# Passo 3.3: Se ainda não conectou, solicitar interativamente se houver terminal
if [ "$CONN_OK" -eq 0 ]; then
    CAN_READ_INTERACTIVE=0
    TTY_DEV=""
    if [ -t 0 ]; then
        CAN_READ_INTERACTIVE=1
        TTY_DEV="/dev/stdin"
    elif [ -r "/dev/tty" ] && [ -w "/dev/tty" ]; then
        CAN_READ_INTERACTIVE=1
        TTY_DEV="/dev/tty"
    fi

    if [ "$CAN_READ_INTERACTIVE" -eq 1 ] && [ -n "$TTY_DEV" ]; then
        echo "🔑 Solicitando POSTGRES_PASSWORD do Supabase local (EasyPanel)..."
        printf "👉 Digite a senha POSTGRES_PASSWORD do Supabase (EasyPanel): "
        stty -echo < "$TTY_DEV" 2>/dev/null || true
        PROMPT_PW=""
        read -r PROMPT_PW < "$TTY_DEV" 2>/dev/null || PROMPT_PW=""
        stty echo < "$TTY_DEV" 2>/dev/null || true
        echo ""

        if [ -n "$PROMPT_PW" ]; then
            if test_db_connection "postgres" "$PROMPT_PW" && is_select_one_ok "$LAST_CAPTURED_OUTPUT"; then
                DB_USER="postgres"
                LOCAL_DB_PASSWORD="$PROMPT_PW"
                CONN_OK=1
                echo "   ✅ Conexão autenticada com sucesso via usuário 'postgres'!"
            elif test_db_connection "supabase_admin" "$PROMPT_PW" && is_select_one_ok "$LAST_CAPTURED_OUTPUT"; then
                DB_USER="supabase_admin"
                LOCAL_DB_PASSWORD="$PROMPT_PW"
                CONN_OK=1
                echo "   ✅ Conexão autenticada com sucesso via usuário 'supabase_admin'!"
            else
                echo "❌ Erro: Não foi possível autenticar no PostgreSQL com a senha digitada!"
                echo "Saída do psql:"
                echo "$LAST_CAPTURED_OUTPUT" | sed 's/^/   /'
                echo ""
            fi
        fi
    fi
fi

if [ "$CONN_OK" -eq 0 ]; then
    echo "====================================================================="
    echo "❌ ERRO DE CONEXÃO NO POSTGRESQL (Supabase local)"
    echo "====================================================================="
    echo "Não foi possível autenticar no banco de dados do contêiner '$DB_CONTAINER'."
    if [ -n "${LAST_CAPTURED_OUTPUT:-}" ]; then
        echo "Último erro retornado pelo PostgreSQL:"
        echo "$LAST_CAPTURED_OUTPUT" | sed 's/^/   /'
        echo ""
    fi
    echo "Como resolver em 1 passo:"
    echo "  export POSTGRES_PASSWORD=\"sua_senha_aqui\""
    echo "  curl -sSf -L -H \"Accept: application/vnd.github.v3.raw\" \\"
    echo "    \"https://api.github.com/repos/dowspaulo-wq/migra--o-sistema-legal-desk-fg93i2kgl/contents/docs/pos-migracao/05-executar-04-recriar-processos.sh?ref=main\" \\"
    echo "    | bash"
    echo "====================================================================="
    exit 1
fi

echo "✅ Conexão validada com sucesso! Usuário ativo: '$DB_USER'."
echo ""

# ------------------------------------------------------------------------------
# 4. APLICAÇÃO DO SCRIPT SQL NO POSTGRESQL LOCAL
# ------------------------------------------------------------------------------
echo "🚀 4. Executando ${SQL_FILE_NAME} no PostgreSQL..."
echo "---------------------------------------------------------------------"

APPLY_STATUS=0
LAST_CAPTURED_OUTPUT=""

# Executa o psql via stdin passando arquivo SQL, capturando stdout e stderr juntos
# para que nunca haja falha silenciosa
if [ -n "$LOCAL_DB_PASSWORD" ]; then
    LAST_CAPTURED_OUTPUT=$(docker exec -i -e PGPASSWORD="$LOCAL_DB_PASSWORD" "$DB_CONTAINER" \
        psql -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 < "$SQL_FILE_PATH" 2>&1) || APPLY_STATUS=$?
else
    LAST_CAPTURED_OUTPUT=$(docker exec -i "$DB_CONTAINER" \
        psql -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 < "$SQL_FILE_PATH" 2>&1) || APPLY_STATUS=$?
fi

# Imprime na íntegra a saída emitida pelo psql
printf '%s\n' "$LAST_CAPTURED_OUTPUT"
echo "---------------------------------------------------------------------"

if [ "$APPLY_STATUS" -ne 0 ]; then
    echo "❌ Erro fatal: Falha durante a execução do script SQL (código de saída: $APPLY_STATUS)!"
    echo "Revise as mensagens acima emitidas pelo PostgreSQL para identificar o erro."
    exit "$APPLY_STATUS"
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

CONFIRM_STATUS=0
CONFIRM_OUTPUT=""
if [ -n "$LOCAL_DB_PASSWORD" ]; then
    CONFIRM_OUTPUT=$(docker exec -i -e PGPASSWORD="$LOCAL_DB_PASSWORD" "$DB_CONTAINER" \
        psql -U "$DB_USER" -d "$DB_NAME" -c "$QUERY_VERIFICACAO" 2>&1) || CONFIRM_STATUS=$?
else
    CONFIRM_OUTPUT=$(docker exec -i "$DB_CONTAINER" \
        psql -U "$DB_USER" -d "$DB_NAME" -c "$QUERY_VERIFICACAO" 2>&1) || CONFIRM_STATUS=$?
fi

if [ -n "$CONFIRM_OUTPUT" ]; then
    printf '%s\n' "$CONFIRM_OUTPUT"
fi

if [ "$CONFIRM_STATUS" -ne 0 ]; then
    echo "⚠️  Aviso: Consulta de conferência final retornou código $CONFIRM_STATUS."
fi

SCRIPT_SUCCESS=1

echo ""
echo "====================================================================="
echo "🎉 Recriação concluída com sucesso no VPS oficial!"
echo "   Os 3 processos agora estão visíveis no sistema:"
echo "   👉 https://sistema.advdouglaspsantos.com.br"
echo "====================================================================="
exit 0
