-- Migration: Adicionar suporte a Despesas do Escritório, Tipos de Despesa e Grupo de Fornecedor em transactions
-- Data: 2026-10-19

DO $$
BEGIN
    -- 1. Coluna supplier_group na tabela transactions
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' AND table_name = 'transactions' AND column_name = 'supplier_group'
    ) THEN
        ALTER TABLE public.transactions ADD COLUMN "supplier_group" TEXT;
    END IF;

    -- 2. Coluna expenseTypes na tabela settings
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' AND table_name = 'settings' AND column_name = 'expenseTypes'
    ) THEN
        ALTER TABLE public.settings ADD COLUMN "expenseTypes" JSONB DEFAULT '["Aluguel", "Bolsa de Estágio", "Contabilidade", "Custas e Emolumentos", "Energia Elétrica", "Impostos e Tributos", "Internet e Telefonia", "Marketing e Publicidade", "Material de Escritório", "Pró-labore", "Retirada de Lucros", "Seguros", "Software e Tecnologia", "Tarifas Bancárias", "Outros"]'::jsonb;
    END IF;

    -- 3. Preencher supplier_group retroativo a partir dos fornecedores já vinculados
    UPDATE public.transactions t
    SET supplier_group = s.group_name
    FROM public.suppliers s
    WHERE t."supplierId" = s.id 
      AND t.supplier_group IS NULL 
      AND s.group_name IS NOT NULL;

END $$;
