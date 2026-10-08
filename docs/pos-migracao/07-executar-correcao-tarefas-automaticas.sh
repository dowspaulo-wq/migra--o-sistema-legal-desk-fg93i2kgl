#!/usr/bin/env bash
# ==============================================================================
# DPSjur / SBJur - Kit Pós-Migração VPS (Hostinger KVM 1 - IP 2.25.181.69)
# Script: docs/pos-migracao/07-executar-correcao-tarefas-automaticas.sh
# Versão: v0.0.534
# ==============================================================================
# Execução no VPS:
# curl -sSf -L -H "Accept: application/vnd.github.v3.raw" \
#   "https://api.github.com/repos/dowspaulo-wq/migra--o-sistema-legal-desk-fg93i2kgl/contents/docs/pos-migracao/07-executar-correcao-tarefas-automaticas.sh?ref=main" \
#   | bash
# ==============================================================================

SCRIPT_VERSION="v0.0.534"
WORK_DIR="/root/sbjur-pos-migracao"
SQL_FILE_NAME="20261008160000_fix_auto_tasks_robust_triggers.sql"
SQL_FILE_PATH="${WORK_DIR}/${SQL_FILE_NAME}"

GITHUB_API_SQL_URL="https://api.github.com/repos/dowspaulo-wq/migra--o-sistema-legal-desk-fg93i2kgl/contents/supabase/migrations/${SQL_FILE_NAME}?ref=main"
GITHUB_RAW_SQL_URL="https://raw.githubusercontent.com/dowspaulo-wq/migra--o-sistema-legal-desk-fg93i2kgl/main/supabase/migrations/${SQL_FILE_NAME}"

# (a) Banner
echo "====================================================================="
echo " DPSjur / SBJur - Correção: Tarefas Automáticas no VPS               "
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

# (d) Teste de conexão simples e direto
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

echo ">> 1. Verificação das funções atualizadas em pg_proc:"
docker exec -i "${DB_CONTAINER}" psql -U postgres -d postgres -c "
SELECT 
    n.nspname AS schema,
    p.proname AS funcao,
    pg_get_function_identity_arguments(p.oid) AS argumentos,
    CASE WHEN p.prosecdef THEN 'SECURITY DEFINER' ELSE 'INVOKER' END AS seguranca
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN ('calculate_next_business_day', 'handle_new_client_tasks', 'handle_new_case_task')
ORDER BY p.proname;
" || {
    echo "⚠️  Aviso: A migração FOI APLICADA com sucesso no banco, mas a consulta de conferência das funções falhou."
}
echo ""

echo ">> 2. Verificação dos triggers ativos (public.clients e public.cases):"
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
  AND c.relname IN ('clients', 'cases')
  AND t.tgname IN ('on_client_created', 'on_case_created')
  AND NOT t.tgisinternal
ORDER BY c.relname;
" || {
    echo "⚠️  Aviso: A migração FOI APLICADA com sucesso no banco, mas a consulta de conferência dos triggers falhou."
}
echo ""

echo ">> 3. Amostra de tarefas com prioridade Baixa em public.tasks:"
docker exec -i "${DB_CONTAINER}" psql -U postgres -d postgres -c "
SELECT 
    t.id,
    t.title,
    t.type,
    t.status,
    t.priority,
    t.\"dueDate\" AS vencimento,
    p.name AS responsavel,
    cb.name AS criado_por,
    t.created_at
FROM public.tasks t
LEFT JOIN public.profiles p ON p.id = t.\"responsibleId\"
LEFT JOIN public.profiles cb ON cb.id = t.created_by
WHERE t.title IN ('Acompanhamento processual mensal', 'Acompanhamento processual', 'Redigir Inicial ou Defesa')
ORDER BY t.created_at DESC
LIMIT 4;
" || {
    echo "⚠️  Aviso: A migração FOI APLICADA com sucesso no banco, mas a consulta de conferência de tarefas falhou."
}

echo ""
echo "====================================================================="
echo "🎉 Correção de tarefas automáticas concluída com sucesso no VPS!"
echo "   Regras ativas:"
echo "   1) 'Acompanhamento processual mensal' -> Responsável Mestre, Vencimento dia 25 do mês subsequente, Prioridade Baixa"
echo "   2) 'Redigir Inicial ou Defesa' -> Responsável Criador (auth.uid()), Vencimento no próximo dia útil, Prioridade Baixa"
echo "   3) Isolamento de blocos contra falhas silenciosas ou interrupção de criação do cliente"
echo "   👉 https://sistema.advdouglaspsantos.com.br"
echo "====================================================================="
exit 0
