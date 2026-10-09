#!/usr/bin/env bash
# ==============================================================================
# DPSjur / SBJur - Fase 6: Sistema de Backup Automático no VPS (Hostinger KVM 1)
# Script: docs/backup-fase6/04-configurar-email.sh
# Versão: v1.1.0
# Destinatário padrão: advdouglaspsantos@gmail.com
# ==============================================================================

set -u

SCRIPT_VERSION="v1.1.0"
WORK_DIR="/root/sbjur-backups"
CONFIG_DIR="${WORK_DIR}/config"
LOGS_DIR="${WORK_DIR}/logs"
MSMTP_CONF="/root/.msmtprc"
EMAIL_ENV_FILE="${CONFIG_DIR}/email.conf"
DEFAULT_EMAIL="advdouglaspsantos@gmail.com"
COPIA_SCRIPT_DEST="${WORK_DIR}/04-configurar-email.sh"

echo "====================================================================="
echo " DPSjur / SBJur - Fase 6: Configuração de Notificação por E-mail"
echo " Versão: ${SCRIPT_VERSION}"
echo "====================================================================="
echo "Data: $(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || true)"
echo ""
echo "Este script configura o envio automático de avisos diários de backup para:"
echo "👉 ${DEFAULT_EMAIL}"
echo "Utiliza o servidor SMTP oficial do Gmail (smtp.gmail.com:587 TLS) com Senha de App."
echo ""

# 1. Garantir diretórios base desde o início
mkdir -p "${WORK_DIR}" 2>/dev/null || true
mkdir -p "${CONFIG_DIR}" 2>/dev/null || true
mkdir -p "${LOGS_DIR}" 2>/dev/null || true
chmod 700 "${WORK_DIR}" 2>/dev/null || true

# 2. Instalar msmtp e ca-certificates se necessário (com /dev/null redirecionado em comandos que poderiam ler stdin)
echo "📦 1. Verificando utilitário de e-mail (msmtp)..."
if ! command -v msmtp >/dev/null 2>&1; then
    echo "Instalando msmtp e certificados SSL..."
    apt-get update -qq </dev/null >/dev/null 2>&1 || true
    DEBIAN_FRONTEND=noninteractive apt-get install -y msmtp msmtp-mta ca-certificates curl </dev/null >/dev/null 2>&1 || {
        echo "⚠️  Tentativa com apt-get normal:"
        DEBIAN_FRONTEND=noninteractive apt-get install -y msmtp msmtp-mta ca-certificates curl </dev/null || true
    }
fi

if command -v msmtp >/dev/null 2>&1; then
    echo "✅ Utilitário msmtp instalado e disponível."
else
    echo "⚠️  msmtp não pôde ser instalado diretamente. O sistema usará o fallback nativo via curl SMTP."
fi
echo ""

# 3. Coleta de dados com o usuário Douglas
echo "🔑 2. Credenciais do Gmail para envio de alertas"
echo "---------------------------------------------------------------------"
echo "Para enviar e-mails de aviso, o Google exige uma 'Senha de App' de 16 letras."
echo "Se você ainda não gerou:"
echo " 1. Acesse: https://myaccount.google.com/apppasswords"
echo " 2. Faça login com: ${DEFAULT_EMAIL}"
echo " 3. Dê o nome 'SBJur Backup VPS' e clique em 'Criar'"
echo " 4. Copie a senha amarela de 16 letras gerada (ex: abcd efgh ijkl mnop)"
echo "---------------------------------------------------------------------"
echo ""

GMAIL_USER=""
GMAIL_PASS=""

# Carregar existente se já configurado
if [ -f "${EMAIL_ENV_FILE}" ]; then
    # shellcheck disable=SC1090
    . "${EMAIL_ENV_FILE}" 2>/dev/null || true
fi

# Leitura segura do e-mail com fallback para /dev/tty caso rodando via pipe
read_user_input() {
    local prompt_msg="$1"
    local var_name="$2"
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
    eval "${var_name}=\"\$val\""
}

read_password_input() {
    local prompt_msg="$1"
    local var_name="$2"
    local val=""
    if [ -t 0 ]; then
        printf "%s" "${prompt_msg}"
        stty -echo 2>/dev/null || true
        read -r val || true
        stty echo 2>/dev/null || true
        echo ""
    elif [ -r /dev/tty ]; then
        printf "%s" "${prompt_msg}" > /dev/tty
        stty -echo < /dev/tty 2>/dev/null || true
        read -r val < /dev/tty || true
        stty echo < /dev/tty 2>/dev/null || true
        echo "" > /dev/tty
    else
        printf "%s" "${prompt_msg}"
        stty -echo 2>/dev/null || true
        read -r val || true
        stty echo 2>/dev/null || true
        echo ""
    fi
    eval "${var_name}=\"\$val\""
}

if [ -n "${SMTP_USER:-}" ]; then
    echo "Configuração atual encontrada para o e-mail: ${SMTP_USER}"
    read_user_input "Deseja manter ${SMTP_USER}? [S/n]: " KEEP_USER
    KEEP_USER="${KEEP_USER:-s}"
    if [ "$KEEP_USER" != "n" ] && [ "$KEEP_USER" != "N" ]; then
        GMAIL_USER="${SMTP_USER}"
    fi
fi

if [ -z "${GMAIL_USER}" ]; then
    read_user_input "👉 Digite o e-mail remetente/destinatário [${DEFAULT_EMAIL}]: " INPUT_USER
    if [ -n "${INPUT_USER}" ]; then
        GMAIL_USER="${INPUT_USER}"
    else
        GMAIL_USER="${DEFAULT_EMAIL}"
    fi
fi

# Validação e coleta da Senha de App (exatamente 16 letras alfabéticas)
while true; do
    read_password_input "👉 Digite ou cole a Senha de App de 16 letras do Gmail: " INPUT_PASS

    # Remove espaços em branco, tabs e quebras de linha
    CLEAN_PASS=$(echo "${INPUT_PASS}" | tr -d '[:space:]')

    # Se estiver vazio mas já tínhamos senha anterior salva
    if [ -z "${CLEAN_PASS}" ]; then
        if [ -n "${SMTP_PASS:-}" ]; then
            echo "ℹ️  Mantendo a senha salva anteriormente."
            GMAIL_PASS="${SMTP_PASS}"
            break
        else
            echo "⚠️  Senha vazia! É necessário informar a Senha de App de 16 letras."
            continue
        fi
    fi

    # Validação antecipada: exatamente 16 caracteres alfabéticos (a-z, A-Z)
    NUM_CHARS=${#CLEAN_PASS}
    IS_ALPHA=0
    if echo "${CLEAN_PASS}" | grep -qE '^[a-zA-Z]{16}$'; then
        IS_ALPHA=1
    fi

    if [ ${IS_ALPHA} -eq 1 ]; then
        GMAIL_PASS="${CLEAN_PASS}"
        break
    else
        echo ""
        echo "❌ Senha de App inválida!"
        echo "   - Tamanho digitado: ${NUM_CHARS} caracteres (esperado: exatamente 16);"
        if ! echo "${CLEAN_PASS}" | grep -qE '^[a-zA-Z]+$'; then
            echo "   - Atenção: a senha deve conter APENAS letras (sem números, sem símbolos)."
        fi
        echo "   Dica: a Senha de App do Google possui 4 blocos de 4 letras (ex: abcd efgh ijkl mnop)."
        echo "   Gere uma nova em https://myaccount.google.com/apppasswords se necessário."
        echo ""
        echo "Por favor, tente novamente:"
    fi
done

# 4. Gravar arquivo de ambiente /root/sbjur-backups/config/email.conf (permissão 600)
echo ""
echo "💾 3. Gravando arquivos de configuração seguros..."

cat <<EOF > "${EMAIL_ENV_FILE}"
# Configuração SMTP gerada pelo kit SBJur Fase 6
SMTP_ENABLED=true
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USER=${GMAIL_USER}
SMTP_PASS=${GMAIL_PASS}
SMTP_TO=${GMAIL_USER}
EOF
chmod 600 "${EMAIL_ENV_FILE}" 2>/dev/null || true

# 5. Gravar /root/.msmtprc
cat <<EOF > "${MSMTP_CONF}"
defaults
auth           on
tls            on
tls_trust_file /etc/ssl/certs/ca-certificates.crt
logfile        /root/sbjur-backups/logs/msmtp.log

account        gmail
host           smtp.gmail.com
port           587
from           ${GMAIL_USER}
user           ${GMAIL_USER}
password       ${GMAIL_PASS}

account default : gmail
EOF
chmod 600 "${MSMTP_CONF}" 2>/dev/null || true

echo "✅ Configurações gravadas com permissão restrita (600)."
echo ""

# 6. Teste de conectividade prévia (Porta 587 no Gmail)
echo "🌐 4. Testando conectividade de rede com smtp.gmail.com:587..."
PORT_OK=0
if timeout 10 bash -c 'cat < /dev/null > /dev/tcp/smtp.gmail.com/587' 2>/dev/null; then
    PORT_OK=1
    echo "✅ Conectividade TCP com smtp.gmail.com:587 confirmada."
else
    echo "⚠️  Não foi possível abrir conexão direta na porta 587 (timeout ou bloqueio de firewall/provedor)."
fi
echo ""

# 7. Teste de envio de e-mail com captura completa de erros técnicos
echo "✉️  5. Enviando e-mail de teste para ${GMAIL_USER}..."
DATA_TESTE=$(date '+%d/%m/%Y às %H:%M:%S' 2>/dev/null || echo "agora")
HOST_NOME=$(hostname 2>/dev/null || echo "VPS-Hostinger")

TEST_MSG_FILE="/tmp/sbjur-teste-email-$$.txt"
cat <<EOF > "${TEST_MSG_FILE}"
From: SBJur Backup <${GMAIL_USER}>
To: ${GMAIL_USER}
Subject: [SBJur] Teste de Notificacao de Backup - Sucesso!
Content-Type: text/plain; charset=UTF-8

Ola, Douglas!

Esta e uma mensagem de teste enviada diretamente do VPS (${HOST_NOME}).

Seu sistema de notificacoes de backup do SBJur foi configurado com sucesso!
A partir de agora, toda madrugada as 03:00 o VPS executara a rotina:
 1. Dump seguro do PostgreSQL do Supabase local;
 2. Aplicacao da politica de retencao (7 diarios, 30 dias de domingo, 1 ano de dia 1);
 3. Envio seguro para o seu Google Drive (pasta SBJur-Backups);
 4. Envio de relatorio diario de status para ${GMAIL_USER}.

Data/Hora do teste: ${DATA_TESTE}
Status: OK
EOF

EMAIL_ENVIADO=0
DIAG_LOG_FILE="/tmp/sbjur-smtp-diag-$$.log"
rm -f "${DIAG_LOG_FILE}" 2>/dev/null || true

# Tentativa 1: msmtp com captura de saída verbosa
if command -v msmtp >/dev/null 2>&1; then
    echo "ℹ️  Tentando envio via msmtp..."
    if msmtp --debug -a default "${GMAIL_USER}" < "${TEST_MSG_FILE}" > "${DIAG_LOG_FILE}" 2>&1; then
        EMAIL_ENVIADO=1
    fi
fi

# Tentativa 2: fallback curl SMTP com verbose completo
if [ $EMAIL_ENVIADO -eq 0 ] && command -v curl >/dev/null 2>&1; then
    echo "ℹ️  Tentando envio via curl SMTP (com diagnóstico detalhado)..."
    CURL_DIAG_FILE="/tmp/sbjur-curl-diag-$$.log"
    if curl -v \
        --url "smtp://smtp.gmail.com:587" \
        --ssl-reqd \
        --mail-from "${GMAIL_USER}" \
        --mail-rcpt "${GMAIL_USER}" \
        --user "${GMAIL_USER}:${GMAIL_PASS}" \
        --upload-file "${TEST_MSG_FILE}" > "${CURL_DIAG_FILE}" 2>&1; then
        EMAIL_ENVIADO=1
    else
        # Acrescenta saída do curl ao log de diagnóstico se msmtp também falhou
        {
            echo "--- Detalhes do fallback curl SMTP ---"
            cat "${CURL_DIAG_FILE}" 2>/dev/null || true
        } >> "${DIAG_LOG_FILE}"
    fi
    rm -f "${CURL_DIAG_FILE}" 2>/dev/null || true
fi

rm -f "${TEST_MSG_FILE}" 2>/dev/null || true

echo ""
if [ $EMAIL_ENVIADO -eq 1 ]; then
    echo "====================================================================="
    echo "🎉 E-MAIL DE TESTE ENVIADO COM SUCESSO!"
    echo "   Abra a caixa de entrada de ${GMAIL_USER} para conferir."
    echo "====================================================================="
    echo ""
    echo "👉 Próximos passos do kit de backup no VPS:"
    echo " 1. Se ainda não executou a instalação mestra com agendamento do cron:"
    echo "    bash /root/sbjur-backups/01-instalar-backup.sh"
    echo " 2. Para testar o ciclo completo de backup (dump + Drive + e-mail agora):"
    echo "    bash /root/sbjur-backups/02-testar-backup.sh"
    echo " 3. Para auditar a recuperação sem risco num banco temporário:"
    echo "    bash /root/sbjur-backups/03-testar-restauracao.sh"
    echo "====================================================================="
else
    echo "====================================================================="
    echo "⚠️  Aviso: O envio do e-mail de teste retornou falha."
    echo "====================================================================="
    echo ""
    echo "🔍 Saída técnica do servidor (para diagnóstico):"
    echo "---------------------------------------------------------------------"
    if [ -s "${DIAG_LOG_FILE}" ]; then
        # Exibe as linhas relevantes de erro/resposta do SMTP filtrando tokens e dados sensíveis
        grep -E -i '535|5\.7\.8|error|failed|alert|auth|password|denied|timeout|refused|handshake|tls|ssl|connect|smtp' "${DIAG_LOG_FILE}" 2>/dev/null || tail -n 25 "${DIAG_LOG_FILE}" 2>/dev/null || true
    else
        echo "Nenhuma resposta obtida do servidor SMTP (possível falha de resolução DNS ou bloqueio total)."
    fi
    echo "---------------------------------------------------------------------"
    echo ""

    # Interpretação amigável do erro técnico capturado
    if grep -q -i -E '535|5\.7\.8|Username and Password not accepted|authentication failed' "${DIAG_LOG_FILE}" 2>/dev/null; then
        echo "💡 Diagnóstico identificado: ERRO 535 5.7.8 - Senha de App recusada pelo Google."
        echo "   Possíveis motivos:"
        echo "    a) A Senha de App foi digitada ou gerada com algum caractere divergente;"
        echo "    b) A Senha de App foi revogada ou excluída no Google;"
        echo "    c) A conta ${GMAIL_USER} não está com a 'Verificação em 2 etapas' ligada;"
        echo "    d) Foi usada a senha pessoal da conta Google em vez de uma 'Senha de App'."
    elif grep -q -i -E 'timed? out|Connection timed out|port 587: Connection refused' "${DIAG_LOG_FILE}" 2>/dev/null || [ ${PORT_OK} -eq 0 ]; then
        echo "💡 Diagnóstico identificado: Falha de conexão na porta 587 (timeout/bloqueio)."
        echo "   O servidor não conseguiu completar o handshake com smtp.gmail.com:587."
    fi
    echo ""

    echo "Causas comuns:"
    echo " 1. Senha de App digitada incorretamente (precisa ser de 16 letras, sem espaços);"
    echo " 2. Verificação em 2 etapas não ativada na conta Google (https://myaccount.google.com/security);"
    echo " 3. Foi digitada a senha normal do e-mail em vez da Senha de App em https://myaccount.google.com/apppasswords;"
    echo " 4. Bloqueio de porta 587 no VPS da Hostinger (muito raro)."
    echo ""
    echo "Você pode rodar este script novamente a qualquer momento para corrigir:"
    echo "  bash /root/sbjur-backups/04-configurar-email.sh"
    echo "====================================================================="
fi

rm -f "${DIAG_LOG_FILE}" 2>/dev/null || true

# 8. Auto-instalação: garantir cópia em /root/sbjur-backups/04-configurar-email.sh
echo ""
echo "📥 Garantindo disponibilidade local do script em ${WORK_DIR}..."
mkdir -p "${WORK_DIR}" 2>/dev/null || true

SCRIPT_COPIADO=0
SCRIPT_ORIGEM="${BASH_SOURCE[0]:-$0}"

# Se estiver rodando a partir de um arquivo já existente no disco
if [ -f "${SCRIPT_ORIGEM}" ] && [ "${SCRIPT_ORIGEM}" != "${COPIA_SCRIPT_DEST}" ]; then
    cp -f "${SCRIPT_ORIGEM}" "${COPIA_SCRIPT_DEST}" 2>/dev/null && SCRIPT_COPIADO=1
elif [ -f "${COPIA_SCRIPT_DEST}" ]; then
    SCRIPT_COPIADO=1
fi

# Se foi executado via pipe (curl ... | bash) ou arquivo origem inacessível, baixa a versão oficial do GitHub
if [ $SCRIPT_COPIADO -eq 0 ]; then
    GH_RAW="https://raw.githubusercontent.com/dowspaulo-wq/migra--o-sistema-legal-desk-fg93i2kgl/main/docs/backup-fase6/04-configurar-email.sh"
    GH_API="https://api.github.com/repos/dowspaulo-wq/migra--o-sistema-legal-desk-fg93i2kgl/contents/docs/backup-fase6/04-configurar-email.sh?ref=main"

    curl -sSf -L -H "Accept: application/vnd.github.v3.raw" -H "User-Agent: DPSjur-BackupKit" \
        "${GH_API}" -o "${COPIA_SCRIPT_DEST}" </dev/null 2>/dev/null || \
    curl -sSf -L -H "Cache-Control: no-cache" "${GH_RAW}" -o "${COPIA_SCRIPT_DEST}" </dev/null 2>/dev/null || true

    if [ -s "${COPIA_SCRIPT_DEST}" ]; then
        SCRIPT_COPIADO=1
    fi
fi

if [ -f "${COPIA_SCRIPT_DEST}" ]; then
    chmod 755 "${COPIA_SCRIPT_DEST}" 2>/dev/null || true
    echo "✅ Script instalado e pronto para reexecução em: ${COPIA_SCRIPT_DEST}"
    echo "   Para reexecutar a qualquer momento no VPS: bash ${COPIA_SCRIPT_DEST}"
else
    echo "⚠️  Não foi possível salvar cópia automática em ${COPIA_SCRIPT_DEST}."
fi
echo ""

exit 0