#!/usr/bin/env bash
# ==============================================================================
# Script: docs/google-calendar/01-atualizar-google-calendar-vps.sh
# Finalidade: Atualizar a Edge Function 'google-calendar' no Supabase self-hosted
#             no VPS Hostinger e aplicar a migration com as colunas googleClientId
#             e googleClientSecret na tabela settings.
# Execução no VPS (copie e cole como root no terminal SSH):
#   curl -sSf -L -H "Accept: application/vnd.github.v3.raw" \
#     "https://api.github.com/repos/dowspaulo-wq/migra--o-sistema-legal-desk-fg93i2kgl/contents/docs/google-calendar/01-atualizar-google-calendar-vps.sh?ref=main" \
#     -o /root/01-atualizar-google-calendar-vps.sh && bash /root/01-atualizar-google-calendar-vps.sh
# ==============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}======================================================${NC}"
echo -e "${BLUE}  DPSjur - Atualização da Integração Google Calendar  ${NC}"
echo -e "${BLUE}======================================================${NC}"
echo ""

# 1. Localizar o contêiner de Edge Functions do Supabase
echo -e "${YELLOW}[1/3] Localizando contêiner de Edge Functions no VPS...${NC}"
FUNCTIONS_CONTAINER="${FUNCTIONS_CONTAINER:-}"
if [ -z "$FUNCTIONS_CONTAINER" ]; then
  FUNCTIONS_CONTAINER=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -iE 'supa?base.*functions|supabase-edge-runtime|edge-runtime' | head -n 1 || true)
fi

WORK_DIR="/tmp/sbjur-google-calendar-deploy"
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR/google-calendar"
mkdir -p "$WORK_DIR/_shared"

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

  curl -sSf -L -H "Cache-Control: no-cache" \
    "https://raw.githubusercontent.com/dowspaulo-wq/migra--o-sistema-legal-desk-fg93i2kgl/main/${rel_path}" -o "$dest_path"
}

echo "Baixando arquivos atualizados da Edge Function..."
download_file "supabase/functions/_shared/cors.ts" "$WORK_DIR/_shared/cors.ts"
download_file "supabase/functions/google-calendar/index.ts" "$WORK_DIR/google-calendar/index.ts"
download_file "supabase/functions/google-calendar/deno.json" "$WORK_DIR/google-calendar/deno.json"

if [ -n "$FUNCTIONS_CONTAINER" ]; then
  echo -e "Contêiner de functions detectado: ${GREEN}$FUNCTIONS_CONTAINER${NC}"
  TARGET_DIR="/home/deno/functions"
  if ! docker exec "$FUNCTIONS_CONTAINER" test -d "$TARGET_DIR" 2>/dev/null; then
    if docker exec "$FUNCTIONS_CONTAINER" test -d "/app/functions" 2>/dev/null; then
      TARGET_DIR="/app/functions"
    elif docker exec "$FUNCTIONS_CONTAINER" test -d "/functions" 2>/dev/null; then
      TARGET_DIR="/functions"
    else
      docker exec "$FUNCTIONS_CONTAINER" mkdir -p "$TARGET_DIR" || true
    fi
  fi
  docker cp "$WORK_DIR/_shared" "$FUNCTIONS_CONTAINER:$TARGET_DIR/" 2>/dev/null || true
  docker cp "$WORK_DIR/google-calendar" "$FUNCTIONS_CONTAINER:$TARGET_DIR/"
  docker restart "$FUNCTIONS_CONTAINER" >/dev/null 2>&1 || true
  echo -e "${GREEN}✓ Edge Function google-calendar atualizada e contêiner $FUNCTIONS_CONTAINER reiniciado com sucesso!${NC}"
else
  echo -e "${YELLOW}Aviso: contêiner de Edge Functions não detectado por nome padrão.${NC}"
fi

# 2. Migration na tabela settings (garante que as colunas existem no Postgres local)
echo ""
echo -e "${YELLOW}[2/3] Aplicando migration na tabela settings (PostgreSQL)...${NC}"
DB_CONTAINER="${DB_CONTAINER:-}"
if [ -z "$DB_CONTAINER" ]; then
  DB_CONTAINER=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -E 'supa?base.*db|supa?base-db' | head -n 1 || true)
fi
if [ -z "$DB_CONTAINER" ]; then
  DB_CONTAINER=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -E 'postgres|db' | grep -v -E 'dpsjur-web|web|frontend|traefik|redis' | head -n 1 || true)
fi

if [ -n "$DB_CONTAINER" ]; then
  echo -e "Contêiner Postgres encontrado: ${GREEN}$DB_CONTAINER${NC}"
  docker exec -i "$DB_CONTAINER" psql -U postgres -d postgres << 'EOSQL'
ALTER TABLE public.settings
  ADD COLUMN IF NOT EXISTS "googleClientId" text,
  ADD COLUMN IF NOT EXISTS "googleClientSecret" text,
  ADD COLUMN IF NOT EXISTS "googleCalendarTokens" jsonb;

ALTER TABLE public.appointments
  ADD COLUMN IF NOT EXISTS "googleEventId" text;

NOTIFY pgrst, 'reload schema';
EOSQL
  echo -e "${GREEN}✓ Migration aplicada e schema recarregado no Postgres do VPS!${NC}"

  # Se houver contêiner PostgREST, reinicia para aplicar na hora
  PGRST_CONTAINER=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -E 'supa?base.*rest|postgrest' | head -n 1 || true)
  if [ -n "$PGRST_CONTAINER" ]; then
    docker restart "$PGRST_CONTAINER" >/dev/null 2>&1 || true
    echo -e "${GREEN}✓ Contêiner PostgREST reiniciado!${NC}"
  fi
else
  echo -e "${YELLOW}Aviso: contêiner Postgres não detectado por nome padrão.${NC}"
fi

# 3. Informações finais
echo ""
echo -e "${YELLOW}[3/3] Próximos passos:${NC}"
echo "1. Acesse https://sistema.advdouglaspsantos.com.br"
echo "2. Configurações > Integrações > Google Agenda"
echo "3. Confirme que o Client ID e Secret estão salvos"
echo "4. Clique em 'Conectar Conta Google'"
echo ""
echo -e "${GREEN}======================================================${NC}"
echo -e "${GREEN}  Concluído com sucesso!                              ${NC}"
echo -e "${GREEN}======================================================${NC}"
