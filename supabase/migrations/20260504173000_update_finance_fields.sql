DO $$
BEGIN
  ALTER TABLE public.transactions ADD COLUMN IF NOT EXISTS "sendToFinance" BOOLEAN DEFAULT true;
  ALTER TABLE public.transactions ADD COLUMN IF NOT EXISTS "bankAccount" TEXT;
  
  ALTER TABLE public.cases ADD COLUMN IF NOT EXISTS "feeType" TEXT;
  ALTER TABLE public.cases ADD COLUMN IF NOT EXISTS "feeValue" NUMERIC DEFAULT 0;
  ALTER TABLE public.cases ADD COLUMN IF NOT EXISTS "feeInstallments" INTEGER DEFAULT 1;
END $$;
