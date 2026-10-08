-- Migração: Correção definitiva da automação de tarefas no cadastro de clientes e processos
-- Regras solicitadas:
-- 1) No cadastro de cliente (trigger on_client_created -> handle_new_client_tasks):
--    - Tarefa "Acompanhamento processual mensal":
--        * Responsável: Usuário "Mestre" (public.profiles.name ILIKE 'Mestre', depois admin@sbjur.com, depois role Admin)
--        * Vencimento: dia 25 do mês subsequente ao cadastro
--        * Prioridade: 'Baixa'
--        * Status: 'atualização'
--        * Tipo: 'interna e adm'
--    - Tarefa "Redigir Inicial ou Defesa":
--        * Responsável: o usuário que cadastrou o cliente (auth.uid() com fallback para NEW."responsibleId", depois Mestre)
--        * Vencimento: próximo dia útil subsequente ao registro (pula sábado e domingo)
--        * Prioridade: 'Baixa'
--        * Status: 'pendente'
--        * Tipo: 'Redigir inicial'
--    - Isolamento de erros: Cada inserção é executada em bloco anônimo protegido (EXCEPTION WHEN OTHERS) para que
--      um erro na 2ª tarefa não impeça a 1ª (nem vice-versa), e nunca aborte o INSERT do cliente.
-- 2) Ajustar também handle_new_case_task (trigger on_case_created em public.cases):
--    - Caso um processo seja cadastrado diretamente, 'Acompanhamento processual' deve apontar para Mestre (não Douglas hardcoded)
--    - Ambas as tarefas automáticas geradas no processo devem ter prioridade 'Baixa'
-- 3) Atualizar retroativamente para 'Baixa' as tarefas automáticas existentes que ainda constam como 'Média'.

-- 1. Função auxiliar para cálculo do próximo dia útil
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

-- 2. Função do trigger ao cadastrar cliente (public.clients)
CREATE OR REPLACE FUNCTION public.handle_new_client_tasks()
RETURNS trigger AS $$
DECLARE
    mestre_id uuid;
    active_user_id uuid;
    reg_date date;
    next_business_day date;
    subsequent_month_25th text;
BEGIN
    -- Determina a data base no timezone local (America/Sao_Paulo)
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

    -- Localizar usuário 'Mestre' (public.profiles.name ILIKE 'Mestre')
    SELECT id INTO mestre_id
    FROM public.profiles
    WHERE name ILIKE 'Mestre'
    ORDER BY is_active DESC NULLS LAST, created_at ASC
    LIMIT 1;

    -- Fallback 1: email admin@sbjur.com
    IF mestre_id IS NULL THEN
        SELECT id INTO mestre_id
        FROM public.profiles
        WHERE email ILIKE 'admin@sbjur.com'
        LIMIT 1;
    END IF;

    -- Fallback 2: usuário Admin ativo
    IF mestre_id IS NULL THEN
        SELECT id INTO mestre_id
        FROM public.profiles
        WHERE role ILIKE 'Admin'
        ORDER BY is_active DESC NULLS LAST, created_at ASC
        LIMIT 1;
    END IF;

    -- Fallback final: responsável informado no cliente
    IF mestre_id IS NULL THEN
        mestre_id := NEW."responsibleId";
    END IF;

    -- Identifica o usuário logado cadastrador
    active_user_id := auth.uid();
    IF active_user_id IS NULL THEN
        active_user_id := NEW."responsibleId";
    END IF;
    IF active_user_id IS NULL THEN
        active_user_id := mestre_id;
    END IF;

    -- Tarefa 1: "Acompanhamento processual mensal" (Responsável: Mestre)
    BEGIN
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
            mestre_id,
            active_user_id
        );
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'Falha ao criar tarefa automática de acompanhamento processual para o cliente %: %', NEW.id, SQLERRM;
    END;

    -- Tarefa 2: "Redigir Inicial ou Defesa" (Responsável: Usuário criador / active_user_id)
    BEGIN
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
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'Falha ao criar tarefa automática de redação para o cliente %: %', NEW.id, SQLERRM;
    END;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Garante o trigger em public.clients
DROP TRIGGER IF EXISTS on_client_created ON public.clients;
CREATE TRIGGER on_client_created
    AFTER INSERT ON public.clients
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_new_client_tasks();

-- 3. Atualizar também handle_new_case_task para coerência entre cadastro de cliente e cadastro de processo
CREATE OR REPLACE FUNCTION public.handle_new_case_task()
RETURNS trigger AS $$
DECLARE
    due_date text;
    mestre_id uuid;
    creator_id uuid;
BEGIN
    -- Vencimento: dia 25 do mês subsequente
    due_date := to_char(
        (date_trunc('month', NEW.created_at) + interval '1 month')::date + interval '24 days',
        'YYYY-MM-DD'
    );

    -- Localiza usuário Mestre
    SELECT id INTO mestre_id FROM public.profiles WHERE name ILIKE 'Mestre' ORDER BY is_active DESC NULLS LAST LIMIT 1;
    IF mestre_id IS NULL THEN
        SELECT id INTO mestre_id FROM public.profiles WHERE email ILIKE 'admin@sbjur.com' LIMIT 1;
    END IF;
    IF mestre_id IS NULL THEN
        SELECT id INTO mestre_id FROM public.profiles WHERE role ILIKE 'Admin' ORDER BY is_active DESC NULLS LAST LIMIT 1;
    END IF;
    IF mestre_id IS NULL THEN
        mestre_id := NEW."responsibleId";
    END IF;

    -- Identifica o criador
    creator_id := COALESCE(auth.uid(), NEW."responsibleId", mestre_id);

    -- Apenas para processos principais (não subprocessos)
    IF NEW."parentId" IS NULL THEN
        -- Tarefa 1: Acompanhamento processual (atribuída ao Mestre)
        BEGIN
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
                'Acompanhamento processual',
                NEW."clientId",
                NEW.id,
                'atualização',
                'Baixa',
                'interna e adm',
                due_date,
                mestre_id,
                creator_id
            );
        EXCEPTION WHEN OTHERS THEN
            RAISE WARNING 'Falha ao criar tarefa automática de acompanhamento do processo %: %', NEW.id, SQLERRM;
        END;

        -- Tarefa 2: Redigir Inicial ou Defesa (atribuída ao criador do processo)
        BEGIN
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
                NEW."clientId",
                NEW.id,
                'pendente',
                'Baixa',
                'Redigir inicial',
                due_date,
                creator_id,
                creator_id
            );
        EXCEPTION WHEN OTHERS THEN
            RAISE WARNING 'Falha ao criar tarefa automática de redação do processo %: %', NEW.id, SQLERRM;
        END;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Garante o trigger em public.cases
DROP TRIGGER IF EXISTS on_case_created ON public.cases;
CREATE TRIGGER on_case_created
    AFTER INSERT ON public.cases
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_new_case_task();

-- 4. Garantir prioridade Baixa em todas as tarefas automáticas existentes
UPDATE public.tasks
SET priority = 'Baixa'
WHERE title IN ('Acompanhamento processual', 'Acompanhamento processual mensal', 'Redigir Inicial ou Defesa')
  AND priority <> 'Baixa';
