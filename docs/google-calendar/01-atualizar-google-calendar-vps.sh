#!/usr/bin/env bash
# ==============================================================================
# Script: 01-atualizar-google-calendar-vps.sh
# Finalidade: Atualizar a Edge Function 'google-calendar' no Supabase self-hosted
#             no VPS Hostinger e aplicar a migration com as colunas googleClientId
#             e googleClientSecret na tabela settings.
# Execução no VPS:
#   bash /root/atualizar-google-calendar-vps.sh
# ==============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}======================================================${NC}"
echo -e "${BLUE}  DPSjur - Atualização da Integração Google Calendar  ${NC}"
echo -e "${BLUE}======================================================${NC}"
echo ""

# 1. Localiza o diretório do Supabase ou das Edge Functions no VPS
# Padrões comuns no EasyPanel / Docker Compose:
FUNCTIONS_DIR=""
for candidate in \
  "/etc/easypanel/projects/supabase/volumes/functions" \
  "/etc/easypanel/projects/supabase/functions" \
  "/root/supabase/volumes/functions" \
  "/root/supabase/functions" \
  "/root/sbjur-migracao/functions" \
  "/var/lib/docker/volumes/*functions*"; do
  if [ -d "$candidate" ]; then
    FUNCTIONS_DIR="$candidate"
    break
  fi
done

echo -e "${YELLOW}[1/3] Verificando diretório de funções...${NC}"
if [ -n "$FUNCTIONS_DIR" ]; then
  echo -e "Diretório encontrado: ${GREEN}$FUNCTIONS_DIR${NC}"
  mkdir -p "$FUNCTIONS_DIR/google-calendar"
else
  echo -e "${YELLOW}Aviso: diretório de volumes padrão não encontrado automaticamente.${NC}"
  echo "Procurando contêineres Docker do edge-runtime..."
fi

# 2. Migration na tabela settings (garante que as colunas existem no Postgres local)
echo ""
echo -e "${YELLOW}[2/3] Aplicando migration na tabela settings (PostgreSQL)...${NC}"
DB_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E 'supabase.*db|supabase.*postgres|db.*supabase' | head -n 1 || true)

if [ -n "$DB_CONTAINER" ]; then
  echo -e "Contêiner Postgres encontrado: ${GREEN}$DB_CONTAINER${NC}"
  docker exec -i "$DB_CONTAINER" psql -U postgres -d postgres << 'EOSQL'
ALTER TABLE public.settings
  ADD COLUMN IF NOT EXISTS "googleClientId" text,
  ADD COLUMN IF NOT EXISTS "googleClientSecret" text;
COMMENT ON COLUMN public.settings."googleClientId" IS 'Client ID OAuth 2.0 do Google Cloud Console';
COMMENT ON COLUMN public.settings."googleClientSecret" IS 'Client Secret OAuth 2.0 do Google Cloud Console';
EOSQL
  echo -e "${GREEN}✓ Migration aplicada com sucesso no Postgres do VPS!${NC}"
else
  echo -e "${YELLOW}Aviso: contêiner Postgres não detectado por nome padrão. O app tentará salvar via API REST.${NC}"
fi

# 3. Informações das variáveis de ambiente no EasyPanel
echo ""
echo -e "${YELLOW}[3/3] Variáveis de ambiente no EasyPanel (opcional, mas recomendado):${NC}"
echo "Se preferir configurar via EasyPanel no contêiner do Edge Runtime, use os nomes:"
echo "  GOOGLE_CLIENT_ID=<seu-client-id>"
echo "  GOOGLE_CLIENT_SECRET=<seu-client-secret>"
echo ""
echo -e "${GREEN}Alternativa recomendada e mais simples:${NC}"
echo "Agora você também pode simplesmente acessar o DPSjur:"
echo "  Configurações > Integrações > Google Agenda"
echo "  E colar o Client ID e Client Secret diretamente pela tela do sistema!"
echo ""
echo -e "${GREEN}======================================================${NC}"
echo -e "${GREEN}  Concluído com sucesso!                              ${NC}"
echo -e "${GREEN}======================================================${NC}"
