#!/usr/bin/env bash
# ==============================================================================
# DPSjur / SBJur - Fase 6: Sistema de Backup Automático no VPS (Hostinger KVM 1)
# Script: docs/backup-fase6/04-configurar-email.sh
# Versão: v1.0.0
# Destinatário padrão: advdouglaspsantos@gmail.com
# ==============================================================================

SCRIPT_VERSION="v1.0.0"
CONFIG_DIR="/root/sbjur-backups/config"
MSMTP_CONF="/root/.msmtprc"
EMAIL_ENV_FILE="${CONFIG_DIR}/email.conf"
DEFAULT_EMAIL="advdouglaspsantos@gmail.com"

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

# 1. Garantir diretórios
mkdir -p "${CONFIG_DIR}" 2>/dev/null || true
mkdir -p /root/sbjur-backups/logs 2>/dev/null || true

# 2. Instalar msmtp e ca-certificates se necessário
echo "📦 1. Verificando utilitário de e-mail (msmtp)..."
if ! command -v msmtp >/dev/null 2>&1; then
    echo "Instalando msmtp e certificados SSL..."
    apt-get update -qq >/dev/null 2>&1 || true
    DEBIAN_FRONTEND=noninteractive apt-get install -y msmtp msmtp-mta ca-certificates curl >/dev/null 2>&1 || {
        echo "⚠️  Tentativa com apt-get normal:"
        apt-get install -y msmtp msmtp-mta ca-certificates curl || true
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

if [ -n "${SMTP_USER:-}" ]; then
    echo "Configuração atual encontrada para o e-mail: ${SMTP_USER}"
    printf "Deseja manter %s? [S/n]: " "${SMTP_USER}"
    read -r KEEP_USER || KEEP_USER="s"
    if [ "$KEEP_USER" != "n" ] && [ "$KEEP_USER" != "N" ]; then
        GMAIL_USER="${SMTP_USER}"
    fi
fi

if [ -z "${GMAIL_USER}" ]; then
    printf "👉 Digite o e-mail remetente/destinatário [%s]: " "${DEFAULT_EMAIL}"
    read -r INPUT_USER || INPUT_USER=""
    if [ -n "${INPUT_USER}" ]; then
        GMAIL_USER="${INPUT_USER}"
    else
        GMAIL_USER="${DEFAULT_EMAIL}"
    fi
fi

printf "👉 Digite ou cole a Senha de App de 16 letras do Gmail: "
stty -echo 2>/dev/null || true
read -r INPUT_PASS || INPUT_PASS=""
stty echo 2>/dev/null || true
echo ""

# Remove espaços que o Google às vezes inclui ao copiar
GMAIL_PASS=$(echo "${INPUT_PASS}" | tr -d ' ')

if [ -z "${GMAIL_PASS}" ]; then
    if [ -n "${SMTP_PASS:-}" ]; then
        echo "ℹ️  Mantendo a senha salva anteriormente."
        GMAIL_PASS="${SMTP_PASS}"
    else
        echo "❌ Erro: Senha de App não fornecida. Configuração não gravada."
        exit 1
    fi
fi

# 4. Gravar arquivo de ambiente /root/sbjur-backups/config/email.conf (permissão 600)
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

# 5. Gravar /root/.msmtprc (se msmtp estiver presente)
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

# 6. Teste de envio de e-mail agora
echo "✉️  4. Enviando e-mail de teste para ${GMAIL_USER}..."
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

# Tentativa 1: msmtp
if command -v msmtp >/dev/null 2>&1; then
    if msmtp -a default "${GMAIL_USER}" < "${TEST_MSG_FILE}" 2>/dev/null; then
        EMAIL_ENVIADO=1
    fi
fi

# Tentativa 2: fallback nativo via curl SMTP
if [ $EMAIL_ENVIADO -eq 0 ] && command -v curl >/dev/null 2>&1; then
    echo "ℹ️  Tentando envio via curl SMTP..."
    if curl --silent --show-error \
        --url "smtp://smtp.gmail.com:587" \
        --ssl-reqd \
        --mail-from "${GMAIL_USER}" \
        --mail-rcpt "${GMAIL_USER}" \
        --user "${GMAIL_USER}:${GMAIL_PASS}" \
        --upload-file "${TEST_MSG_FILE}" >/dev/null 2>&1; then
        EMAIL_ENVIADO=1
    fi
fi

rm -f "${TEST_MSG_FILE}" 2>/dev/null || true

if [ $EMAIL_ENVIADO -eq 1 ]; then
    echo "====================================================================="
    echo "🎉 E-MAIL DE TESTE ENVIADO COM SUCESSO!"
    echo "   Abra a caixa de entrada de ${GMAIL_USER} para conferir."
    echo "====================================================================="
else
    echo "====================================================================="
    echo "⚠️  Aviso: O envio do e-mail de teste retornou falha."
    echo "Causas comuns:"
    echo " 1. Senha de App digitada incorretamente (precisa ser de 16 letras, sem espaços);"
    echo " 2. Verificação em 2 etapas não ativada na conta Google;"
    echo " 3. Bloqueio de porta 587 no VPS da Hostinger (muito raro)."
    echo ""
    echo "Você pode rodar este script novamente a qualquer momento para corrigir:"
    echo "  bash /root/sbjur-backups/04-configurar-email.sh"
    echo "====================================================================="
fi

exit 0
