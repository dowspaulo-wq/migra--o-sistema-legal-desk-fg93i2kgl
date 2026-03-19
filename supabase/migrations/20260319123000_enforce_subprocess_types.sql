-- Update existing subprocesses to have a valid type if they don't already
UPDATE public.cases
SET type = 'Outros'
WHERE "parentId" IS NOT NULL
  AND type NOT IN ('Recurso', 'Precatória', 'Incidente', 'Outros');

-- Add the constraint to enforce subprocess types
ALTER TABLE public.cases
ADD CONSTRAINT cases_subprocess_type_check
CHECK ("parentId" IS NULL OR type IN ('Recurso', 'Precatória', 'Incidente', 'Outros'));
