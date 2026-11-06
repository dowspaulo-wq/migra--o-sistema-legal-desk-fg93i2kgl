#!/usr/bin/env bash
# ==============================================================================
# DPSjur / SBJur - Instalador das Rotinas Automáticas de E-mail no VPS
# Script: docs/vps/11-rotinas-email-vps.sh
# Versão: v1.0.0
#
# O QUE INSTALA (pedidos exatos do Douglas):
#   ROTINA 1 - Véspera: e-mail às 07:00 BSB com audiências/compromissos do
#     DIA SEGUINTE. Regra do usuário: compromisso de segunda-feira é avisado
#     na sexta-feira — o e-mail de sexta cobre sábado, domingo e segunda;
#     sábado e domingo NÃO rodam.
#   ROTINA 2 - Aniversariantes: e-mail às 08:00 BSB com os clientes que fazem
#     aniversário NAQUELE dia, com telefone e link wa.me (clique manual).
#
# DESTINATÁRIO: dowspaulo@gmail.com (padrão; editável na variável abaixo).
#
# COMO INSTALAR (NÃO usar curl | bash — o pipe engole a entrada, lição já
# aprendida neste projeto):
#
#   curl -fsSL -o /root/11-rotinas-email-vps.sh <URL_RAW_DO_REPOSITORIO>/docs/vps/11-rotinas-email-vps.sh
#   bash /root/11-rotinas-email-vps.sh
#
#   (ou copie o arquivo para o VPS por SCP e execute "bash /root/11-rotinas-email-vps.sh")
#
# O script é IDEMPOTENTE: pode ser rodado quantas vezes quiser.
#
# PRÉ-REQUISITO (já existente no VPS): e-mail de backup funcionando —
#   /root/.msmtprc + /root/sbjur-backups/config/email.conf
#   (instalados por docs/backup-fase6/04-configurar-email.sh). Se ainda não
#   existirem, rode aquele script antes; sem eles o envio falha (o log registra).
#
# TESTE SEM ENVIAR E-MAIL (modo dry-run, imprime o e-mail no terminal):
#   bash /root/sbjur-emails/rotinas-email.sh --vespera --dry-run
#   bash /root/sbjur-emails/rotinas-email.sh --aniversarios --dry-run
#
# TESTE ENVIANDO DE VERDADE (fora do horário do cron):
#   bash /root/sbjur-emails/rotinas-email.sh --vespera
#   bash /root/sbjur-emails/rotinas-email.sh --aniversarios
# ==============================================================================

set -euo pipefail

SCRIPT_VERSION="v1.0.0"
WORK_DIR="/root/sbjur-emails"
RUNNER_SCRIPT="${WORK_DIR}/rotinas-email.sh"
LOGS_DIR="${WORK_DIR}/logs"
LOG_FILE="${LOGS_DIR}/rotinas-email.log"
CRON_FILE="/etc/cron.d/sbjur-rotinas-email"

# Destinatário padrão (pedidos do usuário); pode sobrescrever:
#   SBJUR_EMAIL_TO=outro@email.com bash /root/11-rotinas-email-vps.sh
EMAIL_TO="${SBJUR_EMAIL_TO:-dowspaulo@gmail.com}"

# Horários em Brasília (UTC-3). Se o host estiver em UTC (padrão em VPS
# Hostinger/Ubuntu), 07:00 BSB = 10:00 UTC e 08:00 BSB = 11:00 UTC.
# O script runner fixa TZ=America/Sao_Paulo internamente, e o cron usa
# CRON_TZ quando disponível; as duas linhas abaixo cobrem os dois cenários.
CRON_VESPERA_MIN_HOUR="10 7"   # min hora "de UTC" (10:00 UTC = 07:00 BSB)
CRON_ANIVER_MIN_HOUR="11 8"   # 11:00 UTC = 08:00 BSB

# Bloco do runner (mesmo arquivo embutido — copiado verbatim do repositório).
RUNNER_B64="__RUNNER_B64__"

echo "====================================================================="
echo " DPSjur / SBJur - Instalação das Rotinas de E-mail (véspera + aniversariantes)"
echo " Versão: ${SCRIPT_VERSION}"
echo " Data: $(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || true)"
echo " Host: $(hostname 2>/dev/null || echo 'VPS-Hostinger')"
echo " Destinatário: ${EMAIL_TO}"
echo "====================================================================="
echo ""

# 1. Checagens
if [ "$(id -u)" -ne 0 ]; then
    echo "❌ Erro: este script precisa ser executado como root."
    echo "   Execute: sudo bash $0"
    exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
    echo "❌ Erro: Docker não encontrado (necessário para ler o Postgres do Supabase)."
    exit 1
fi

if ! command -v crontab >/dev/null 2>&1; then
    echo "📦 Instalando cron..."
    DEBIAN_FRONTEND=noninteractive apt-get update -qq >/dev/null 2>&1 || true
    DEBIAN_FRONTEND=noninteractive apt-get install -y cron >/dev/null 2>&1 || true
fi
systemctl enable cron >/dev/null 2>&1 || true
systemctl start cron >/dev/null 2>&1 || service cron start >/dev/null 2>&1 || true

if ! [ -f /root/.msmtprc ] && ! command -v msmtp >/dev/null 2>&1; then
    echo "⚠️  Aviso: /root/.msmtprc e msmtp não encontrados."
    echo "   O envio de e-mail depende do kit de backup (docs/backup-fase6/04-configurar-email.sh)."
    echo "   Rode aquele script antes se o envio falhar."
fi

# 2. Gravar o runner
echo "⚙️  1. Gravando o runner em ${RUNNER_SCRIPT}..."
mkdir -p "${WORK_DIR}" "${LOGS_DIR}"
chmod 700 "${WORK_DIR}" 2>/dev/null || true

if [ "${RUNNER_B64}" = "__RUNNER_B64__" ]; then
    # Executado direto do repositório: o runner está no mesmo diretório do instalador.
    SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
    RUNNER_SRC="${SRC_DIR}/11-rotinas-email.sh"
    if [ ! -f "${RUNNER_SRC}" ]; then
        echo "❌ Erro: runner não encontrado em ${RUNNER_SRC}."
        echo "   Baixe TANTO o instalador (11-rotinas-email-vps.sh) QUANTO o runner (11-rotinas-email.sh)"
        echo "   para o mesmo diretório, ou instale pela versão empacotada (veja RUN-ROTINAS-EMAIL.md)."
        exit 1
    fi
    cp -f "${RUNNER_SRC}" "${RUNNER_SCRIPT}"
else
    echo "${RUNNER_B64}" | base64 -d > "${RUNNER_SCRIPT}"
fi

chmod 755 "${RUNNER_SCRIPT}"
echo "✅ Runner instalado: ${RUNNER_SCRIPT}"

# 3. Config do destinatário (idempotente, sobrescreve a cada instalação)
cat > "${WORK_DIR}/config.env" <<EOF
# Configuração das rotinas de e-mail (gerada por 11-rotinas-email-vps.sh)
SBJUR_EMAIL_TO=${EMAIL_TO}
EOF
chmod 600 "${WORK_DIR}/config.env"

# 4. Agendamento via /etc/cron.d (idempotente: sobrescreve sempre)
echo "⏰ 2. Configurando ${CRON_FILE}..."
cat > "${CRON_FILE}" <<EOF
# /etc/cron.d/sbjur-rotinas-email - Rotinas de e-mail DPSjur/SBJur
# Horários em UTC (07:00 BSB = 10:00 UTC; 08:00 BSB = 11:00 UTC).
# Véspera: pula fim de semana (sáb/dom); sexta cobre sábado+domingo+segunda.
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
CRON_TZ=America/Sao_Paulo

# ROTINA 1 - Véspera de compromissos: 07:00 BSB, seg. a sexta (sem sáb/dom)
0 7 * * 1-5 root . ${WORK_DIR}/config.env && ${RUNNER_SCRIPT} --vespera >> ${LOG_FILE} 2>&1

# ROTINA 2 - Aniversariantes do dia: 08:00 BSB, todos os dias (inclusive fim de semana)
0 8 * * * root . ${WORK_DIR}/config.env && ${RUNNER_SCRIPT} --aniversarios >> ${LOG_FILE} 2>&1
EOF
chmod 644 "${CRON_FILE}"
echo "✅ Crons instalados em ${CRON_FILE}:"
grep -v '^#' "${CRON_FILE}" | grep -v '^$' || true
echo ""

# Nota: se o cron do host respeitar CRON_TZ (cronie/cron modernos), os horários
# acima já valem em BSB. Em versões sem suporte a CRON_TZ, o host estando em UTC
# os disparos aconteceriam às 07/08 UTC (=04/05 BSB). O runner é idempotente e
# barato; caso isso ocorra, ajuste as linhas para "0 10 * * 1-5" e "0 11 * * *"
# (veja RUN-ROTINAS-EMAIL.md, seção 'Ajuste fino de horário').
echo "ℹ️  Verificação recomendada: confirme o fuso do host com 'date' e, se o cron"
echo "   não respeitar CRON_TZ (host em UTC), troque '0 7'/'0 8' por '0 10'/'0 11'."
echo ""

# 5. Validação rápida (não envia nada)
echo "🧪 3. Validação do runner (modo dry-run, imprime no terminal e NÃO envia)..."
if bash "${RUNNER_SCRIPT}" --vespera --dry-run >/dev/null 2>&1; then
    echo "✅ Runner --vespera respondeu OK (dry-run)."
else
    echo "⚠️  Runner --vespera retornou erro no dry-run (ver log abaixo)."
    bash "${RUNNER_SCRIPT}" --vespera --dry-run 2>&1 | tail -n 5 || true
fi

echo ""
# 6. Validação do banco (aponta o contêiner e testa uma query real de cada rotina)
echo "🧪 4. Validando acesso ao Postgres do Supabase (somente leitura)..."
DB_CONTAINER=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -E 'supabase[-_]db' | head -n 1 || true)
if [ -z "${DB_CONTAINER}" ]; then
    echo "⚠️  Conteiner PostgreSQL do Supabase não encontrado — as rotinas vão falhar até o Supabase subir."
else
    DB_PASSWORD=$(docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "${DB_CONTAINER}" 2>/dev/null | grep -E '^POSTGRES_PASSWORD=' | head -n 1 | cut -d= -f2- || true)
    DB_USER="postgres"
    if ! docker exec -e PGPASSWORD="${DB_PASSWORD}" "${DB_CONTAINER}" psql -U "${DB_USER}" -d postgres -tAc "SELECT 1;" >/dev/null 2>&1; then
        DB_USER="supabase_admin"
    fi
    if APPTS=$(docker exec -e PGPASSWORD="${DB_PASSWORD}" "${DB_CONTAINER}" psql -U "${DB_USER}" -d postgres -tAc \
        "SELECT count(*) FROM public.appointments WHERE date ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$';" 2>/dev/null) && \
       ANIVS=$(docker exec -e PGPASSWORD="${DB_PASSWORD}" "${DB_CONTAINER}" psql -U "${DB_USER}" -d postgres -tAc \
        "SELECT count(*) FROM public.clients WHERE birthday ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' AND birthday NOT LIKE '0001-%';" 2>/dev/null); then
        echo "✅ Banco OK (usuário ${DB_USER}, contêiner ${DB_CONTAINER}): ${APPTS} compromissos datados, ${ANIVS} clientes com aniversário válido."
    else
        echo "⚠️  Falha ao consultar o banco com usuário ${DB_USER} — conferir POSTGRES_PASSWORD do contêiner."
    fi
fi
echo ""

echo "====================================================================="
echo "🎉 ROTINAS DE E-MAIL INSTALADAS!"
echo "====================================================================="
echo "Runner:        ${RUNNER_SCRIPT}"
echo "Crons:         ${CRON_FILE}"
echo "  - Véspera:        07:00 BSB, seg-sexta (sexta cobre sáb+dom+seg)"
echo "  - Aniversariantes: 08:00 BSB, todos os dias"
echo "Destinatário:  ${EMAIL_TO} (em ${WORK_DIR}/config.env)"
echo "Log:           ${LOG_FILE}"
echo ""
echo "Testar agora (sem enviar e-mail):"
echo "  bash ${RUNNER_SCRIPT} --vespera --dry-run"
echo "  bash ${RUNNER_SCRIPT} --aniversarios --dry-run"
echo ""
echo "Testar enviando de verdade:"
echo "  bash ${RUNNER_SCRIPT} --vespera"
echo "  bash ${RUNNER_SCRIPT} --aniversarios"
echo "====================================================================="
