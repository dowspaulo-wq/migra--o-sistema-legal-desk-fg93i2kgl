DO $$
DECLARE
    douglas_id uuid;
    mestre_id uuid;
BEGIN
    -- Identify the UUIDs for the users with name = 'DOUGLAS' and name = 'MESTRE'
    SELECT id INTO douglas_id FROM public.profiles WHERE name = 'DOUGLAS' LIMIT 1;
    SELECT id INTO mestre_id FROM public.profiles WHERE name = 'MESTRE' LIMIT 1;

    -- Ensure both users exist to maintain constraint compliance
    IF douglas_id IS NOT NULL AND mestre_id IS NOT NULL THEN
        
        -- Client Transfer
        UPDATE public.clients
        SET "responsibleId" = mestre_id
        WHERE "responsibleId" = douglas_id;

        -- Case Transfer
        UPDATE public.cases
        SET "responsibleId" = mestre_id
        WHERE "responsibleId" = douglas_id;

        -- Task Transfer
        UPDATE public.tasks
        SET "responsibleId" = mestre_id
        WHERE "responsibleId" = douglas_id;

        -- Appointment Transfer
        UPDATE public.appointments
        SET "responsibleId" = mestre_id
        WHERE "responsibleId" = douglas_id;

        -- User Deletion (Cascades to public.profiles)
        DELETE FROM auth.users 
        WHERE id = douglas_id;
        
    ELSE
        RAISE NOTICE 'Required users (DOUGLAS or MESTRE) not found. Migration skipped.';
    END IF;
END $$;
