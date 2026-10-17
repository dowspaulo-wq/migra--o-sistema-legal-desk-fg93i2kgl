-- Migração idempotente para o módulo Financeiro
-- 1. Unificar status 'Realizado' -> 'Pago'
-- 2. Extinguir status 'Êxito' -> 'Pago' (se valor > 0) ou 'Previsto' (se 0)
-- 3. Extinguir 'quota littis' / 'quota litis' -> 'Honorários de Êxito'
-- 4. Normalizar capitalização de categorias
-- 5. Adicionar feePercentage em cases se não existir

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' 
          AND table_name = 'cases' 
          AND column_name = 'feePercentage'
    ) THEN
        ALTER TABLE public.cases ADD COLUMN "feePercentage" numeric;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' 
          AND table_name = 'transactions' 
          AND column_name = 'percentage'
    ) THEN
        ALTER TABLE public.transactions ADD COLUMN percentage numeric;
    END IF;

    UPDATE public.transactions
    SET status = 'Pago'
    WHERE status ILIKE 'realizado' OR status = 'Realizado';

    UPDATE public.transactions
    SET 
        category = 'Honorários de Êxito',
        type = 'income',
        status = CASE 
            WHEN COALESCE(amount, 0) > 0 THEN 'Pago'
            ELSE 'Previsto'
        END
    WHERE status ILIKE 'êxito' OR status ILIKE 'exito';

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
