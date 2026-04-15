DO $$
DECLARE
    eduardo_id uuid;
    mestre_id uuid;
BEGIN
    SELECT id INTO eduardo_id FROM public.profiles WHERE name ILIKE '%Eduardo%' LIMIT 1;
    SELECT id INTO mestre_id FROM public.profiles WHERE name ILIKE '%Mestre%' LIMIT 1;

    IF eduardo_id IS NOT NULL AND mestre_id IS NOT NULL THEN
        UPDATE public.tasks SET "responsibleId" = mestre_id WHERE "responsibleId" = eduardo_id;
        UPDATE public.appointments SET "responsibleId" = mestre_id WHERE "responsibleId" = eduardo_id;
        UPDATE public.cases SET "responsibleId" = mestre_id WHERE "responsibleId" = eduardo_id;
        UPDATE public.clients SET "responsibleId" = mestre_id WHERE "responsibleId" = eduardo_id;

        BEGIN
            UPDATE public.profiles SET active = false WHERE id = eduardo_id;
        EXCEPTION WHEN undefined_column THEN NULL; END;
        
        BEGIN
            UPDATE public.profiles SET status = 'inativo' WHERE id = eduardo_id;
        EXCEPTION WHEN undefined_column THEN NULL; END;
    END IF;
END $$;
