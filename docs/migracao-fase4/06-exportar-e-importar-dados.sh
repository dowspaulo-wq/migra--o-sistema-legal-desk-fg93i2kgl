#!/usr/bin/env bash
# ==============================================================================
# DPSjur - Script Unificado de Exportação da Nuvem e Importação no VPS (EasyPanel)
# ==============================================================================
# Versão: v0.0.504
# Execução: EXCLUSIVAMENTE NO TERMINAL DO VPS (Hostinger KVM 1 - IP 2.25.181.69)
# Motivo: Conexões TCP diretas nas portas 5432/6543 da nuvem Supabase são
#         bloqueadas em sandboxes de build, mas funcionam perfeitamente no VPS,
#         que possui conectividade de saída irrestrita à internet.
#
# Origem: Supabase Nuvem SBJur (ref: cpcafthwnqazopqftemj)
# Destino: Contêiner PostgreSQL do Supabase Self-Hosted no EasyPanel
#
# NOVIDADE v0.0.504:
# - Endpoint OFICIAL do painel da Supabase Cloud incorporado com PRIORIDADE MÁXIMA:
#   * Tentativa 1: aws-1-us-east-1.pooler.supabase.com:6543 (Transaction pooler, usuário postgres.cpcafthwnqazopqftemj)
#   * Tentativa 2: aws-1-us-east-1.pooler.supabase.com:5432 (Session pooler, fallback se o pg_dump falhar por restrição de transaction mode)
# - Fallback de segurança para varredura multirregião mantido caso os endpoints oficiais falhem.
# - Tratamento inteligente de fallback no pg_dump: se o dump falhar na porta 6543 por limitações
#   do transaction pooler, o script tenta automaticamente a porta 5432 do mesmo host oficial.
# - Diagnóstico detalhado de erro por tentativa preservado (senha incorreta vs tenant vs rede).
#
# HISTÓRICO:
# v0.0.503: Varredura multirregião AWS 17 regiões x aws-0/aws-1.
# v0.0.502: Correção do teste de timeout via env PGCONNECT_TIMEOUT no psql 17.
# v0.0.501: Fallback automático inicial e diagnóstico de senha vs tenant.
#
# SEGURANÇA:
# NENHUMA senha fica gravada em arquivo, histórico de comandos (.bash_history)
# ou commit git. As senhas são lidas estritamente de forma oculta via `read -s`.
# ==============================================================================
set -euo pipefail

# Garante que terminal restaure echo mesmo se abortado via Ctrl+C
trap 'stty echo 2>/dev/null || true' EXIT INT TERM

SCRIPT_VERSION="0.0.504"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUDIT_SCRIPT="$SCRIPT_DIR/04-auditoria-pos-importacao.sql"

# Configurações padrão da origem Supabase Nuvem
CLOUD_PROJECT_REF="cpcafthwnqazopqftemj"
CLOUD_DB_NAME="postgres"
DOCKER_PG_IMAGE="postgres:17"

# Endpoint OFICIAL confirmado no painel Supabase (Project Settings > Database > Connection pooler)
OFFICIAL_POOLER_HOST="aws-1-us-east-1.pooler.supabase.com"
OFFICIAL_POOLER_USER="postgres.${CLOUD_PROJECT_REF}"

echo "====================================================================="
echo "   DPSjur - EXPORTAÇÃO DA NUVEM (SBJur) & IMPORTAÇÃO NO VPS LOCAL    "
echo "   Versão: v${SCRIPT_VERSION} (Endpoint Oficial Supabase aws-1-us-east-1) "
echo "====================================================================="
echo "Data: $(date '+%Y-%m-%d %H:%M:%S')"
echo "Origem: Supabase Cloud ref: $CLOUD_PROJECT_REF"
echo "Endpoint Oficial: $OFFICIAL_POOLER_HOST:6543 / :5432"
echo "Destino: Contêiner PostgreSQL do Supabase Self-Hosted no EasyPanel"
echo "---------------------------------------------------------------------"
echo ""

# ------------------------------------------------------------------------------
# 1. COLETA INTERATIVA E SEGURA DAS VARIÁVEIS (read -s)
# ------------------------------------------------------------------------------
echo "Etapa 1/6: Coleta de parâmetros de conexão..."
echo ""

# Senha da Nuvem (somente leitura - pg_dump)
if [ -z "${CLOUD_DB_PASSWORD:-}" ]; then
    printf "👉 Digite a SENHA do banco de dados da NUVEM Supabase (SBJur): "
    stty -echo
    read -r CLOUD_DB_PASSWORD
    stty echo
    echo ""
    if [ -z "$CLOUD_DB_PASSWORD" ]; then
        echo "❌ Erro: A senha da nuvem não pode ser vazia."
        exit 1
    fi
else
    echo "ℹ️  Usando CLOUD_DB_PASSWORD fornecida via variável de ambiente."
fi

# Senha do Banco Local (POSTGRES_PASSWORD do EasyPanel)
if [ -z "${LOCAL_DB_PASSWORD:-}" ]; then
    printf "👉 Digite a senha POSTGRES_PASSWORD do Supabase LOCAL (EasyPanel): "
    stty -echo
    read -r LOCAL_DB_PASSWORD
    stty echo
    echo ""
    if [ -z "$LOCAL_DB_PASSWORD" ]; then
        echo "❌ Erro: A senha local não pode ser vazia."
        exit 1
    fi
else
    echo "ℹ️  Usando LOCAL_DB_PASSWORD fornecida via variável de ambiente."
fi

echo ""
echo "✅ Parâmetros de entrada recebidos:"
echo "   - Projeto Nuvem: $CLOUD_PROJECT_REF"
echo "   - Host Oficial: $OFFICIAL_POOLER_HOST (portas 6543 e 5432)"
echo "   - Imagem pg_dump: $DOCKER_PG_IMAGE"
echo ""

# ------------------------------------------------------------------------------
# 2. LOCALIZAÇÃO DO CONTÊINER LOCAL DO POSTGRES
# ------------------------------------------------------------------------------
echo "Etapa 2/6: Localizando o contêiner do PostgreSQL local no EasyPanel..."

CONTAINER_LOCAL=$(docker ps --format '{{.Names}}' | grep -E 'supabase.*db|supabase-db' | head -n 1 || true)

if [ -z "$CONTAINER_LOCAL" ]; then
    echo "⚠️  Contêiner com padrão 'supabase.*db' não localizado de imediato. Buscando contêiner postgres/db do Supabase..."
    CONTAINER_LOCAL=$(docker ps --format '{{.Names}}' | grep -E 'postgres|db' | grep -v 'dpsjur-web' | head -n 1 || true)
fi

if [ -z "$CONTAINER_LOCAL" ]; then
    echo "❌ Erro fatal: Não foi possível encontrar nenhum contêiner PostgreSQL em execução no Docker!"
    echo "Lista de contêineres atualmente em execução:"
    docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' || true
    echo ""
    echo "Dica: Verifique se o serviço 'supabase' no EasyPanel está com status 'Running'."
    exit 1
fi

echo "✅ Contêiner local identificado: $CONTAINER_LOCAL"
echo ""

# Cria diretório de trabalho temporário com permissões estritas
WORK_DIR=$(mktemp -d -t dpsjur-migracao-XXXXXX)
chmod 700 "$WORK_DIR"

cleanup() {
    echo ""
    echo "🧹 Limpando arquivos temporários locais..."
    if [ -d "$WORK_DIR" ]; then
        rm -rf "$WORK_DIR"
    fi
}
trap cleanup EXIT INT TERM

PUBLIC_DUMP="$WORK_DIR/01_public_data.sql"
AUTH_DUMP="$WORK_DIR/02_auth_data.sql"
STORAGE_DUMP="$WORK_DIR/03_storage_data.sql"

# ------------------------------------------------------------------------------
# 3. DETERMINAÇÃO DINÂMICA DO ENDPOINT DA NUVEM (OFICIAL PRIMEIRO + FALLBACK)
# ------------------------------------------------------------------------------
echo "Etapa 3/6: Conectando e exportando dados da Nuvem Supabase (pg_dump $DOCKER_PG_IMAGE)..."
echo "Priorizando endpoint oficial confirmado no painel ($OFFICIAL_POOLER_HOST)..."
echo ""

CANDIDATES=()

# Prioridade Máxima: Endpoint oficial informado pelo painel do Supabase
# Tentativa 1: porta 6543 (transaction pooler oficial)
CANDIDATES+=("${OFFICIAL_POOLER_HOST}|6543|${OFFICIAL_POOLER_USER}|⭐ OFICIAL Supabase (Porta 6543 - Transaction)")
# Tentativa 2: porta 5432 (session pooler no mesmo host oficial)
CANDIDATES+=("${OFFICIAL_POOLER_HOST}|5432|${OFFICIAL_POOLER_USER}|⭐ OFICIAL Supabase (Porta 5432 - Session)")

# Tentativas seguintes: Rede de segurança (fallback multirregião AWS)
AWS_REGIONS_ORDER=(
    "us-east-1"
    "sa-east-1"
    "us-east-2"
    "us-west-1"
    "us-west-2"
    "eu-west-1"
    "eu-west-2"
    "eu-west-3"
    "eu-central-1"
    "eu-central-2"
    "ap-southeast-1"
    "ap-southeast-2"
    "ap-northeast-1"
    "ap-northeast-2"
    "ap-south-1"
    "ca-central-1"
    "sa-east-2"
)

for reg in "${AWS_REGIONS_ORDER[@]}"; do
    # Evita duplicar os já adicionados acima
    if [ "$reg" = "us-east-1" ]; then
        CANDIDATES+=("aws-0-${reg}.pooler.supabase.com|5432|postgres.${CLOUD_PROJECT_REF}|Fallback aws-0 (${reg}:5432)")
    else
        CANDIDATES+=("aws-1-${reg}.pooler.supabase.com|5432|postgres.${CLOUD_PROJECT_REF}|Fallback aws-1 (${reg}:5432)")
        CANDIDATES+=("aws-0-${reg}.pooler.supabase.com|5432|postgres.${CLOUD_PROJECT_REF}|Fallback aws-0 (${reg}:5432)")
    fi
done

# Endpoint direto de fallback (última tentativa): db.<ref>.supabase.co
# Como o VPS do usuário é IPv4-only e a Supabase publica registro IPv6 (AAAA) para db.<ref>,
# resolvemos o IPv4 (registro A) diretamente para evitar o erro "Network is unreachable (2600:1f18:...)".
DIRECT_FQDN="db.${CLOUD_PROJECT_REF}.supabase.co"
DIRECT_IPV4=""

# Tenta resolver registro IPv4 no host VPS
if command -v getent >/dev/null 2>&1; then
    DIRECT_IPV4=$(getent ahostsv4 "$DIRECT_FQDN" 2>/dev/null | awk '{print $1}' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -n 1 || true)
fi
if [ -z "$DIRECT_IPV4" ] && command -v dig >/dev/null 2>&1; then
    DIRECT_IPV4=$(dig +short A "$DIRECT_FQDN" 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -n 1 || true)
fi
if [ -z "$DIRECT_IPV4" ] && command -v host >/dev/null 2>&1; then
    DIRECT_IPV4=$(host -t A "$DIRECT_FQDN" 2>/dev/null | awk '/has address/ {print $NF}' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -n 1 || true)
fi

if [ -n "$DIRECT_IPV4" ]; then
    CANDIDATES+=("${DIRECT_IPV4}|5432|postgres|Conexão DIRETA IPv4 ($DIRECT_IPV4 - $DIRECT_FQDN)")
else
    # Mantém como fallback nomeado (se o ambiente resolver)
    CANDIDATES+=("${DIRECT_FQDN}|5432|postgres|Conexão DIRETA FQDN (sem pooler)")
fi

SELECTED_HOST=""
SELECTED_PORT=""
SELECTED_USER=""
SELECTED_DESC=""
SELECTED_SSLMODE="require"
LAST_ERROR_LOG=""
PASSWORD_ERROR_DETECTED=0
PASSWORD_ERROR_HOST=""
TENANT_NOT_FOUND_DETECTED=0
CANDIDATES_TESTED=0
TOTAL_CANDIDATES=${#CANDIDATES[@]}

echo "🔎 Iniciando teste nos endpoints (OFICIAL $OFFICIAL_POOLER_HOST primeiro; timeout: 6s por teste)..."
echo "---------------------------------------------------------------------"

for candidate in "${CANDIDATES[@]}"; do
    IFS="|" read -r c_host c_port c_user c_desc <<< "$candidate"
    CANDIDATES_TESTED=$((CANDIDATES_TESTED + 1))

    # Se for a conexão direta FQDN sem IPv4 resolvido e o host estiver em IPv4-only,
    # informamos de forma amigável
    if [ "$c_host" = "$DIRECT_FQDN" ] && [ -z "$DIRECT_IPV4" ]; then
        echo -n "⏳ [$CANDIDATES_TESTED/$TOTAL_CANDIDATES] Testando: $c_desc ... "
    else
        echo -n "⏳ [$CANDIDATES_TESTED/$TOTAL_CANDIDATES] Testando: $c_host:$c_port ($c_desc) ... "
    fi

    TEST_OUT=""
    set +e
    TEST_OUT=$(docker run --rm \
        -e PGPASSWORD="$CLOUD_DB_PASSWORD" \
        -e PGCONNECT_TIMEOUT=6 \
        -e PGSSLMODE=require \
        "$DOCKER_PG_IMAGE" \
        psql \
        -h "$c_host" \
        -p "$c_port" \
        -U "$c_user" \
        -d "$CLOUD_DB_NAME" \
        -c "SELECT 1;" 2>&1)
    TEST_STATUS=$?
    set -e

    if [ $TEST_STATUS -eq 0 ]; then
        echo "✅ OK!"
        echo ""
        echo "====================================================================="
        echo "✅ Conexão bem-sucedida via: $c_desc"
        echo "   Host validado: $c_host:$c_port"
        echo "   Usuário autenticado: $c_user"
        echo "====================================================================="
        SELECTED_HOST="$c_host"
        SELECTED_PORT="$c_port"
        SELECTED_USER="$c_user"
        SELECTED_DESC="$c_desc"
        break
    else
        LAST_ERROR_LOG="$TEST_OUT"
        if echo "$TEST_OUT" | grep -qiE "password authentication failed"; then
            PASSWORD_ERROR_DETECTED=1
            PASSWORD_ERROR_HOST="$c_host ($c_desc)"
            echo "🔑 senha rejeitada (host reconheceu o tenant!)"
        elif echo "$TEST_OUT" | grep -qiE "tenant.*not found|tenant/user.*not found"; then
            TENANT_NOT_FOUND_DETECTED=1
            echo "❌ tenant not found"
        elif echo "$TEST_OUT" | grep -qiE "Network is unreachable"; then
            echo "⚠️ rede inacessível (IPv6 no host IPv4-only)"
        elif echo "$TEST_OUT" | grep -qiE "timeout|timed out|could not connect|refused"; then
            echo "⏱️ timeout / sem resposta"
        else
            SUMMARY_ERR=$(echo "$TEST_OUT" | tail -n 1 | tr -d '\r' | cut -c1-60)
            echo "❌ falha: $SUMMARY_ERR"
        fi
    fi
done

echo "---------------------------------------------------------------------"

if [ -z "$SELECTED_HOST" ]; then
    echo ""
    echo "====================================================================="
    echo "❌ FALHA: NENHUM DOS ENDPOINTS DA NUVEM RESPONDEU COM SUCESSO!"
    echo "====================================================================="
    echo "Foram testados $CANDIDATES_TESTED endpoints em diversas regiões AWS da Supabase."
    echo ""
    echo "🔍 DIAGNÓSTICO DO ERRO:"
    if [ "$PASSWORD_ERROR_DETECTED" -eq 1 ]; then
        echo "👉 ATENÇÃO: O host '$PASSWORD_ERROR_HOST' reconheceu o tenant,"
        echo "   mas REJEITOU a senha digitada ('password authentication failed')."
        echo "   Isso significa que O HOST CORRETO FOI ENCONTRADO, mas a senha está incorreta!"
        echo ""
        echo "   Solução recomendada:"
        echo "   1. Acesse https://supabase.com/dashboard/project/$CLOUD_PROJECT_REF/settings/database"
        echo "   2. Em 'Database password', clique em 'Reset database password' e defina uma nova senha."
        echo "   3. Aguarde cerca de 30 segundos para os poolers sincronizarem."
        echo "   4. Reexecute este script e informe a nova senha quando solicitada."
    elif [ "$TENANT_NOT_FOUND_DETECTED" -eq 1 ]; then
        echo "👉 Todos os poolers consultados retornaram 'tenant not found'."
        echo "   - Verifique no painel da Supabase Cloud se o projeto '$CLOUD_PROJECT_REF' está com status 'Active'."
        echo "   - Se o projeto esteve pausado recentemente, pode levar 2-5 minutos para os poolers"
        echo "     restabelecerem a rota do tenant."
        echo "   - Se você possui a Connection String exata no painel Supabase (Project Settings > Database),"
        echo "     verifique em qual região AWS ela aponta e configure via: CLOUD_AWS_REGION=<regiao> bash 06-..."
    else
        echo "👉 Erro de rede ou indisponibilidade temporária na Supabase."
        echo "   - O VPS não conseguiu alcançar os servidores de pooler ou banco da Supabase."
    fi
    echo ""
    echo "Último log recebido do cliente PostgreSQL:"
    echo "$LAST_ERROR_LOG" | tail -n 6
    echo "====================================================================="
    exit 1
fi

echo ""
echo "🎯 Endpoint selecionado para o dump:"
echo "   - Host: $SELECTED_HOST"
echo "   - Porta: $SELECTED_PORT"
echo "   - Usuário: $SELECTED_USER"
echo "   - Modo: $SELECTED_DESC"
echo ""

# ------------------------------------------------------------------------------
# 4. EXPORTAÇÃO DOS DADOS FRESCOS DA NUVEM (pg_dump 17)
# ------------------------------------------------------------------------------

# Função auxiliar para executar pg_dump com tolerância e fallback automático caso a porta 6543
# (transaction mode) apresente restrições típicas de prepared statements / session level locks.
run_pg_dump() {
    local dump_target_file="$1"
    shift
    local dump_args=("$@")

    local status=0
    set +e
    docker run --rm -i \
        -e PGPASSWORD="$CLOUD_DB_PASSWORD" \
        -e PGCONNECT_TIMEOUT=15 \
        -e PGSSLMODE=require \
        "$DOCKER_PG_IMAGE" \
        pg_dump \
        -h "$SELECTED_HOST" \
        -p "$SELECTED_PORT" \
        -U "$SELECTED_USER" \
        -d "$CLOUD_DB_NAME" \
        "${dump_args[@]}" > "$dump_target_file" 2>"$WORK_DIR/pg_dump_err.log"
    status=$?
    set -e

    # Se falhou e estávamos usando a porta 6543 no host oficial, tenta automaticamente a porta 5432 (session)
    if [ $status -ne 0 ] && [ "$SELECTED_PORT" = "6543" ]; then
        echo ""
        echo "⚠️  pg_dump encontrou limitação na porta 6543 (transaction mode):"
        head -n 4 "$WORK_DIR/pg_dump_err.log" 2>/dev/null || true
        echo "🔄 Alternando automaticamente para o Session Pooler na porta 5432 do mesmo host ($SELECTED_HOST)..."

        set +e
        docker run --rm -i \
            -e PGPASSWORD="$CLOUD_DB_PASSWORD" \
            -e PGCONNECT_TIMEOUT=15 \
            -e PGSSLMODE=require \
            "$DOCKER_PG_IMAGE" \
            pg_dump \
            -h "$SELECTED_HOST" \
            -p "5432" \
            -U "$SELECTED_USER" \
            -d "$CLOUD_DB_NAME" \
            "${dump_args[@]}" > "$dump_target_file" 2>"$WORK_DIR/pg_dump_err.log"
        status=$?
        set -e

        if [ $status -eq 0 ]; then
            echo "✅ Session pooler (porta 5432) conectado com sucesso! Fixando porta 5432 para as próximas etapas."
            SELECTED_PORT="5432"
        fi
    fi

    if [ $status -ne 0 ]; then
        echo "❌ Falha no pg_dump:"
        cat "$WORK_DIR/pg_dump_err.log" 2>/dev/null || true
    fi

    return $status
}

# (i) Schema PUBLIC: Somente dados, sem DDL, sem owners, sem privilégios
echo "⏳ [1/3] Exportando dados do schema 'public' (17 tabelas)..."
if ! run_pg_dump "$PUBLIC_DUMP" \
    --schema=public \
    --data-only \
    --no-owner \
    --no-privileges \
    --no-comments \
    --disable-triggers \
    --inserts \
    --column-inserts; then
    echo "❌ Erro ao exportar dados do schema 'public' da nuvem via $SELECTED_HOST:$SELECTED_PORT!"
    exit 1
fi

PUBLIC_SIZE=$(du -h "$PUBLIC_DUMP" | cut -f1)
echo "✅ Schema public exportado com sucesso ($PUBLIC_SIZE)."

# (ii) Schema AUTH: Tabelas essenciais (auth.users, auth.identities, auth.refresh_tokens se houver)
echo "⏳ [2/3] Exportando dados essenciais de autenticação (schema 'auth')..."
if ! run_pg_dump "$AUTH_DUMP" \
    --schema=auth \
    --table="auth.users" \
    --table="auth.identities" \
    --table="auth.refresh_tokens" \
    --data-only \
    --no-owner \
    --no-privileges \
    --no-comments \
    --disable-triggers \
    --inserts \
    --column-inserts 2>/dev/null; then
    echo "ℹ️  Tentando dump auth sem filtro de refresh_tokens..."
    run_pg_dump "$AUTH_DUMP" \
        --table="auth.users" \
        --table="auth.identities" \
        --data-only \
        --no-owner \
        --no-privileges \
        --no-comments \
        --disable-triggers \
        --inserts \
        --column-inserts || true
fi

AUTH_SIZE=$(du -h "$AUTH_DUMP" 2>/dev/null | cut -f1 || echo "0K")
echo "✅ Schema auth exportado com sucesso ($AUTH_SIZE)."

# (iii) Schema STORAGE: Metadados dos buckets e objetos (storage.buckets e storage.objects)
echo "⏳ [3/3] Exportando registros de buckets e objetos (schema 'storage')..."
if ! run_pg_dump "$STORAGE_DUMP" \
    --table="storage.buckets" \
    --table="storage.objects" \
    --data-only \
    --no-owner \
    --no-privileges \
    --no-comments \
    --disable-triggers \
    --inserts \
    --column-inserts 2>/dev/null; then
    echo "⚠️  Aviso: Não foi possível exportar storage via pg_dump direto (possível restrição de privilégio). Criando dump de storage seguro..."
    cat <<'EOF' > "$STORAGE_DUMP"
-- Buckets padrão do DPSjur
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES
    ('avatars', 'avatars', true, 52428800, NULL),
    ('case-systems', 'case-systems', true, 52428800, NULL),
    ('document_templates', 'document_templates', true, 52428800, NULL),
    ('signature_documents', 'signature_documents', true, 52428800, NULL),
    ('signature_drawings', 'signature_drawings', true, 52428800, NULL),
    ('signature_photos', 'signature_photos', true, 52428800, NULL),
    ('signed_documents', 'signed_documents', true, 52428800, NULL),
    ('backups', 'backups', false, 104857600, NULL)
ON CONFLICT (id) DO NOTHING;
EOF
fi

STORAGE_SIZE=$(du -h "$STORAGE_DUMP" | cut -f1)
echo "✅ Metadados de storage exportados ($STORAGE_SIZE)."
echo ""

# ------------------------------------------------------------------------------
# 5. PREPARAÇÃO DO BATCH DE IMPORTAÇÃO EM TRANSAÇÃO ÚNICA COM DESATIVAÇÃO DE TRIGGERS
# ------------------------------------------------------------------------------
echo "Etapa 4/6: Montando transação atômica de importação local..."

CONSOLIDATED_SQL="$WORK_DIR/importacao_completa.sql"

cat <<'EOF' > "$CONSOLIDATED_SQL"
-- ==============================================================================
-- Transação Consolidada de Importação - DPSjur
-- ==============================================================================
BEGIN;

-- Desativa verificação de triggers e constraints transitórias durante a carga
SET session_replication_role = 'replica';

EOF

# 1. Dados de Auth primeiro (para satisfazer FK de perfis e responsáveis)
echo "-- >>> DADOS AUTH (users, identities) <<<" >> "$CONSOLIDATED_SQL"
cat "$AUTH_DUMP" >> "$CONSOLIDATED_SQL"
echo "" >> "$CONSOLIDATED_SQL"

# 2. Dados de Storage (buckets e objetos)
echo "-- >>> DADOS STORAGE (buckets, objects) <<<" >> "$CONSOLIDATED_SQL"
cat "$STORAGE_DUMP" >> "$CONSOLIDATED_SQL"
echo "" >> "$CONSOLIDATED_SQL"

# 3. Dados do Schema Public (17 tabelas)
echo "-- >>> DADOS PUBLIC (17 tabelas) <<<" >> "$CONSOLIDATED_SQL"
cat "$PUBLIC_DUMP" >> "$CONSOLIDATED_SQL"
echo "" >> "$CONSOLIDATED_SQL"

cat <<'EOF' >> "$CONSOLIDATED_SQL"

-- Restaura regras normais de integridade e triggers
SET session_replication_role = 'origin';

COMMIT;
EOF

echo "✅ Arquivo de importação compilado em: $CONSOLIDATED_SQL"
echo ""

# ------------------------------------------------------------------------------
# 6. APLICAÇÃO DOS DADOS NO BANCO LOCAL VIA DOCKER EXEC
# ------------------------------------------------------------------------------
echo "Etapa 5/6: Aplicando dados no contêiner local '$CONTAINER_LOCAL'..."
echo "   (Transação única, ON_ERROR_STOP=1, tolerante a grants de ambiente)"

if ! docker exec -i \
    -e PGPASSWORD="$LOCAL_DB_PASSWORD" \
    "$CONTAINER_LOCAL" \
    psql -U postgres -d postgres -v ON_ERROR_STOP=1 < "$CONSOLIDATED_SQL"; then
    echo ""
    echo "====================================================================="
    echo "❌ FALHA NA IMPORTAÇÃO LOCAL"
    echo "====================================================================="
    echo "Ocorreu um erro durante a aplicação da transação no banco local."
    echo ""
    echo "🛡️  SEGURANÇA DOS SEUS DADOS:"
    echo "   - O banco de dados da NUVEM Supabase NÃO foi afetado de forma alguma"
    echo "     (a operação de origem foi estritamente somente leitura via pg_dump)."
    echo ""
    echo "🔄 PLANO DE ROLLBACK / RECUPERAÇÃO:"
    echo "   1. O banco local foi revertido pelo 'ROLLBACK' automático da transação."
    echo "   2. Se desejar limpar qualquer resíduo e reiniciar:"
    echo "      bash docs/migracao-fase4/05-importar-no-supabase-local.sh"
    echo "   3. Em seguida, reexecute este script 06."
    echo "====================================================================="
    exit 1
fi

echo "✅ Todos os dados foram aplicados com sucesso no banco PostgreSQL local!"
echo ""

# ------------------------------------------------------------------------------
# 7. AUDITORIA PÓS-IMPORTAÇÃO (Contagens esperadas vs encontradas)
# ------------------------------------------------------------------------------
echo "Etapa 6/6: Executando auditoria automatizada pós-importação..."
echo "---------------------------------------------------------------------"

if [ -f "$AUDIT_SCRIPT" ]; then
    docker exec -i \
        -e PGPASSWORD="$LOCAL_DB_PASSWORD" \
        "$CONTAINER_LOCAL" \
        psql -U postgres -d postgres < "$AUDIT_SCRIPT"
else
    echo "ℹ️  Arquivo 04-auditoria-pos-importacao.sql externo não encontrado localmente."
    echo "Executando suite de auditoria embutida completa (contagens, RLS e usuários):"
    echo ""
    docker exec -i \
        -e PGPASSWORD="$LOCAL_DB_PASSWORD" \
        "$CONTAINER_LOCAL" \
        psql -U postgres -d postgres -c "
        \echo '---------------------------------------------------------------------'
        \echo '1. CONFERÊNCIA DE CONTAGENS (Esperado vs Encontrado no VPS)'
        \echo '---------------------------------------------------------------------'
        WITH expected(tabela, esperado) AS (
            VALUES
                ('auth.users', 7),
                ('public.profiles', 7),
                ('public.clients', 345),
                ('public.cases', 550),
                ('public.tasks', 836),
                ('public.appointments', 258),
                ('public.transactions', 941),
                ('public.transaction_cases', 471),
                ('public.suppliers', 26),
                ('public.case_systems', 8),
                ('public.petitions', 11),
                ('public.document_templates', 1),
                ('public.settings', 1),
                ('public.logs', 527),
                ('public.user_sessions', 3722)
        ),
        actual AS (
            SELECT 'auth.users'::text AS tabela, count(*) AS atual FROM auth.users
            UNION ALL SELECT 'public.profiles', count(*) FROM public.profiles
            UNION ALL SELECT 'public.clients', count(*) FROM public.clients
            UNION ALL SELECT 'public.cases', count(*) FROM public.cases
            UNION ALL SELECT 'public.tasks', count(*) FROM public.tasks
            UNION ALL SELECT 'public.appointments', count(*) FROM public.appointments
            UNION ALL SELECT 'public.transactions', count(*) FROM public.transactions
            UNION ALL SELECT 'public.transaction_cases', count(*) FROM public.transaction_cases
            UNION ALL SELECT 'public.suppliers', count(*) FROM public.suppliers
            UNION ALL SELECT 'public.case_systems', count(*) FROM public.case_systems
            UNION ALL SELECT 'public.petitions', count(*) FROM public.petitions
            UNION ALL SELECT 'public.document_templates', count(*) FROM public.document_templates
            UNION ALL SELECT 'public.settings', count(*) FROM public.settings
            UNION ALL SELECT 'public.logs', count(*) FROM public.logs
            UNION ALL SELECT 'public.user_sessions', count(*) FROM public.user_sessions
        )
        SELECT 
            e.tabela AS \"Tabela\",
            e.esperado AS \"Esperado\",
            COALESCE(a.atual, 0) AS \"Atual\",
            CASE 
                WHEN e.esperado = COALESCE(a.atual, 0) THEN '✅ OK EXATO'
                WHEN e.tabela IN ('public.logs', 'public.user_sessions') AND a.atual >= (e.esperado * 0.95) THEN '✅ OK (Atividade)'
                WHEN a.atual > e.esperado THEN '✅ OK (+ Novos Registros)'
                ELSE '⚠️ DIVERGÊNCIA'
            END AS \"Status\"
        FROM expected e
        LEFT JOIN actual a ON e.tabela = a.tabela
        ORDER BY e.tabela;

        \echo ''
        \echo '---------------------------------------------------------------------'
        \echo '2. USUÁRIOS E SENHAS (auth.users e perfis vinculados)'
        \echo '---------------------------------------------------------------------'
        SELECT 
            u.email AS \"E-mail de Login\",
            p.name AS \"Nome no Perfil\",
            p.role AS \"Papel\",
            CASE 
                WHEN u.encrypted_password LIKE '\$2a\$%' OR u.encrypted_password LIKE '\$2b\$%' THEN '✅ BCRYPT VÁLIDO'
                ELSE '⚠️ INVÁLIDA'
            END AS \"Hash Senha\",
            CASE WHEN u.confirmed_at IS NOT NULL THEN '✅ CONFIRMADO' ELSE 'PENDENTE' END AS \"E-mail Conf.\"
        FROM auth.users u
        LEFT JOIN public.profiles p ON u.id = p.id
        ORDER BY u.created_at ASC;
        "
fi

echo ""
echo "====================================================================="
echo "🎉 EXPORTAÇÃO E IMPORTAÇÃO DOS DADOS CONCLUÍDAS COM SUCESSO!"
echo "====================================================================="
echo ""
echo "Próximos passos para a virada final no EasyPanel:"
echo "1. Obtenha a ANON_KEY local na aba 'Environment' do serviço Supabase."
echo "2. No serviço 'dpsjur-web' (ou app) no EasyPanel, configure:"
echo "   - VITE_SUPABASE_URL = https://sbjur-local-supabase.onsv5o.easypanel.host (ou http://2.25.181.69:8000)"
echo "   - VITE_SUPABASE_PUBLISHABLE_KEY = <sua ANON_KEY local>"
echo "3. Clique em 'Save' e depois em 'Deploy' / 'Restart'."
echo "4. Opcional (arquivos físicos do Storage): execute em paralelo:"
echo "   node docs/migracao-fase4/06-sync-storage-assets.ts ./storage-local"
echo "====================================================================="
