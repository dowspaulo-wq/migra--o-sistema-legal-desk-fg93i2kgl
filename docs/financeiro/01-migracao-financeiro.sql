-- ==============================================================================
-- SCRIPT DE MIGRAÇÃO SQL IDEMPOTENTE: MÓDULO FINANCEIRO DPSJUR / SBJUR
-- Versão: v0.0.568
-- Decisões do Douglas:
-- 1. Unificação de status: "Realizado" -> "Pago"
-- 2. Extinção do status "Êxito" -> status "Pago" (se com valor/recebido) ou "Previsto" (se pendente/a apurar)
-- 3. Quota Litis extinta -> Unificada como "Honorários de Êxito" (case-insensitive)
-- 4. Capitalização correta de categorias e tipos
-- 5. Garantia de colunas de percentual e suporte a honorários de êxito
-- ==============================================================================

DO $$
BEGIN
    -- 1. Garantir coluna de percentual na tabela cases (caso não exista)
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' 
          AND table_name = 'cases' 
          AND column_name = 'feePercentage'
    ) THEN
        ALTER TABLE public.cases ADD COLUMN "feePercentage" numeric;
    END IF;

    -- 2. Garantir coluna percentage na tabela transactions (caso não exista)
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' 
          AND table_name = 'transactions' 
          AND column_name = 'percentage'
    ) THEN
        ALTER TABLE public.transactions ADD COLUMN percentage numeric;
    END IF;

    -- 3. Unificação de status em transactions: 'Realizado' -> 'Pago'
    UPDATE public.transactions
    SET status = 'Pago'
    WHERE status ILIKE 'realizado' OR status = 'Realizado';

    -- 4. Extinção do status "Êxito" em transactions:
    -- Se tem valor > 0 e já foi realizado/recebido -> 'Pago'
    -- Se não tem valor ou valor = 0 -> 'Previsto'
    UPDATE public.transactions
    SET 
        category = 'Honorários de Êxito',
        type = 'income',
        status = CASE 
            WHEN COALESCE(amount, 0) > 0 THEN 'Pago'
            ELSE 'Previsto'
        END
    WHERE status ILIKE 'êxito' OR status ILIKE 'exito';

    -- 5. Unificação e extinção de variações de "quota littis" / "quota litis"
    -- Nas transactions:
    UPDATE public.transactions
    SET category = 'Honorários de Êxito'
    WHERE category ILIKE '%quota%litis%' 
       OR category ILIKE '%quota%littis%'
       OR category ILIKE '%quota%';

    -- Nos cases ("feeType"):
    UPDATE public.cases
    SET "feeType" = 'Honorários de Êxito'
    WHERE "feeType" ILIKE '%quota%litis%' 
       OR "feeType" ILIKE '%quota%littis%'
       OR "feeType" ILIKE '%quota%';

    -- 6. Normalização de capitalização das categorias conhecidas de transactions
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

    -- 7. Normalizar primeira letra maiúscula em outras categorias (initcap onde aplicável)
    UPDATE public.transactions
    SET category = initcap(category)
    WHERE category IS NOT NULL 
      AND category != ''
      AND category NOT IN (
          'Honorários Contratuais',
          'Honorários de Êxito',
          'Honorários Sucumbenciais',
          'Honorários Periciais',
          'Custas Iniciais',
          'Custas Finais',
          'Depósito Recursal',
          'Diligência',
          'Repasse ao cliente'
      )
      AND category = lower(category);

    -- 8. Atualizar lista de categorias em settings (se houver quota littis no jsonb)
    -- Remove variações de quota e garante 'Honorários de Êxito'
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
