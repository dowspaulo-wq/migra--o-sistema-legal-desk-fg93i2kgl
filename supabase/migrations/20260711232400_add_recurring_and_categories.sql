-- Add recurring_id to transactions for grouping recurring series
ALTER TABLE public.transactions ADD COLUMN IF NOT EXISTS recurring_id UUID;

-- Add transactionCategories to settings
ALTER TABLE public.settings ADD COLUMN IF NOT EXISTS "transactionCategories" JSONB;

-- Seed default transaction categories if not present
UPDATE public.settings
SET "transactionCategories" = COALESCE(
  "transactionCategories",
  '["Custas Iniciais","Custas Finais","Depósito Recursal","Honorários Periciais","Honorários Contratuais","Honorários de Êxito","Honorários de Permuta","Honorários Sucumbenciais","Alvará / Condenação","Diligência","Acordo","Outros"]'::jsonb
)
WHERE "transactionCategories" IS NULL;

-- Ensure suppliers has status column (already exists but idempotent check)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'suppliers' AND column_name = 'status'
  ) THEN
    ALTER TABLE public.suppliers ADD COLUMN status TEXT DEFAULT 'Ativo';
  END IF;
END $$;

-- Create index for recurring_id lookups
CREATE INDEX IF NOT EXISTS idx_transactions_recurring_id ON public.transactions(recurring_id)
  WHERE recurring_id IS NOT NULL;
