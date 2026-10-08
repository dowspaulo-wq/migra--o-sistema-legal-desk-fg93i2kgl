-- Restaura e ajusta a criação automática de tarefas no cadastro de clientes (fluxo de criação em /clientes).
-- Regras especificadas:
-- 1) Tarefa "Acompanhamento processual mensal":
--    - Título: 'Acompanhamento processual mensal'
--    - Responsável: usuário chamado 'Mestre' (public.profiles.name ILIKE 'Mestre', com fallback seguro)
--    - Vencimento: dia 25 do MÊS SUBSEQUENTE ao cadastro (ex.: 10/10/2026 -> 25/11/2026)
--    - clientId: ID do cliente cadastrado
--    - priority: 'Baixa'
--    - type: 'interna e adm'
--    - status: 'atualização' (ou 'Pendente')
-- 2) Tarefa "Redigir Inicial ou Defesa":
--    - Título: 'Redigir Inicial ou Defesa'
--    - Responsável: o PRÓPRIO usuário que estiver cadastrando o cliente (auth.uid(), com fallback para NEW."responsibleId" ou Mestre)
--    - Vencimento: o PRÓXIMO DIA ÚTIL subsequente à data do registro (pula sábado e domingo; se sexta -> segunda)
--    - clientId: ID do cliente cadastrado
--    - priority: 'Baixa'
--    - type: 'Redigir inicial'
--    - status: 'pendente'
--    - created_by: o usuário logado que executou o cadastro

CREATE OR REPLACE FUNCTION public.calculate_next_business_day(base_date date)
RETURNS date AS $$
DECLARE
    candidate date;
    dow int;
BEGIN
    candidate := base_date + interval '1 day';
    dow := EXTRACT(DOW FROM candidate); -- 0 = Domingo, 6 = Sábado
    IF dow = 6 THEN -- Sábado -> pula para Segunda (+2 dias)
        candidate := candidate + interval '2 days';
    ELSIF dow = 0 THEN -- Domingo -> pula para Segunda (+1 dia)
        candidate := candidate + interval '1 day';
    END IF;
    RETURN candidate;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

CREATE OR REPLACE FUNCTION public.handle_new_client_tasks()
RETURNS trigger AS $$
DECLARE
    mestre_id uuid;
    active_user_id uuid;
    reg_date date;
    next_business_day date;
    subsequent_month_25th text;
BEGIN
    -- Determina a data base no timezone local (America/Sao_Paulo) a partir do created_at do cliente
    reg_date := (NEW.created_at AT TIME ZONE 'America/Sao_Paulo')::date;
    IF reg_date IS NULL THEN
        reg_date := CURRENT_DATE;
    END IF;

    -- Vencimento 1: dia 25 do mês subsequente ao cadastro
    subsequent_month_25th := to_char(
        (date_trunc('month', reg_date) + interval '1 month')::date + interval '24 days',
        'YYYY-MM-DD'
    );

    -- Vencimento 2: próximo dia útil subsequente à data de registro
    next_business_day := public.calculate_next_business_day(reg_date);

    -- Localizar o usuário 'Mestre' na tabela public.profiles
    SELECT id INTO mestre_id
    FROM public.profiles
    WHERE name ILIKE 'Mestre'
    ORDER BY is_active DESC NULLS LAST, created_at ASC
    LIMIT 1;

    -- Se não encontrar 'Mestre', busca por email admin@sbjur.com ou role Admin
    IF mestre_id IS NULL THEN
        SELECT id INTO mestre_id
        FROM public.profiles
        WHERE email ILIKE 'admin@sbjur.com'
        LIMIT 1;
    END IF;

    IF mestre_id IS NULL THEN
        SELECT id INTO mestre_id
        FROM public.profiles
        WHERE role ILIKE 'Admin'
        LIMIT 1;
    END IF;

    -- Identifica o usuário logado cadastrador
    active_user_id := auth.uid();
    IF active_user_id IS NULL THEN
        active_user_id := NEW."responsibleId";
    END IF;
    IF active_user_id IS NULL THEN
        active_user_id := mestre_id;
    END IF;

    -- 1) Tarefa "Acompanhamento processual mensal"
    -- Responsável: Mestre (fallback para NEW."responsibleId" se mestre_id for nulo)
    INSERT INTO public.tasks (
        title,
        "clientId",
        "relatedProcessId",
        status,
        priority,
        type,
        "dueDate",
        "responsibleId",
        created_by
    ) VALUES (
        'Acompanhamento processual mensal',
        NEW.id,
        NULL,
        'atualização',
        'Baixa',
        'interna e adm',
        subsequent_month_25th,
        COALESCE(mestre_id, NEW."responsibleId"),
        active_user_id
    );

    -- 2) Tarefa "Redigir Inicial ou Defesa"
    -- Responsável: o próprio usuário que estiver cadastrando o cliente (active_user_id)
    INSERT INTO public.tasks (
        title,
        "clientId",
        "relatedProcessId",
        status,
        priority,
        type,
        "dueDate",
        "responsibleId",
        created_by
    ) VALUES (
        'Redigir Inicial ou Defesa',
        NEW.id,
        NULL,
        'pendente',
        'Baixa',
        'Redigir inicial',
        to_char(next_business_day, 'YYYY-MM-DD'),
        active_user_id,
        active_user_id
    );

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_client_created ON public.clients;
CREATE TRIGGER on_client_created
    AFTER INSERT ON public.clients
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_new_client_tasks();
