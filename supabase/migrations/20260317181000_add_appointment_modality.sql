DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 
    FROM information_schema.columns 
    WHERE table_name='appointments' AND column_name='modality'
  ) THEN
    ALTER TABLE public.appointments ADD COLUMN modality TEXT;
  END IF;
END
$$;

-- Ensure AIJ is present in appointment types
UPDATE public.settings 
SET "appointmentTypes" = (
  SELECT jsonb_agg(DISTINCT elem)
  FROM jsonb_array_elements(
    CASE 
      WHEN "appointmentTypes" IS NULL THEN '["Reunião", "Aud.conciliação", "Diligência", "Feriado", "Outro", "AIJ"]'::jsonb
      ELSE "appointmentTypes" || '["AIJ"]'::jsonb
    END
  ) AS elem
);
