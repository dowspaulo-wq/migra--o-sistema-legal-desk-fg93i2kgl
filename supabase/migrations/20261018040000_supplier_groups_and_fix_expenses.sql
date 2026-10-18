-- Migração: Grupos de Fornecedores e Correção de Despesas do Escritório / Fornecedores
-- Data: 2026-10-18

DO $$
BEGIN
    -- 1. Adicionar coluna group_name na tabela suppliers se não existir
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' AND table_name = 'suppliers' AND column_name = 'group_name'
    ) THEN
        ALTER TABLE public.suppliers ADD COLUMN "group_name" TEXT;
    END IF;

    -- 2. Categorizar fornecedores existentes em grupos úteis
    UPDATE public.suppliers SET "group_name" = 'Bolsa de Estágio'
    WHERE name ILIKE '%guilherme%' OR name ILIKE '%fernanda%' OR name ILIKE '%estagi%';

    UPDATE public.suppliers SET "group_name" = 'Telefonia'
    WHERE name IN ('CLARO', 'TIM', 'Whatssap', 'Teleprompter') OR name ILIKE '%telef%';

    UPDATE public.suppliers SET "group_name" = 'Contabilidade'
    WHERE name ILIKE '%contabil%';

    UPDATE public.suppliers SET "group_name" = 'Tecnologia'
    WHERE name IN ('Microsoft', 'JURISOFT', 'ZapSign', 'Smart Ideas', 'QUALITYCERT') OR name ILIKE '%software%';

    UPDATE public.suppliers SET "group_name" = 'Marketing'
    WHERE name IN ('ADAPTA', 'ZENO', 'Marcelo Brandão');

    UPDATE public.suppliers SET "group_name" = 'Tributos'
    WHERE name ILIKE 'Tributo%' OR name ILIKE '%imposto%';

    UPDATE public.suppliers SET "group_name" = 'Serviços Financeiros'
    WHERE name IN ('ASAAS', 'SICOOB', 'SEGURO CRED SOLUCOES PARA CREDITO E COB', 'Fator Seguradora');

    -- 3. Vincular despesas órfãs de estagiários aos seus respectivos fornecedores
    -- Guilherme:
    UPDATE public.transactions
    SET "supplierId" = (SELECT id FROM public.suppliers WHERE name = 'Estagiário Guilherme' LIMIT 1)
    WHERE description ILIKE '%Bolsa Guilherme%' AND ("supplierId" IS NULL OR "supplierId" != (SELECT id FROM public.suppliers WHERE name = 'Estagiário Guilherme' LIMIT 1));

    -- Fernanda:
    UPDATE public.transactions
    SET "supplierId" = (SELECT id FROM public.suppliers WHERE name = 'Estagiária Fernanda' LIMIT 1)
    WHERE description ILIKE '%Bolsa Fernanda%' AND ("supplierId" IS NULL OR "supplierId" != (SELECT id FROM public.suppliers WHERE name = 'Estagiária Fernanda' LIMIT 1));

    -- SeguroCred: garantir fornecedor Seguro Cred
    UPDATE public.transactions
    SET "supplierId" = (SELECT id FROM public.suppliers WHERE name ILIKE '%SEGURO CRED%' LIMIT 1)
    WHERE description ILIKE '%SeguroCred%' AND "supplierId" IS NULL;

END $$;
