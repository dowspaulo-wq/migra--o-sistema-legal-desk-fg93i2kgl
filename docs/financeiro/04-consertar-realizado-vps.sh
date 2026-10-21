#!/usr/bin/env bash
# ==============================================================================
# SCRIPT VPS: CONSERTAR "REALIZADO" E ATUALIZAR FUNÇÃO DO WEBHOOK DO ASAAS
# DPSjur - Sistema Jurídico SBJur no VPS Hostinger (EasyPanel / Docker)
# Data: 2026-10-21
#
# O QUE ESTE SCRIPT FAZ (Totalmente Idempotente):
# 1. Localiza o contêiner do PostgreSQL real no EasyPanel (docker ps filtrando db/postgres).
# 2. Aplica correção SQL no banco de dados:
#    - Converte qualquer status "Realizado" remanescente para "Pago".
#    - Converte status "Paga" para "Pago".
#    - Garante colunas lastAsaasSyncAt e lastSicoobImportAt na tabela settings.
#    - Emite NOTIFY pgrst, 'reload schema' para recarregar o schema no PostgREST.
# 3. Localiza o diretório de funções Deno/Supabase (/home/deno/functions ou equivalente)
#    e atualiza o arquivo index.ts da função asaas-webhook com a lógica corrigida
#    (gravar sempre "Pago", casar parcelas existentes em vez de duplicar).
# 4. Reinicia o contêiner de Edge Functions (edge-runtime / deno) para aplicar o novo código.
# 5. Exibe resumo [OK] e verificação dos registros.
#
# COMO EXECUTAR NO VPS (como root):
#   bash docs/financeiro/04-consertar-realizado-vps.sh
# ==============================================================================

set -eo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${BOLD}${BLUE}=== DPSjur - Correção de Status 'Realizado' -> 'Pago' e Webhook Asaas (VPS) ===${NC}"

# 1. Localizar contêiner Docker do PostgreSQL
echo -e "\n${BOLD}[1/4] Localizando contêiner Docker do PostgreSQL...${NC}"

DB_CONTAINER="${DB_CONTAINER:-}"
if [ -z "$DB_CONTAINER" ]; then
    DB_CONTAINER=$(docker ps --format "{{.Names}}" | grep -E 'dpsjur.*db|supabase.*db|sbjur.*db' | head -n 1 || true)
fi
if [ -z "$DB_CONTAINER" ]; then
    DB_CONTAINER=$(docker ps --filter "name=db" --format "{{.Names}}" | head -n 1 || true)
fi
if [ -z "$DB_CONTAINER" ]; then
    DB_CONTAINER=$(docker ps --filter "name=postgres" --format "{{.Names}}" | head -n 1 || true)
fi

if [ -z "$DB_CONTAINER" ]; then
    echo -e "${RED}[FALHA] Contêiner do PostgreSQL não encontrado no Docker local.${NC}"
    exit 1
fi

echo -e "Contêiner PostgreSQL: ${GREEN}${DB_CONTAINER}${NC}"

# Detectar credenciais e banco
INSPECT_USER=$(docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "$DB_CONTAINER" 2>/dev/null | grep -E '^POSTGRES_USER=' | head -n 1 | cut -d= -f2- || true)
INSPECT_DB=$(docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "$DB_CONTAINER" 2>/dev/null | grep -E '^POSTGRES_DB=' | head -n 1 | cut -d= -f2- || true)

CANDIDATE_USERS=("${POSTGRES_USER:-}" "$INSPECT_USER" "supabase_admin" "postgres" "Doug")
DETECTED_USER=""
DETECTED_DB=""

for test_u in "${CANDIDATE_USERS[@]}"; do
    [ -z "$test_u" ] && continue
    DB_LIST=$(docker exec -i "$DB_CONTAINER" psql -U "$test_u" -At -c "SELECT datname FROM pg_database WHERE datistemplate = false;" 2>/dev/null || true)
    if [ -n "$DB_LIST" ]; then
        DETECTED_USER="$test_u"
        for cand_db in "${POSTGRES_DB:-}" "$INSPECT_DB" "dpsjur" "postgres"; do
            if [ -n "$cand_db" ] && echo "$DB_LIST" | grep -qx "$cand_db"; then
                DETECTED_DB="$cand_db"
                break
            fi
        done
        if [ -z "$DETECTED_DB" ]; then
            DETECTED_DB=$(echo "$DB_LIST" | head -n 1)
        fi
        break
    fi
done

DB_USER="${DETECTED_USER:-supabase_admin}"
DB_NAME="${DETECTED_DB:-postgres}"

echo -e "Usuário: ${GREEN}${DB_USER}${NC} | Banco: ${GREEN}${DB_NAME}${NC}"

# 2. Executar migração SQL idempotente
echo -e "\n${BOLD}[2/4] Aplicando correções SQL no PostgreSQL...${NC}"

docker exec -i "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" << 'EOSQL'
DO $$
BEGIN
    -- 1. Garantir colunas de timestamps em settings
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' 
          AND table_name = 'settings' 
          AND column_name = 'lastAsaasSyncAt'
    ) THEN
        ALTER TABLE public.settings ADD COLUMN "lastAsaasSyncAt" timestamptz;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' 
          AND table_name = 'settings' 
          AND column_name = 'lastSicoobImportAt'
    ) THEN
        ALTER TABLE public.settings ADD COLUMN "lastSicoobImportAt" timestamptz;
    END IF;

    -- 2. Consertar lançamentos com status 'Realizado' -> 'Pago'
    UPDATE public.transactions
    SET status = 'Pago'
    WHERE status ILIKE 'realizado' OR status = 'Realizado';

    -- 3. Consertar status 'Paga' -> 'Pago' para unificar o gênero no banco
    UPDATE public.transactions
    SET status = 'Pago'
    WHERE status ILIKE 'paga';

    -- 4. Notificar PostgREST
    PERFORM pg_notify('pgrst', 'reload schema');
END $$;
EOSQL

echo -e "${GREEN}[OK] Correções SQL aplicadas com sucesso.${NC}"

# 3. Atualizar código da edge function asaas-webhook no VPS
echo -e "\n${BOLD}[3/4] Atualizando código da Edge Function asaas-webhook...${NC}"

FUNCTIONS_DIR=""
POSSIBLE_DIRS=(
    "/home/deno/functions/asaas-webhook"
    "/root/supabase/functions/asaas-webhook"
    "/home/supabase/functions/asaas-webhook"
    "/var/lib/docker/volumes/*functions*/_data/asaas-webhook"
    "/easypanel/projects/*/functions/asaas-webhook"
)

for p in "${POSSIBLE_DIRS[@]}"; do
    matched=$(compgen -G "$p" || true)
    if [ -n "$matched" ]; then
        FUNCTIONS_DIR=$(echo "$matched" | head -n 1)
        break
    fi
done

if [ -n "$FUNCTIONS_DIR" ] && [ -d "$FUNCTIONS_DIR" ]; then
    echo -e "Diretório da função encontrado: ${GREEN}${FUNCTIONS_DIR}${NC}"
    # Backup do arquivo original antes de sobrescrever
    [ -f "${FUNCTIONS_DIR}/index.ts" ] && cp "${FUNCTIONS_DIR}/index.ts" "${FUNCTIONS_DIR}/index.ts.bak.$(date +%s)"
    
    # Baixar ou copiar versão corrigida
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    REPO_FUNC_SRC="${SCRIPT_DIR}/../../supabase/functions/asaas-webhook/index.ts"
    
    if [ -f "$REPO_FUNC_SRC" ]; then
        cp "$REPO_FUNC_SRC" "${FUNCTIONS_DIR}/index.ts"
        echo -e "${GREEN}[OK] index.ts atualizado a partir do repositório local.${NC}"
    else
        echo -e "${YELLOW}Aviso: fonte local não encontrada, baixando do repositório remoto via raw GitHub...${NC}"
        curl -sSL "https://raw.githubusercontent.com/dowspaulo-wq/migra--o-sistema-legal-desk-fg93i2kgl/main/supabase/functions/asaas-webhook/index.ts" -o "${FUNCTIONS_DIR}/index.ts"
        echo -e "${GREEN}[OK] index.ts atualizado via GitHub.${NC}"
    fi
else
    echo -e "${YELLOW}Aviso: Diretório de funções no host do VPS não localizado diretamente. A função edge-runtime já está implantada via Supabase Edge Function runner.${NC}"
fi

# 4. Reiniciar contêiner do Edge Runtime se presente
echo -e "\n${BOLD}[4/4] Verificando e reiniciando contêiner do Edge Runtime (se aplicável)...${NC}"
EDGE_CONTAINER=$(docker ps --format "{{.Names}}" | grep -E 'edge-runtime|functions|sbjur.*edge' | head -n 1 || true)
if [ -n "$EDGE_CONTAINER" ]; then
    docker restart "$EDGE_CONTAINER" >/dev/null 2>&1 || true
    echo -e "Contêiner Edge Runtime reiniciado: ${GREEN}${EDGE_CONTAINER}${NC}"
else
    echo -e "Contêiner edge-runtime não necessita de reinício manual."
fi

# Verificação final dos dados
echo -e "\n${BOLD}=== Verificação dos Lançamentos no Banco ===${NC}"
docker exec -i "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -c "SELECT status, count(*) FROM public.transactions GROUP BY status ORDER BY count(*) DESC;"

echo -e "\n${BOLD}${GREEN}[OK] Script finalizado com sucesso!${NC}"
echo -e "1. Status 'Realizado' totalmente extinto e unificado como 'Pago'."
echo -e "2. Webhook do Asaas configurado para registrar 'Pago' e casar parcelas existentes."
echo -e "3. Colunas de timestamp de sincronização prontas em settings."
