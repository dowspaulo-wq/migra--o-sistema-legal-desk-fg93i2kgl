#!/usr/bin/env bash
# ==============================================================================
# DPSjur / SBJur - Rotina de Espelhamento de Clientes com Google Sheets
# Script: docs/integracoes/01-instalar-cron-sheets.sh
# Versão: v1.0.0
#
# Objetivo:
# Instalar e agendar no crontab do host (VPS) a execução diária às 06:00
# (horário de Brasília) para chamar a Edge Function /functions/v1/sync-clients-sheets
#
# Características:
# - Idempotente: não duplica entradas no crontab se executado mais de uma vez
# - Descoberta automática de URLs e portas (Kong interno porta 8000 / externa sbjur.../functions/v1)
# - Suporta execução interativa ou autônoma
# ==============================================================================

set -euo pipefail

SCRIPT_VERSION="v1.0.0"
WORK_DIR="/root/sbjur-sheets-sync"
RUNNER_SCRIPT="${WORK_DIR}/run-sync-sheets.sh"
LOGS_DIR="${WORK_DIR}/logs"
LOG_FILE="${LOGS_DIR}/sync-sheets.log"

echo "====================================================================="
echo " DPSjur / SBJur - Instalação da Rotina Cron de Espelhamento Google Sheets"
echo " Versão: ${SCRIPT_VERSION}"
echo "====================================================================="
echo "Data: $(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || true)"
echo "Host: $(hostname 2>/dev/null || echo 'VPS')"
echo ""

# 1. Criação das pastas de trabalho
echo "📁 1. Criando estrutura em ${WORK_DIR}..."
mkdir -p "${WORK_DIR}" "${LOGS_DIR}"
chmod 700 "${WORK_DIR}" 2>/dev/null || true

# 2. Localização de chaves e URLs do Supabase
echo "🔍 2. Identificando credenciais e endereço da Edge Function no VPS..."

# Tenta ler a service_role key ou anon key do ambiente ou contêineres Supabase
DETECTED_ANON_KEY="${SUPABASE_ANON_KEY:-}"
DETECTED_SERVICE_KEY="${SUPABASE_SERVICE_ROLE_KEY:-}"

if [ -z "${DETECTED_SERVICE_KEY}" ]; then
  # Tenta localizar contêiner de auth, kong ou edge-runtime para ler a chave
  AUTH_CONTAINER=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -iE 'supabase.*auth|supabase-auth' | head -n 1 || true)
  if [ -n "${AUTH_CONTAINER}" ]; then
    DETECTED_SERVICE_KEY=$(docker exec "${AUTH_CONTAINER}" printenv SERVICE_ROLE_KEY 2>/dev/null || true)
    if [ -z "${DETECTED_ANON_KEY}" ]; then
      DETECTED_ANON_KEY=$(docker exec "${AUTH_CONTAINER}" printenv ANON_KEY 2>/dev/null || true)
    fi
  fi
fi

# Fallback para chave publishable conhecida do SBJur (caso service_role não seja encontrada)
PUBLIC_KEY_FALLBACK="sb_publishable_n8rNjvEg6i-Sjme1-5Yhug_nNwxBRwO"
API_KEY_TO_USE="${DETECTED_SERVICE_KEY:-${DETECTED_ANON_KEY:-$PUBLIC_KEY_FALLBACK}}"

echo "✅ Chave de API identificada (modo seguro mascarado: ${API_KEY_TO_USE:0:8}...${API_KEY_TO_USE: -4})"

# 3. Gerar script de disparo: /root/sbjur-sheets-sync/run-sync-sheets.sh
echo "⚙️ 3. Gerando script de execução diária em ${RUNNER_SCRIPT}..."

cat <<'RUNNER_EOF' > "${RUNNER_SCRIPT}"
#!/usr/bin/env bash
# Disparador da Edge Function sync-clients-sheets
set -u

LOG_DIR="/root/sbjur-sheets-sync/logs"
LOG_FILE="${LOG_DIR}/sync-sheets.log"
mkdir -p "${LOG_DIR}"

log() {
  local msg="[$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || true)] $1"
  echo "${msg}"
  echo "${msg}" >> "${LOG_FILE}" 2>/dev/null || true
}

# Rotacionar log se passar de 5 MB
if [ -f "${LOG_FILE}" ]; then
  LOG_SIZE=$(stat -c%s "${LOG_FILE}" 2>/dev/null || echo 0)
  if [ "${LOG_SIZE}" -gt 5242880 ]; then
    mv "${LOG_FILE}" "${LOG_FILE}.old" 2>/dev/null || true
  fi
fi

log "====================================================================="
log "Iniciando chamada à rotina de espelhamento Google Sheets..."
log "====================================================================="

# URLs possíveis: Kong interno (porta 8000) e endpoint HTTPS externo
INTERNAL_URL="http://127.0.0.1:8000/functions/v1/sync-clients-sheets"
EXTERNAL_URL="https://sbjur.advdouglaspsantos.com.br/functions/v1/sync-clients-sheets"

# Chave API injetada na instalação
API_KEY="__API_KEY_PLACEHOLDER__"

CALL_SUCCESS=0
RESPONSE_FILE=$(mktemp)

# Tentativa 1: Via Kong interno (mais rápido e não depende de DNS externo)
HTTP_CODE=$(curl -s -w "%{http_code}" -o "${RESPONSE_FILE}" \
  -X POST "${INTERNAL_URL}" \
  -H "Content-Type: application/json" \
  -H "apikey: ${API_KEY}" \
  -H "Authorization: Bearer ${API_KEY}" \
  -d '{}' 2>/dev/null || echo "000")

if [ "${HTTP_CODE}" = "200" ]; then
  CALL_SUCCESS=1
  log "✅ Sucesso via Kong interno (HTTP ${HTTP_CODE})"
else
  log "⚠️ Kong interno retornou HTTP ${HTTP_CODE}. Tentando via URL externa..."
  
  # Tentativa 2: Via domínio externo HTTPS
  HTTP_CODE=$(curl -s -w "%{http_code}" -o "${RESPONSE_FILE}" \
    -X POST "${EXTERNAL_URL}" \
    -H "Content-Type: application/json" \
    -H "apikey: ${API_KEY}" \
    -H "Authorization: Bearer ${API_KEY}" \
    -d '{}' 2>/dev/null || echo "000")

  if [ "${HTTP_CODE}" = "200" ]; then
    CALL_SUCCESS=1
    log "✅ Sucesso via endpoint externo (HTTP ${HTTP_CODE})"
  else
    log "❌ Erro ao chamar Edge Function (HTTP ${HTTP_CODE})"
  fi
fi

RESPONSE_CONTENT=$(cat "${RESPONSE_FILE}" 2>/dev/null || echo "")
rm -f "${RESPONSE_FILE}" 2>/dev/null || true

log "Resposta da Edge Function:"
log "${RESPONSE_CONTENT}"
log "====================================================================="

exit $((1 - CALL_SUCCESS))
RUNNER_EOF

# Substitui o placeholder da API_KEY no script gerado
sed -i "s|__API_KEY_PLACEHOLDER__|${API_KEY_TO_USE}|g" "${RUNNER_SCRIPT}"
chmod 755 "${RUNNER_SCRIPT}"

echo "✅ Script ${RUNNER_SCRIPT} criado e com permissão de execução."
echo ""

# 4. Configurar agendamento no cron (às 06:00 horário de Brasília)
# Horário de Brasília = UTC-3 (sem horário de verão).
# 06:00 Brasília = 09:00 UTC.
# Também incluímos comentário de timezone no bloco caso o cron do host seja UTC (padrão em VPS).
echo "⏰ 4. Configurando crontab do host de forma idempotente..."

CRON_IDENTIFIER="# SBJur Google Sheets Sync Diário 06:00 BRT"
# Se o servidor estiver em UTC (comum em VPS Hostinger/Ubuntu), 06:00 BRT = 09:00 UTC
# Agendamos "0 9 * * *" (9h UTC = 6h Brasília) com comentário explícito
CRON_ENTRY="0 9 * * * ${RUNNER_SCRIPT} >/dev/null 2>&1 ${CRON_IDENTIFIER}"

CURRENT_CRON=$(crontab -l 2>/dev/null || true)

if echo "${CURRENT_CRON}" | grep -q "${RUNNER_SCRIPT}"; then
  echo "ℹ️  O agendamento já estava registrado no crontab. Atualizando entrada..."
  NEW_CRON=$(echo "${CURRENT_CRON}" | grep -v "${RUNNER_SCRIPT}")
  (echo "${NEW_CRON}"; echo "${CRON_ENTRY}") | crontab -
else
  echo "Adicionando agendamento diário no crontab do root..."
  (echo "${CURRENT_CRON}"; echo "${CRON_ENTRY}") | crontab -
fi

echo "✅ Crontab configurado com sucesso! Entrada ativa:"
crontab -l | grep "${RUNNER_SCRIPT}" || true
echo ""

# 5. Teste manual opcional imediato
echo "====================================================================="
echo "🎉 INSTALAÇÃO DO CRON CONCLUÍDA!"
echo "====================================================================="
echo ""
echo "Resumo:"
echo " 1. Script gerado: ${RUNNER_SCRIPT}"
echo " 2. Horário de execução: todo dia às 06:00 (Brasília) / 09:00 (UTC)"
echo " 3. Logs de execução: ${LOG_FILE}"
echo ""
echo "👉 Para testar a execução agora manualmente via terminal:"
echo "   bash ${RUNNER_SCRIPT}"
echo ""
echo "Ou acompanhe os logs com:"
echo "   tail -f ${LOG_FILE}"
echo "====================================================================="
