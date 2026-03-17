ALTER TABLE public.appointments ADD COLUMN IF NOT EXISTS status text NOT NULL DEFAULT 'Pendente';
ALTER TABLE public.cases ADD COLUMN IF NOT EXISTS "parentId" uuid REFERENCES public.cases(id) ON DELETE CASCADE;
