-- Migration: Add noFees column to cases
-- Idempotent: uses ADD COLUMN IF NOT EXISTS

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' 
          AND table_name = 'cases' 
          AND column_name = 'noFees'
    ) THEN
        ALTER TABLE public.cases ADD COLUMN "noFees" BOOLEAN NOT NULL DEFAULT false;
    END IF;
END $$;
