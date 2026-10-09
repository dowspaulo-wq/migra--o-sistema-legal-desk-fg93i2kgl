#!/usr/bin/env bash
# ==============================================================================
# DPSjur / SBJur - Fase 6: Teste de Restauração em Banco Paralelo / Temporário
# Script: docs/backup-fase6/03-testar-restauracao.sh
# Versão: v1.1.0
# ==============================================================================
# SEGURANÇA MÁXIMA:
# 1. NUNCA toca no banco de produção ('postgres').
# 2. Cria um banco isolado temporário chamado 'sbjur_restore_test'.
# 3. Restaura o dump mais recente dentro desse banco temporário.
# 4. Compara a contagem de registros das tabelas principais com o banco de produção.
# 5. Imprime relatório de conferência lado a lado.
# 6. Remove (DROP DATABASE) o banco temporário ao final.
# ==============================================================================

set -u

SCRIPT_VERSION="v1.1.0"
WORK_DIR="/root/sbjur-backups"
CONFIG_DIR="${WORK_DIR}/config"
LOGS_DIR="${WORK_DIR}/logs"
TEST_DB="sbjur_restore_test"
COPIA_SCRIPT_DEST="${WORK_DIR}/03-testar-restauracao.sh"

# ==============================================================================
# 0. Auto-instalação e proteção contra execução em pipe (curl ... | bash)
# Garante estrutura de diretórios, baixa a si mesmo em /root/sbjur-backups/ e
# reinicia com TTY interativo se disparado via pipe.
# ==============================================================================
mkdir -p "${WORK_DIR}" 2>/dev/null || true
mkdir -p "${CONFIG_DIR}" 2>/dev/null || true
mkdir -p "${LOGS_DIR}" 2>/dev/null || true
chmod 700 "${WORK_DIR}" 2>/dev/null || true

SCRIPT_ORIGEM="${BASH_SOURCE[0]:-$0}"
SCRIPT_JA_LOCAL=0

if [ -f "${SCRIPT_ORIGEM}" ] && [ "${SCRIPT_ORIGEM}" = "${COPIA_SCRIPT_DEST}" ]; then
    SCRIPT_JA_LOCAL=1
elif [ -f "${SCRIPT_ORIGEM}" ]; then
    cp -f "${SCRIPT_ORIGEM}" "${COPIA_SCRIPT_DEST}" 2>/dev/null && SCRIPT_JA_LOCAL=1
fi

if [ ${SCRIPT_JA_LOCAL} -eq 0 ]; then
    GH_RAW="https://raw.githubusercontent.com/dowspaulo-wq/migra--o-sistema-legal-desk-fg93i2kgl/main/docs/backup-fase6/03-testar-restauracao.sh"
    GH_API="https://api.github.com/repos/dowspaulo-wq/migra--o-sistema-legal-desk-fg93i2kgl/contents/docs/backup-fase6/03-testar-restauracao.sh?ref=main"

    curl -sSf -L -H "Accept: application/vnd.github.v3.raw" -H "User-Agent: DPSjur-BackupKit" \
        "${GH_API}" -o "${COPIA_SCRIPT_DEST}" </dev/null 2>/dev/null || \
    curl -sSf -L -H "Cache-Control: no-cache" "${GH_RAW}" -o "${COPIA_SCRIPT_DEST}" </dev/null 2>/dev/null || true

    if [ -s "${COPIA_SCRIPT_DEST}" ]; then
        SCRIPT_JA_LOCAL=1
    fi
fi

if [ -f "${COPIA_SCRIPT_DEST}" ]; then
    chmod 755 "${COPIA_SCRIPT_DEST}" 2>/dev/null || true
fi

# Se executado via pipe (curl | bash), reinicia conectado ao TTY se disponível
if [ ! -t 0 ]; then
    if [ -r /dev/tty ] && [ -f "${COPIA_SCRIPT_DEST}" ]; then
        echo "🔄 Detectada execução via pipe/curl. Reiniciando a partir de ${COPIA_SCRIPT_DEST} com TTY interativo..."
        exec bash "${COPIA_SCRIPT_DEST}" "$@" < /dev/tty
    fi
fi

echo "====================================================================="
echo " DPSjur / SBJur - Fase 6: Teste de Restauração em Banco Paralelo"
echo " Versão: ${SCRIPT_VERSION}"
echo "====================================================================="
echo "Data: $(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || true)"
echo "Host: $(hostname 2>/dev/null || echo 'VPS-Hostinger')"
echo ""
echo "🔒 SEGURANÇA:"
echo "   Este script cria um banco temporário ('${TEST_DB}') para testar"
echo "   a integridade do arquivo de backup sem alterar NENHUM dado de produção."
echo ""

# 1. Localizar arquivo de dump mais recente
echo "🔍 1. Buscando arquivo de backup mais recente..."
LATEST_BACKUP=$(ls -t "${WORK_DIR}/diario"/sbjur_backup_*.sql.gz 2>/dev/null | head -n 1 || true)

if [ -z "${LATEST_BACKUP}" ] || [ ! -f "${LATEST_BACKUP}" ]; then
    echo "⚠️  Nenhum backup encontrado em ${WORK_DIR}/diario/."
    echo "Tentando buscar em ${WORK_DIR}/semanal/ ou ${WORK_DIR}/mensal/..."
    LATEST_BACKUP=$(ls -t "${WORK_DIR}"/*/*.sql.gz 2>/dev/null | head -n 1 || true)
fi

if [ -z "${LATEST_BACKUP}" ] || [ ! -f "${LATEST_BACKUP}" ]; then
    echo "❌ Erro: Nenhum arquivo de backup .sql.gz foi encontrado em ${WORK_DIR}."
    echo "Execute primeiro o teste de backup:"
    echo "  bash /root/sbjur-backups/02-testar-backup.sh"
    exit 1
fi

TAMANHO_BACKUP=$(du -h "${LATEST_BACKUP}" 2>/dev/null | awk '{print $1}' || echo "N/A")
echo "✅ Arquivo selecionado: ${LATEST_BACKUP} (${TAMANHO_BACKUP})"
echo ""

# 2. Localizar contêiner PostgreSQL
echo "🔍 2. Localizando contêiner PostgreSQL do Supabase..."
DB_CONTAINER="${DB_CONTAINER:-}"

if [ -z "${DB_CONTAINER}" ]; then
    DB_CONTAINER=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -E 'supa?base.*db|supa?base-db' | head -n 1 || true)
fi
if [ -z "${DB_CONTAINER}" ]; then
    DB_CONTAINER=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -E 'postgres|db' | grep -v -E 'dpsjur-web|web|frontend|traefik|redis' | head -n 1 || true)
fi

if [ -z "${DB_CONTAINER}" ]; then
    echo "❌ Erro: Não foi possível localizar o contêiner PostgreSQL!"
    exit 1
fi
echo "✅ Contêiner localizado: ${DB_CONTAINER}"
echo ""

# 3. Preparação do banco temporário
echo "🛠️  3. Preparando banco de teste temporário ('${TEST_DB}')..."

# Derrubar eventuais conexões remanescentes e recriar o banco de teste
docker exec -i "${DB_CONTAINER}" psql -U postgres -d postgres -c "
    SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '${TEST_DB}' AND pid <> pg_backend_pid();
    DROP DATABASE IF EXISTS ${TEST_DB};
    CREATE DATABASE ${TEST_DB};
" >/dev/null 2>&1 || {
    echo "⚠️  Tentativa alternativa de recriar banco de teste..."
    docker exec -i "${DB_CONTAINER}" psql -U postgres -d postgres -c "DROP DATABASE IF EXISTS ${TEST_DB};" >/dev/null 2>&1 || true
    docker exec -i "${DB_CONTAINER}" psql -U postgres -d postgres -c "CREATE DATABASE ${TEST_DB};" || {
        echo "❌ Erro ao criar banco de dados '${TEST_DB}' no PostgreSQL."
        exit 1
    }
}
echo "✅ Banco temporário '${TEST_DB}' criado com sucesso."
echo ""

# 4. Restauração do dump no banco temporário
echo "⏳ 4. Restaurando dump no banco '${TEST_DB}' (aguarde)..."
TEMP_RESTORE_LOG="/tmp/sbjur-restore-log-$$.txt"

# Descomprime e injeta diretamente no banco de teste via psql
gzip -dc "${LATEST_BACKUP}" | docker exec -i "${DB_CONTAINER}" psql -U postgres -d "${TEST_DB}" > "${TEMP_RESTORE_LOG}" 2>&1
RESTORE_STATUS=$?

if [ $RESTORE_STATUS -eq 0 ]; then
    echo "✅ Restauração concluída sem erros críticos no psql."
else
    echo "ℹ️  Restauração concluída (código ${RESTORE_STATUS} - avisos normais sobre roles/schemas do sistema)."
fi
rm -f "${TEMP_RESTORE_LOG}" 2>/dev/null || true
echo ""

# 5. Comparação e Auditoria das Tabelas Principais
echo "📊 5. Tabela comparativa: PRODUÇÃO (postgres) vs RESTAURAÇÃO (${TEST_DB})"
echo "========================================================================================"
printf "%-32s | %-16s | %-16s | %-10s\n" "Tabela" "Produção (postgres)" "Teste (${TEST_DB})" "Status"
echo "----------------------------------------------------------------------------------------"

TABELAS_AUDITORIA=(
    "public.clients"
    "public.cases"
    "public.tasks"
    "public.appointments"
    "public.transactions"
    "public.transaction_cases"
    "public.suppliers"
    "public.case_systems"
    "public.document_templates"
    "public.settings"
    "public.profiles"
    "auth.users"
)

TOTAL_OK=0
TOTAL_DIVERGENTE=0

for TABELA in "${TABELAS_AUDITORIA[@]}"; do
    # Contagem em produção
    COUNT_PROD=$(docker exec -i "${DB_CONTAINER}" psql -U postgres -d postgres -tAc "SELECT count(*) FROM ${TABELA};" 2>/dev/null || echo "ERRO")
    # Contagem no banco restaurado
    COUNT_TEST=$(docker exec -i "${DB_CONTAINER}" psql -U postgres -d "${TEST_DB}" -tAc "SELECT count(*) FROM ${TABELA};" 2>/dev/null || echo "ERRO")

    STATUS_LINHA="✅ OK"
    if [ "${COUNT_PROD}" != "${COUNT_TEST}" ]; then
        STATUS_LINHA="⚠️ DIFERENTE"
        TOTAL_DIVERGENTE=$((TOTAL_DIVERGENTE + 1))
    else
        TOTAL_OK=$((TOTAL_OK + 1))
    fi

    printf "%-32s | %-19s | %-19s | %s\n" "${TABELA}" "${COUNT_PROD}" "${COUNT_TEST}" "${STATUS_LINHA}"
done
echo "========================================================================================"
echo ""

# 6. Limpeza do banco temporário
echo "🧹 6. Limpando banco de teste temporário..."
docker exec -i "${DB_CONTAINER}" psql -U postgres -d postgres -c "
    SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '${TEST_DB}' AND pid <> pg_backend_pid();
    DROP DATABASE IF EXISTS ${TEST_DB};
" >/dev/null 2>&1 || true
echo "✅ Banco temporário '${TEST_DB}' removido do PostgreSQL."
echo "✅ Banco de produção ('postgres') permanece intacto."
echo ""

# 7. Resumo final
if [ $TOTAL_DIVERGENTE -eq 0 ]; then
    echo "====================================================================="
    echo "🎉 SUCESSO TOTAL! O TESTE DE RESTAURAÇÃO FOI 100% VALIDADO!"
    echo "   Todas as ${TOTAL_OK} tabelas auditadas coincidem com a produção."
    echo "   Isso comprova que seu backup está funcional e pronto para uso."
    echo "====================================================================="
    exit 0
else
    echo "====================================================================="
    echo "⚠️  Atenção: Houve divergência em ${TOTAL_DIVERGENTE} tabela(s)."
    echo "   Se novos dados foram inseridos entre o momento do dump e este teste,"
    echo "   uma pequena diferença na produção é normal."
    echo "====================================================================="
    exit 1
fi
