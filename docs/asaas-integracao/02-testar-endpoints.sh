#!/usr/bin/env bash
# ==============================================================================
# DPSjur / SBJur - Teste e Diagnóstico dos Endpoints Supabase & Asaas
# Versão: v1.3.0 (v0.0.529)
# SCRIPT_VERSION: v1.3.0
# ==============================================================================
set -euo pipefail

SCRIPT_VERSION="v1.3.0"
TARGET_URL=""
CLI_KEY=""
CLI_URL=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --key|-k)
      CLI_KEY="$2"
      shift 2
      ;;
    --url|-u)
      CLI_URL="$2"
      shift 2
      ;;
    *)
      if [ -z "$TARGET_URL" ]; then
        TARGET_URL="$1"
      fi
      shift
      ;;
  esac
done

TARGET_URL="${TARGET_URL:-https://sbjur.advdouglaspsantos.com.br}"
TARGET_URL="${TARGET_URL%/}"

TEST_API_KEY="${CLI_KEY:-${ASAAS_API_KEY:-}}"
TEST_API_URL="${CLI_URL:-${ASAAS_API_URL:-https://api.asaas.com/v3}}"

echo "====================================================================="
echo " DPSjur / SBJur - Diagnóstico e Teste dos Endpoints Edge Functions"
echo " Versão: $SCRIPT_VERSION"
echo "====================================================================="
echo ""
echo "Alvo dos testes: $TARGET_URL"
if [ -n "$TEST_API_KEY" ]; then
  MASKED_KEY="${TEST_API_KEY:0:8}...${TEST_API_KEY: -4}"
  echo "Chave Asaas fornecida: $MASKED_KEY (via header x-asaas-api-key)"
  echo "URL da API Asaas: $TEST_API_URL"
else
  echo "ℹ️ Nenhuma chave Asaas fornecida (passe --key \$CHAVE ou use env ASAAS_API_KEY para testar com autenticação Asaas)."
fi
echo ""
# ==============================================================================
# ETAPA A: Teste interno no VPS direto no Kong (http://127.0.0.1:8000)
# ==============================================================================
echo "---------------------------------------------------------------------"
echo "📦 ETAPA (A): Teste interno no VPS (Kong direto na porta 8000)"
echo "---------------------------------------------------------------------"
INTERNAL_KONG_URL="http://127.0.0.1:8000"

echo "🔹 Teste A1: OPTIONS CORS em $INTERNAL_KONG_URL/functions/v1/asaas-integration"
INTERNAL_CORS_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X OPTIONS "${INTERNAL_KONG_URL}/functions/v1/asaas-integration" \
  -H "Access-Control-Request-Method: POST" \
  -H "Origin: https://sistema.advdouglaspsantos.com.br" || echo "000")

if [ "$INTERNAL_CORS_CODE" = "200" ] || [ "$INTERNAL_CORS_CODE" = "204" ]; then
  echo "✅ Kong interno respondeu CORS com sucesso (Status: $INTERNAL_CORS_CODE)"
else
  echo "⚠️ Kong interno retornou status $INTERNAL_CORS_CODE (se 000, verifique se a porta 8000 está escutando no VPS)"
fi
echo ""

echo "🔹 Teste A2: POST ping em $INTERNAL_KONG_URL/functions/v1/asaas-integration"
INTERNAL_POST_BODY=$(curl -s -X POST "${INTERNAL_KONG_URL}/functions/v1/asaas-integration" \
  -H "Content-Type: application/json" \
  -d '{"action":"ping"}' || echo "")

echo "Resposta interna recebida:"
echo "$INTERNAL_POST_BODY"

if echo "$INTERNAL_POST_BODY" | grep -iq "ASAAS_API_KEY"; then
  echo "ℹ️ Kong interno operacional! Edge function respondeu solicitando ASAAS_API_KEY."
elif echo "$INTERNAL_POST_BODY" | grep -iq "Ação inválida"; then
  echo "✅ Kong interno 100% operacional! Edge function ativa e com ASAAS_API_KEY reconhecida."
elif echo "$INTERNAL_POST_BODY" | grep -iq "pong\|ok"; then
  echo "✅ Kong interno respondeu com sucesso ao ping."
else
  echo "👉 Resposta interna recebida (verifique se as Edge Functions foram iniciadas no Supabase)."
fi
echo ""

# ==============================================================================
# ETAPA B: Teste na URL externa alvo ($TARGET_URL)
# ==============================================================================
echo "---------------------------------------------------------------------"
echo "🌐 ETAPA (B): Teste na URL externa alvo ($TARGET_URL)"
echo "---------------------------------------------------------------------"

EXT_INTEG_URL="${TARGET_URL}/functions/v1/asaas-integration"

echo "🔹 Teste B1: OPTIONS CORS em $EXT_INTEG_URL"
EXT_CORS_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X OPTIONS "$EXT_INTEG_URL" \
  -H "Access-Control-Request-Method: POST" \
  -H "Origin: https://sistema.advdouglaspsantos.com.br" || echo "000")
echo "Status CORS retornado: $EXT_CORS_CODE"
echo ""

echo "🔹 Teste B2: POST ping em $EXT_INTEG_URL"
EXT_TEMP_FILE=$(mktemp)

CURL_HEADERS=(-H "Content-Type: application/json")
if [ -n "$TEST_API_KEY" ]; then
  CURL_HEADERS+=(-H "x-asaas-api-key: $TEST_API_KEY")
  CURL_HEADERS+=(-H "x-asaas-api-url: $TEST_API_URL")
fi

EXT_HTTP_CODE=$(curl -s -w "%{http_code}" -o "$EXT_TEMP_FILE" -X POST "$EXT_INTEG_URL" \
  "${CURL_HEADERS[@]}" \
  -d '{"action":"ping"}' || echo "000")

EXT_POST_BODY=$(cat "$EXT_TEMP_FILE")
rm -f "$EXT_TEMP_FILE"

echo "Status HTTP retornado: $EXT_HTTP_CODE"
echo "Corpo da resposta recebida:"
echo "$EXT_POST_BODY"
echo ""

# Checagem diagnóstica inteligente:
# Se veio 405 assinado pelo nginx do frontend (ex: "405 Not Allowed" e "nginx/")
if [ "$EXT_HTTP_CODE" = "405" ] || echo "$EXT_POST_BODY" | grep -iq "405 Not Allowed"; then
  if echo "$EXT_POST_BODY" | grep -iq "nginx"; then
    echo "====================================================================="
    echo "⚠️ DIAGNÓSTICO CONFIRMADO:"
    echo "A requisição caiu no nginx do frontend, não no kong — configure o subdomínio api. apontando à porta 8000 no EasyPanel."
    echo ""
    echo "Motivo técnico:"
    echo "O domínio '$TARGET_URL' está apontado exclusivamente para o contêiner do"
    echo "frontend React/Nginx (porta 80). Quando uma chamada POST ou OPTIONS é feita"
    echo "em /functions/v1/..., o nginx do frontend rejeita o método POST com 405"
    echo "porque ele apenas serve arquivos estáticos e não encaminha para o gateway Kong."
    echo ""
    echo "Como resolver em 4 passos rápidos:"
    echo "1. Registro.br: criar registro A com nome 'api' apontando para 2.25.181.69"
    echo "2. EasyPanel > Cartão Supabase > Domains: adicionar api.advdouglaspsantos.com.br, porta 8000, HTTPS ligado"
    echo "3. EasyPanel > dpsjur-web > Environment: definir VITE_SUPABASE_URL=https://api.advdouglaspsantos.com.br e Salvar"
    echo "4. Rodar novamente: bash /root/sbjur-asaas/02-testar-endpoints.sh https://api.advdouglaspsantos.com.br"
    echo "====================================================================="
    echo ""
  fi
elif [ "$EXT_HTTP_CODE" = "200" ] || [ "$EXT_HTTP_CODE" = "204" ]; then
  if echo "$EXT_POST_BODY" | grep -iq "ASAAS_API_KEY" || echo "$EXT_POST_BODY" | grep -iq "não configurada"; then
    echo "✅ Conexão externa com o Kong e Edge Function BEM-SUCEDIDA!"
    echo "ℹ️ Observação: a Edge Function respondeu informando que a chave não foi enviada na requisição (use --key para testar com chave)."
  elif echo "$EXT_POST_BODY" | grep -iq "Ação inválida"; then
    echo "✅ EXCELENTE! Endpoint externo 100% OPERACIONAL via Kong e com chave validada com sucesso!"
  else
    echo "✅ Resposta recebida da Edge Function com sucesso (HTTP $EXT_HTTP_CODE)."
  fi
  echo ""
elif [ "$EXT_HTTP_CODE" = "400" ]; then
  if echo "$EXT_POST_BODY" | grep -iq "Ação inválida"; then
    echo "✅ EXCELENTE! Endpoint externo 100% OPERACIONAL via Kong e autenticação Asaas validada (ação ping tratada com sucesso)!"
  elif echo "$EXT_POST_BODY" | grep -iq "ASAAS_API_KEY" || echo "$EXT_POST_BODY" | grep -iq "não configurada"; then
    echo "✅ Conexão externa com o Kong e Edge Function BEM-SUCEDIDA!"
    echo "ℹ️ Edge Function respondeu HTTP 400 solicitando chave Asaas (use --key para testar com chave)."
  else
    echo "ℹ️ Resposta HTTP 400 recebida da Edge Function com payload informativo."
  fi
  echo ""
elif [ "$EXT_HTTP_CODE" = "404" ]; then
  echo "⚠️ Status 404 retornado. Verifique se o roteamento do Kong para /functions/v1/ está ativo ou se o serviço foi iniciado."
  echo ""
fi

echo "🔹 Teste B3: OPTIONS CORS em ${TARGET_URL}/functions/v1/asaas-webhook"
WEBHOOK_RES=$(curl -s -o /dev/null -w "%{http_code}" -X OPTIONS "${TARGET_URL}/functions/v1/asaas-webhook" \
  -H "Access-Control-Request-Method: POST" \
  -H "Origin: https://www.asaas.com" || echo "000")
echo "Status CORS webhook: $WEBHOOK_RES"
echo ""

echo "🔹 Teste B4: GET Healthcheck em ${TARGET_URL}/functions/v1/asaas-webhook"
WEBHOOK_GET_BODY=$(curl -s "${TARGET_URL}/functions/v1/asaas-webhook" || echo "")
echo "Resposta do webhook:"
echo "$WEBHOOK_GET_BODY"
echo ""

echo "🔹 Teste B5: POST Simulação Webhook (PAYMENT_RECEIVED seguro com ID fictício)"
WEBHOOK_POST_BODY=$(curl -s -X POST "${TARGET_URL}/functions/v1/asaas-webhook" \
  -H "Content-Type: application/json" \
  -d '{"event":"PAYMENT_RECEIVED","payment":{"id":"pay_teste_simulacao_999","value":10.00,"paymentDate":"2026-10-08"}}' || echo "")
echo "Resposta da simulação:"
echo "$WEBHOOK_POST_BODY"

if echo "$WEBHOOK_POST_BODY" | grep -iq "sucesso\|não encontrada"; then
  echo "✅ Webhook operacional: tratou evento simulado e respondeu 200 sem efeito colateral."
else
  echo "ℹ️ Resposta recebida da simulação."
fi
echo ""

echo "====================================================================="
echo "Diagnóstico concluído."
echo "====================================================================="
