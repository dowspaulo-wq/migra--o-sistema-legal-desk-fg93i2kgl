DO $$
BEGIN
  ALTER TABLE public.settings ADD COLUMN IF NOT EXISTS "clientPositions" jsonb;
END $$;

UPDATE public.settings
SET "clientPositions" = COALESCE(
  "clientPositions",
  '["AUTOR","RÉU","EXEQUENTE","EXECUTADO","EMBARGANTE","EMBARGADO","INVENTARIANTE","RECLAMADO","RECLAMANTE","ACUSADO","VÍTIMA","TERCEIRO"]'::jsonb
)
WHERE "clientPositions" IS NULL;
