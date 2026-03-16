DO $$
BEGIN
    -- Add captacao to clients
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='clients' AND column_name='captacao') THEN
        ALTER TABLE public.clients ADD COLUMN captacao TEXT;
    END IF;

    -- Add captacaoOptions to settings
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='settings' AND column_name='captacaoOptions') THEN
        ALTER TABLE public.settings ADD COLUMN "captacaoOptions" JSONB DEFAULT '["Douglas", "Eduardo", "Luisito", "MB", "Zeno"]'::jsonb;
    END IF;
END $$;

-- Ensure default values for existing rows in settings
UPDATE public.settings
SET "captacaoOptions" = '["Douglas", "Eduardo", "Luisito", "MB", "Zeno"]'::jsonb
WHERE "captacaoOptions" IS NULL;
