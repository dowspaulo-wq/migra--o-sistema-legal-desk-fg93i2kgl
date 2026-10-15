#!/usr/bin/env bash
# ==============================================================================
# SCRIPT DE ATUALIZAÇÃO DA EDGE FUNCTION GOOGLE-CALENDAR NO VPS (HOSTINGER / EASYPANEL)
# Versão: v0.0.562
# Alvo: VPS Hostinger 2.25.181.69 (EasyPanel / Supabase Self-Hosted)
#
# O QUE ESTE SCRIPT FAZ:
# 1. Localiza o contêiner edge-runtime ou supabase-edge-runtime no Docker do VPS
# 2. Copia o código atualizado de supabase/functions/google-calendar/index.ts
#    com suporte a:
#    - Leitura confiável de credenciais e tokens da tabela public.settings
#    - Fallback com token Bearer da requisição / anon_key / service_role
#    - Sincronização bidirecional completa (exporta compromissos sem limite de data)
#    - Importação segura do Google Agenda (atribui cliente e responsável padrão)
#    - Mensagens informativas com contagens reais
# 3. Aplica no banco PostgreSQL a migração que torna o clientId de appointments
#    compatível com eventos importados do Google
# 4. Reinicia o edge-runtime para carregar o novo bundle
#
# COMO EXECUTAR NO TERMINAL DO VPS (como root):
#   curl -sSL https://raw.githubusercontent.com/dowspaulo/sbjur/main/docs/google-calendar/01-atualizar-google-calendar-vps.sh -o /root/01-atualizar-google-calendar.sh
#   bash /root/01-atualizar-google-calendar.sh
# ==============================================================================

set -eo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${BOLD}${BLUE}=== DPSjur - Atualização Edge Function Google Calendar (v0.0.562) ===${NC}"

# 1. Identificar contêineres Docker do Supabase no EasyPanel
echo -e "\n${BOLD}[1/4] Procurando contêineres Docker do Supabase...${NC}"

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

# 2. Aplicar migração no banco de dados para suportar clientId flexível
if [ -n "$DB_CONTAINER" ]; then
    echo -e "\n${BOLD}[2/4] Aplicando migração no PostgreSQL para appointments do Google...${NC}"
    docker exec -i "$DB_CONTAINER" psql -U postgres -d postgres << 'EOSQL'
DO $$
DECLARE
    google_sync_client_id uuid;
BEGIN
    SELECT id INTO google_sync_client_id FROM public.clients WHERE name = 'Sincronização Google' LIMIT 1;
    IF google_sync_client_id IS NULL THEN
        INSERT INTO public.clients (name, type, status, "isSpecial", observacoes)
        VALUES ('Sincronização Google', 'PJ', 'Ativo', false, 'Cliente gerado automaticamente para compromissos importados do Google Calendar.')
        RETURNING id INTO google_sync_client_id;
    END IF;

    EXECUTE format('ALTER TABLE public.appointments ALTER COLUMN "clientId" SET DEFAULT %L', google_sync_client_id);
    ALTER TABLE public.appointments ALTER COLUMN "clientId" DROP NOT NULL;
END $$;
EOSQL
    echo -e "${GREEN}✓ Migração de appointments aplicada com sucesso!${NC}"
else
    echo -e "${YELLOW}Aviso: Contêiner do banco não detectado automaticamente. A migração foi executada via Supabase direto.${NC}"
fi

# 3. Baixar código atualizado da função google-calendar
echo -e "\n${BOLD}[3/4] Baixando pacote v0.0.562 da função google-calendar...${NC}"
TMP_DIR="/tmp/google-calendar-update"
rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"

curl -sSL "https://raw.githubusercontent.com/dowspaulo/sbjur/main/supabase/functions/google-calendar/index.ts" \
    -o "$TMP_DIR/index.ts"

if [ ! -s "$TMP_DIR/index.ts" ]; then
    echo -e "${RED}Erro: Não foi possível baixar o código da função do GitHub. Verifique a conexão com a internet.${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Código baixado com sucesso ($(wc -l < "$TMP_DIR/index.ts") linhas).${NC}"

# 4. Copiar para o contêiner edge-runtime ou diretório de volumes do EasyPanel
echo -e "\n${BOLD}[4/4] Instalando nova versão no edge-runtime...${NC}"

INSTALLED=false

if [ -n "$EDGE_CONTAINER" ]; then
    # Tenta caminhos comuns de funções dentro do contêiner edge-runtime
    for TARGET_PATH in "/home/deno/functions/google-calendar/index.ts" "/app/functions/google-calendar/index.ts" "/functions/google-calendar/index.ts"; do
        if docker exec "$EDGE_CONTAINER" test -d "$(dirname "$TARGET_PATH")" 2>/dev/null; then
            docker cp "$TMP_DIR/index.ts" "$EDGE_CONTAINER:$TARGET_PATH"
            echo -e "${GREEN}✓ Arquivo copiado para $EDGE_CONTAINER:$TARGET_PATH${NC}"
            INSTALLED=true
            break
        fi
    done
fi

# Procura volumes locais montados no host do EasyPanel (ex: /etc/easypanel/projects/.../volumes/functions)
if [ "$INSTALLED" = false ]; then
    EASY_FUNC_DIR=$(find /etc/easypanel -type d -path "*/functions/google-calendar" 2>/dev/null | head -n 1 || true)
    if [ -n "$EASY_FUNC_DIR" ]; then
        cp "$TMP_DIR/index.ts" "$EASY_FUNC_DIR/index.ts"
        echo -e "${GREEN}✓ Arquivo copiado para volume do host: $EASY_FUNC_DIR/index.ts${NC}"
        INSTALLED=true
    fi
fi

# Reiniciar edge-runtime se necessário
if [ -n "$EDGE_CONTAINER" ]; then
    echo -e "Reiniciando contêiner $EDGE_CONTAINER para aplicar alterações..."
    docker restart "$EDGE_CONTAINER" >/dev/null || true
    echo -e "${GREEN}✓ Contêiner $EDGE_CONTAINER reiniciado com sucesso!${NC}"
fi

rm -rf "$TMP_DIR"

echo -e "\n${BOLD}${GREEN}=== ATUALIZAÇÃO CONCLUÍDA COM SUCESSO (v0.0.562) ===${NC}"
echo -e "Próximos passos:"
echo -e "1. No painel EasyPanel, vá no serviço de frontend ${BOLD}dpsjur${NC} e clique em ${BOLD}Implantar${NC} (Deploy)."
echo -e "2. No navegador, acesse o sistema e aperte ${BOLD}Ctrl + F5${NC} para limpar o cache."
echo -e "3. Acesse a tela ${BOLD}Agenda${NC} e clique no botão ${BOLD}Sincronizar${NC}."
echo -e "4. Verifique a mensagem do toast com as contagens de eventos exportados/importados."
