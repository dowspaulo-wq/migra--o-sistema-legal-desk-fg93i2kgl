-- 1. Drop old redundant triggers that caused duplicate tasks
DROP TRIGGER IF EXISTS on_task_completed_automation ON public.tasks;
DROP TRIGGER IF EXISTS on_task_completed ON public.tasks;

-- 2. Drop the redundant old function
DROP FUNCTION IF EXISTS public.handle_task_completion_automation();

-- 3. Update the v2 function to include idempotency check
CREATE OR REPLACE FUNCTION public.handle_task_completion_automation_v2()
RETURNS trigger AS $$
DECLARE
    v_user_role text;
    v_douglas_id uuid;
    v_client_name text;
    v_process_number text;
    v_new_title text;
    v_task_exists boolean;
BEGIN
    -- Only trigger on status change to 'Concluída' or 'Concluído'
    IF NEW.status ILIKE 'concluíd%' AND OLD.status NOT ILIKE 'concluíd%' THEN
        
        -- Check if original task type is one of the target types
        IF NEW.type ILIKE 'recorrer' OR NEW.type ILIKE 'redigir inicial' OR NEW.type ILIKE 'petições' THEN
            
            -- Get the current user's role
            SELECT role INTO v_user_role FROM public.profiles WHERE id = auth.uid();
            
            -- If user is a 'User' or 'Colaborador'
            IF v_user_role ILIKE 'User' OR v_user_role ILIKE 'Colaborador' THEN
                
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
                    
                    -- Idempotency check: prevent duplicate tasks for the same event
                    SELECT EXISTS (
                        SELECT 1 FROM public.tasks 
                        WHERE title = v_new_title
                        AND type = 'Revisão/protocolo'
                        AND "relatedProcessId" IS NOT DISTINCT FROM NEW."relatedProcessId"
                        AND "clientId" IS NOT DISTINCT FROM NEW."clientId"
                        AND description = 'Tarefa gerada automaticamente após a conclusão da tarefa: ' || NEW.title
                        AND created_at >= CURRENT_DATE
                    ) INTO v_task_exists;

                    IF NOT v_task_exists THEN
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
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
