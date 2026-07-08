-- Add asaas_id column to clients table for ASAAS customer sync
ALTER TABLE public.clients ADD COLUMN IF NOT EXISTS asaas_id TEXT;

-- Add asaas_id column to transactions table for ASAAS charge sync
ALTER TABLE public.transactions ADD COLUMN IF NOT EXISTS asaas_id TEXT;
