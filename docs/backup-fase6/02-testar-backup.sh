#!/usr/bin/env bash
# ==============================================================================
# DPSjur / SBJur - Fase 6: Teste Imediato de Backup no VPS (Hostinger KVM 1)
# Script: docs/backup-fase6/02-testar-backup.sh
# Versão: v1.0.0
# ==============================================================================

SCRIPT_VERSION="v1.0.0"
WORK_DIR="/root/sbjur-backups"
BACKUP_SCRIPT="${WORK_DIR}/backup.sh"
LOG_FILE="${WORK_DIR}/logs/backup.log"

echo "====================================================================="
echo " DPSjur / SBJur - Fase 6: Execução Manual / Teste de Backup"
echo " Versão: ${SCRIPT_VERSION}"
echo "====================================================================="
echo "Data: $(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || true)"
echo "Host: $(hostname 2>/dev/null || echo 'VPS-Hostinger')"
echo ""

# 1. Verificar se o instalador foi executado
if [ ! -f "${BACKUP_SCRIPT}" ]; then
    echo "⚠️  O script mestre ${BACKUP_SCRIPT} não foi encontrado."
    echo "Executando o instalador da Fase 6 primeiro..."

    INSTALADOR="$(dirname "$0")/01-instalar-backup.sh"
    if [ -f "${INSTALADOR}" ]; then
        bash "${INSTALADOR}" || true
    else
        mkdir -p "${WORK_DIR}" && cd "${WORK_DIR}" || true
        curl -sSf -L -H "Accept: application/vnd.github.v3.raw" \
            -H "User-Agent: DPSjur-BackupKit" \
            "https://api.github.com/repos/dowspaulo-wq/migra--o-sistema-legal-desk-fg93i2kgl/contents/docs/backup-fase6/01-instalar-backup.sh?ref=main" \
            -o 01-instalar-backup.sh 2>/dev/null || true
        if [ -s 01-instalar-backup.sh ]; then
            bash 01-instalar-backup.sh || true
        fi
    fi
fi

if [ ! -f "${BACKUP_SCRIPT}" ]; then
    echo "❌ Erro: Não foi possível preparar o script de backup."
    exit 1
fi

echo "🚀 Iniciando execução imediata da rotina de backup..."
echo "---------------------------------------------------------------------"
bash "${BACKUP_SCRIPT}"
EXIT_CODE=$?
echo "---------------------------------------------------------------------"
echo ""

# 2. Diagnóstico pós-execução
echo "📊 Verificação do resultado:"

ULTIMO_DUMP=$(ls -t "${WORK_DIR}/diario"/sbjur_backup_*.sql.gz 2>/dev/null | head -n 1 || true)

if [ -n "${ULTIMO_DUMP}" ] && [ -f "${ULTIMO_DUMP}" ]; then
    TAMANHO=$(du -h "${ULTIMO_DUMP}" 2>/dev/null | awk '{print $1}' || echo "N/A")
    DATA_ARQUIVO=$(date -r "${ULTIMO_DUMP}" '+%d/%m/%Y %H:%M:%S' 2>/dev/null || echo "recente")
    echo "✅ Arquivo de dump gerado com sucesso:"
    echo "   👉 Caminho: ${ULTIMO_DUMP}"
    echo "   👉 Tamanho: ${TAMANHO}"
    echo "   👉 Criado em: ${DATA_ARQUIVO}"
else
    echo "❌ Nenhum arquivo de dump foi encontrado em ${WORK_DIR}/diario/!"
fi
echo ""

# 3. Status do Google Drive
echo "☁️  Status do Google Drive:"
if command -v rclone >/dev/null 2>&1; then
    if rclone listremotes 2>/dev/null | grep -q '^gdrive:'; then
        echo "Arquivos na pasta remota 'gdrive:SBJur-Backups/diario':"
        rclone lsl gdrive:SBJur-Backups/diario 2>/dev/null | tail -n 5 || echo "   (Sem arquivos ou acesso pendente)"
    else
        echo "ℹ️  O remoto 'gdrive:' ainda não foi autorizado no rclone."
        echo "   Para ativar o envio para o Google Drive, execute:"
        echo "   rclone config"
    fi
else
    echo "ℹ️  rclone não instalado."
fi
echo ""

# 4. Exibir últimas linhas do log
if [ -f "${LOG_FILE}" ]; then
    echo "📝 Últimas 10 linhas do log (${LOG_FILE}):"
    echo "---------------------------------------------------------------------"
    tail -n 10 "${LOG_FILE}" 2>/dev/null || true
    echo "---------------------------------------------------------------------"
fi
echo ""

if [ $EXIT_CODE -eq 0 ]; then
    echo "====================================================================="
    echo "🎉 TESTE DE BACKUP FINALIZADO COM SUCESSO!"
    echo "   Verifique se o e-mail de aviso chegou em advdouglaspsantos@gmail.com"
    echo "====================================================================="
else
    echo "====================================================================="
    echo "⚠️  O teste encerrou com código de retorno ${EXIT_CODE}."
    echo "   Verifique as mensagens acima para diagnosticar eventuais alertas."
    echo "====================================================================="
fi

exit $EXIT_CODE
