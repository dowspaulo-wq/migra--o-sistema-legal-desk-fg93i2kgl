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

# 1. Identificar contêiner Docker do PostgreSQL
echo -e "\n${BOLD}[1/3] Procurando contêiner Docker do PostgreSQL no VPS...${NC}"

DB_CONTAINER=$(docker ps --filter "name=db" --format "{{.Names}}" | head -n 1 || true)
if [ -z "$DB_CONTAINER" ]; then
    DB_CONTAINER=$(docker ps --filter "name=postgres" --format "{{.Names}}" | head -n 1 || true)
fi

echo -e "Contêiner Banco Postgres: ${GREEN}${DB_CONTAINER:-'não encontrado'}${NC}"

if [ -z "$DB_CONTAINER" ]; then
    echo -e "${RED}Erro fatal: Contêiner do banco de dados não foi encontrado. Verifique se o EasyPanel/Supabase está rodando.${NC}"
    exit 1
fi

# 2. Aplicar script SQL idempotente
echo -e "\n${BOLD}[2/3] Aplicando migração SQL no PostgreSQL...${NC}"

docker exec -i "$DB_CONTAINER" psql -U postgres -d postgres << 'EOSQL'
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
echo -e "\n${BOLD}[3/3] Conferência do banco pós-migração:${NC}"
docker exec -i "$DB_CONTAINER" psql -U postgres -d postgres -c "SELECT status, count(*) FROM public.transactions GROUP BY status ORDER BY count(*) DESC;"

echo -e "\n${BOLD}${GREEN}=== ATUALIZAÇÃO DO BANCO CONCLUÍDA COM SUCESSO (v0.0.568) ===${NC}"
echo -e "Próximos passos para o Douglas:"
echo -e "1. No painel EasyPanel, vá no serviço de frontend ${BOLD}dpsjur${NC} e clique em ${BOLD}Implantar${NC} (Deploy)."
echo -e "2. No navegador, acesse https://sistema.advdouglaspsantos.com.br e aperte ${BOLD}Ctrl + F5${NC} para limpar o cache."
echo -e "3. Acesse a tela ${BOLD}Financeiro${NC} e teste os novos filtros e a seção 'Êxito a apurar'."
