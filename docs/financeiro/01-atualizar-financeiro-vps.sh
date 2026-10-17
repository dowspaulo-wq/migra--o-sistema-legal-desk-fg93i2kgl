#!/usr/bin/env bash
# ==============================================================================
# SCRIPT DE ATUALIZAÇÃO DO MÓDULO FINANCEIRO NO VPS (HOSTINGER / EASYPANEL)
# Versão: v0.0.568
# Alvo: VPS Hostinger 2.25.181.69 (EasyPanel / Supabase Self-Hosted)
#
# O QUE ESTE SCRIPT FAZ:
# 1. Localiza o contêiner do banco PostgreSQL no EasyPanel
# 2. Executa a migração SQL idempotente do Financeiro:
#    - Unifica status: "Realizado" -> "Pago"
#    - Extingue status "Êxito" -> status "Pago" / "Previsto" (êxito é tipo, nunca status)
#    - Extingue "quota littis" / "quota litis" -> "Honorários de Êxito" em todas tabelas
#    - Normaliza capitalização de tipos e categorias
#    - Adiciona coluna feePercentage em cases se necessário
# 3. Dá instruções para deploy do frontend dpsjur no EasyPanel
#
# COMO EXECUTAR NO TERMINAL DO VPS (como root - NÃO INTERATIVO):
#   curl -sSL "https://raw.githubusercontent.com/dowspaulo-wq/migra--o-sistema-legal-desk-fg93i2kgl/main/docs/financeiro/01-atualizar-financeiro-vps.sh" -o /root/01-atualizar-financeiro-vps.sh
#   bash /root/01-atualizar-financeiro-vps.sh
# ==============================================================================

set -eo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${BOLD}${BLUE}=== DPSjur - Atualização Módulo Financeiro VPS (v0.0.568) ===${NC}"

# 1. Identificar contêiner Docker do PostgreSQL e credenciais de acesso
echo -e "\n${BOLD}[1/3] Procurando contêiner Docker do PostgreSQL no VPS...${NC}"

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

echo -e "Contêiner Banco Postgres: ${GREEN}${DB_CONTAINER:-'não encontrado'}${NC}"

if [ -z "$DB_CONTAINER" ]; then
    echo -e "${RED}Erro fatal: Contêiner do banco de dados não foi encontrado. Verifique se o EasyPanel/Supabase está rodando.${NC}"
    exit 1
fi

# Derivar variáveis de ambiente do contêiner via docker inspect (com fallback)
INSPECT_USER=$(docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "$DB_CONTAINER" 2>/dev/null | grep -E '^POSTGRES_USER=' | head -n 1 | cut -d= -f2- || true)
INSPECT_DB=$(docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "$DB_CONTAINER" 2>/dev/null | grep -E '^POSTGRES_DB=' | head -n 1 | cut -d= -f2- || true)
INSPECT_PASS=$(docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "$DB_CONTAINER" 2>/dev/null | grep -E '^POSTGRES_PASSWORD=' | head -n 1 | cut -d= -f2- || true)

# Detectar usuário funcional com fallback (supabase_admin superuser Supabase, postgres, INSPECT_USER, etc.)
CANDIDATE_USERS=()
[ -n "${POSTGRES_USER:-}" ] && CANDIDATE_USERS+=("${POSTGRES_USER}")
[ -n "$INSPECT_USER" ] && CANDIDATE_USERS+=("$INSPECT_USER")
CANDIDATE_USERS+=("supabase_admin" "postgres" "Doug")

# Deduplica usuários candidatos mantendo a ordem
UNIQUE_USERS=()
for u in "${CANDIDATE_USERS[@]}"; do
    [[ " ${UNIQUE_USERS[*]} " =~ " ${u} " ]] || UNIQUE_USERS+=("$u")
done

DETECTED_USER=""
DETECTED_DB=""

echo -e "Detectando usuário e banco de dados disponíveis..."

for test_u in "${UNIQUE_USERS[@]}"; do
    # Tenta listar bancos para este usuário
    DB_LIST=$(docker exec -i "$DB_CONTAINER" psql -U "$test_u" -At -c "SELECT datname FROM pg_database WHERE datistemplate = false;" 2>/dev/null || true)
    if [ -n "$DB_LIST" ]; then
        DETECTED_USER="$test_u"
        # Escolhe o melhor banco: POSTGRES_DB informado, ou banco da aplicação existente, ou 'postgres'
        for cand_db in "${POSTGRES_DB:-}" "$INSPECT_DB" "dpsjur" "postgres"; do
            if [ -n "$cand_db" ] && echo "$DB_LIST" | grep -qx "$cand_db"; then
                DETECTED_DB="$cand_db"
                break
            fi
        done
        # Se nenhum casou exatamente, pega o primeiro da lista que não seja template
        if [ -z "$DETECTED_DB" ]; then
            DETECTED_DB=$(echo "$DB_LIST" | head -n 1)
        fi
        break
    fi
done

# Fallback seguro caso 'pg_database' precise de banco específico para conectar
if [ -z "$DETECTED_USER" ]; then
    for test_u in "${UNIQUE_USERS[@]}"; do
        for test_d in "${POSTGRES_DB:-}" "$INSPECT_DB" "postgres" "dpsjur"; do
            [ -z "$test_d" ] && continue
            if docker exec -i "$DB_CONTAINER" psql -U "$test_u" -d "$test_d" -At -c "SELECT 1;" >/dev/null 2>&1; then
                DETECTED_USER="$test_u"
                DETECTED_DB="$test_d"
                break 2
            fi
        done
    done
fi

# Fallback final se nada respondeu
DB_USER="${DETECTED_USER:-supabase_admin}"
DB_NAME="${DETECTED_DB:-postgres}"

echo -e "Usuário PostgreSQL detectado: ${GREEN}${DB_USER}${NC}"
echo -e "Banco de Dados detectado:     ${GREEN}${DB_NAME}${NC}"

# 2. Aplicar script SQL idempotente
echo -e "\n${BOLD}[2/3] Aplicando migração SQL no PostgreSQL (usuário: ${DB_USER}, banco: ${DB_NAME})...${NC}"

docker exec -i "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" << 'EOSQL'
DO $$
BEGIN
    -- 1. Garantir coluna feePercentage na tabela cases
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' 
          AND table_name = 'cases' 
          AND column_name = 'feePercentage'
    ) THEN
        ALTER TABLE public.cases ADD COLUMN "feePercentage" numeric;
    END IF;

    -- 2. Garantir coluna percentage na tabela transactions
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' 
          AND table_name = 'transactions' 
          AND column_name = 'percentage'
    ) THEN
        ALTER TABLE public.transactions ADD COLUMN percentage numeric;
    END IF;

    -- 3. Unificação de status: Realizado -> Pago
    UPDATE public.transactions
    SET status = 'Pago'
    WHERE status ILIKE 'realizado' OR status = 'Realizado';

    -- 4. Extinção do status "Êxito":
    UPDATE public.transactions
    SET 
        category = 'Honorários de Êxito',
        type = 'income',
        status = CASE 
            WHEN COALESCE(amount, 0) > 0 THEN 'Pago'
            ELSE 'Previsto'
        END
    WHERE status ILIKE 'êxito' OR status ILIKE 'exito';

    -- 5. Extinção de "quota littis" / "quota litis":
    UPDATE public.transactions
    SET category = 'Honorários de Êxito'
    WHERE category ILIKE '%quota%litis%' 
       OR category ILIKE '%quota%littis%'
       OR category ILIKE '%quota%';

    UPDATE public.cases
    SET "feeType" = 'Honorários de Êxito'
    WHERE "feeType" ILIKE '%quota%litis%' 
       OR "feeType" ILIKE '%quota%littis%'
       OR "feeType" ILIKE '%quota%';

    -- 6. Capitalização padrão de categorias conhecidas
    UPDATE public.transactions
    SET category = 'Honorários Contratuais'
    WHERE category ILIKE 'honorários contratuais' OR category ILIKE 'honorarios contratuais';

    UPDATE public.transactions
    SET category = 'Honorários de Êxito'
    WHERE category ILIKE 'honorários de êxito' OR category ILIKE 'honorarios de exito' OR category ILIKE 'honorários de exito' OR category ILIKE 'honorarios de êxito';

    UPDATE public.transactions
    SET category = 'Honorários Sucumbenciais'
    WHERE category ILIKE 'honorários sucumbenciais' OR category ILIKE 'honorarios sucumbenciais';

    UPDATE public.transactions
    SET category = 'Honorários Periciais'
    WHERE category ILIKE 'honorários periciais' OR category ILIKE 'honorarios periciais';

    UPDATE public.transactions
    SET category = 'Custas Iniciais'
    WHERE category ILIKE 'custas iniciais';

    UPDATE public.transactions
    SET category = 'Custas Finais'
    WHERE category ILIKE 'custas finais';

    UPDATE public.transactions
    SET category = 'Depósito Recursal'
    WHERE category ILIKE 'depósito recursal' OR category ILIKE 'deposito recursal';

    UPDATE public.transactions
    SET category = 'Diligência'
    WHERE category ILIKE 'diligência' OR category ILIKE 'diligencia';

    UPDATE public.transactions
    SET category = 'Repasse ao cliente'
    WHERE category ILIKE 'repasse ao cliente';

    -- 7. Normalizar categorias em settings
    UPDATE public.settings
    SET "transactionCategories" = (
        SELECT jsonb_agg(DISTINCT elem ORDER BY elem)
        FROM (
            SELECT 
                CASE 
                    WHEN elem::text ILIKE '%quota%' THEN '"Honorários de Êxito"'::jsonb
                    WHEN elem::text ILIKE '%honorarios de exito%' THEN '"Honorários de Êxito"'::jsonb
                    WHEN elem::text ILIKE '%honorários de êxito%' THEN '"Honorários de Êxito"'::jsonb
                    ELSE elem
                END AS elem
            FROM jsonb_array_elements("transactionCategories") AS elem
        ) sub
    )
    WHERE "transactionCategories" IS NOT NULL;

END $$;
EOSQL

echo -e "${GREEN}✓ Migração SQL aplicada no banco com sucesso!${NC}"

# 3. Conferência dos dados
echo -e "\n${BOLD}[3/3] Conferência do banco pós-migração (usuário: ${DB_USER}, banco: ${DB_NAME}):${NC}"
docker exec -i "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -c "SELECT status, count(*) FROM public.transactions GROUP BY status ORDER BY count(*) DESC;"

echo -e "\n${BOLD}${GREEN}=== ATUALIZAÇÃO DO BANCO CONCLUÍDA COM SUCESSO (v0.0.568) ===${NC}"
echo -e "Próximos passos para o Douglas:"
echo -e "1. No painel EasyPanel, vá no serviço de frontend ${BOLD}dpsjur${NC} e clique em ${BOLD}Implantar${NC} (Deploy)."
echo -e "2. No navegador, acesse https://sistema.advdouglaspsantos.com.br e aperte ${BOLD}Ctrl + F5${NC} para limpar o cache."
echo -e "3. Acesse a tela ${BOLD}Financeiro${NC} e teste os novos filtros e a seção 'Êxito a apurar'."
