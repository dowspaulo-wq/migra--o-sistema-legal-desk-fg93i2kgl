-- Add created_by and completed_by to tasks table referencing profiles(id)
ALTER TABLE public.tasks ADD COLUMN IF NOT EXISTS created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL;
ALTER TABLE public.tasks ADD COLUMN IF NOT EXISTS completed_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_tasks_created_by ON public.tasks(created_by);
CREATE INDEX IF NOT EXISTS idx_tasks_completed_by ON public.tasks(completed_by);

-- Update handle_new_case_task to record created_by from the creating user or case's responsibleId
CREATE OR REPLACE FUNCTION public.handle_new_case_task()
RETURNS trigger AS $$
DECLARE
    due_date text;
    douglas_id uuid;
    creator_id uuid;
BEGIN
    -- Calculate the 25th of the month following creation date
    due_date := to_char(
        (date_trunc('month', NEW.created_at) + interval '1 month')::date + interval '24 days',
        'YYYY-MM-DD'
    );

    -- Look up Douglas's profile id
    SELECT id INTO douglas_id FROM public.profiles WHERE name ILIKE 'Douglas' LIMIT 1;

    -- If Douglas not found, fall back to the case's responsibleId
    IF douglas_id IS NULL THEN
        douglas_id := NEW."responsibleId";
    END IF;

    -- Try to get the active user or fall back to case responsibleId or douglas_id
    creator_id := COALESCE(auth.uid(), NEW."responsibleId", douglas_id);

    -- Only create tasks for top-level cases (not subprocesses)
    IF NEW."parentId" IS NULL THEN
        INSERT INTO public.tasks (
            title,
            "clientId",
            "relatedProcessId",
            status,
            priority,
            type,
            "dueDate",
            "responsibleId",
            created_by
        ) VALUES (
            'Acompanhamento processual',
            NEW."clientId",
            NEW.id,
            'atualização',
            'Baixa',
            'interna e adm',
            due_date,
            douglas_id,
            creator_id
        );

        INSERT INTO public.tasks (
            title,
            "clientId",
            "relatedProcessId",
            status,
            priority,
            type,
            "dueDate",
            "responsibleId",
            created_by
        ) VALUES (
            'Redigir Inicial ou Defesa',
            NEW."clientId",
            NEW.id,
            'pendente',
            'Baixa',
            'Redigir inicial',
            due_date,
            douglas_id,
            creator_id
        );
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
