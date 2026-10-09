#!/usr/bin/env bash
# ==============================================================================
# DPSjur / SBJur - Fase 6: Sistema de Backup Automático no VPS (Hostinger KVM 1)
# Script: docs/backup-fase6/01-instalar-backup.sh
# Versão: v1.1.0
# Destinatário padrão: advdouglaspsantos@gmail.com
# ==============================================================================

set -u

SCRIPT_VERSION="v1.1.0"
WORK_DIR="/root/sbjur-backups"
CONFIG_DIR="${WORK_DIR}/config"
LOGS_DIR="${WORK_DIR}/logs"
BACKUP_SCRIPT="${WORK_DIR}/backup.sh"
DEFAULT_EMAIL="advdouglaspsantos@gmail.com"
COPIA_SCRIPT_DEST="${WORK_DIR}/01-instalar-backup.sh"

# ==============================================================================
# 0. Auto-instalação e proteção contra execução em pipe (curl ... | bash)
# Se o script estiver rodando via pipe/stdin sem TTY interativo, ele se salva
# em /root/sbjur-backups/01-instalar-backup.sh (e baixa os scripts irmãos 02, 03 e 04)
# e se re-executa localmente com TTY real (/dev/tty), permitindo que o assistente
# do rclone config e demais leituras recebam a entrada do teclado do usuário.
# ==============================================================================
mkdir -p "${WORK_DIR}" 2>/dev/null || true
mkdir -p "${CONFIG_DIR}" 2>/dev/null || true
mkdir -p "${LOGS_DIR}" 2>/dev/null || true
chmod 700 "${WORK_DIR}" 2>/dev/null || true

download_aux_script() {
    local script_name="$1"
    local dest="${WORK_DIR}/${script_name}"
    local gh_api="https://api.github.com/repos/dowspaulo-wq/migra--o-sistema-legal-desk-fg93i2kgl/contents/docs/backup-fase6/${script_name}?ref=main"
    local gh_raw="https://raw.githubusercontent.com/dowspaulo-wq/migra--o-sistema-legal-desk-fg93i2kgl/main/docs/backup-fase6/${script_name}"

    local script_dir
    script_dir="$(dirname "${BASH_SOURCE[0]:-$0}")"
    local local_src="${script_dir}/${script_name}"

    if [ -s "${local_src}" ] && [ "${local_src}" != "${dest}" ]; then
        cp -f "${local_src}" "${dest}" 2>/dev/null && chmod 755 "${dest}" 2>/dev/null && return 0
    fi

    # Baixar via API do GitHub (ou fallback raw)
    curl -sSf -L \
        -H "Accept: application/vnd.github.v3.raw" \
        -H "User-Agent: DPSjur-BackupKit" \
        "${gh_api}" -o "${dest}" </dev/null 2>/dev/null || \
    curl -sSf -L -H "Cache-Control: no-cache" "${gh_raw}" -o "${dest}" </dev/null 2>/dev/null || true

    chmod 755 "${dest}" 2>/dev/null || true
}

# Salvar o próprio script no destino permanente se executado de outro caminho ou via pipe
SCRIPT_ORIGEM="${BASH_SOURCE[0]:-$0}"
SCRIPT_JA_LOCAL=0

if [ -f "${SCRIPT_ORIGEM}" ] && [ "${SCRIPT_ORIGEM}" = "${COPIA_SCRIPT_DEST}" ]; then
    SCRIPT_JA_LOCAL=1
elif [ -f "${SCRIPT_ORIGEM}" ]; then
    cp -f "${SCRIPT_ORIGEM}" "${COPIA_SCRIPT_DEST}" 2>/dev/null && SCRIPT_JA_LOCAL=1
fi

if [ ${SCRIPT_JA_LOCAL} -eq 0 ]; then
    GH_RAW="https://raw.githubusercontent.com/dowspaulo-wq/migra--o-sistema-legal-desk-fg93i2kgl/main/docs/backup-fase6/01-instalar-backup.sh"
    GH_API="https://api.github.com/repos/dowspaulo-wq/migra--o-sistema-legal-desk-fg93i2kgl/contents/docs/backup-fase6/01-instalar-backup.sh?ref=main"

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

# Pré-baixar scripts irmãos 02, 03 e 04 para /root/sbjur-backups/
download_aux_script "02-testar-backup.sh"
download_aux_script "03-testar-restauracao.sh"
download_aux_script "04-configurar-email.sh"

# Se stdin não é terminal (rodando via `curl ... | bash`), re-executa o script local conectado ao /dev/tty
if [ ! -t 0 ]; then
    if [ -r /dev/tty ] && [ -f "${COPIA_SCRIPT_DEST}" ]; then
        echo "🔄 Detectada execução via pipe/curl. Reiniciando a partir de ${COPIA_SCRIPT_DEST} com TTY interativo..."
        exec bash "${COPIA_SCRIPT_DEST}" "$@" < /dev/tty
    fi
fi

# Leitura segura de prompt interativo com fallback para /dev/tty
read_interactive_input() {
    local prompt_msg="$1"
    local var_name="$2"
    local default_val="${3:-}"
    local val=""

    if [ -t 0 ]; then
        printf "%s" "${prompt_msg}"
        read -r val || true
    elif [ -r /dev/tty ]; then
        printf "%s" "${prompt_msg}" > /dev/tty
        read -r val < /dev/tty || true
    else
        read -r val || true
    fi

    if [ -z "${val}" ]; then
        val="${default_val}"
    fi
    eval "${var_name}=\"\$val\""
}

echo "====================================================================="
echo " DPSjur / SBJur - Fase 6: Instalação do Backup Automático no VPS"
echo " Versão: ${SCRIPT_VERSION}"
echo "====================================================================="
echo "Data: $(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || true)"
echo "Host: $(hostname 2>/dev/null || echo 'VPS-Hostinger')"
echo ""

# 1. Criação da estrutura de pastas
echo "📁 1. Criando estrutura de diretórios em ${WORK_DIR}..."
mkdir -p "${WORK_DIR}/diario" \
         "${WORK_DIR}/semanal" \
         "${WORK_DIR}/mensal" \
         "${CONFIG_DIR}" \
         "${LOGS_DIR}" || {
    echo "❌ Erro ao criar diretórios em ${WORK_DIR}."
    exit 1
}
chmod 700 "${WORK_DIR}" 2>/dev/null || true
echo "✅ Pastas criadas:"
echo "   - ${WORK_DIR}/diario   (mantém últimos 7 dias)"
echo "   - ${WORK_DIR}/semanal  (domingos, mantém 30 dias)"
echo "   - ${WORK_DIR}/mensal   (dia 1º do mês, mantém 1 ano)"
echo "   - ${WORK_DIR}/logs     (histórico rotativo)"
echo ""

# 2. Verificação de dependências do sistema
echo "📦 2. Verificando dependências (rclone, curl, msmtp, cron)..."
DEPS_TO_INSTALL=""

if ! command -v rclone >/dev/null 2>&1; then
    DEPS_TO_INSTALL="${DEPS_TO_INSTALL} rclone"
fi
if ! command -v curl >/dev/null 2>&1; then
    DEPS_TO_INSTALL="${DEPS_TO_INSTALL} curl"
fi
if ! command -v crontab >/dev/null 2>&1; then
    DEPS_TO_INSTALL="${DEPS_TO_INSTALL} cron"
fi
if ! command -v msmtp >/dev/null 2>&1; then
    DEPS_TO_INSTALL="${DEPS_TO_INSTALL} msmtp msmtp-mta ca-certificates"
fi

if [ -n "${DEPS_TO_INSTALL}" ]; then
    echo "Instalando pacotes necessários:${DEPS_TO_INSTALL}..."
    apt-get update -qq </dev/null >/dev/null 2>&1 || true
    # Instalação com flags não interativas e /dev/null
    DEBIAN_FRONTEND=noninteractive apt-get install -y ${DEPS_TO_INSTALL} </dev/null >/dev/null 2>&1 || {
        echo "⚠️  Tentando instalação direta..."
        apt-get install -y ${DEPS_TO_INSTALL} </dev/null || true
    }
fi

# Se rclone ainda não estiver instalado pelo apt, instala via script oficial
if ! command -v rclone >/dev/null 2>&1; then
    echo "Instalando rclone via instalador oficial..."
    curl -sSf -L https://rclone.org/install.sh </dev/null | bash 2>/dev/null || true
fi

if command -v rclone >/dev/null 2>&1; then
    echo "✅ rclone: $(rclone --version 2>/dev/null | head -n 1)"
else
    echo "⚠️  rclone não pôde ser instalado. Verifique sua conexão com a internet."
fi

# Garantir que o serviço cron esteja ativo
systemctl enable cron >/dev/null 2>&1 || true
systemctl start cron >/dev/null 2>&1 || service cron start >/dev/null 2>&1 || true
echo "✅ Serviço cron verificado."
echo ""

# 3. Localizar contêiner PostgreSQL
echo "🔍 3. Localizando contêiner PostgreSQL do Supabase..."
DB_CONTAINER="${DB_CONTAINER:-}"

if [ -z "${DB_CONTAINER}" ]; then
    DB_CONTAINER=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -E 'supa?base.*db|supa?base-db' | head -n 1 || true)
fi
if [ -z "${DB_CONTAINER}" ]; then
    DB_CONTAINER=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -E 'postgres|db' | grep -v -E 'dpsjur-web|web|frontend|traefik|redis' | head -n 1 || true)
fi

if [ -z "${DB_CONTAINER}" ]; then
    echo "❌ Erro: Não foi possível localizar o contêiner do PostgreSQL via docker ps!"
    echo "Contêineres ativos:"
    docker ps --format 'table {{.Names}}\t{{.Status}}' 2>/dev/null || true
    exit 1
fi
echo "✅ Contêiner localizado: ${DB_CONTAINER}"

# Teste de conexão local socket
if docker exec "${DB_CONTAINER}" psql -U postgres -d postgres -tAc "SELECT 1;" >/dev/null 2>&1; then
    echo "✅ Conexão direta com PostgreSQL confirmada (socket local, sem senha)."
else
    echo "⚠️  Aviso: Não foi possível executar SELECT 1 no contêiner com usuário postgres."
fi
echo ""

# 4. Verificação do remoto Google Drive no rclone
echo "☁️  4. Verificando configuração do Google Drive no rclone..."
GDRIVE_CONFIGURED=0

if command -v rclone >/dev/null 2>&1; then
    if rclone listremotes 2>/dev/null | grep -q '^gdrive:'; then
        GDRIVE_CONFIGURED=1
        echo "✅ Remoto 'gdrive:' já configurado no rclone!"
    fi
fi

if [ $GDRIVE_CONFIGURED -eq 0 ]; then
    echo "---------------------------------------------------------------------"
    echo "⚠️  O remoto 'gdrive:' ainda NÃO está configurado no rclone."
    echo ""
    echo "Deseja configurar a autorização do Google Drive agora? [S/n]"
    read_interactive_input "👉 Escolha: " RESPOSTA_RCLONE "s"

    if [ "$RESPOSTA_RCLONE" != "n" ] && [ "$RESPOSTA_RCLONE" != "N" ]; then
        echo ""
        echo "====================================================================="
        echo "📋 PASSO A PASSO PARA AUTORIZAR O GOOGLE DRIVE NO RCLONE:"
        echo "====================================================================="
        echo "O rclone vai iniciar o assistente. Siga as respostas abaixo:"
        echo ""
        echo " 1. 'n/s/q> ': Digite 'n' (New remote)"
        echo " 2. 'name> ': Digite 'gdrive' (tudo minúsculo, sem aspas)"
        echo " 3. 'Storage> ': Digite 'drive' (ou o número correspondente a Google Drive)"
        echo " 4. 'client_id> ': Deixe em branco (aperte Enter)"
        echo " 5. 'client_secret> ': Deixe em branco (aperte Enter)"
        echo " 6. 'scope> ': Digite '1' (Full access to all files)"
        echo " 7. 'service_account_file> ': Deixe em branco (aperte Enter)"
        echo " 8. 'Edit advanced config?': Digite 'n' (No)"
        echo " 9. 'Use auto config?': Digite 'n' (No, pois o VPS não tem navegador)"
        echo ""
        echo " 10. O rclone mostrará um link longo na tela:"
        echo "     👉 COPIE O LINK COMPLETO, abra no navegador do seu computador,"
        echo "     faça login com advdouglaspsantos@gmail.com, autorize o rclone"
        echo "     e copie o CÓDIGO DE VERIFICAÇÃO que aparecerá na tela."
        echo ""
        echo " 11. Volte ao terminal do VPS e cole o código quando pedir 'verification code>'"
        echo " 12. 'Configure this as a Shared Drive (Team Drive)?': Digite 'n'"
        echo " 13. 'y/e/d> ': Digite 'y' (Yes this is OK)"
        echo " 14. 'e/n/d/r/c/s/q> ': Digite 'q' (Quit config)"
        echo "====================================================================="
        echo ""
        read_interactive_input "Pressione [Enter] para iniciar o assistente do rclone..." _ ""

        # O assistente interativo do rclone roda diretamente no terminal sem redirecionamento /dev/null
        if [ -t 0 ]; then
            rclone config
        elif [ -r /dev/tty ]; then
            rclone config < /dev/tty
        else
            rclone config
        fi

        if rclone listremotes 2>/dev/null | grep -q '^gdrive:'; then
            GDRIVE_CONFIGURED=1
            echo "✅ Google Drive configurado com sucesso como 'gdrive:'!"
            # Testar criação da pasta SBJur-Backups no Drive
            rclone mkdir gdrive:SBJur-Backups 2>/dev/null || true
        else
            echo "⚠️  O remoto 'gdrive:' não foi detectado após a configuração."
            echo "Você poderá rodar 'rclone config' novamente a qualquer momento."
        fi
    else
        echo "ℹ️  Etapa do Google Drive adiada. O backup local funcionará normalmente"
        echo "e a cópia externa será ativada assim que você rodar 'rclone config'."
    fi
fi
echo ""

# 5. Verificação da configuração de e-mail
echo "✉️  5. Verificando configuração de e-mail..."
EMAIL_ENV_FILE="${CONFIG_DIR}/email.conf"

if [ ! -f "${EMAIL_ENV_FILE}" ]; then
    echo "ℹ️  Configuração de e-mail ainda não realizada."
    read_interactive_input "Deseja configurar o envio de notificações por e-mail agora? [S/n]: " RESPOSTA_EMAIL "s"

    if [ "$RESPOSTA_EMAIL" != "n" ] && [ "$RESPOSTA_EMAIL" != "N" ]; then
        SCRIPT_EMAIL_DIR="$(dirname "${BASH_SOURCE[0]:-$0}")"
        if [ -f "${WORK_DIR}/04-configurar-email.sh" ]; then
            if [ -t 0 ]; then
                bash "${WORK_DIR}/04-configurar-email.sh" || true
            elif [ -r /dev/tty ]; then
                bash "${WORK_DIR}/04-configurar-email.sh" < /dev/tty || true
            else
                bash "${WORK_DIR}/04-configurar-email.sh" || true
            fi
        elif [ -f "${SCRIPT_EMAIL_DIR}/04-configurar-email.sh" ]; then
            if [ -t 0 ]; then
                bash "${SCRIPT_EMAIL_DIR}/04-configurar-email.sh" || true
            elif [ -r /dev/tty ]; then
                bash "${SCRIPT_EMAIL_DIR}/04-configurar-email.sh" < /dev/tty || true
            else
                bash "${SCRIPT_EMAIL_DIR}/04-configurar-email.sh" || true
            fi
        else
            echo "Baixando assistente de e-mail..."
            curl -sSf -L -H "Accept: application/vnd.github.v3.raw" \
                -H "User-Agent: DPSjur-BackupKit" \
                "https://api.github.com/repos/dowspaulo-wq/migra--o-sistema-legal-desk-fg93i2kgl/contents/docs/backup-fase6/04-configurar-email.sh?ref=main" \
                -o "/tmp/04-configurar-email.sh" </dev/null 2>/dev/null || true
            if [ -s "/tmp/04-configurar-email.sh" ]; then
                if [ -t 0 ]; then
                    bash "/tmp/04-configurar-email.sh" || true
                elif [ -r /dev/tty ]; then
                    bash "/tmp/04-configurar-email.sh" < /dev/tty || true
                else
                    bash "/tmp/04-configurar-email.sh" || true
                fi
                rm -f "/tmp/04-configurar-email.sh" 2>/dev/null || true
            else
                echo "⚠️  Não foi possível baixar o assistente de e-mail automaticamente."
            fi
        fi
    else
        echo "ℹ️  Configuração de e-mail ignorada por enquanto."
    fi
else
    echo "✅ Arquivo de configuração de e-mail já existe (${EMAIL_ENV_FILE})."
fi
echo ""

# 6. Gerar o script principal de execução diária: /root/sbjur-backups/backup.sh
echo "⚙️  6. Gerando script mestre de backup: ${BACKUP_SCRIPT}..."

cat <<'MASTER_BACKUP_EOF' > "${BACKUP_SCRIPT}"
#!/usr/bin/env bash
# ==============================================================================
# DPSjur / SBJur - Rotina Mestre de Backup Automático no VPS
# Executado diariamente às 03:00 pelo cron
# ==============================================================================

WORK_DIR="/root/sbjur-backups"
CONFIG_DIR="${WORK_DIR}/config"
LOGS_DIR="${WORK_DIR}/logs"
EMAIL_ENV_FILE="${CONFIG_DIR}/email.conf"
LOG_FILE="${LOGS_DIR}/backup.log"
DATE_STAMP=$(date '+%Y-%m-%d_%H%M%S' 2>/dev/null || echo "sem_data")
DAY_OF_WEEK=$(date '+%u' 2>/dev/null || echo "1")   # 1=Segunda ... 7=Domingo
DAY_OF_MONTH=$(date '+%d' 2>/dev/null || echo "01") # 01 ... 31
HUMAN_DATE=$(date '+%d/%m/%Y às %H:%M:%S' 2>/dev/null || echo "agora")
HOST_NOME=$(hostname 2>/dev/null || echo "VPS-Hostinger")

# Função para log duplo (terminal e arquivo)
log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || true)] $1"
    echo "${msg}"
    echo "${msg}" >> "${LOG_FILE}" 2>/dev/null || true
}

# Rotacionar log se passar de 10 MB
if [ -f "${LOG_FILE}" ]; then
    LOG_SIZE=$(stat -c%s "${LOG_FILE}" 2>/dev/null || echo 0)
    if [ "${LOG_SIZE}" -gt 10485760 ]; then
        mv "${LOG_FILE}" "${LOG_FILE}.old" 2>/dev/null || true
    fi
fi

log "====================================================================="
log "Iniciando rotina de backup SBJur (PostgreSQL Supabase + Google Drive)"
log "====================================================================="

# 1. Localizar contêiner PostgreSQL
DB_CONTAINER=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -E 'supa?base.*db|supa?base-db' | head -n 1 || true)
if [ -z "${DB_CONTAINER}" ]; then
    DB_CONTAINER=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -E 'postgres|db' | grep -v -E 'dpsjur-web|web|frontend|traefik|redis' | head -n 1 || true)
fi

if [ -z "${DB_CONTAINER}" ]; then
    log "❌ Erro crítico: Contêiner do banco PostgreSQL não encontrado via docker ps!"
    STATUS_BACKUP="FALHA"
    ERRO_DETALHE="Contêiner do PostgreSQL não encontrado no Docker."
fi

FILE_NAME="sbjur_backup_${DATE_STAMP}.sql.gz"
DAILY_PATH="${WORK_DIR}/diario/${FILE_NAME}"
STATUS_BACKUP="INICIADO"
ERRO_DETALHE=""
DUMP_SIZE="0"
TOTAL_TABELAS=0
TOTAL_REGISTROS=0

# 2. Executar pg_dump se contêiner foi localizado
if [ -n "${DB_CONTAINER}" ]; then
    log "Executando pg_dump no contêiner '${DB_CONTAINER}'..."

    # Execução do pg_dump comprimido com gzip
    if docker exec -i "${DB_CONTAINER}" pg_dump -U postgres -d postgres --clean --if-exists | gzip -9 > "${DAILY_PATH}"; then
        # Verificar se arquivo gerado não está vazio
        DUMP_BYTES=$(stat -c%s "${DAILY_PATH}" 2>/dev/null || echo 0)
        if [ "${DUMP_BYTES}" -gt 1000 ]; then
            DUMP_SIZE=$(du -h "${DAILY_PATH}" 2>/dev/null | awk '{print $1}' || echo "N/A")
            log "✅ Dump concluído com sucesso: ${DAILY_PATH} (${DUMP_SIZE}, ${DUMP_BYTES} bytes)"
            STATUS_BACKUP="SUCESSO"
        else
            log "❌ Erro: Arquivo de dump gerado possui tamanho insignificante (${DUMP_BYTES} bytes)!"
            STATUS_BACKUP="FALHA"
            ERRO_DETALHE="Dump gerado muito pequeno (${DUMP_BYTES} bytes), possível falha no pg_dump."
        fi
    else
        log "❌ Erro na execução do pg_dump dentro do contêiner!"
        STATUS_BACKUP="FALHA"
        ERRO_DETALHE="Comando pg_dump retornou erro no PostgreSQL."
    fi

    # Coleta de contagens rápidas para o relatório
    if [ "${STATUS_BACKUP}" = "SUCESSO" ]; then
        CONTAGENS_RESUMO=$(docker exec -i "${DB_CONTAINER}" psql -U postgres -d postgres -tAc "
            SELECT 
                (SELECT count(*) FROM public.clients) || ' clientes | ' ||
                (SELECT count(*) FROM public.cases) || ' processos | ' ||
                (SELECT count(*) FROM public.tasks) || ' tarefas | ' ||
                (SELECT count(*) FROM public.transactions) || ' transações | ' ||
                (SELECT count(*) FROM auth.users) || ' usuários auth';
        " 2>/dev/null || echo "Contagem não disponível")
        log "Estatísticas do banco: ${CONTAGENS_RESUMO}"
    fi
fi

# 3. Política de retenção local
if [ "${STATUS_BACKUP}" = "SUCESSO" ]; then
    # Se hoje for Domingo (DAY_OF_WEEK=7), copiar para /semanal/
    if [ "${DAY_OF_WEEK}" = "7" ]; then
        log "📅 Hoje é Domingo: salvando snapshot na pasta /semanal/..."
        cp "${DAILY_PATH}" "${WORK_DIR}/semanal/${FILE_NAME}" 2>/dev/null || true
    fi

    # Se hoje for dia 1º do mês (DAY_OF_MONTH=01), copiar para /mensal/
    if [ "${DAY_OF_MONTH}" = "01" ] || [ "${DAY_OF_MONTH}" = "1" ]; then
        log "📅 Hoje é 1º dia do mês: salvando snapshot na pasta /mensal/..."
        cp "${DAILY_PATH}" "${WORK_DIR}/mensal/${FILE_NAME}" 2>/dev/null || true
    fi

    # Limpeza de retenção local:
    # Diários: manter apenas últimos 7 dias (apagar com mais de 7 dias)
    find "${WORK_DIR}/diario" -type f -name "sbjur_backup_*.sql.gz" -mtime +7 -delete 2>/dev/null || true

    # Semanal: manter 30 dias (apagar com mais de 30 dias)
    find "${WORK_DIR}/semanal" -type f -name "sbjur_backup_*.sql.gz" -mtime +30 -delete 2>/dev/null || true

    # Mensal: manter 1 ano (apagar com mais de 365 dias)
    find "${WORK_DIR}/mensal" -type f -name "sbjur_backup_*.sql.gz" -mtime +365 -delete 2>/dev/null || true

    log "✅ Política de retenção local aplicada (diário 7d, semanal 30d, mensal 365d)."
fi

# 4. Sincronização externa com Google Drive via rclone
UPLOAD_DRIVE_STATUS="NAO_CONFIGURADO"
if command -v rclone >/dev/null 2>&1; then
    if rclone listremotes 2>/dev/null | grep -q '^gdrive:'; then
        if [ "${STATUS_BACKUP}" = "SUCESSO" ]; then
            log "☁️ Sincronizando pastas com o Google Drive (gdrive:SBJur-Backups)..."

            # Copiar diário para o Drive
            if rclone copy "${DAILY_PATH}" gdrive:SBJur-Backups/diario/ --drive-stop-on-upload-limit 2>> "${LOG_FILE}"; then
                UPLOAD_DRIVE_STATUS="SUCESSO"
                log "✅ Arquivo diário enviado ao Google Drive com sucesso."
            else
                UPLOAD_DRIVE_STATUS="FALHA"
                log "⚠️ Falha ao enviar backup para o Google Drive."
            fi

            # Se domingo, copiar semanal
            if [ "${DAY_OF_WEEK}" = "7" ] && [ -f "${WORK_DIR}/semanal/${FILE_NAME}" ]; then
                rclone copy "${WORK_DIR}/semanal/${FILE_NAME}" gdrive:SBJur-Backups/semanal/ 2>> "${LOG_FILE}" || true
            fi

            # Se dia 1, copiar mensal
            if [ "${DAY_OF_MONTH}" = "01" ] || [ "${DAY_OF_MONTH}" = "1" ]; then
                if [ -f "${WORK_DIR}/mensal/${FILE_NAME}" ]; then
                    rclone copy "${WORK_DIR}/mensal/${FILE_NAME}" gdrive:SBJur-Backups/mensal/ 2>> "${LOG_FILE}" || true
                fi
            fi

            # Política de retenção no Google Drive via rclone delete
            # Diários no drive: apagar com mais de 7 dias
            rclone delete --min-age 7d gdrive:SBJur-Backups/diario/ 2>> "${LOG_FILE}" || true
            # Semanal no drive: apagar com mais de 30 dias
            rclone delete --min-age 30d gdrive:SBJur-Backups/semanal/ 2>> "${LOG_FILE}" || true
            # Mensal no drive: apagar com mais de 365 dias
            rclone delete --min-age 365d gdrive:SBJur-Backups/mensal/ 2>> "${LOG_FILE}" || true

            log "✅ Política de retenção remota no Google Drive aplicada."
        fi
    else
        log "ℹ️ Remoto 'gdrive:' não configurado no rclone. Cópia externa ignorada."
    fi
else
    log "ℹ️ rclone não instalado. Cópia externa ignorada."
fi

# 5. Envio do relatório por e-mail
if [ -f "${EMAIL_ENV_FILE}" ]; then
    # shellcheck disable=SC1090
    . "${EMAIL_ENV_FILE}" 2>/dev/null || true
fi

DEST_EMAIL="${SMTP_TO:-advdouglaspsantos@gmail.com}"
REMET_EMAIL="${SMTP_USER:-advdouglaspsantos@gmail.com}"

if [ -n "${SMTP_PASS:-}" ] && [ "${SMTP_ENABLED:-true}" = "true" ]; then
    log "✉️ Preparando envio de notificação por e-mail para ${DEST_EMAIL}..."

    MSG_FILE="/tmp/sbjur-email-report-$$.txt"

    if [ "${STATUS_BACKUP}" = "SUCESSO" ]; then
        ASSUNTO="[SBJur] Backup Diario Concluido com Sucesso - ${DATE_STAMP}"
        cat <<'EMAIL_EOF' > "${MSG_FILE}"
From: SBJur Backup <${REMET_EMAIL}>
To: ${DEST_EMAIL}
Subject: ${ASSUNTO}
Content-Type: text/plain; charset=UTF-8

Ola, Douglas!

O backup diario do SBJur no VPS (${HOST_NOME}) foi executado com SUCESSO.

Resumo da Operacao:
---------------------------------------------------------------------
Data/Hora: ${HUMAN_DATE}
Arquivo: ${FILE_NAME}
Tamanho: ${DUMP_SIZE}
Status Local: Sucesso (/root/sbjur-backups/diario)
Google Drive: ${UPLOAD_DRIVE_STATUS} (pasta SBJur-Backups/diario)
Conteudo do Banco: ${CONTAGENS_RESUMO:-OK}
---------------------------------------------------------------------

Politica de Retencao Aplicada:
 - Diarios: ultimos 7 dias mantidos
 - Semanal: domingo mantido por 30 dias
 - Mensal: dia 1 mantido por 1 ano

Seus dados estao seguros!
EMAIL_EOF
    else
        ASSUNTO="[ALERTA SBJur] FALHA no Backup Diario - ${DATE_STAMP}"
        cat <<'EMAIL_EOF' > "${MSG_FILE}"
From: SBJur Backup <${REMET_EMAIL}>
To: ${DEST_EMAIL}
Subject: ${ASSUNTO}
Content-Type: text/plain; charset=UTF-8

ATENCAO DOUGLAS!

Ocorreu uma FALHA durante a execucao da rotina de backup diario do SBJur no VPS (${HOST_NOME}).

Detalhes da Falha:
---------------------------------------------------------------------
Data/Hora: ${HUMAN_DATE}
Erro identificado: ${ERRO_DETALHE:-Falha desconhecida no pg_dump ou Docker}
Contêiner: ${DB_CONTAINER:-Nao localizado}
Log: /root/sbjur-backups/logs/backup.log
---------------------------------------------------------------------

Por favor, verifique o terminal do VPS ou execute manualmente:
  bash /root/sbjur-backups/02-testar-backup.sh
EMAIL_EOF
    fi

    # Envio via msmtp com fallback para curl
    ENVIADO=0
    if command -v msmtp >/dev/null 2>&1; then
        if msmtp -a default "${DEST_EMAIL}" < "${MSG_FILE}" 2>/dev/null; then
            ENVIADO=1
        fi
    fi

    if [ $ENVIADO -eq 0 ] && command -v curl >/dev/null 2>&1; then
        if curl --silent --show-error \
            --url "smtp://smtp.gmail.com:587" \
            --ssl-reqd \
            --mail-from "${REMET_EMAIL}" \
            --mail-rcpt "${DEST_EMAIL}" \
            --user "${REMET_EMAIL}:${SMTP_PASS}" \
            --upload-file "${MSG_FILE}" >/dev/null 2>&1; then
            ENVIADO=1
        fi
    fi

    rm -f "${MSG_FILE}" 2>/dev/null || true

    if [ $ENVIADO -eq 1 ]; then
        log "✅ E-mail de notificação enviado para ${DEST_EMAIL}."
    else
        log "⚠️ Falha ao despachar e-mail via SMTP."
    fi
else
    log "ℹ️ Envio de e-mail desativado ou credenciais ausentes em ${EMAIL_ENV_FILE}."
fi

log "Rotina de backup finalizada com status: ${STATUS_BACKUP}."
log "====================================================================="
MASTER_BACKUP_EOF

chmod 755 "${BACKUP_SCRIPT}" || true
echo "✅ Script ${BACKUP_SCRIPT} gravado com permissão de execução."
echo ""

# 7. Registrar no Cron do sistema (às 03:00 todo dia) de forma idempotente
echo "⏰ 7. Configurando agendamento no cron (todos os dias às 03:00)..."
CRON_CMD="0 3 * * * ${BACKUP_SCRIPT} >/dev/null 2>&1"
CURRENT_CRON=$(crontab -l 2>/dev/null || true)

if echo "${CURRENT_CRON}" | grep -q "${BACKUP_SCRIPT}"; then
    echo "ℹ️  O agendamento já estava registrado no crontab. Atualizando entrada..."
    # Remove entradas antigas do backup.sh e readiciona uma única
    NEW_CRON=$(echo "${CURRENT_CRON}" | grep -v "${BACKUP_SCRIPT}")
    (echo "${NEW_CRON}"; echo "${CRON_CMD}") | crontab -
else
    echo "Adicionando linha no crontab do root..."
    (echo "${CURRENT_CRON}"; echo "${CRON_CMD}") | crontab -
fi

echo "✅ Crontab atualizado com sucesso. Entrada ativa:"
crontab -l 2>/dev/null | grep "${BACKUP_SCRIPT}" || true
echo ""

# 8. Baixar scripts complementares para /root/sbjur-backups/
echo "📥 8. Baixando scripts complementares para ${WORK_DIR}..."
download_aux_script "02-testar-backup.sh"
download_aux_script "03-testar-restauracao.sh"
download_aux_script "04-configurar-email.sh"

echo "✅ Scripts em ${WORK_DIR}:"
ls -la "${WORK_DIR}" | grep -E '\.sh$' || true
echo ""

# 9. Conclusão e instruções finais
echo "====================================================================="
echo "🎉 INSTALAÇÃO DA FASE 6 CONCLUÍDA COM SUCESSO!"
echo "====================================================================="
echo ""
echo "Resumo do que foi instalado e configurado:"
echo " 1. Pastas criadas: /root/sbjur-backups/{diario,semanal,mensal,logs}"
echo " 2. Script mestre: /root/sbjur-backups/backup.sh (pg_dump + gzip + retenção)"
echo " 3. Cron ativado: diariamente às 03:00 da manhã"
echo " 4. Destinatário de avisos: ${DEFAULT_EMAIL}"
echo ""
echo "👉 Próximo passo recomendado para validar tudo agora:"
echo "   bash /root/sbjur-backups/02-testar-backup.sh"
echo "====================================================================="

exit 0
