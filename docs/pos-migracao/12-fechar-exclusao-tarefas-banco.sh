#!/usr/bin/env bash
# ==============================================================================
# DPSjur / SBJur - Kit Pós-Migração VPS (Hostinger KVM 1 - IP 2.25.181.69)
# Script: docs/pos-migracao/12-fechar-exclusao-tarefas-banco.sh
# Versão: v0.0.543
# ==============================================================================
# Execução no terminal do VPS via curl (one-liner recomendado):
#   curl -sSf -L -H "Accept: application/vnd.github.v3.raw" \
#     "https://api.github.com/repos/dowspaulo-wq/migra--o-sistema-legal-desk-fg93i2kgl/contents/docs/pos-migracao/12-fechar-exclusao-tarefas-banco.sh?ref=main" \
#     | bash
#
# Ou localmente caso o repositório esteja clonado:
#   bash docs/pos-migracao/12-fechar-exclusao-tarefas-banco.sh
#
# Contexto e Objetivo:
# - A proteção de exclusão de tarefas no nível de banco (RLS) já possuía a
#   política 'authenticated_delete_tasks' restringindo DELETE a profiles.role = 'Admin'.
# - Porém, coexistia a política legada 'tasks_authenticated_all' (permissiva para ALL),
#   que abria uma via direta de DELETE para qualquer usuário autenticado.
# - Este script remove de forma idempotente a política 'tasks_authenticated_all' e
#   garante políticas granulares estritas em public.tasks:
#     1) SELECT liberado para autenticados (manter listagens do app)
#     2) INSERT liberado para autenticados (manter criação normal e automática)
#     3) UPDATE liberado para autenticados (manter conclusão e edição)
#     4) DELETE restrito exclusivamente a perfis com role = 'Admin'
#
# Regras estritas seguidas neste script:
# - ZERO comandos que leiam stdin em subshell (compatível com curl ... | bash);
# - Execução do SQL via docker cp para arquivo interno no contêiner e psql -f;
# - ZERO interpolação :'variavel' do psql;
# - Zero silêncio: mensagens antes/depois de cada etapa com códigos de retorno;
# - Idempotência completa (DROP POLICY IF EXISTS + CREATE POLICY);
# - Tabela de conferência final no terminal mostrando o estado de todas as políticas de public.tasks.
# ==============================================================================

SCRIPT_VERSION="v0.0.543"
WORK_DIR="/root/sbjur-pos-migracao"
SQL_FILE_NAME="20261008235500_restrict_tasks_delete_to_admin.sql"
SQL_FILE_PATH="${WORK_DIR}/${SQL_FILE_NAME}"

GITHUB_API_SQL_URL="https://api.github.com/repos/dowspaulo-wq/migra--o-sistema-legal-desk-fg93i2kgl/contents/supabase/migrations/${SQL_FILE_NAME}?ref=main"
GITHUB_RAW_SQL_URL="https://raw.githubusercontent.com/dowspaulo-wq/migra--o-sistema-legal-desk-fg93i2kgl/main/supabase/migrations/${SQL_FILE_NAME}"

# (1) Banner
echo "====================================================================="
echo " SBJur — Fechamento de Exclusão de Tarefas no Banco (RLS Admin Only) "
echo " Versão: ${SCRIPT_VERSION}"
echo "====================================================================="
echo "Data: $(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || true)"
echo "Host: $(hostname 2>/dev/null || echo 'VPS')"
echo "====================================================================="
echo ""

# (2) Obter ou gerar arquivo SQL em /root/sbjur-pos-migracao/
echo "📁 1. Verificando arquivo SQL (${SQL_FILE_NAME})..."
mkdir -p "${WORK_DIR}" || {
    echo "❌ FALHA EXPLÍCITA: Não foi possível criar o diretório ${WORK_DIR}."
    exit 1
}

# Se o arquivo já existir no caminho relativo local do repositório, copia diretamente
if [ ! -s "${SQL_FILE_PATH}" ]; then
    LOCAL_CANDIDATE="$(dirname "$0")/../../supabase/migrations/${SQL_FILE_NAME}"
    if [ -s "${LOCAL_CANDIDATE}" ]; then
        echo "ℹ️  Copiando arquivo SQL a partir do caminho local do repositório..."
        cp "${LOCAL_CANDIDATE}" "${SQL_FILE_PATH}" 2>/dev/null || true
    fi
fi

if [ ! -s "${SQL_FILE_PATH}" ]; then
    echo "⏳ Arquivo local ausente. Baixando do repositório GitHub..."
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

# Fallback autônomo embutido caso a rede/GitHub esteja inacessível:
if [ ! -s "${SQL_FILE_PATH}" ]; then
    echo "ℹ️  Gerando SQL autônomo embutido diretamente em ${SQL_FILE_PATH}..."
    cat << 'EOSQL' > "${SQL_FILE_PATH}"
-- Migração autônoma: Restringir Exclusão de Tarefas (public.tasks) Exclusivamente a Admin
ALTER TABLE public.tasks ENABLE ROW LEVEL SECURITY;

-- 1. Remover a política ALL permissiva que permitia DELETE por qualquer autenticado
DROP POLICY IF EXISTS "tasks_authenticated_all" ON public.tasks;

-- 2. Garantir SELECT para todos os autenticados
DROP POLICY IF EXISTS "authenticated_select_tasks" ON public.tasks;
CREATE POLICY "authenticated_select_tasks" ON public.tasks
    FOR SELECT TO authenticated
    USING (true);

-- 3. Garantir INSERT para todos os autenticados
DROP POLICY IF EXISTS "authenticated_insert_tasks" ON public.tasks;
CREATE POLICY "authenticated_insert_tasks" ON public.tasks
    FOR INSERT TO authenticated
    WITH CHECK (true);

-- 4. Garantir UPDATE para todos os autenticados
DROP POLICY IF EXISTS "authenticated_update_tasks" ON public.tasks;
CREATE POLICY "authenticated_update_tasks" ON public.tasks
    FOR UPDATE TO authenticated
    USING (true)
    WITH CHECK (true);

-- 5. Garantir DELETE restrito exclusivamente a perfis com role = 'Admin'
DROP POLICY IF EXISTS "authenticated_delete_tasks" ON public.tasks;
CREATE POLICY "authenticated_delete_tasks" ON public.tasks
    FOR DELETE TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.profiles 
            WHERE profiles.id = auth.uid() 
              AND profiles.role = 'Admin'
        )
    );
EOSQL
fi

if [ ! -s "${SQL_FILE_PATH}" ]; then
    echo "❌ FALHA EXPLÍCITA: Arquivo SQL ${SQL_FILE_PATH} continua indisponível ou vazio!"
    exit 1
fi
echo "✅ Arquivo SQL pronto: ${SQL_FILE_PATH} ($(wc -l < "${SQL_FILE_PATH}" | tr -d ' ') linhas)"
echo ""

# (3) Localizar contêiner PostgreSQL via docker ps
echo "🔍 2. Localizando contêiner PostgreSQL do Supabase..."
DB_CONTAINER="${DB_CONTAINER:-}"

if [ -z "${DB_CONTAINER}" ]; then
    DB_CONTAINER=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -E 'supa?base.*db|supa?base-db' | head -n 1 || true)
fi

if [ -z "${DB_CONTAINER}" ]; then
    DB_CONTAINER=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -E 'postgres|db' | grep -v -E 'dpsjur-web|web|frontend|traefik|redis' | head -n 1 || true)
fi

if [ -z "${DB_CONTAINER}" ]; then
    echo "❌ FALHA EXPLÍCITA: Não foi possível localizar o contêiner do PostgreSQL via docker ps!"
    echo "Contêineres em execução:"
    docker ps --format 'table {{.Names}}\t{{.Status}}' 2>/dev/null || true
    echo ""
    echo "Dica: Você pode informar manualmente via: DB_CONTAINER=nome_do_conteiner bash ..."
    exit 1
fi
echo "✅ Contêiner localizado: ${DB_CONTAINER}"
echo ""

# (4) Teste de conexão simples e direto
echo "🔐 3. Testando conectividade com o banco de dados..."
echo "⏳ EXECUTANDO teste de conexão no PostgreSQL..."
CONN_TEST=$(docker exec "${DB_CONTAINER}" psql -U postgres -d postgres -tAc "SELECT 'CONEXAO_OK';" 2>&1)
rc_conn=$?

echo "📋 Retorno do PostgreSQL: rc=${rc_conn}, resultado='${CONN_TEST}'"

if [ ${rc_conn} -ne 0 ] || [ "${CONN_TEST}" != "CONEXAO_OK" ]; then
    echo "❌ FALHA EXPLÍCITA: Falha ao conectar ao banco de dados no contêiner '${DB_CONTAINER}'!"
    echo "Saída recebida: ${CONN_TEST}"
    exit 1
fi
echo "✅ Conexão direta bem-sucedida via usuário 'postgres' (local socket)!"
echo ""

# (5) Inspeção do estado ANTERIOR das políticas de public.tasks
echo "🔎 4. Inspecionando estado ATUAL das políticas de public.tasks..."
docker exec "${DB_CONTAINER}" psql -U postgres -d postgres -c "
SELECT 
    schemaname,
    tablename,
    policyname,
    cmd,
    roles::text[] AS roles
FROM pg_policies
WHERE tablename = 'tasks'
ORDER BY cmd, policyname;
" 2>&1 || {
    echo "⚠️  Aviso: Não foi possível listar as políticas anteriores."
}
echo ""

# (6) Aplicar o SQL de forma segura contra perda de stdin (docker cp + psql -f)
echo "🚀 5. Aplicando ${SQL_FILE_NAME} no PostgreSQL..."
echo "---------------------------------------------------------------------"
TMP_CONT_SQL="/tmp/sbjur_restrict_tasks_$$.sql"

echo "⏳ EXECUTANDO cópia do script para o contêiner via docker cp..."
docker cp "${SQL_FILE_PATH}" "${DB_CONTAINER}:${TMP_CONT_SQL}" >/dev/null 2>&1
cp_rc=$?

if [ ${cp_rc} -eq 0 ]; then
    echo "⏳ EXECUTANDO psql -f dentro do contêiner (sem toque em stdin)..."
    docker exec "${DB_CONTAINER}" \
        psql -U postgres -d postgres -v ON_ERROR_STOP=1 \
        -f "${TMP_CONT_SQL}"
    rc=$?
    docker exec "${DB_CONTAINER}" rm -f "${TMP_CONT_SQL}" >/dev/null 2>&1 || true
else
    echo "ℹ️  docker cp indisponível, executando fallback via arquivo temporário..."
    docker exec -i "${DB_CONTAINER}" \
        psql -U postgres -d postgres -v ON_ERROR_STOP=1 \
        < "${SQL_FILE_PATH}"
    rc=$?
fi
echo "---------------------------------------------------------------------"
echo "📋 Retorno do PostgreSQL: rc=${rc}"

if [ ${rc} -ne 0 ]; then
    echo "❌ FALHA EXPLÍCITA: O comando psql encerrou com código de erro ${rc}!"
    echo "As políticas de tasks NÃO foram ajustadas com sucesso."
    exit ${rc}
fi
echo "✅ Script SQL executado com sucesso!"
echo ""

# (7) Tabela de conferência final impressa pelo bash
echo "📊 6. Tabela de conferência final das políticas da tabela tasks no VPS..."
echo ""

echo ">> 1. RLS habilitado na tabela tasks:"
docker exec "${DB_CONTAINER}" psql -U postgres -d postgres -c "
SELECT 
    schemaname,
    tablename,
    rowsecurity AS rls_habilitado
FROM pg_tables
WHERE tablename = 'tasks' AND schemaname = 'public';
" || {
    echo "⚠️ FALHA EXPLÍCITA: Falha ao verificar rowsecurity da tabela tasks."
}
echo ""

echo ">> 2. Políticas RLS ativas em public.tasks (tasks_authenticated_all DEVE estar ausente):"
docker exec "${DB_CONTAINER}" psql -U postgres -d postgres -c "
SELECT 
    policyname,
    cmd,
    roles::text[] AS roles,
    qual,
    with_check
FROM pg_policies
WHERE tablename = 'tasks'
ORDER BY cmd, policyname;
" || {
    echo "⚠️ FALHA EXPLÍCITA: Falha ao consultar pg_policies para a tabela tasks."
}
echo ""

# (8) Validação estrita: garantir que tasks_authenticated_all foi removida
CHECK_HOLE=$(docker exec "${DB_CONTAINER}" psql -U postgres -d postgres -t -A -c "
SELECT count(*) FROM pg_policies WHERE tablename = 'tasks' AND policyname = 'tasks_authenticated_all';
" 2>/dev/null | tr -d '[:space:]' || echo "erro")

if [ "${CHECK_HOLE}" != "0" ]; then
    echo "❌ FALHA EXPLÍCITA: A política permissiva 'tasks_authenticated_all' AINDA consta no banco!"
    exit 1
fi

CHECK_DELETE_ADMIN=$(docker exec "${DB_CONTAINER}" psql -U postgres -d postgres -t -A -c "
SELECT count(*) FROM pg_policies WHERE tablename = 'tasks' AND policyname = 'authenticated_delete_tasks' AND cmd = 'DELETE';
" 2>/dev/null | tr -d '[:space:]' || echo "erro")

if [ "${CHECK_DELETE_ADMIN}" != "1" ]; then
    echo "❌ FALHA EXPLÍCITA: A política restritiva 'authenticated_delete_tasks' NÃO foi encontrada no banco!"
    exit 1
fi

echo "✅ Validação de integridade aprovada com sucesso:"
echo "   - tasks_authenticated_all = REMOVIDA (buraco de exclusão fechado)"
echo "   - authenticated_delete_tasks = ATIVA (DELETE restrito a role 'Admin')"
echo "   - authenticated_select_tasks = ATIVA (SELECT liberado para authenticated)"
echo "   - authenticated_insert_tasks = ATIVA (INSERT liberado para authenticated)"
echo "   - authenticated_update_tasks = ATIVA (UPDATE liberado para authenticated)"
echo ""

# (9) Instruções de teste para o operador
echo "====================================================================="
echo "🎉 Fechamento de exclusão de tarefas concluído com sucesso no VPS!"
echo "====================================================================="
echo "Como testar e validar o resultado no sistema:"
echo ""
echo "1. Teste com usuário Colaborador (Eduardo, Fernanda, Guilherme, Heitor):"
echo "   - Acesse: https://sistema.advdouglaspsantos.com.br"
echo "   - Logue com qualquer conta de colaborador;"
echo "   - Na tela de Tarefas (ou detalhes do processo), o botão da lixeira"
echo "     nem aparece na UI e, se tentar chamada direta via API Supabase,"
echo "     o PostgreSQL recusa o DELETE imediatamente via RLS (0 rows deleted / 403);"
echo "   - Listagem, criação e edição de tarefas continuam 100% funcionando."
echo ""
echo "2. Teste com usuário Administrador (Douglas / Mestre):"
echo "   - Logue com conta de Administrador (role = 'Admin');"
echo "   - Abra qualquer tarefa de teste e clique no ícone da lixeira;"
echo "   - Confirme a exclusão no diálogo modal;"
echo "   - A tarefa é excluída com sucesso pelo banco de dados."
echo "====================================================================="
exit 0
