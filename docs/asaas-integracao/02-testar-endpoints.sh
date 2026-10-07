#!/usr/bin/env bash
# ==============================================================================
# DPSjur / SBJur - Teste de Endpoints Edge Functions Asaas
# Versão: v1.0.0
# SCRIPT_VERSION: v1.0.0
# ==============================================================================
set -euo pipefail

SCRIPT_VERSION="v1.0.0"

echo "====================================================================="
echo " DPSjur / SBJur - Diagnóstico e Teste dos Endpoints Asaas"
echo " Versão: $SCRIPT_VERSION"
echo "====================================================================="
echo ""

SUPABASE_URL="${1:-https://sistema.advdouglaspsantos.com.br}"
echo "Testando contra o domínio: $SUPABASE_URL"
echo ""

# 1. Teste de OPTIONS (CORS preflight) no asaas-integration
echo "🔹 Teste 1: OPTIONS /functions/v1/asaas-integration"
CORS_RES=$(curl -s -o /dev/null -w "%{http_code}" -X OPTIONS "${SUPABASE_URL}/functions/v1/asaas-integration" \
  -H "Access-Control-Request-Method: POST" \
  -H "Origin: ${SUPABASE_URL}" || true)

if [ "$CORS_RES" = "200" ] || [ "$CORS_RES" = "204" ]; then
  echo "✅ Endpoint asaas-integration respondeu CORS status $CORS_RES (OK)"
else
  echo "⚠️ Status retornado: $CORS_RES (se for 404, verifique o roteamento do Kong/Traefik para /functions/v1/)"
fi
echo ""

# 2. Teste de POST com payload inválido de propósito para checar se a function executa e valida a chave
echo "🔹 Teste 2: POST /functions/v1/asaas-integration (checar se função responde JSON)"
RESP_BODY=$(curl -s -X POST "${SUPABASE_URL}/functions/v1/asaas-integration" \
  -H "Content-Type: application/json" \
  -d '{"action":"ping"}' || true)

echo "Resposta recebida da function:"
echo "$RESP_BODY"
echo ""

if echo "$RESP_BODY" | grep -iq "ASAAS_API_KEY"; then
  echo "ℹ️ A function está respondendo! Ela indicou que ASAAS_API_KEY precisa ser configurada nas env."
elif echo "$RESP_BODY" | grep -iq "Ação inválida"; then
  echo "✅ A function está 100% OPERACIONAL e com a chave configurada!"
else
  echo "👉 Resposta: $RESP_BODY"
fi
echo ""

# 3. Teste de OPTIONS no asaas-webhook
echo "🔹 Teste 3: OPTIONS /functions/v1/asaas-webhook"
WEBHOOK_RES=$(curl -s -o /dev/null -w "%{http_code}" -X OPTIONS "${SUPABASE_URL}/functions/v1/asaas-webhook" \
  -H "Access-Control-Request-Method: POST" \
  -H "Origin: https://www.asaas.com" || true)

echo "Status CORS webhook: $WEBHOOK_RES"
echo ""

echo "====================================================================="
echo "Diagnóstico concluído."
echo "====================================================================="
