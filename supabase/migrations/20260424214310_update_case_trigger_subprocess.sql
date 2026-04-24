CREATE OR REPLACE FUNCTION public.handle_new_case_task()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    next_month date;
    due_date text;
    internal_task_type text := 'interna e adm';
BEGIN
    -- Do not create the update task for subprocesses
    IF NEW."parentId" IS NULL THEN
        next_month := (date_trunc('month', NEW.created_at) + interval '1 month')::date;
        due_date := to_char(next_month + interval '24 days', 'YYYY-MM-DD');

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
            'Atualização de Processo - ' || NEW.number,
            NEW."clientId",
            NEW.id,
            'atualização',
            'Média',
            internal_task_type,
            due_date,
            NEW."responsibleId"
        );
    END IF;

    RETURN NEW;
END;
$function$
