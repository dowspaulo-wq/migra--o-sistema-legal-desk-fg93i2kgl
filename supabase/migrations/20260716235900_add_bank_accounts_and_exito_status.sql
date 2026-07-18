DO $$
BEGIN
  -- Add CAIXA and PESSOAL to existing bankAccounts in settings
  UPDATE public.settings
  SET "bankAccounts" = (
    SELECT jsonb_agg(DISTINCT val)
    FROM jsonb_array_elements(
      COALESCE("bankAccounts", '[]'::jsonb) || '["CAIXA", "PESSOAL"]'::jsonb
    ) AS val
  );

  -- For settings rows where bankAccounts is still NULL, set default
  UPDATE public.settings
  SET "bankAccounts" = '["ASAAS", "SICOOB", "CAIXA", "PESSOAL"]'::jsonb
  WHERE "bankAccounts" IS NULL;

  -- Update column default for future inserts
  ALTER TABLE public.settings ALTER COLUMN "bankAccounts" SET DEFAULT '["ASAAS", "SICOOB", "CAIXA", "PESSOAL"]'::jsonb;
END $$;
