-- Add percentage column to transactions table if it does not exist
ALTER TABLE public.transactions ADD COLUMN IF NOT EXISTS percentage NUMERIC;

-- Make date column nullable to allow recording success fees without a known date
ALTER TABLE public.transactions ALTER COLUMN date DROP NOT NULL;
