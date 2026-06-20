DO $$
BEGIN
  -- Rename task status 'aguarda protocolo' to 'Revisão/protocolo'
  UPDATE public.tasks
  SET status = 'Revisão/protocolo'
  WHERE status ILIKE 'aguarda protocolo';

  -- Also rename type if it was used interchangeably
  UPDATE public.tasks
  SET type = 'Revisão/protocolo'
  WHERE type ILIKE 'aguarda protocolo';

  -- Update settings JSONB array if exists
  UPDATE public.settings
  SET "taskStatuses" = (
    SELECT jsonb_agg(
      CASE 
        WHEN value::text ILIKE '"aguarda protocolo"' THEN '"Revisão/protocolo"'::jsonb 
        ELSE value 
      END
    )
    FROM jsonb_array_elements("taskStatuses")
  )
  WHERE "taskStatuses" IS NOT NULL;

  UPDATE public.settings
  SET "taskTypes" = (
    SELECT jsonb_agg(
      CASE 
        WHEN value::text ILIKE '"aguarda protocolo"' THEN '"Revisão/protocolo"'::jsonb 
        ELSE value 
      END
    )
    FROM jsonb_array_elements("taskTypes")
  )
  WHERE "taskTypes" IS NOT NULL;

  -- Ensure 'Revisão/protocolo' exists in taskTypes
  UPDATE public.settings
  SET "taskTypes" = "taskTypes" || '["Revisão/protocolo"]'::jsonb
  WHERE "taskTypes" IS NOT NULL 
    AND NOT "taskTypes" @> '["Revisão/protocolo"]'::jsonb;
END $$;

-- Automation Trigger
CREATE OR REPLACE FUNCTION public.handle_task_completion_automation()
RETURNS trigger AS $$
DECLARE
    v_user_role text;
    v_douglas_id uuid;
    v_client_name text;
    v_process_number text;
    v_new_title text;
BEGIN
    -- Only trigger on status change to 'Concluída' or 'Concluído'
    IF NEW.status ILIKE 'concluíd%' AND OLD.status NOT ILIKE 'concluíd%' THEN
        
        -- Check if original task type is one of the target types
        IF NEW.type ILIKE 'recorrer' OR NEW.type ILIKE 'redigir inicial' OR NEW.type ILIKE 'petições' THEN
            
            -- Get the current user's role
            SELECT role INTO v_user_role FROM public.profiles WHERE id = auth.uid();
            
            -- If user is a 'User' (Colaborador)
            IF v_user_role = 'User' THEN
                
                -- Get Douglas's ID
                SELECT id INTO v_douglas_id FROM public.profiles WHERE email ILIKE 'dowspaulo@gmail.com' LIMIT 1;
                
                -- If Douglas doesn't have an email dowspaulo@gmail.com, try by name
                IF v_douglas_id IS NULL THEN
                    SELECT id INTO v_douglas_id FROM public.profiles WHERE name ILIKE '%douglas%' LIMIT 1;
                END IF;

                -- If Douglas exists
                IF v_douglas_id IS NOT NULL THEN
                    
                    -- Get Client Name
                    SELECT name INTO v_client_name FROM public.clients WHERE id = NEW."clientId";
                    
                    -- Get Process Number
                    SELECT number INTO v_process_number FROM public.cases WHERE id = NEW."relatedProcessId";
                    
                    -- Format Title
                    v_new_title := COALESCE(v_client_name, 'Sem Cliente') || ' - ' || COALESCE(v_process_number, 'Sem Processo');
                    
                    -- Insert new task
                    INSERT INTO public.tasks (
                        title,
                        description,
                        "dueDate",
                        status,
                        priority,
                        "responsibleId",
                        "relatedProcessId",
                        type,
                        "clientId",
                        "internalNotes"
                    ) VALUES (
                        v_new_title,
                        'Tarefa gerada automaticamente após a conclusão da tarefa: ' || NEW.title,
                        to_char(CURRENT_DATE, 'YYYY-MM-DD'),
                        'Revisão/protocolo',
                        'Média',
                        v_douglas_id,
                        NEW."relatedProcessId",
                        'Revisão/protocolo',
                        NEW."clientId",
                        ''
                    );
                END IF;
            END IF;
        END IF;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_task_completed ON public.tasks;
CREATE TRIGGER on_task_completed
    AFTER UPDATE ON public.tasks
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_task_completion_automation();
