-- Migration: Adiciona coluna documents (jsonb) na tabela public.cases
-- Idempotente com ADD COLUMN IF NOT EXISTS e default '[]'::jsonb

DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.tables 
        WHERE table_schema = 'public' AND table_name = 'cases'
    ) THEN
        ALTER TABLE public.cases 
        ADD COLUMN IF NOT EXISTS documents JSONB NOT NULL DEFAULT '[]'::jsonb;
    END IF;
END $$;

-- Recarrega o cache do PostgREST
NOTIFY pgrst, 'reload schema';
