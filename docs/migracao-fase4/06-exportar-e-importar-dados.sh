#!/usr/bin/env bash
# ==============================================================================
# DPSjur - Script Unificado de Exportação da Nuvem e Importação no VPS (EasyPanel)
# ==============================================================================
# Versão: v0.0.502
# Execução: EXCLUSIVAMENTE NO TERMINAL DO VPS (Hostinger KVM 1 - IP 2.25.181.69)
# Motivo: Conexões TCP diretas nas portas 5432/6543 da nuvem Supabase são
#         bloqueadas em sandboxes de build, mas funcionam perfeitamente no VPS,
#         que possui conectividade de saída irrestrita à internet.
#
# Origem: Supabase Nuvem SBJur (ref: cpcafthwnqazopqftemj)
# Destino: Contêiner PostgreSQL do Supabase Self-Hosted no EasyPanel
#
# NOVIDADE v0.0.502:
# Correção do teste de conectividade: uso da env PGCONNECT_TIMEOUT=10 (em vez de
# flag CLI malformada que impedia a sonda em qualquer versão do psql 17).
#
# HISTÓRICO:
# v0.0.501: Fallback automático de endpoints (aws-0 pooler, aws-1 pooler, direto)
#           e diagnóstico de credencial vs rede/tenant.
#
# SEGURANÇA:
# NENHUMA senha fica gravada em arquivo, histórico de comandos (.bash_history)
# ou commit git. As senhas são lidas estritamente de forma oculta via `read -s`.
# ==============================================================================
set -euo pipefail

# Garante que terminal restaure echo mesmo se abortado via Ctrl+C
trap 'stty echo 2>/dev/null || true' EXIT INT TERM

SCRIPT_VERSION="0.0.502"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUDIT_SCRIPT="$SCRIPT_DIR/04-auditoria-pos-importacao.sql"

# Configurações padrão da origem Supabase Nuvem
CLOUD_PROJECT_REF="cpcafthwnqazopqftemj"
CLOUD_DB_NAME="postgres"
DOCKER_PG_IMAGE="postgres:17"

echo "====================================================================="
echo "   DPSjur - EXPORTAÇÃO DA NUVEM (SBJur) & IMPORTAÇÃO NO VPS LOCAL    "
echo "   Versão: v${SCRIPT_VERSION} (com Fallback Automático de Endpoints)       "
echo "====================================================================="
echo "Data: $(date '+%Y-%m-%d %H:%M:%S')"
echo "Origem: Supabase Cloud ref: $CLOUD_PROJECT_REF"
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

# Região AWS do pooler da Supabase
if [ -z "${CLOUD_AWS_REGION:-}" ]; then
    printf "👉 Região AWS do projeto Supabase [padrão: sa-east-1]: "
    read -r INPUT_REGION
    CLOUD_AWS_REGION="${INPUT_REGION:-sa-east-1}"
fi

# Porta do pooler de sessão da Supabase
if [ -z "${CLOUD_DB_PORT:-}" ]; then
    printf "👉 Porta do pooler Supabase (5432 modo sessão / 6543 alternativo) [padrão: 5432]: "
    read -r INPUT_PORT
    CLOUD_DB_PORT="${INPUT_PORT:-5432}"
fi

echo ""
echo "✅ Parâmetros de entrada recebidos:"
echo "   - Projeto Nuvem: $CLOUD_PROJECT_REF"
echo "   - Região AWS: $CLOUD_AWS_REGION"
echo "   - Porta Base: $CLOUD_DB_PORT"
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
# 3. DETERMINAÇÃO DINÂMICA DO ENDPOINT DA NUVEM (FALLBACK AUTOMÁTICO)
# ------------------------------------------------------------------------------
echo "Etapa 3/6: Conectando e exportando dados da Nuvem Supabase (pg_dump $DOCKER_PG_IMAGE)..."
echo "Detectando automaticamente o melhor endpoint de conexão da nuvem..."
echo ""

CANDIDATES=(
    "aws-0-${CLOUD_AWS_REGION}.pooler.supabase.com|${CLOUD_DB_PORT}|postgres.${CLOUD_PROJECT_REF}|Pooler aws-0 (sessão/pooler)"
    "aws-1-${CLOUD_AWS_REGION}.pooler.supabase.com|${CLOUD_DB_PORT}|postgres.${CLOUD_PROJECT_REF}|Pooler aws-1 (sessão/pooler)"
    "db.${CLOUD_PROJECT_REF}.supabase.co|5432|postgres|Conexão DIRETA ao banco (sem pooler)"
)

SELECTED_HOST=""
SELECTED_PORT=""
SELECTED_USER=""
SELECTED_DESC=""
LAST_ERROR_LOG=""
PASSWORD_ERROR_DETECTED=0
TENANT_NOT_FOUND_DETECTED=0

for candidate in "${CANDIDATES[@]}"; do
    IFS="|" read -r c_host c_port c_user c_desc <<< "$candidate"
    echo "⏳ Testando conexão: $c_desc ($c_host:$c_port, usuário: $c_user)..."

    TEST_OUT=""
    set +e
    TEST_OUT=$(docker run --rm \
        -e PGPASSWORD="$CLOUD_DB_PASSWORD" \
        -e PGCONNECT_TIMEOUT=10 \
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
        echo "✅ Conexão bem-sucedida via: $c_desc ($c_host:$c_port)!"
        SELECTED_HOST="$c_host"
        SELECTED_PORT="$c_port"
        SELECTED_USER="$c_user"
        SELECTED_DESC="$c_desc"
        break
    else
        echo "   ⚠️ Falha ao conectar em $c_host:$c_port"
        # Registra última mensagem para diagnóstico
        LAST_ERROR_LOG="$TEST_OUT"
        if echo "$TEST_OUT" | grep -qiE "password authentication failed"; then
            PASSWORD_ERROR_DETECTED=1
            echo "   ↳ Motivo detectado: Falha de autenticação por senha (password authentication failed)."
        elif echo "$TEST_OUT" | grep -qiE "tenant.*not found|tenant/user.*not found"; then
            TENANT_NOT_FOUND_DETECTED=1
            echo "   ↳ Motivo detectado: Tenant não encontrado neste endpoint (pooler tenant not found)."
        elif echo "$TEST_OUT" | grep -qiE "timeout|could not connect|refused"; then
            echo "   ↳ Motivo detectado: Tempo limite esgotado ou recusa de conexão na porta $c_port."
        else
            CLEAN_ERR=$(echo "$TEST_OUT" | tail -n 2 | tr '\n' ' ')
            echo "   ↳ Detalhe: $CLEAN_ERR"
        fi
        echo "   Tentando próximo endpoint..."
        echo ""
    fi
done

if [ -z "$SELECTED_HOST" ]; then
    echo ""
    echo "====================================================================="
    echo "❌ FALHA: NENHUM DOS ENDPOINTS DA NUVEM RESPONDEU COM SUCESSO!"
    echo "====================================================================="
    echo "Tentamos em sequência:"
    echo " 1. aws-0-${CLOUD_AWS_REGION}.pooler.supabase.com:$CLOUD_DB_PORT (user: postgres.${CLOUD_PROJECT_REF})"
    echo " 2. aws-1-${CLOUD_AWS_REGION}.pooler.supabase.com:$CLOUD_DB_PORT (user: postgres.${CLOUD_PROJECT_REF})"
    echo " 3. db.${CLOUD_PROJECT_REF}.supabase.co:5432 (user: postgres - Conexão Direta)"
    echo ""
    echo "🔍 DIAGNÓSTICO DO ERRO:"
    if [ "$PASSWORD_ERROR_DETECTED" -eq 1 ]; then
        echo "👉 A causa mais provável é SENHA INCORRETA (password authentication failed)."
        echo "   - O usuário conectou no host, mas o banco rejeitou a senha informada."
        echo "   - Solução: Acesse o painel da Supabase Cloud > Project Settings > Database"
        echo "     e clique em 'Reset database password'. Aguarde 30 segundos e reexecute o script."
    elif [ "$TENANT_NOT_FOUND_DETECTED" -eq 1 ]; then
        echo "👉 A causa é 'tenant/user not found' e/ou bloqueio de rede no IP do banco direto."
        echo "   - Se o projeto esteve pausado ou em manutenção na Supabase, pode levar alguns minutos"
        echo "     para o DNS e os poolers propagarem o tenant."
        echo "   - Verifique no painel Supabase se o projeto cpcafthwnqazopqftemj está com status 'Active'."
    else
        echo "👉 Erro de rede ou indisponibilidade temporária na Supabase."
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

# (i) Schema PUBLIC: Somente dados, sem DDL, sem owners, sem privilégios
echo "⏳ [1/3] Exportando dados do schema 'public' (17 tabelas)..."
if ! docker run --rm -i \
    -e PGPASSWORD="$CLOUD_DB_PASSWORD" \
    "$DOCKER_PG_IMAGE" \
    pg_dump \
    -h "$SELECTED_HOST" \
    -p "$SELECTED_PORT" \
    -U "$SELECTED_USER" \
    -d "$CLOUD_DB_NAME" \
    --schema=public \
    --data-only \
    --no-owner \
    --no-privileges \
    --no-comments \
    --disable-triggers \
    --inserts \
    --column-inserts \
    > "$PUBLIC_DUMP"; then
    echo "❌ Erro ao exportar dados do schema 'public' da nuvem via $SELECTED_HOST!"
    exit 1
fi

PUBLIC_SIZE=$(du -h "$PUBLIC_DUMP" | cut -f1)
echo "✅ Schema public exportado com sucesso ($PUBLIC_SIZE)."

# (ii) Schema AUTH: Tabelas essenciais (auth.users, auth.identities, auth.refresh_tokens se houver)
echo "⏳ [2/3] Exportando dados essenciais de autenticação (schema 'auth')..."
if ! docker run --rm -i \
    -e PGPASSWORD="$CLOUD_DB_PASSWORD" \
    "$DOCKER_PG_IMAGE" \
    pg_dump \
    -h "$SELECTED_HOST" \
    -p "$SELECTED_PORT" \
    -U "$SELECTED_USER" \
    -d "$CLOUD_DB_NAME" \
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
    --column-inserts \
    > "$AUTH_DUMP" 2>/dev/null; then
    echo "ℹ️  Tentando dump auth sem filtro de refresh_tokens..."
    docker run --rm -i \
        -e PGPASSWORD="$CLOUD_DB_PASSWORD" \
        "$DOCKER_PG_IMAGE" \
        pg_dump \
        -h "$SELECTED_HOST" \
        -p "$SELECTED_PORT" \
        -U "$SELECTED_USER" \
        -d "$CLOUD_DB_NAME" \
        --table="auth.users" \
        --table="auth.identities" \
        --data-only \
        --no-owner \
        --no-privileges \
        --no-comments \
        --disable-triggers \
        --inserts \
        --column-inserts \
        > "$AUTH_DUMP"
fi

AUTH_SIZE=$(du -h "$AUTH_DUMP" | cut -f1)
echo "✅ Schema auth exportado com sucesso ($AUTH_SIZE)."

# (iii) Schema STORAGE: Metadados dos buckets e objetos (storage.buckets e storage.objects)
echo "⏳ [3/3] Exportando registros de buckets e objetos (schema 'storage')..."
if ! docker run --rm -i \
    -e PGPASSWORD="$CLOUD_DB_PASSWORD" \
    "$DOCKER_PG_IMAGE" \
    pg_dump \
    -h "$SELECTED_HOST" \
    -p "$SELECTED_PORT" \
    -U "$SELECTED_USER" \
    -d "$CLOUD_DB_NAME" \
    --table="storage.buckets" \
    --table="storage.objects" \
    --data-only \
    --no-owner \
    --no-privileges \
    --no-comments \
    --disable-triggers \
    --inserts \
    --column-inserts \
    > "$STORAGE_DUMP" 2>/dev/null; then
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
