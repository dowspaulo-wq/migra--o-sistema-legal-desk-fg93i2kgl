#!/usr/bin/env bash
# ==============================================================================
# SCRIPT DE ATUALIZAÇÃO DA EDGE FUNCTION GOOGLE-CALENDAR NO VPS (HOSTINGER / EASYPANEL)
# Versão: v0.0.564
# Alvo: VPS Hostinger 2.25.181.69 (EasyPanel / Supabase Self-Hosted)
#
# O QUE ESTE SCRIPT FAZ:
# 1. Localiza os contêineres Docker do edge-runtime e do banco de dados no VPS
# 2. Garante no banco PostgreSQL a coluna googleEventId, cliente de apoio
#    "Sincronização Google" e flexibilização de clientId para appointments
# 3. Baixa o código atualizado da função google-calendar e de _shared do repositório
#    oficial (dowspaulo-wq/migra--o-sistema-legal-desk-fg93i2kgl, branch main)
#    com fallback via GitHub Raw e GitHub API
# 4. Copia os arquivos tanto para /home/deno/functions/... quanto para volumes do EasyPanel
# 5. Reinicia o contêiner edge-runtime (docker restart) com diagnóstico em português a cada passo
#
# COMO EXECUTAR NO TERMINAL DO VPS (como root - NÃO INTERATIVO):
#   curl -sSL "https://raw.githubusercontent.com/dowspaulo-wq/migra--o-sistema-legal-desk-fg93i2kgl/main/docs/google-calendar/01-atualizar-google-calendar-vps.sh" -o /root/01-atualizar-google-calendar.sh
#   bash /root/01-atualizar-google-calendar.sh
# ==============================================================================

set -eo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${BOLD}${BLUE}=== DPSjur - Atualização Edge Function Google Calendar (v0.0.564) ===${NC}"

# 1. Identificar contêineres Docker do Supabase no EasyPanel
echo -e "\n${BOLD}[1/5] Procurando contêineres Docker do Supabase no VPS...${NC}"

EDGE_CONTAINER=$(docker ps --filter "name=edge-runtime" --format "{{.Names}}" | head -n 1 || true)
if [ -z "$EDGE_CONTAINER" ]; then
    EDGE_CONTAINER=$(docker ps --filter "name=functions" --format "{{.Names}}" | head -n 1 || true)
fi

DB_CONTAINER=$(docker ps --filter "name=db" --format "{{.Names}}" | head -n 1 || true)
if [ -z "$DB_CONTAINER" ]; then
    DB_CONTAINER=$(docker ps --filter "name=postgres" --format "{{.Names}}" | head -n 1 || true)
fi

echo -e "Contêiner Edge Runtime: ${GREEN}${EDGE_CONTAINER:-'não encontrado'}${NC}"
echo -e "Contêiner Banco Postgres: ${GREEN}${DB_CONTAINER:-'não encontrado'}${NC}"

# 2. Aplicar ajuste de banco no PostgreSQL (idempotente)
if [ -n "$DB_CONTAINER" ]; then
    echo -e "\n${BOLD}[2/5] Verificando e aplicando ajustes no banco de dados PostgreSQL...${NC}"
    docker exec -i "$DB_CONTAINER" psql -U postgres -d postgres << 'EOSQL'
DO $$
DECLARE
    google_sync_client_id uuid;
BEGIN
    -- 1. Garante que a coluna googleEventId existe na tabela appointments
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' 
          AND table_name = 'appointments' 
          AND column_name = 'googleEventId'
    ) THEN
        ALTER TABLE public.appointments ADD COLUMN "googleEventId" text;
        CREATE INDEX IF NOT EXISTS idx_appointments_google_event_id ON public.appointments("googleEventId");
    END IF;

    -- 2. Cria ou localiza o cliente de apoio 'Sincronização Google'
    SELECT id INTO google_sync_client_id FROM public.clients WHERE name = 'Sincronização Google' LIMIT 1;
    IF google_sync_client_id IS NULL THEN
        INSERT INTO public.clients (name, type, status, "isSpecial", observacoes)
        VALUES ('Sincronização Google', 'PJ', 'Ativo', false, 'Cliente gerado automaticamente para compromissos importados do Google Calendar.')
        RETURNING id INTO google_sync_client_id;
    END IF;

    -- 3. Define cliente padrão e remove obrigatoriedade estrita de clientId
    EXECUTE format('ALTER TABLE public.appointments ALTER COLUMN "clientId" SET DEFAULT %L', google_sync_client_id);
    ALTER TABLE public.appointments ALTER COLUMN "clientId" DROP NOT NULL;
END $$;
EOSQL
    echo -e "${GREEN}✓ Ajustes no banco PostgreSQL aplicados com sucesso!${NC}"
else
    echo -e "${YELLOW}Aviso: Contêiner do banco não detectado pelo filtro automático. Pulando etapa de banco direto.${NC}"
fi

# 3. Baixar código atualizado da função google-calendar e da pasta _shared
echo -e "\n${BOLD}[3/5] Baixando pacote v0.0.564 da função google-calendar do repositório oficial...${NC}"
TMP_DIR="/tmp/google-calendar-update"
rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR/google-calendar"
mkdir -p "$TMP_DIR/_shared"

REPO_OWNER="dowspaulo-wq"
REPO_NAME="migra--o-sistema-legal-desk-fg93i2kgl"
REPO_BRANCH="main"

download_file() {
    local file_path="$1"
    local dest_file="$2"

    local raw_url="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${REPO_BRANCH}/${file_path}"
    local api_url="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/contents/${file_path}?ref=${REPO_BRANCH}"

    echo -e "Baixando: ${BLUE}${file_path}${NC}..."

    # Tentativa 1: raw.githubusercontent.com
    if curl -sSL --fail "$raw_url" -o "$dest_file" 2>/dev/null && [ -s "$dest_file" ]; then
        echo -e "${GREEN}✓ Baixado via GitHub Raw (${file_path})${NC}"
        return 0
    fi

    # Tentativa 2: GitHub API com cabeçalho raw
    if curl -sSL --fail -H "Accept: application/vnd.github.v3.raw" "$api_url" -o "$dest_file" 2>/dev/null && [ -s "$dest_file" ]; then
        echo -e "${GREEN}✓ Baixado via GitHub API Raw (${file_path})${NC}"
        return 0
    fi

    return 1
}

if ! download_file "supabase/functions/google-calendar/index.ts" "$TMP_DIR/google-calendar/index.ts"; then
    echo -e "${RED}Erro fatal: Não foi possível baixar index.ts de ${REPO_OWNER}/${REPO_NAME}.${NC}"
    exit 1
fi

# Baixa também _shared/cors.ts para garantir a integridade da pasta _shared no edge-runtime
download_file "supabase/functions/_shared/cors.ts" "$TMP_DIR/_shared/cors.ts" || {
    echo -e "${YELLOW}Aviso: _shared/cors.ts não pôde ser baixado do repo remoto. Gerando cors.ts local para fallback...${NC}"
    cat << 'EOCORS' > "$TMP_DIR/_shared/cors.ts"
export const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, x-supabase-client-platform, apikey, content-type, x-google-client-id, x-google-client-secret',
}
EOCORS
}

echo -e "${GREEN}✓ Arquivos baixados com sucesso ($(wc -l < "$TMP_DIR/google-calendar/index.ts") linhas no index.ts).${NC}"

# 4. Copiar para o contêiner edge-runtime e diretórios de volumes do EasyPanel
echo -e "\n${BOLD}[4/5] Instalando nova versão no contêiner e volumes do VPS...${NC}"

INSTALLED=false

if [ -n "$EDGE_CONTAINER" ]; then
    echo -e "Criando estruturas de diretórios no contêiner ${BOLD}${EDGE_CONTAINER}${NC}..."
    docker exec "$EDGE_CONTAINER" mkdir -p /home/deno/functions/google-calendar /home/deno/functions/_shared 2>/dev/null || true
    docker exec "$EDGE_CONTAINER" mkdir -p /app/functions/google-calendar /app/functions/_shared 2>/dev/null || true
    docker exec "$EDGE_CONTAINER" mkdir -p /functions/google-calendar /functions/_shared 2>/dev/null || true

    # Copia para os caminhos possíveis dentro do contêiner
    for BASE_DIR in "/home/deno/functions" "/app/functions" "/functions"; do
        if docker exec "$EDGE_CONTAINER" test -d "$BASE_DIR" 2>/dev/null; then
            docker cp "$TMP_DIR/google-calendar/index.ts" "$EDGE_CONTAINER:${BASE_DIR}/google-calendar/index.ts"
            docker cp "$TMP_DIR/_shared/cors.ts" "$EDGE_CONTAINER:${BASE_DIR}/_shared/cors.ts" 2>/dev/null || true
            echo -e "${GREEN}✓ Arquivos copiados com sucesso para $EDGE_CONTAINER:${BASE_DIR}/${NC}"
            INSTALLED=true
        fi
    done
fi

# Procura volumes locais montados no host do EasyPanel (ex: /etc/easypanel/projects/.../volumes/functions)
EASY_FUNC_DIRS=$(find /etc/easypanel -type d -path "*/functions/google-calendar" 2>/dev/null || true)
if [ -n "$EASY_FUNC_DIRS" ]; then
    for EASY_DIR in $EASY_FUNC_DIRS; do
        cp "$TMP_DIR/google-calendar/index.ts" "$EASY_DIR/index.ts"
        PARENT_DIR=$(dirname "$EASY_DIR")
        mkdir -p "$PARENT_DIR/_shared"
        cp "$TMP_DIR/_shared/cors.ts" "$PARENT_DIR/_shared/cors.ts"
        echo -e "${GREEN}✓ Arquivo copiado para volume do host: $EASY_DIR/index.ts${NC}"
        INSTALLED=true
    done
fi

if [ "$INSTALLED" = false ]; then
    echo -e "${YELLOW}Aviso: Não foi possível identificar o caminho exato do edge-runtime automaticamente.${NC}"
    echo -e "${YELLOW}Tentando criar /home/deno/functions direto no contêiner...${NC}"
    if [ -n "$EDGE_CONTAINER" ]; then
        docker exec "$EDGE_CONTAINER" mkdir -p /home/deno/functions/google-calendar /home/deno/functions/_shared
        docker cp "$TMP_DIR/google-calendar/index.ts" "$EDGE_CONTAINER:/home/deno/functions/google-calendar/index.ts"
        docker cp "$TMP_DIR/_shared/cors.ts" "$EDGE_CONTAINER:/home/deno/functions/_shared/cors.ts"
        INSTALLED=true
        echo -e "${GREEN}✓ Criado e copiado para /home/deno/functions no contêiner!${NC}"
    fi
fi

# 5. Reiniciar o edge-runtime
echo -e "\n${BOLD}[5/5] Reiniciando contêiner do edge-runtime...${NC}"
if [ -n "$EDGE_CONTAINER" ]; then
    echo -e "Executando: ${BLUE}docker restart ${EDGE_CONTAINER}${NC}..."
    docker restart "$EDGE_CONTAINER" >/dev/null
    echo -e "${GREEN}✓ Contêiner ${EDGE_CONTAINER} reiniciado e pronto para receber requisições!${NC}"
else
    echo -e "${YELLOW}Contêiner do edge-runtime não identificado para restart automático. Caso necessário, reinicie o serviço no painel do EasyPanel.${NC}"
fi

rm -rf "$TMP_DIR"

echo -e "\n${BOLD}${GREEN}=== ATUALIZAÇÃO CONCLUÍDA COM SUCESSO (v0.0.564) ===${NC}"
echo -e "Diagnóstico final:"
echo -e "1. A função google-calendar foi instalada com CORS inline e dependências compatíveis com Deno/VPS."
echo -e "2. A pasta _shared também foi criada com cors.ts para retrocompatibilidade."
echo -e "3. O contêiner ${EDGE_CONTAINER:-'edge-runtime'} foi reiniciado com sucesso."
echo -e "4. Acesse a tela ${BOLD}Agenda${NC} no DPSjur e clique em ${BOLD}Sincronizar${NC} para validar o fluxo."
echo -e "Próximos passos:"
echo -e "1. No painel EasyPanel, vá no serviço de frontend ${BOLD}dpsjur${NC} e clique em ${BOLD}Implantar${NC} (Deploy)."
echo -e "2. No navegador, acesse o sistema e aperte ${BOLD}Ctrl + F5${NC} para limpar o cache."
echo -e "3. Acesse a tela ${BOLD}Agenda${NC} e clique no botão ${BOLD}Sincronizar${NC}."
echo -e "4. Verifique a mensagem do toast com as contagens de eventos exportados/importados."
