DO $$
DECLARE
    case_record RECORD;
    next_month DATE;
    due_date TEXT;
    internal_task_type TEXT := 'interna e adm';
    task_exists BOOLEAN;
BEGIN
    FOR case_record IN SELECT * FROM public.cases
    LOOP
        -- Check if an 'atualização' task already exists for this case
        SELECT EXISTS (
            SELECT 1 FROM public.tasks 
            WHERE "relatedProcessId" = case_record.id 
            AND type = internal_task_type 
            AND title LIKE 'Atualização de Processo%'
        ) INTO task_exists;
        
        IF NOT task_exists THEN
            next_month := (date_trunc('month', case_record.created_at) + interval '1 month')::date;
            due_date := to_char(next_month + interval '24 days', 'YYYY-MM-DD');
            
            INSERT INTO public.tasks (
                title,
                "clientId",
                "relatedProcessId",
                status,
                priority,
                type,
                "dueDate",
                "responsibleId",
                created_at
            ) VALUES (
                'Atualização de Processo - ' || case_record.number,
                case_record."clientId",
                case_record.id,
                'atualização',
                'Média',
                internal_task_type,
                due_date,
                case_record."responsibleId",
                now()
            );
        END IF;
    END LOOP;
END $$;
