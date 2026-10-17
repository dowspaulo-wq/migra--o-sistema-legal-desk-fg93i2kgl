-- Migration: Create payment_plans table and add plan_id/pair_id to transactions
-- Follows camelCase naming convention matching the rest of the schema

-- 1. Create table payment_plans
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

-- Enable RLS
ALTER TABLE public.payment_plans ENABLE ROW LEVEL SECURITY;

-- 2. Drop and recreate idempotent RLS policies for payment_plans
DROP POLICY IF EXISTS "payment_plans_authenticated_all" ON public.payment_plans;
CREATE POLICY "payment_plans_authenticated_all" ON public.payment_plans
    FOR ALL TO authenticated USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "payment_plans_service_role_all" ON public.payment_plans;
CREATE POLICY "payment_plans_service_role_all" ON public.payment_plans
    FOR ALL TO service_role USING (true) WITH CHECK (true);

-- 3. Add plan_id and pair_id columns to transactions
ALTER TABLE public.transactions ADD COLUMN IF NOT EXISTS "plan_id" UUID REFERENCES public.payment_plans(id) ON DELETE CASCADE;
ALTER TABLE public.transactions ADD COLUMN IF NOT EXISTS "pair_id" UUID REFERENCES public.transactions(id) ON DELETE SET NULL;
ALTER TABLE public.transactions ADD COLUMN IF NOT EXISTS "installment_number" INTEGER;
ALTER TABLE public.transactions ADD COLUMN IF NOT EXISTS "installment_total" INTEGER;

-- 4. Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_payment_plans_client_id ON public.payment_plans("clientId");
CREATE INDEX IF NOT EXISTS idx_payment_plans_process_id ON public.payment_plans("processId");
CREATE INDEX IF NOT EXISTS idx_transactions_plan_id ON public.transactions("plan_id");
CREATE INDEX IF NOT EXISTS idx_transactions_pair_id ON public.transactions("pair_id");

-- 5. Ensure "Repasse ao Cliente" category exists in public.settings
DO $$
BEGIN
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
