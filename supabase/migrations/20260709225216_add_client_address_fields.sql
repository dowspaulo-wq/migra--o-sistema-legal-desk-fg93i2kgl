-- Add detailed address columns to clients table for ASAAS integration
ALTER TABLE public.clients ADD COLUMN IF NOT EXISTS cep TEXT;
ALTER TABLE public.clients ADD COLUMN IF NOT EXISTS street TEXT;
ALTER TABLE public.clients ADD COLUMN IF NOT EXISTS number TEXT;
ALTER TABLE public.clients ADD COLUMN IF NOT EXISTS complement TEXT;
ALTER TABLE public.clients ADD COLUMN IF NOT EXISTS neighborhood TEXT;
ALTER TABLE public.clients ADD COLUMN IF NOT EXISTS city TEXT;
