CREATE OR REPLACE FUNCTION public.handle_new_case_task()
RETURNS trigger AS $$
DECLARE
    due_date text;
    douglas_id uuid;
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
            "responsibleId"
        ) VALUES (
            'Acompanhamento processual',
            NEW."clientId",
            NEW.id,
            'atualização',
            'Baixa',
            'interna e adm',
            due_date,
            douglas_id
        );

        INSERT INTO public.tasks (
            title,
            "clientId",
            "relatedProcessId",
            status,
            priority,
            type,
            "dueDate",
            "responsibleId"
        ) VALUES (
            'Redigir Inicial ou Defesa',
            NEW."clientId",
            NEW.id,
            'pendente',
            'Baixa',
            'Redigir inicial',
            due_date,
            douglas_id
        );
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_case_created ON public.cases;
CREATE TRIGGER on_case_created
    AFTER INSERT ON public.cases
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_new_case_task();

-- Retroactively update any existing automatic tasks created with Média priority
UPDATE public.tasks
SET priority = 'Baixa'
WHERE title IN ('Acompanhamento processual', 'Redigir Inicial ou Defesa')
  AND priority = 'Média';
