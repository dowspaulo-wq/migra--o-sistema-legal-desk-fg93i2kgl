DO $block$
DECLARE
    eduardo_id uuid;
    mestre_id uuid;
BEGIN
    -- Obter os IDs dos usuários
    SELECT id INTO eduardo_id FROM public.profiles WHERE name ILIKE '%Eduardo%' LIMIT 1;
    SELECT id INTO mestre_id FROM public.profiles WHERE name ILIKE '%Mestre%' LIMIT 1;

    IF eduardo_id IS NOT NULL AND mestre_id IS NOT NULL THEN
        -- Transferir todas as tarefas
        UPDATE public.tasks SET "responsibleId" = mestre_id WHERE "responsibleId" = eduardo_id;
        
        -- Transferir todos os agendamentos
        UPDATE public.appointments SET "responsibleId" = mestre_id WHERE "responsibleId" = eduardo_id;
        
        -- Transferir todos os processos
        UPDATE public.cases SET "responsibleId" = mestre_id WHERE "responsibleId" = eduardo_id;
        
        -- Transferir todos os clientes
        UPDATE public.clients SET "responsibleId" = mestre_id WHERE "responsibleId" = eduardo_id;

        -- Inativar o usuário Eduardo alterando sua role
        UPDATE public.profiles SET role = 'Inativo' WHERE id = eduardo_id;
    END IF;
END $block$;
