-- Migration: Update Douglas's email from dowspaulo@gmail.com to advdouglaspsantos@gmail.com
-- Preserving UUID, password hash, metadata, active status and roles.

DO $$
DECLARE
  v_target_user_id uuid;
  v_existing_new_user uuid;
BEGIN
  -- 1. Double-check if destination email already belongs to a different user
  SELECT id INTO v_existing_new_user FROM auth.users WHERE email = 'advdouglaspsantos@gmail.com';
  
  -- 2. Find Douglas user ID by current email
  SELECT id INTO v_target_user_id FROM auth.users WHERE email = 'dowspaulo@gmail.com';

  -- If advdouglaspsantos already exists for this exact same user, nothing to do in auth.users
  IF v_target_user_id IS NOT NULL THEN
    IF v_existing_new_user IS NOT NULL AND v_existing_new_user <> v_target_user_id THEN
      RAISE EXCEPTION 'Destination email advdouglaspsantos@gmail.com already exists with id %', v_existing_new_user;
    END IF;

    -- Update auth.users (note: confirmed_at is generated in PostgreSQL auth.users, do not update it directly)
    UPDATE auth.users
    SET
      email = 'advdouglaspsantos@gmail.com',
      email_confirmed_at = COALESCE(email_confirmed_at, NOW()),
      email_change = '',
      email_change_token_new = '',
      email_change_token_current = '',
      confirmation_token = COALESCE(confirmation_token, ''),
      recovery_token = COALESCE(recovery_token, ''),
      phone_change = COALESCE(phone_change, ''),
      phone_change_token = COALESCE(phone_change_token, ''),
      reauthentication_token = COALESCE(reauthentication_token, ''),
      updated_at = NOW()
    WHERE id = v_target_user_id;

    -- Update public.profiles
    UPDATE public.profiles
    SET
      email = 'advdouglaspsantos@gmail.com'
    WHERE id = v_target_user_id;

  ELSE
    -- If user was already updated or not found by old email, ensure profile matches if id exists
    UPDATE public.profiles
    SET email = 'advdouglaspsantos@gmail.com'
    WHERE email = 'dowspaulo@gmail.com';
  END IF;
END $$;

-- Update trigger function handle_task_completion_automation_v2 so it references the new email
CREATE OR REPLACE FUNCTION public.handle_task_completion_automation_v2()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
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
                
                -- Get Douglas's ID (try new email, then legacy email, then by name)
                SELECT id INTO v_douglas_id FROM public.profiles 
                WHERE email ILIKE 'advdouglaspsantos@gmail.com' OR email ILIKE 'dowspaulo@gmail.com' 
                LIMIT 1;
                
                -- If Douglas doesn't have an email match, try by name
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
$function$;

-- Update RLS policies referencing dowspaulo@gmail.com
DROP POLICY IF EXISTS "admin_select_backup_logs" ON public.backup_logs;
CREATE POLICY "admin_select_backup_logs" ON public.backup_logs
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM profiles 
      WHERE profiles.id = auth.uid() 
      AND (profiles.role = 'Admin' OR profiles.email IN ('advdouglaspsantos@gmail.com', 'dowspaulo@gmail.com'))
    )
  );

DROP POLICY IF EXISTS "admin_read_backups" ON storage.objects;
CREATE POLICY "admin_read_backups" ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'backups' AND
    EXISTS (
      SELECT 1 FROM profiles 
      WHERE profiles.id = auth.uid() 
      AND (profiles.role = 'Admin' OR profiles.email IN ('advdouglaspsantos@gmail.com', 'dowspaulo@gmail.com'))
    )
  );
