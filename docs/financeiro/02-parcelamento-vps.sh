#!/usr/bin/env bash
# ==============================================================================
# SCRIPT DE INSTALAÇÃO DO RECURSO DE PARCELAMENTO COM REPASSE NO VPS (EASYPANEL)
# Versão: v0.0.569
# Alvo: VPS Hostinger 2.25.181.69 (EasyPanel / Supabase Self-Hosted)
#
# O QUE ESTE SCRIPT FAZ:
# 1. Localiza o contêiner do banco PostgreSQL no EasyPanel
# 2. Executa a migração SQL idempotente do Parcelamento com Repasse ao Cliente:
#    - Cria tabela public.payment_plans (se não existir)
#    - Habilita RLS e aplica políticas para authenticated e service_role
#    - Adiciona colunas em transactions: plan_id, pair_id, installment_number, installment_total
#    - Cria índices de performance
#    - Insere categoria "Repasse ao Cliente" nas configurações do sistema
# 3. Exibe conferência do schema pós-migração
#
# COMO EXECUTAR NO TERMINAL DO VPS (como root - NÃO INTERATIVO):
#   curl -sSL "https://raw.githubusercontent.com/dowspaulo-wq/migra--o-sistema-legal-desk-fg93i2kgl/main/docs/financeiro/02-parcelamento-vps.sh" -o /root/02-parcelamento-vps.sh
#   bash /root/02-parcelamento-vps.sh
# ==============================================================================

set -eo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${BOLD}${BLUE}=== DPSjur - Recurso Parcelamento com Repasse ao Cliente (v0.0.569) ===${NC}"

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
    -- 1. Criar tabela payment_plans se não existir
    CREATE TABLE IF NOT EXISTS public.payment_plans (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        "clientId" UUID REFERENCES public.clients(id) ON DELETE CASCADE NOT NULL,
        "processId" UUID REFERENCES public.cases(id) ON DELETE SET NULL,
        title TEXT NOT NULL,
        "installmentAmount" NUMERIC NOT NULL DEFAULT 0,
        "installmentsCount" INTEGER NOT NULL DEFAULT 1,
        periodicity TEXT NOT NULL DEFAULT 'mensal',
        "firstDueDate" TEXT NOT NULL,
        "feePercentage" NUMERIC NOT NULL DEFAULT 0,
        "clientPercentage" NUMERIC NOT NULL DEFAULT 0,
        "feeInstallmentAmount" NUMERIC NOT NULL DEFAULT 0,
        "clientInstallmentAmount" NUMERIC NOT NULL DEFAULT 0,
        "totalAmount" NUMERIC NOT NULL DEFAULT 0,
        "totalFeeAmount" NUMERIC NOT NULL DEFAULT 0,
        "totalClientAmount" NUMERIC NOT NULL DEFAULT 0,
        "bankAccount" TEXT DEFAULT 'ASAAS',
        "paymentMethod" TEXT DEFAULT 'PIX',
        status TEXT NOT NULL DEFAULT 'Ativo',
        notes TEXT,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );

    -- Habilitar RLS
    ALTER TABLE public.payment_plans ENABLE ROW LEVEL SECURITY;

    -- Políticas RLS idempotentes
    DROP POLICY IF EXISTS "payment_plans_authenticated_all" ON public.payment_plans;
    CREATE POLICY "payment_plans_authenticated_all" ON public.payment_plans
        FOR ALL TO authenticated USING (true) WITH CHECK (true);

    DROP POLICY IF EXISTS "payment_plans_service_role_all" ON public.payment_plans;
    CREATE POLICY "payment_plans_service_role_all" ON public.payment_plans
        FOR ALL TO service_role USING (true) WITH CHECK (true);

    -- 2. Colunas em transactions
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' AND table_name = 'transactions' AND column_name = 'plan_id'
    ) THEN
        ALTER TABLE public.transactions ADD COLUMN "plan_id" UUID REFERENCES public.payment_plans(id) ON DELETE CASCADE;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' AND table_name = 'transactions' AND column_name = 'pair_id'
    ) THEN
        ALTER TABLE public.transactions ADD COLUMN "pair_id" UUID REFERENCES public.transactions(id) ON DELETE SET NULL;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' AND table_name = 'transactions' AND column_name = 'installment_number'
    ) THEN
        ALTER TABLE public.transactions ADD COLUMN "installment_number" INTEGER;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' AND table_name = 'transactions' AND column_name = 'installment_total'
    ) THEN
        ALTER TABLE public.transactions ADD COLUMN "installment_total" INTEGER;
    END IF;

    -- 3. Índices de busca
    CREATE INDEX IF NOT EXISTS idx_payment_plans_client_id ON public.payment_plans("clientId");
    CREATE INDEX IF NOT EXISTS idx_payment_plans_process_id ON public.payment_plans("processId");
    CREATE INDEX IF NOT EXISTS idx_transactions_plan_id ON public.transactions("plan_id");
    CREATE INDEX IF NOT EXISTS idx_transactions_pair_id ON public.transactions("pair_id");

    -- 4. Adicionar categoria 'Repasse ao Cliente' em settings
    UPDATE public.settings
    SET "transactionCategories" = (
        SELECT jsonb_agg(DISTINCT elem ORDER BY elem)
        FROM (
            SELECT elem
            FROM jsonb_array_elements("transactionCategories") AS elem
            UNION
            SELECT '"Repasse ao Cliente"'::jsonb AS elem
        ) sub
    )
    WHERE "transactionCategories" IS NOT NULL;

END $$;
EOSQL

echo -e "${GREEN}✓ Migração SQL aplicada no banco com sucesso!${NC}"

# 3. Conferência dos dados
echo -e "\n${BOLD}[3/3] Conferência do banco pós-migração:${NC}"
docker exec -i "$DB_CONTAINER" psql -U postgres -d postgres -c "\d public.payment_plans"
docker exec -i "$DB_CONTAINER" psql -U postgres -d postgres -c "SELECT column_name, data_type FROM information_schema.columns WHERE table_name = 'transactions' AND column_name IN ('plan_id', 'pair_id', 'installment_number', 'installment_total');"

echo -e "\n${BOLD}${GREEN}=== ATUALIZAÇÃO CONCLUÍDA COM SUCESSO (v0.0.569) ===${NC}"
echo -e "Próximos passos para o Douglas:"
echo -e "1. No painel EasyPanel, vá no serviço de frontend ${BOLD}dpsjur${NC} e clique em ${BOLD}Implantar${NC} (Deploy)."
echo -e "2. No navegador, acesse https://sistema.advdouglaspsantos.com.br e aperte ${BOLD}Ctrl + F5${NC} para limpar o cache."
echo -e "3. Em Cliente ou Processo, use o botão 'Novo Parcelamento' para cadastrar planos longos com repasse!"
