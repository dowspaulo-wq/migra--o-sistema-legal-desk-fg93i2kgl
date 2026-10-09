#!/usr/bin/env bash
# ==============================================================================
# DPSjur / SBJur - Fase 6: Teste Imediato de Backup no VPS (Hostinger KVM 1)
# Script: docs/backup-fase6/02-testar-backup.sh
# Versão: v1.1.0
# ==============================================================================

set -u

SCRIPT_VERSION="v1.1.0"
WORK_DIR="/root/sbjur-backups"
CONFIG_DIR="${WORK_DIR}/config"
LOGS_DIR="${WORK_DIR}/logs"
BACKUP_SCRIPT="${WORK_DIR}/backup.sh"
LOG_FILE="${WORK_DIR}/logs/backup.log"
COPIA_SCRIPT_DEST="${WORK_DIR}/02-testar-backup.sh"

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
    GH_RAW="https://raw.githubusercontent.com/dowspaulo-wq/migra--o-sistema-legal-desk-fg93i2kgl/main/docs/backup-fase6/02-testar-backup.sh"
    GH_API="https://api.github.com/repos/dowspaulo-wq/migra--o-sistema-legal-desk-fg93i2kgl/contents/docs/backup-fase6/02-testar-backup.sh?ref=main"

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

    INSTALADOR_LOCAL="${WORK_DIR}/01-instalar-backup.sh"
    SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]:-$0}")"

    if [ -f "${INSTALADOR_LOCAL}" ]; then
        if [ -t 0 ]; then
            bash "${INSTALADOR_LOCAL}" || true
        elif [ -r /dev/tty ]; then
            bash "${INSTALADOR_LOCAL}" < /dev/tty || true
        else
            bash "${INSTALADOR_LOCAL}" || true
        fi
    elif [ -f "${SCRIPT_DIR}/01-instalar-backup.sh" ]; then
        if [ -t 0 ]; then
            bash "${SCRIPT_DIR}/01-instalar-backup.sh" || true
        elif [ -r /dev/tty ]; then
            bash "${SCRIPT_DIR}/01-instalar-backup.sh" < /dev/tty || true
        else
            bash "${SCRIPT_DIR}/01-instalar-backup.sh" || true
        fi
    else
        curl -sSf -L -H "Accept: application/vnd.github.v3.raw" \
            -H "User-Agent: DPSjur-BackupKit" \
            "https://api.github.com/repos/dowspaulo-wq/migra--o-sistema-legal-desk-fg93i2kgl/contents/docs/backup-fase6/01-instalar-backup.sh?ref=main" \
            -o "${INSTALADOR_LOCAL}" </dev/null 2>/dev/null || true
        if [ -s "${INSTALADOR_LOCAL}" ]; then
            chmod 755 "${INSTALADOR_LOCAL}" 2>/dev/null || true
            if [ -t 0 ]; then
                bash "${INSTALADOR_LOCAL}" || true
            elif [ -r /dev/tty ]; then
                bash "${INSTALADOR_LOCAL}" < /dev/tty || true
            else
                bash "${INSTALADOR_LOCAL}" || true
            fi
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
