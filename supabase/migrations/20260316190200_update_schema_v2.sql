DO $$
DECLARE
    first_client_id uuid;
    first_case_id uuid;
BEGIN
    SELECT id INTO first_client_id FROM public.clients LIMIT 1;
    SELECT id INTO first_case_id FROM public.cases LIMIT 1;

    -- cases table updates
    ALTER TABLE public.cases ADD COLUMN IF NOT EXISTS "isSpecial" BOOLEAN NOT NULL DEFAULT false;
    ALTER TABLE public.cases ADD COLUMN IF NOT EXISTS "description" TEXT;
    ALTER TABLE public.cases ADD COLUMN IF NOT EXISTS "internalNotes" TEXT;
    ALTER TABLE public.cases ADD COLUMN IF NOT EXISTS "alerts" TEXT;

    -- appointments table updates
    ALTER TABLE public.appointments ADD COLUMN IF NOT EXISTS "priority" TEXT NOT NULL DEFAULT 'Média';
    ALTER TABLE public.appointments ADD COLUMN IF NOT EXISTS "time" TEXT NOT NULL DEFAULT '00:00';
    ALTER TABLE public.appointments ADD COLUMN IF NOT EXISTS "description" TEXT;
    
    UPDATE public.appointments SET "clientId" = first_client_id WHERE "clientId" IS NULL AND first_client_id IS NOT NULL;
    UPDATE public.appointments SET "processId" = first_case_id WHERE "processId" IS NULL AND first_case_id IS NOT NULL;
    
    IF first_client_id IS NOT NULL THEN
        ALTER TABLE public.appointments ALTER COLUMN "clientId" SET NOT NULL;
    END IF;
    IF first_case_id IS NOT NULL THEN
        ALTER TABLE public.appointments ALTER COLUMN "processId" SET NOT NULL;
    END IF;

    -- tasks table updates
    ALTER TABLE public.tasks ADD COLUMN IF NOT EXISTS "type" TEXT NOT NULL DEFAULT 'Outro';
    ALTER TABLE public.tasks ADD COLUMN IF NOT EXISTS "clientId" UUID REFERENCES public.clients(id) ON DELETE CASCADE;
    ALTER TABLE public.tasks ADD COLUMN IF NOT EXISTS "internalNotes" TEXT;

    UPDATE public.tasks SET "clientId" = first_client_id WHERE "clientId" IS NULL AND first_client_id IS NOT NULL;
    UPDATE public.tasks SET "relatedProcessId" = first_case_id WHERE "relatedProcessId" IS NULL AND first_case_id IS NOT NULL;

    IF first_client_id IS NOT NULL THEN
        ALTER TABLE public.tasks ALTER COLUMN "clientId" SET NOT NULL;
    END IF;
    IF first_case_id IS NOT NULL THEN
        ALTER TABLE public.tasks ALTER COLUMN "relatedProcessId" SET NOT NULL;
    END IF;

    -- settings table updates
    ALTER TABLE public.settings ADD COLUMN IF NOT EXISTS "caseStatuses" JSONB DEFAULT '["Em andamento", "Pendente", "Concluído", "Arquivado"]'::jsonb;
    ALTER TABLE public.settings ADD COLUMN IF NOT EXISTS "caseTypes" JSONB DEFAULT '["Cível", "Trabalhista", "Tributário", "Criminal", "Família"]'::jsonb;
    ALTER TABLE public.settings ADD COLUMN IF NOT EXISTS "appointmentTypes" JSONB DEFAULT '["Reunião", "Aud.conciliação", "Diligência", "Feriado", "Outro"]'::jsonb;
    ALTER TABLE public.settings ADD COLUMN IF NOT EXISTS "taskStatuses" JSONB DEFAULT '["em andamento", "pendente", "atualização", "Concluída", "aguarda protocolo", "cancelada"]'::jsonb;

END $$;
