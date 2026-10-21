-- Migration: Adicionar campos de timestamp de sincronização/importação em settings
-- e unificar status 'Realizado' e 'Paga' -> 'Pago' no DPSjur
-- Data: 2026-10-21

-- 1. Colunas para registrar última sincronização Asaas e última importação Sicoob/Cartões
ALTER TABLE public.settings
  ADD COLUMN IF NOT EXISTS "lastAsaasSyncAt" TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS "lastSicoobImportAt" TIMESTAMPTZ;

-- 2. Consertar os lançamentos com status 'Realizado' -> 'Pago'
UPDATE public.transactions
SET status = 'Pago'
WHERE status ILIKE 'realizado' OR status = 'Realizado';

-- 3. Garantir que status gravados como 'Paga' ou 'pago' sejam normalizados para 'Pago'
UPDATE public.transactions
SET status = 'Pago'
WHERE status ILIKE 'paga';

-- 4. Notificar PostgREST para recarregar o schema
DO $$
BEGIN
  PERFORM pg_notify('pgrst', 'reload schema');
EXCEPTION WHEN OTHERS THEN
  -- Ignora se pg_notify não estiver disponível
  NULL;
END $$;
