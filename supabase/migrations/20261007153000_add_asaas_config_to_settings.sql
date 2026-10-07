-- Migration: Add asaasApiKey and asaasApiUrl to settings table
-- Date: 2026-10-07

ALTER TABLE public.settings
  ADD COLUMN IF NOT EXISTS "asaasApiKey" TEXT,
  ADD COLUMN IF NOT EXISTS "asaasApiUrl" TEXT DEFAULT 'https://api.asaas.com/v3';
