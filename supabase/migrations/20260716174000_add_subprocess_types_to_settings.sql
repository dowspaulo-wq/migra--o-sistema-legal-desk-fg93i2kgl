DO $$
BEGIN
  ALTER TABLE public.settings ADD COLUMN IF NOT EXISTS "subprocessTypes" jsonb;
END $$;

UPDATE public.settings
SET "subprocessTypes" = COALESCE(
  "subprocessTypes",
  '["Recurso", "Precatória", "Incidente", "Outros"]'::jsonb
)
WHERE "subprocessTypes" IS NULL;

ALTER TABLE public.cases DROP CONSTRAINT IF EXISTS cases_subprocess_type_check;
