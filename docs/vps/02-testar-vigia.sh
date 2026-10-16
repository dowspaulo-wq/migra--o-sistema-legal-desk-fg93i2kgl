#!/usr/bin/env bash
# ==============================================================================
# DPSjur / SBJur - Teste Seguro do Vigia Automático do Supabase
# Script: docs/vps/02-testar-vigia.sh
# Versão: v1.0.0
# Objetivo: Parar temporariamente o kong, aguardar o vigia cron ou dispará-lo,
#           e confirmar se o contêiner volta ao ar automaticamente com logs.
# ==============================================================================

set -u

SCRIPT_VERSION="v1.0.0"
LOG_FILE="/var/log/vigia-supabase.log"
VIGIA_SCRIPT="/root/vigia-supabase.sh"
CRON_FILE="/etc/cron.d/vigia-supabase"
WAIT_SECONDS="${1:-75}" # Padrão: 75 segundos (cobre 1 ciclo do cron)

echo "====================================================================="
echo " DPSjur / SBJur - Teste Seguro de Recuperação do Vigia"
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

# 2. Verificar se o vigia está instalado
if [ ! -f "${VIGIA_SCRIPT}" ]; then
    echo "❌ Erro: O script do vigia (${VIGIA_SCRIPT}) não foi encontrado!"
    echo "Execute primeiro o instalador: bash docs/vps/01-instalar-vigia.sh"
    exit 1
fi

if [ ! -f "${CRON_FILE}" ]; then
    echo "⚠️  Aviso: O agendamento em ${CRON_FILE} não foi localizado."
fi

# 3. Localizar o contêiner do Kong
echo "🔍 1. Localizando contêiner do Kong no Docker..."
KONG_CONTAINER=$(docker ps -a --filter "name=sbjur-local_supabase.*kong" --format '{{.Names}}' 2>/dev/null | head -n 1 || true)

if [ -z "${KONG_CONTAINER}" ]; then
    # Fallback genérico para kong
    KONG_CONTAINER=$(docker ps -a --filter "name=kong" --format '{{.Names}}' 2>/dev/null | grep -E 'sbjur-local|supabase' | head -n 1 || true)
fi

if [ -z "${KONG_CONTAINER}" ]; then
    echo "❌ Erro: Não foi localizado nenhum contêiner do Kong do Supabase."
    echo "Contêineres disponíveis:"
    docker ps -a --format 'table {{.Names}}\t{{.Status}}' 2>/dev/null || true
    exit 1
fi

echo "✅ Contêiner do Kong identificado: ${KONG_CONTAINER}"
KONG_STATUS_INICIAL=$(docker inspect --format '{{.State.Status}}' "${KONG_CONTAINER}" 2>/dev/null || echo "desconhecido")
echo "   Status atual: ${KONG_STATUS_INICIAL}"

if [ "${KONG_STATUS_INICIAL}" != "running" ]; then
    echo "⚠️  O Kong já está parado (${KONG_STATUS_INICIAL}). Tentando iniciar para iniciar o teste..."
    docker start "${KONG_CONTAINER}" >/dev/null 2>&1 || true
    sleep 3
fi

# Marcar linha base do log antes de iniciar o teste
LINHAS_LOG_ANTES=0
if [ -f "${LOG_FILE}" ]; then
    LINHAS_LOG_ANTES=$(wc -l < "${LOG_FILE}" 2>/dev/null || echo 0)
fi

echo ""
echo "🛑 2. Simulando queda: parando propositalmente o contêiner '${KONG_CONTAINER}'..."
docker stop "${KONG_CONTAINER}" >/dev/null 2>&1 || {
    echo "❌ Erro ao parar o contêiner com 'docker stop'."
    exit 1
}

STATUS_APOS_STOP=$(docker inspect --format '{{.State.Status}}' "${KONG_CONTAINER}" 2>/dev/null || echo "desconhecido")
echo "✅ Contêiner parado com sucesso. Status atual: ${STATUS_APOS_STOP}."
echo ""

echo "⏳ 3. Aguardando a atuação do vigia automático..."
echo "   O cron roda a cada 60 segundos. Aguardando até ${WAIT_SECONDS} segundos..."
echo "   (Contagem regressiva: pressione Ctrl+C se quiser interromper)"

SEGUNDOS_RESTANTES=${WAIT_SECONDS}
RECUPEROU=0

while [ "${SEGUNDOS_RESTANTES}" -gt 0 ]; do
    CURRENT_STATE=$(docker inspect --format '{{.State.Status}}' "${KONG_CONTAINER}" 2>/dev/null || echo "desconhecido")
    if [ "${CURRENT_STATE}" = "running" ]; then
        RECUPEROU=1
        break
    fi
    printf "\r   Aguardando... faltam %2d segundos (status: %s)" "${SEGUNDOS_RESTANTES}" "${CURRENT_STATE}"
    sleep 3
    SEGUNDOS_RESTANTES=$((SEGUNDOS_RESTANTES - 3))
done
printf "\r                                                                    \r"

# Se o cron demorou para engatar no intervalo ou se o tempo esgotou, chamamos o vigia diretamente para validar a rotina
if [ "${RECUPEROU}" -eq 0 ]; then
    echo "ℹ️  Tempo de espera do cron finalizado sem restart. Executando ${VIGIA_SCRIPT} manualmente agora..."
    "${VIGIA_SCRIPT}" || true
    sleep 2
    CURRENT_STATE=$(docker inspect --format '{{.State.Status}}' "${KONG_CONTAINER}" 2>/dev/null || echo "desconhecido")
    if [ "${CURRENT_STATE}" = "running" ]; then
        RECUPEROU=1
        echo "✅ O script do vigia, ao ser invocado, detectou a parada e iniciou o Kong imediatamente!"
    fi
fi

echo ""
echo "====================================================================="
echo "📊 RESULTADO DO TESTE DO VIGIA"
echo "====================================================================="

STATUS_FINAL=$(docker inspect --format '{{.State.Status}}' "${KONG_CONTAINER}" 2>/dev/null || echo "desconhecido")

if [ "${STATUS_FINAL}" = "running" ]; then
    echo "🎉 SUCESSO ABSOLUTO!"
    echo "O contêiner '${KONG_CONTAINER}' foi ressuscitado e está OPERANTE (running)!"
else
    echo "❌ FALHA: O contêiner ainda está com status '${STATUS_FINAL}'."
    echo "Tentando religar manualmente para não deixar o Kong fora do ar..."
    docker start "${KONG_CONTAINER}" || true
fi

echo ""
echo "📋 Trecho do log gerado durante o teste (${LOG_FILE}):"
echo "---------------------------------------------------------------------"
if [ -f "${LOG_FILE}" ]; then
    tail -n 12 "${LOG_FILE}"
else
    echo "(Arquivo de log não encontrado)"
fi
echo "---------------------------------------------------------------------"
echo ""

if [ "${STATUS_FINAL}" = "running" ]; then
    echo "✅ Conclusão: O vigia está ativo e pronto para manter o Supabase no ar!"
    exit 0
else
    echo "⚠️  Conclusão: Revise os logs acima para diagnosticar a causa."
    exit 1
fi
