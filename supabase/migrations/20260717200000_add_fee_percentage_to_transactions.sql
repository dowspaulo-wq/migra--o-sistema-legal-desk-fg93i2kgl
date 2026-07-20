ALTER TABLE public.transactions ADD COLUMN IF NOT EXISTS fee_percentage NUMERIC(5,2);

COMMENT ON COLUMN public.transactions.fee_percentage IS 'Percentage for success fee type transactions';
