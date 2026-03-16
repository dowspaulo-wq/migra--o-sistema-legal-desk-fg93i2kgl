DO $
DECLARE
    adv_jr_id uuid;
    admin_id uuid;
BEGIN
    -- Settings Task Types
    ALTER TABLE public.settings ADD COLUMN IF NOT EXISTS "taskTypes" JSONB DEFAULT '["Cartórios", "Petições", "Recorrer", "Redigir inicial", "interna e adm"]'::jsonb;
    UPDATE public.settings SET "taskTypes" = '["Cartórios", "Petições", "Recorrer", "Redigir inicial", "interna e adm"]'::jsonb WHERE "taskTypes" IS NULL;

    -- Cleanup Advogado Jr
    SELECT id INTO adv_jr_id FROM public.profiles WHERE name ILIKE '%Advogado Jr%' LIMIT 1;
    IF adv_jr_id IS NOT NULL THEN
        DELETE FROM auth.users WHERE id = adv_jr_id;
    END IF;

    -- Update Admin to Douglas Master Administrator
    SELECT id INTO admin_id FROM public.profiles WHERE name ILIKE '%Admin SBJur%' OR email ILIKE 'admin@%' LIMIT 1;
    IF admin_id IS NOT NULL THEN
        UPDATE public.profiles SET name = 'Douglas', role = 'Admin' WHERE id = admin_id;
        UPDATE auth.users SET raw_user_meta_data = jsonb_set(COALESCE(raw_user_meta_data, '{}'::jsonb), '{name}', '"Douglas"') WHERE id = admin_id;
    END IF;
END $;

CREATE OR REPLACE FUNCTION public.handle_new_case_task()
RETURNS trigger AS $
DECLARE
    next_month date;
    due_date text;
    internal_task_type text := 'interna e adm';
BEGIN
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

    RETURN NEW;
END;
$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_case_created ON public.cases;
CREATE TRIGGER on_case_created
    AFTER INSERT ON public.cases
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_new_case_task();

