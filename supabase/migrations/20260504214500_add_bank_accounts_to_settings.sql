DO $$
BEGIN
  -- Add bankAccounts to settings
  ALTER TABLE public.settings ADD COLUMN IF NOT EXISTS "bankAccounts" jsonb DEFAULT '["ASAAS", "SICOOB"]'::jsonb;

  -- Fix the existing transactions with ASSAS -> ASAAS
  UPDATE public.transactions SET "bankAccount" = 'ASAAS' WHERE "bankAccount" = 'ASSAS';
END $$;
