DO $BODY$
BEGIN
    -- Add "revisão/protocolo" to taskTypes in settings if not exists
    UPDATE public.settings
    SET "taskTypes" = CASE
        WHEN "taskTypes" ? 'revisão/protocolo' THEN "taskTypes"
        WHEN "taskTypes" IS NULL THEN '["revisão/protocolo"]'::jsonb
        WHEN jsonb_typeof("taskTypes") = 'array' THEN "taskTypes" || '["revisão/protocolo"]'::jsonb
        ELSE '["revisão/protocolo"]'::jsonb
    END;
END $BODY$;

CREATE OR REPLACE FUNCTION public.handle_task_completion_automation()
RETURNS trigger AS $BODY$
DECLARE
    updater_role text;
    douglas_id uuid;
    client_name text;
    case_number text;
    task_title text;
BEGIN
    -- Check if status changed to 'concluído' (case insensitive)
    IF (NEW.status ILIKE 'concluído' OR NEW.status ILIKE 'concluido') 
       AND (OLD.status IS NULL OR (OLD.status NOT ILIKE 'concluído' AND OLD.status NOT ILIKE 'concluido')) THEN
        
        -- Check task type: 'RECORRER', 'REDIGIR INICIAL', or 'PETIÇÕES'
        IF NEW.type ILIKE 'recorrer' OR NEW.type ILIKE 'redigir inicial' OR NEW.type ILIKE 'petições' OR NEW.type ILIKE 'peticoes' THEN
            
            -- Get the role of the user performing the update (from auth.uid())
            SELECT role INTO updater_role FROM public.profiles WHERE id = auth.uid();
            
            IF updater_role ILIKE 'colaborador' THEN
                
                -- Get Douglas ID
                SELECT id INTO douglas_id FROM public.profiles WHERE name ILIKE 'Douglas' LIMIT 1;
                
                IF douglas_id IS NOT NULL THEN
                    
                    -- Get client name safely
                    IF NEW."clientId" IS NOT NULL THEN
                        SELECT name INTO client_name FROM public.clients WHERE id = NEW."clientId";
                    END IF;
                    
                    -- Get case number safely
                    IF NEW."relatedProcessId" IS NOT NULL THEN
                        SELECT number INTO case_number FROM public.cases WHERE id = NEW."relatedProcessId";
                    END IF;
                    
                    -- Format title: "[Client Name] [Case Number]"
                    task_title := trim(concat_ws(' ', client_name, case_number));
                    IF task_title = '' THEN
                        task_title := 'Revisão/Protocolo Automática';
                    END IF;
                    
                    -- Insert new task
                    INSERT INTO public.tasks (
                        title,
                        type,
                        status,
                        priority,
                        "dueDate",
                        "responsibleId",
                        "clientId",
                        "relatedProcessId"
                    ) VALUES (
                        task_title,
                        'revisão/protocolo',
                        'pendente',
                        'Média',
                        to_char(current_date, 'YYYY-MM-DD'),
                        douglas_id,
                        NEW."clientId",
                        NEW."relatedProcessId"
                    );
                    
                END IF;
            END IF;
        END IF;
    END IF;
    
    RETURN NEW;
END;
$BODY$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_task_completed_automation ON public.tasks;
CREATE TRIGGER on_task_completed_automation
    AFTER UPDATE ON public.tasks
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_task_completion_automation();
