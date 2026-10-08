#!/usr/bin/env bash
# ==============================================================================
# DPSjur / SBJur - Kit Pós-Migração VPS (Hostinger KVM 1 - IP 2.25.181.69)
# Script: docs/pos-migracao/06-executar-migracao-tarefas-automaticas.sh
# Versão: v0.0.533
# ==============================================================================
# Execução no VPS:
# curl -sSf -L -H "Accept: application/vnd.github.v3.raw" \
#   "https://api.github.com/repos/dowspaulo-wq/migra--o-sistema-legal-desk-fg93i2kgl/contents/docs/pos-migracao/06-executar-migracao-tarefas-automaticas.sh?ref=main" \
#   | bash
# ==============================================================================

SCRIPT_VERSION="v0.0.533"
WORK_DIR="/root/sbjur-pos-migracao"
SQL_FILE_NAME="20261008150000_create_auto_tasks_on_client_creation.sql"
SQL_FILE_PATH="${WORK_DIR}/${SQL_FILE_NAME}"

GITHUB_API_SQL_URL="https://api.github.com/repos/dowspaulo-wq/migra--o-sistema-legal-desk-fg93i2kgl/contents/supabase/migrations/${SQL_FILE_NAME}?ref=main"
GITHUB_RAW_SQL_URL="https://raw.githubusercontent.com/dowspaulo-wq/migra--o-sistema-legal-desk-fg93i2kgl/main/supabase/migrations/${SQL_FILE_NAME}"

# (a) Banner
echo "====================================================================="
echo " DPSjur / SBJur - Migração: Tarefas Automáticas no VPS              "
echo " Versão: ${SCRIPT_VERSION}"
echo "====================================================================="
echo "Data: $(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || true)"
echo "Host: $(hostname 2>/dev/null || echo 'VPS')"
echo ""

# (b) Garantir arquivo SQL em /root/sbjur-pos-migracao/
echo "📁 1. Verificando arquivo SQL (${SQL_FILE_NAME})..."
mkdir -p "${WORK_DIR}" || {
    echo "❌ Erro: Não foi possível criar o diretório ${WORK_DIR}."
    exit 1
}

# Se o arquivo já existir no caminho relativo local do repositório, copia diretamente
if [ ! -s "${SQL_FILE_PATH}" ]; then
    LOCAL_CANDIDATE="$(dirname "$0")/../../supabase/migrations/${SQL_FILE_NAME}"
    if [ -s "${LOCAL_CANDIDATE}" ]; then
        echo "ℹ️  Copiando arquivo SQL a partir do repositório local..."
        cp "${LOCAL_CANDIDATE}" "${SQL_FILE_PATH}" 2>/dev/null || true
    fi
fi

if [ ! -s "${SQL_FILE_PATH}" ]; then
    echo "⏳ Arquivo local ausente ou vazio. Baixando do repositório GitHub..."
    curl -sSf -L \
        -H "Accept: application/vnd.github.v3.raw" \
        -H "User-Agent: DPSjur-PosMigracao" \
        "${GITHUB_API_SQL_URL}" \
        -o "${SQL_FILE_PATH}" 2>/dev/null || true

    if [ ! -s "${SQL_FILE_PATH}" ]; then
        echo "ℹ️  Tentando download alternativo via raw.githubusercontent.com..."
        CACHE_BUST=$(date +%s 2>/dev/null || echo "1")
        curl -sSf -L \
            -H "Cache-Control: no-cache, no-store, must-revalidate" \
            "${GITHUB_RAW_SQL_URL}?ts=${CACHE_BUST}" \
            -o "${SQL_FILE_PATH}" 2>/dev/null || true
    fi
fi

if [ ! -s "${SQL_FILE_PATH}" ]; then
    echo "❌ Erro fatal: Não foi possível baixar o arquivo SQL ${SQL_FILE_NAME}!"
    echo "Execute manualmente:"
    echo "  mkdir -p ${WORK_DIR} && cd ${WORK_DIR}"
    echo "  curl -sSf -L -H 'Accept: application/vnd.github.v3.raw' '${GITHUB_API_SQL_URL}' -o ${SQL_FILE_NAME}"
    exit 1
fi
echo "✅ Arquivo SQL pronto: ${SQL_FILE_PATH}"
echo ""

# (c) Localizar contêiner PostgreSQL via docker ps
echo "🔍 2. Localizando contêiner PostgreSQL do Supabase..."
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

# (d) Teste de conexão simples e direto (sem captura em variável)
echo "🔐 3. Testando conectividade com o banco de dados..."
if docker exec "${DB_CONTAINER}" psql -U postgres -d postgres -tAc "SELECT 1;" >/dev/null 2>&1; then
    echo "✅ Conexão direta bem-sucedida via usuário 'postgres' (local socket)!"
else
    echo "❌ Erro: Falha ao conectar ao banco de dados no contêiner '${DB_CONTAINER}' com usuário 'postgres'."
    echo "Verifique se o contêiner está pronto ou se o serviço do banco está ativo."
    exit 1
fi
echo ""

# (e) Aplicar o SQL deixando stdout/stderr fluírem direto para o terminal
echo "🚀 4. Aplicando ${SQL_FILE_NAME} no PostgreSQL..."
echo "---------------------------------------------------------------------"
docker exec -i "${DB_CONTAINER}" psql -U postgres -d postgres -v ON_ERROR_STOP=1 < "${SQL_FILE_PATH}"
rc=$?
echo "---------------------------------------------------------------------"

if [ $rc -ne 0 ]; then
    echo "❌ Erro fatal: O comando psql encerrou com código de erro ${rc}!"
    echo "Verifique os erros apontados pelo PostgreSQL acima."
    exit $rc
fi
echo "✅ Script SQL executado com sucesso!"
echo ""

# (f) Tabela de conferência simples
echo "📊 5. Tabela de conferência do schema e das funções no VPS..."
echo ""

echo ">> 1. Verificação das funções criadas em pg_proc:"
docker exec -i "${DB_CONTAINER}" psql -U postgres -d postgres -c "
SELECT 
    n.nspname AS schema,
    p.proname AS funcao,
    pg_get_function_identity_arguments(p.oid) AS argumentos,
    CASE WHEN p.prosecdef THEN 'SECURITY DEFINER' ELSE 'INVOKER' END AS seguranca
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN ('calculate_next_business_day', 'handle_new_client_tasks')
ORDER BY p.proname;
" || {
    echo "⚠️  Aviso: A migração FOI APLICADA com sucesso no banco, mas a consulta de conferência das funções falhou."
}
echo ""

echo ">> 2. Verificação do trigger em public.clients (pg_trigger):"
docker exec -i "${DB_CONTAINER}" psql -U postgres -d postgres -c "
SELECT 
    c.relname AS tabela,
    t.tgname AS trigger_nome,
    p.proname AS funcao_executada,
    CASE WHEN t.tgenabled = 'O' THEN 'HABILITADO' ELSE 'DESABILITADO' END AS status
FROM pg_trigger t
JOIN pg_class c ON c.oid = t.tgrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
JOIN pg_proc p ON p.oid = t.tgfoid
WHERE n.nspname = 'public'
  AND c.relname = 'clients'
  AND t.tgname = 'on_client_created'
  AND NOT t.tgisinternal;
" || {
    echo "⚠️  Aviso: A migração FOI APLICADA com sucesso no banco, mas a consulta de conferência do trigger falhou."
}
echo ""

echo ">> 3. Amostra de tarefas mais recentes em public.tasks (se houver):"
docker exec -i "${DB_CONTAINER}" psql -U postgres -d postgres -c "
SELECT 
    t.id,
    t.title,
    t.type,
    t.status,
    t.priority,
    t.\"dueDate\" AS vencimento,
    cl.name AS cliente,
    p.name AS responsavel,
    t.created_at
FROM public.tasks t
LEFT JOIN public.clients cl ON cl.id = t.\"clientId\"
LEFT JOIN public.profiles p ON p.id = t.\"responsibleId\"
WHERE t.title IN ('Acompanhamento processual mensal', 'Redigir Inicial ou Defesa')
ORDER BY t.created_at DESC
LIMIT 2;
" || {
    echo "⚠️  Aviso: A migração FOI APLICADA com sucesso no banco, mas a consulta de conferência de amostra de tarefas falhou."
}

echo ""
echo "====================================================================="
echo "🎉 Migração de tarefas automáticas concluída com sucesso no VPS!"
echo "   Ao cadastrar um novo cliente no sistema:"
echo "   1) 'Acompanhamento processual mensal' será atribuída ao Mestre (dia 25 do mês subsequente)"
echo "   2) 'Redigir Inicial ou Defesa' será atribuída ao usuário criador (próximo dia útil)"
echo "   👉 https://sistema.advdouglaspsantos.com.br"
echo "====================================================================="
exit 0
