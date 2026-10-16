#!/usr/bin/env bash
# ==============================================================================
# DPSjur / SBJur - Vigia Automático do Supabase no VPS (Hostinger KVM 1)
# Script: docs/vps/01-instalar-vigia.sh
# Versão: v1.0.0
# Objetivo: Instalar /root/vigia-supabase.sh e agendamento cron a cada 1 minuto
# ==============================================================================

set -euo pipefail

SCRIPT_VERSION="v1.0.0"
VIGIA_TARGET="/root/vigia-supabase.sh"
CRON_FILE="/etc/cron.d/vigia-supabase"
LOG_FILE="/var/log/vigia-supabase.log"

echo "====================================================================="
echo " DPSjur / SBJur - Instalação do Vigia Automático Supabase"
echo " Versão: ${SCRIPT_VERSION}"
echo " Data: $(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || true)"
echo " Host: $(hostname 2>/dev/null || echo 'VPS-Hostinger')"
echo "====================================================================="
echo ""

# 1. Checagem de privilégio de root
if [ "$(id -u)" -ne 0 ]; then
    echo "❌ Erro: Este script precisa ser executado como root."
    echo "Execute: sudo bash $0 ou faça login como root."
    exit 1
fi

# 2. Verificação de dependências básicas
if ! command -v docker >/dev/null 2>&1; then
    echo "❌ Erro: Docker não foi encontrado no sistema!"
    exit 1
fi

if ! command -v cron >/dev/null 2>&1 && ! command -v crond >/dev/null 2>&1; then
    echo "📦 Instalando serviço cron..."
    DEBIAN_FRONTEND=noninteractive apt-get update -qq >/dev/null 2>&1 || true
    DEBIAN_FRONTEND=noninteractive apt-get install -y cron >/dev/null 2>&1 || true
fi

# Garantir que o serviço cron esteja ativo
systemctl enable cron >/dev/null 2>&1 || true
systemctl start cron >/dev/null 2>&1 || service cron start >/dev/null 2>&1 || true

# 3. Gerar o script do vigia: /root/vigia-supabase.sh
echo "⚙️  1. Gerando script do vigia em ${VIGIA_TARGET}..."

cat <<'VIGIA_SCRIPT_EOF' > "${VIGIA_TARGET}"
#!/usr/bin/env bash
# ==============================================================================
# DPSjur / SBJur - Vigia Automático dos Contêineres Supabase (EasyPanel)
# Executado a cada 1 minuto via /etc/cron.d/vigia-supabase
# ==============================================================================

set -u

LOG_FILE="/var/log/vigia-supabase.log"
LOCK_FILE="/tmp/vigia-supabase.lock"
MAX_LOG_SIZE=5242880 # 5 MB em bytes

# 1. Rotação / controle de tamanho de log simples e seguro
if [ -f "${LOG_FILE}" ]; then
    LOG_SIZE=$(stat -c%s "${LOG_FILE}" 2>/dev/null || echo 0)
    if [ "${LOG_SIZE}" -gt "${MAX_LOG_SIZE}" ]; then
        # Preserva últimos ~1000 registros para não perder histórico recente
        TEMP_LOG=$(mktemp 2>/dev/null || echo "/tmp/vigia-rot.tmp")
        tail -n 1000 "${LOG_FILE}" > "${TEMP_LOG}" 2>/dev/null || true
        mv -f "${TEMP_LOG}" "${LOG_FILE}" 2>/dev/null || true
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [VIGIA-INFO] Log truncado automaticamente (> 5 MB). Mantidas as ultimas 1000 linhas." >> "${LOG_FILE}" 2>/dev/null || true
    fi
fi

log_msg() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "${msg}" >> "${LOG_FILE}" 2>/dev/null || echo "${msg}"
}

# 2. Lock para impedir execuções sobrepostas caso um docker start demore
if command -v flock >/dev/null 2>&1; then
    exec 200>"${LOCK_FILE}"
    if ! flock -n 200; then
        exit 0
    fi
fi

# 3. Componentes esperados do Supabase no EasyPanel
# Lista mínima canônica do compose Supabase
COMPONENTES_ESPERADOS=(
    "kong"
    "functions"
    "auth"
    "rest"
    "db"
    "storage"
    "studio"
    "realtime"
    "supavisor"
    "meta"
    "vector"
    "imgproxy"
)

# 4. Detecção dinâmica dos contêineres do sbjur-local_supabase
# O docker ps -a nos dá todos os contêineres criados (ativos ou parados)
# Formato: ID|Nome|Status|RunningState
CONTAINER_DUMP=$(docker ps -a --filter "name=sbjur-local_supabase" --format '{{.Names}}|{{.Status}}|{{.State}}' 2>/dev/null || true)

HOUVE_ACAO=0
FALHAS_DETECTADAS=0

for comp in "${COMPONENTES_ESPERADOS[@]}"; do
    # Localizar contêiner cujo nome corresponda ao componente
    # Exemplos reais: sbjur-local_supabase-kong-1, sbjur-local_supabase-functions-1, sbjur-local_supabase-db-1
    REGISTRO=$(echo "${CONTAINER_DUMP}" | grep -E "sbjur-local_supabase[-_]${comp}([-_][0-9]+)?$" | head -n 1 || true)

    if [ -z "${REGISTRO}" ]; then
        # Caso o nome não termine exatamente com número (fallback genérico)
        REGISTRO=$(echo "${CONTAINER_DUMP}" | grep -E "sbjur-local_supabase[-_]${comp}" | head -n 1 || true)
    fi

    if [ -z "${REGISTRO}" ]; then
        # Contêiner esperado NÃO EXISTE no Docker
        # NÃO recriar — isso é papel do EasyPanel/humano. Apenas registrar aviso no log uma vez por ciclo com falha
        log_msg "[VIGIA-AVISO] Componente '${comp}' ausente no Docker (nenhum conteiner 'sbjur-local_supabase*${comp}*' encontrado). Recriacao depende do EasyPanel."
        FALHAS_DETECTADAS=$((FALHAS_DETECTADAS + 1))
        continue
    fi

    C_NAME=$(echo "${REGISTRO}" | awk -F'|' '{print $1}')
    C_STATUS=$(echo "${REGISTRO}" | awk -F'|' '{print $2}')
    C_STATE=$(echo "${REGISTRO}" | awk -F'|' '{print $3}')

    # Se o contêiner NÃO estiver "running" (ex: exited, created, paused, dead)
    if [ "${C_STATE}" != "running" ]; then
        HOUVE_ACAO=1
        log_msg "[VIGIA-ALERTA] Conteiner '${C_NAME}' NAO esta Up! Status anterior: '${C_STATUS}' (State: ${C_STATE}). Tentando 'docker start'..."

        # Tentar start simples (não recriação)
        START_OUTPUT=$(docker start "${C_NAME}" 2>&1)
        START_CODE=$?

        if [ ${START_CODE} -eq 0 ]; then
            log_msg "[VIGIA-SUCESSO] Conteiner '${C_NAME}' reiniciado com sucesso via 'docker start'."
        else
            log_msg "[VIGIA-ERRO] Falha ao iniciar '${C_NAME}'. Codigo de saida: ${START_CODE}. Mensagem do Docker: ${START_OUTPUT}"
            # Não faz loops agressivos; o próximo minuto tentará novamente se ainda parado
        fi
    fi
done

# 5. Registro leve de saúde
# Se agiu ou houve componente ausente, os logs detalhados já foram gravados acima.
# Se todos os contêineres existentes estavam "running" e sem ausências, gravamos uma linha leve de heartbeat.
if [ ${HOUVE_ACAO} -eq 0 ] && [ ${FALHAS_DETECTADAS} -eq 0 ]; then
    log_msg "[VIGIA-OK] Todos os servicos Supabase estao saudaveis e operantes."
fi

exit 0
VIGIA_SCRIPT_EOF

chmod 755 "${VIGIA_TARGET}"
echo "✅ Script ${VIGIA_TARGET} gerado com permissão de execução."

# 4. Criar arquivo de log inicial se não existir
touch "${LOG_FILE}"
chmod 644 "${LOG_FILE}"
echo "✅ Arquivo de log inicial garantido em ${LOG_FILE}."

# 5. Instalar o agendamento no cron (/etc/cron.d/vigia-supabase)
echo "⏰ 2. Configurando agendamento em ${CRON_FILE} (a cada 1 minuto)..."

# Cria entrada cron de sistema idempotente com permissões estritas (0644 exigido por /etc/cron.d)
cat <<'CRON_EOF' > "${CRON_FILE}"
# /etc/cron.d/vigia-supabase: Vigia automatico do Supabase DPSjur/SBJur
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

* * * * * root /root/vigia-supabase.sh >> /var/log/vigia-supabase.log 2>&1
CRON_EOF

chmod 644 "${CRON_FILE}"
echo "✅ Arquivo ${CRON_FILE} configurado."

# 6. Execução de teste inicial do vigia para validar sintaxe e permissões
echo "🧪 3. Executando primeira rodada de verificação do vigia..."
if /root/vigia-supabase.sh; then
    echo "✅ Execução inicial do vigia concluída com sucesso."
else
    echo "⚠️  Execução inicial retornou código diferente de zero. Verifique o log."
fi

echo ""
echo "📋 Últimas linhas do log (${LOG_FILE}):"
tail -n 5 "${LOG_FILE}" 2>/dev/null || echo "(Log vazio ou ainda sem mensagens)"

echo ""
echo "====================================================================="
echo "🎉 VIGIA AUTOMÁTICO INSTALADO COM SUCESSO!"
echo "====================================================================="
echo "Arquivo do vigia:  ${VIGIA_TARGET}"
echo "Agendamento cron:  ${CRON_FILE} (a cada 1 min)"
echo "Arquivo de log:    ${LOG_FILE}"
echo ""
echo "Para testar na prática se o vigia ressuscita um contêiner caído:"
echo "  bash docs/vps/02-testar-vigia.sh"
echo "  (ou /root/02-testar-vigia.sh se você baixou no servidor)"
echo "====================================================================="

exit 0
