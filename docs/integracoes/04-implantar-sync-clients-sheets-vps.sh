#!/usr/bin/env bash
# ==============================================================================
# SCRIPT DE IMPLANTAÇÃO / ATUALIZAÇÃO DA EDGE FUNCTION SYNC-CLIENTS-SHEETS NO VPS
# Versão: v1.0.0
# Alvo: VPS Hostinger 2.25.181.69 (EasyPanel / Supabase Self-Hosted)
#
# O QUE ESTE SCRIPT FAZ:
# 1. Localiza os contêineres Docker de Edge Functions (sbjur-local_supabase-functions-1, etc.)
# 2. Baixa os arquivos atualizados de sync-clients-sheets/index.ts e _shared/cors.ts
#    do repositório oficial (com fallback via GitHub Raw / API)
# 3. Copia index.ts e deno.json para /home/deno/functions/sync-clients-sheets e volumes EasyPanel
# 4. Garante que as permissões estejam corretas (chmod 644/755)
# 5. Reinicia o contêiner de Edge Functions (docker restart sbjur-local_supabase-functions-1)
# 6. Valida com curl HTTP GET e POST /functions/v1/sync-clients-sheets
#
# COMO EXECUTAR NO TERMINAL DO VPS (como root - NÃO INTERATIVO):
#   curl -sSL "https://raw.githubusercontent.com/dowspaulo-wq/migra--o-sistema-legal-desk-fg93i2kgl/main/docs/integracoes/04-implantar-sync-clients-sheets-vps.sh" -o /root/04-implantar-sync-clients-sheets-vps.sh
#   bash /root/04-implantar-sync-clients-sheets-vps.sh
# ==============================================================================

set -eo pipefail

SCRIPT_VERSION="v1.0.0"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${BOLD}${BLUE}=====================================================================${NC}"
echo -e "${BOLD}${BLUE} DPSjur - Implantação Edge Function sync-clients-sheets (VPS)        ${NC}"
echo -e "${BOLD}${BLUE} Versão: ${SCRIPT_VERSION}${NC}"
echo -e "${BOLD}${BLUE}=====================================================================${NC}"
echo -e "Data: $(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || true)"
echo -e "Host: $(hostname 2>/dev/null || echo 'VPS')"
echo -e "${BOLD}${BLUE}=====================================================================${NC}\n"

# 1. Localizar o contêiner de Edge Functions do Supabase no VPS
echo -e "${BOLD}${CYAN}[1/5] Localizando contêiner de Edge Functions no VPS...${NC}"

FUNCTIONS_CONTAINER="${FUNCTIONS_CONTAINER:-}"

if [ -z "$FUNCTIONS_CONTAINER" ]; then
    FUNCTIONS_CONTAINER=$(docker ps --format '{{.Names}}' | grep -iE 'supabase.*functions|supabase-edge-runtime|sbjur.*functions' | head -n 1 || true)
fi

if [ -z "$FUNCTIONS_CONTAINER" ]; then
    FUNCTIONS_CONTAINER=$(docker ps --filter "ancestor=supabase/edge-runtime" --format '{{.Names}}' | head -n 1 || true)
fi

if [ -z "$FUNCTIONS_CONTAINER" ]; then
    echo -e "${RED}Erro fatal: Contêiner de functions não localizado automaticamente via docker ps.${NC}"
    echo "Contêineres em execução:"
    docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}'
    exit 1
fi

echo -e "Contêiner de Edge Functions: ${GREEN}${BOLD}${FUNCTIONS_CONTAINER}${NC}"

# 2. Criar diretório temporário e baixar código atualizado
echo -e "\n${BOLD}${CYAN}[2/5] Baixando código atualizado da função sync-clients-sheets...${NC}"
TMP_DIR="/tmp/sbjur-sheets-deploy"
rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR/sync-clients-sheets"
mkdir -p "$TMP_DIR/_shared"

REPO_OWNER="dowspaulo-wq"
REPO_NAME="migra--o-sistema-legal-desk-fg93i2kgl"
REPO_BRANCH="main"

download_file() {
    local file_path="$1"
    local dest_file="$2"

    local raw_url="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${REPO_BRANCH}/${file_path}"
    local api_url="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/contents/${file_path}?ref=${REPO_BRANCH}"

    echo -e "  Baixando: ${BLUE}${file_path}${NC}..."

    # Tentativa 1: raw.githubusercontent.com
    if curl -sSL --fail "$raw_url" -o "$dest_file" 2>/dev/null && [ -s "$dest_file" ]; then
        echo -e "  ${GREEN}✓ Baixado via GitHub Raw (${file_path})${NC}"
        return 0
    fi

    # Tentativa 2: GitHub API com cabeçalho raw
    if curl -sSL --fail -H "Accept: application/vnd.github.v3.raw" "$api_url" -o "$dest_file" 2>/dev/null && [ -s "$dest_file" ]; then
        echo -e "  ${GREEN}✓ Baixado via GitHub API Raw (${file_path})${NC}"
        return 0
    fi

    return 1
}

if ! download_file "supabase/functions/sync-clients-sheets/index.ts" "$TMP_DIR/sync-clients-sheets/index.ts"; then
    echo -e "${RED}Erro fatal: Não foi possível baixar index.ts de ${file_path}.${NC}"
    exit 1
fi

download_file "supabase/functions/sync-clients-sheets/deno.json" "$TMP_DIR/sync-clients-sheets/deno.json" || {
    echo -e "${YELLOW}Criando deno.json padrão compatível...${NC}"
    echo '{"imports":{}}' > "$TMP_DIR/sync-clients-sheets/deno.json"
}

download_file "supabase/functions/_shared/cors.ts" "$TMP_DIR/_shared/cors.ts" || {
    echo -e "${YELLOW}Gerando _shared/cors.ts de contingência...${NC}"
    cat << 'EOCORS' > "$TMP_DIR/_shared/cors.ts"
export const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, x-supabase-client-platform, apikey, content-type',
}
EOCORS
}

echo -e "${GREEN}✓ Arquivos baixados e preparados com sucesso!${NC}"

# 3. Copiar para o contêiner de Edge Functions e volumes do host
echo -e "\n${BOLD}${CYAN}[3/5] Instalando arquivos no contêiner ${FUNCTIONS_CONTAINER}...${NC}"

INSTALLED=false

for BASE_DIR in "/home/deno/functions" "/app/functions" "/functions"; do
    if docker exec "$FUNCTIONS_CONTAINER" test -d "$BASE_DIR" 2>/dev/null; then
        echo -e "  Copiando para ${BOLD}${FUNCTIONS_CONTAINER}:${BASE_DIR}/sync-clients-sheets/${NC}..."
        docker exec "$FUNCTIONS_CONTAINER" mkdir -p "${BASE_DIR}/sync-clients-sheets" "${BASE_DIR}/_shared" 2>/dev/null || true
        docker cp "$TMP_DIR/sync-clients-sheets/index.ts" "$FUNCTIONS_CONTAINER:${BASE_DIR}/sync-clients-sheets/index.ts"
        docker cp "$TMP_DIR/sync-clients-sheets/deno.json" "$FUNCTIONS_CONTAINER:${BASE_DIR}/sync-clients-sheets/deno.json"
        docker cp "$TMP_DIR/_shared/cors.ts" "$FUNCTIONS_CONTAINER:${BASE_DIR}/_shared/cors.ts" 2>/dev/null || true
        # Ajusta permissões dentro do contêiner
        docker exec "$FUNCTIONS_CONTAINER" chmod -R 755 "${BASE_DIR}/sync-clients-sheets" 2>/dev/null || true
        INSTALLED=true
    fi
done

# Copiar também para eventuais volumes EasyPanel montados no host (/etc/easypanel/projects/.../volumes/functions)
EASY_FUNC_DIRS=$(find /etc/easypanel -type d -path "*/functions/sync-clients-sheets" 2>/dev/null || true)
if [ -n "$EASY_FUNC_DIRS" ]; then
    for EASY_DIR in $EASY_FUNC_DIRS; do
        cp "$TMP_DIR/sync-clients-sheets/index.ts" "$EASY_DIR/index.ts"
        cp "$TMP_DIR/sync-clients-sheets/deno.json" "$EASY_DIR/deno.json"
        PARENT_DIR=$(dirname "$EASY_DIR")
        mkdir -p "$PARENT_DIR/_shared"
        cp "$TMP_DIR/_shared/cors.ts" "$PARENT_DIR/_shared/cors.ts"
        chmod -R 755 "$EASY_DIR"
        echo -e "  ${GREEN}✓ Copiado para volume do host: $EASY_DIR/${NC}"
        INSTALLED=true
    done
fi

if [ "$INSTALLED" = false ]; then
    echo -e "  ${YELLOW}Criando caminho padrão /home/deno/functions/sync-clients-sheets no contêiner...${NC}"
    docker exec "$FUNCTIONS_CONTAINER" mkdir -p "/home/deno/functions/sync-clients-sheets" "/home/deno/functions/_shared"
    docker cp "$TMP_DIR/sync-clients-sheets/index.ts" "$FUNCTIONS_CONTAINER:/home/deno/functions/sync-clients-sheets/index.ts"
    docker cp "$TMP_DIR/sync-clients-sheets/deno.json" "$FUNCTIONS_CONTAINER:/home/deno/functions/sync-clients-sheets/deno.json"
    docker cp "$TMP_DIR/_shared/cors.ts" "$FUNCTIONS_CONTAINER:/home/deno/functions/_shared/cors.ts"
    docker exec "$FUNCTIONS_CONTAINER" chmod -R 755 "/home/deno/functions/sync-clients-sheets"
    INSTALLED=true
fi

echo -e "${GREEN}✓ Arquivos instalados com sucesso no contêiner!${NC}"

# 4. Reiniciar o contêiner de Edge Functions
echo -e "\n${BOLD}${CYAN}[4/5] Reiniciando contêiner ${FUNCTIONS_CONTAINER}...${NC}"
docker restart "$FUNCTIONS_CONTAINER"
echo -e "${GREEN}✓ Contêiner reiniciado com sucesso!${NC}"
echo -e "Aguardando 4 segundos para boot completo do edge-runtime..."
sleep 4

# 5. Verificação e teste dos endpoints
echo -e "\n${BOLD}${CYAN}[5/5] Testando boot da função sync-clients-sheets...${NC}"

# Chave API de fallback ou lida do ambiente
API_KEY="${SUPABASE_ANON_KEY:-sb_publishable_n8rNjvEg6i-Sjme1-5Yhug_nNwxBRwO}"

# Teste HTTP GET (healthcheck da função)
echo -e "1. Testando chamada HTTP GET em https://sbjur.advdouglaspsantos.com.br/functions/v1/sync-clients-sheets..."
GET_CODE=$(curl -s -o /tmp/sheets_get_resp.txt -w "%{http_code}" -X GET "https://sbjur.advdouglaspsantos.com.br/functions/v1/sync-clients-sheets" -H "apikey: ${API_KEY}" 2>/dev/null || echo "000")
GET_BODY=$(cat /tmp/sheets_get_resp.txt 2>/dev/null || true)

if [ "$GET_CODE" = "200" ]; then
    echo -e "   ${GREEN}✓ Boot OK! HTTP 200 recebido:${NC} ${GET_BODY}"
else
    echo -e "   ${YELLOW}HTTP GET retornou ${GET_CODE}.${NC} Resposta: ${GET_BODY:0:150}"
fi

# Teste HTTP POST
echo -e "\n2. Testando chamada HTTP POST em https://sbjur.advdouglaspsantos.com.br/functions/v1/sync-clients-sheets..."
POST_CODE=$(curl -s -o /tmp/sheets_post_resp.txt -w "%{http_code}" -X POST "https://sbjur.advdouglaspsantos.com.br/functions/v1/sync-clients-sheets" -H "apikey: ${API_KEY}" -H "Content-Type: application/json" -d '{}' 2>/dev/null || echo "000")
POST_BODY=$(cat /tmp/sheets_post_resp.txt 2>/dev/null || true)

if [ "$POST_CODE" = "200" ]; then
    echo -e "   ${GREEN}✓ Sincronização executada com sucesso! (HTTP 200)${NC}"
    echo -e "   Resposta: ${POST_BODY}"
elif [ "$POST_CODE" = "400" ]; then
    echo -e "   ${GREEN}✓ Função bootou com sucesso!${NC} (HTTP 400 esperado caso Service Account ainda não esteja preenchida em Configurações):"
    echo -e "   Resposta: ${POST_BODY:0:200}..."
elif [ "$POST_CODE" = "500" ]; then
    echo -e "   ${RED}Aviso: HTTP 500 recebido.${NC} Exibindo logs recentes do contêiner:"
    docker logs "$FUNCTIONS_CONTAINER" --tail 20 || true
else
    echo -e "   Status HTTP: ${POST_CODE}. Resposta: ${POST_BODY:0:200}"
fi

rm -rf "$TMP_DIR" /tmp/sheets_get_resp.txt /tmp/sheets_post_resp.txt

echo -e "\n${BOLD}${GREEN}=====================================================================${NC}"
echo -e "${BOLD}${GREEN}🎉 IMPLANTAÇÃO DA FUNÇÃO SYNC-CLIENTS-SHEETS CONCLUÍDA NO VPS!       ${NC}"
echo -e "${BOLD}${GREEN}=====================================================================${NC}"
echo -e "Próximos passos para Douglas:"
echo -e "1. Acesse o sistema: ${BOLD}https://sistema.advdouglaspsantos.com.br/configuracoes${NC}"
echo -e "2. Vá em ${BOLD}Integrações${NC} → Cartão ${BOLD}Espelhamento de Clientes (Google Sheets)${NC}."
echo -e "3. Clique em ${BOLD}\"Sincronizar Planilha Agora\"${NC} para validar o espelhamento completo."
echo -e "${BOLD}${GREEN}=====================================================================${NC}\n"
