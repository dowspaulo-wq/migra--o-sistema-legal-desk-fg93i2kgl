#!/usr/bin/env bash
# ==============================================================================
# DPSjur / SBJur - Kit de Implantação Edge Functions Asaas no VPS (EasyPanel)
# Versão: v1.2.0
# SCRIPT_VERSION: v1.2.0
# KIT-SQL-VERSION: v1.2.0
# ==============================================================================
set -euo pipefail

SCRIPT_VERSION="v1.2.0"
REPO_RAW_BASE="https://raw.githubusercontent.com/dowspaulo-wq/migra--o-sistema-legal-desk-fg93i2kgl/main"

echo "====================================================================="
echo " DPSjur / SBJur - Implantação de Edge Functions Asaas no VPS"
echo " Versão do Kit: $SCRIPT_VERSION"
echo "====================================================================="
echo ""

# 1. Localizar o contêiner de Edge Functions do Supabase
echo "🔍 1. Buscando contêiner de Edge Functions do Supabase no EasyPanel..."
FUNCTIONS_CONTAINER="${FUNCTIONS_CONTAINER:-}"

if [ -z "$FUNCTIONS_CONTAINER" ]; then
  FUNCTIONS_CONTAINER=$(docker ps --format '{{.Names}}' | grep -iE 'supabase.*functions|supabase-edge-runtime|sbjur.*functions' | head -n 1 || true)
fi

if [ -z "$FUNCTIONS_CONTAINER" ]; then
  # Procura por imagem supabase/edge-runtime
  FUNCTIONS_CONTAINER=$(docker ps --filter "ancestor=supabase/edge-runtime" --format '{{.Names}}' | head -n 1 || true)
fi

if [ -z "$FUNCTIONS_CONTAINER" ]; then
  echo "⚠️ Contêiner de edge-runtime não identificado automaticamente via 'docker ps'."
  echo "Containers em execução atualmente:"
  docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}'
  echo ""
  echo "Informe o nome exato do contêiner de functions (ou pressione Ctrl+C para sair):"
  read -r -p "Nome do contêiner: " FUNCTIONS_CONTAINER
fi

if [ -z "$FUNCTIONS_CONTAINER" ]; then
  echo "❌ Erro: Contêiner de functions não informado. Abortando."
  exit 1
fi

echo "✅ Contêiner de functions selecionado: $FUNCTIONS_CONTAINER"
echo ""

# 2. Diretório local temporário para receber os arquivos das functions
WORK_DIR="/tmp/sbjur-asaas-deploy"
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR/functions/asaas-integration"
mkdir -p "$WORK_DIR/functions/asaas-webhook"
mkdir -p "$WORK_DIR/functions/_shared"

echo "📥 2. Baixando arquivos atualizados do repositório..."

download_file() {
  local rel_path="$1"
  local dest_path="$2"
  local github_api_url="https://api.github.com/repos/dowspaulo-wq/migra--o-sistema-legal-desk-fg93i2kgl/contents/${rel_path}?ref=main"

  if curl -sSf -L \
    -H "Accept: application/vnd.github.v3.raw" \
    -H "User-Agent: DPSjur-DeployKit" \
    "$github_api_url" -o "$dest_path" 2>/dev/null; then
    return 0
  fi

  # Fallback para raw.githubusercontent.com
  curl -sSf -L -H "Cache-Control: no-cache" "${REPO_RAW_BASE}/${rel_path}" -o "$dest_path"
}

download_file "supabase/functions/_shared/cors.ts" "$WORK_DIR/functions/_shared/cors.ts"
download_file "supabase/functions/asaas-integration/index.ts" "$WORK_DIR/functions/asaas-integration/index.ts"
download_file "supabase/functions/asaas-integration/deno.json" "$WORK_DIR/functions/asaas-integration/deno.json"
download_file "supabase/functions/asaas-webhook/index.ts" "$WORK_DIR/functions/asaas-webhook/index.ts"
download_file "supabase/functions/asaas-webhook/deno.json" "$WORK_DIR/functions/asaas-webhook/deno.json"

echo "✅ Arquivos baixados com sucesso em $WORK_DIR."
echo ""

# 3. Copiar para dentro do contêiner ou volume mapeado
echo "🚚 3. Copiando arquivos para o contêiner $FUNCTIONS_CONTAINER..."

# Descobrir diretório de funções no contêiner (padrão Supabase Docker /home/deno/functions ou /app/functions)
TARGET_DIR="/home/deno/functions"
if ! docker exec "$FUNCTIONS_CONTAINER" test -d "$TARGET_DIR" 2>/dev/null; then
  if docker exec "$FUNCTIONS_CONTAINER" test -d "/app/functions" 2>/dev/null; then
    TARGET_DIR="/app/functions"
  elif docker exec "$FUNCTIONS_CONTAINER" test -d "/functions" 2>/dev/null; then
    TARGET_DIR="/functions"
  else
    # Cria /home/deno/functions
    docker exec "$FUNCTIONS_CONTAINER" mkdir -p "$TARGET_DIR" || true
  fi
fi

docker cp "$WORK_DIR/functions/_shared" "$FUNCTIONS_CONTAINER:$TARGET_DIR/"
docker cp "$WORK_DIR/functions/asaas-integration" "$FUNCTIONS_CONTAINER:$TARGET_DIR/"
docker cp "$WORK_DIR/functions/asaas-webhook" "$FUNCTIONS_CONTAINER:$TARGET_DIR/"

echo "✅ Arquivos copiados para $TARGET_DIR no contêiner $FUNCTIONS_CONTAINER."
echo ""

# 4. Reiniciar o contêiner de functions para carregar o novo código
echo "🔄 4. Reiniciando contêiner $FUNCTIONS_CONTAINER..."
docker restart "$FUNCTIONS_CONTAINER"
echo "✅ Contêiner reiniciado!"
echo ""

# 5. Instruções finais
echo "====================================================================="
echo "🎉 DEPLOY CONCLUÍDO COM SUCESSO!"
echo "====================================================================="
echo ""
echo "Próximos passos recomendados:"
echo "1. Abra o sistema SBJur no navegador (https://sistema.advdouglaspsantos.com.br)."
echo "2. Acesse 'Configurações' no menu lateral e vá para a aba 'Integrações'."
echo "3. Cole sua Chave de API do Asaas e clique em 'Salvar Configurações do Asaas'."
echo "   (Opcional / Fallback: definir ASAAS_API_KEY no ambiente do Supabase no EasyPanel se desejar)."
echo ""
echo "4. Teste o endpoint com o script:"
echo "   bash /root/sbjur-asaas/02-testar-endpoints.sh"
echo "====================================================================="
