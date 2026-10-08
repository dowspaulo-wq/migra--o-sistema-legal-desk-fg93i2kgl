-- Migração: Correção do vencimento da tarefa "Redigir Inicial ou Defesa" na criação de processos
-- Solicitação do usuário: "a tarefa de redação foi criada, porém, para o dia 25 do mês subsequente,
-- modifique para que ela seja para o imediato dia útil subsequente".
--
-- Regras implementadas em public.handle_new_case_task():
-- 1) Tarefa "Acompanhamento processual":
--    - Responsável: Usuário 'Mestre' (public.profiles.name ILIKE 'Mestre' com fallbacks existentes)
--    - Vencimento: Dia 25 do mês subsequente à data de criação do processo
--    - Prioridade: 'Baixa'
--    - Status: 'atualização'
--    - Tipo: 'interna e adm'
-- 2) Tarefa "Redigir Inicial ou Defesa":
--    - Responsável: Usuário que cadastrou o processo (creator_id = COALESCE(auth.uid(), NEW."responsibleId", mestre_id))
--    - Vencimento: Imediato próximo dia útil subsequente à data de criação do processo (public.calculate_next_business_day)
--    - Prioridade: 'Baixa'
--    - Status: 'pendente'
--    - Tipo: 'Redigir inicial'
-- 3) Isolamento de erros via blocos BEGIN ... EXCEPTION WHEN OTHERS para garantir que
--    nenhuma falha em tarefas interrompa o cadastro do processo.
-- 4) Trigger idempotente on_case_created em public.cases.

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

CREATE OR REPLACE FUNCTION public.handle_new_case_task()
RETURNS trigger AS $$
DECLARE
    reg_date date;
    next_business_day date;
    subsequent_month_25th text;
    mestre_id uuid;
    creator_id uuid;
BEGIN
    -- Determina a data base no timezone local (America/Sao_Paulo)
    reg_date := (NEW.created_at AT TIME ZONE 'America/Sao_Paulo')::date;
    IF reg_date IS NULL THEN
        reg_date := CURRENT_DATE;
    END IF;

    -- Vencimento 1: dia 25 do mês subsequente à criação do processo
    subsequent_month_25th := to_char(
        (date_trunc('month', reg_date) + interval '1 month')::date + interval '24 days',
        'YYYY-MM-DD'
    );

    -- Vencimento 2: imediato próximo dia útil subsequente (pula sábado e domingo)
    next_business_day := public.calculate_next_business_day(reg_date);

    -- Localiza usuário Mestre
    SELECT id INTO mestre_id
    FROM public.profiles
    WHERE name ILIKE 'Mestre'
    ORDER BY is_active DESC NULLS LAST, created_at ASC
    LIMIT 1;

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
        ORDER BY is_active DESC NULLS LAST, created_at ASC
        LIMIT 1;
    END IF;

    IF mestre_id IS NULL THEN
        mestre_id := NEW."responsibleId";
    END IF;

    -- Identifica o criador do processo (usuário logado, fallback para responsável do caso ou Mestre)
    creator_id := COALESCE(auth.uid(), NEW."responsibleId", mestre_id);

    -- Apenas para processos principais (não subprocessos)
    IF NEW."parentId" IS NULL THEN
        -- Tarefa 1: Acompanhamento processual (atribuída ao Mestre, dia 25 do mês subsequente)
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
                subsequent_month_25th,
                mestre_id,
                creator_id
            );
        EXCEPTION WHEN OTHERS THEN
            RAISE WARNING 'Falha ao criar tarefa automática de acompanhamento do processo %: %', NEW.id, SQLERRM;
        END;

        -- Tarefa 2: Redigir Inicial ou Defesa (atribuída ao criador do processo, imediato próximo dia útil)
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
                to_char(next_business_day, 'YYYY-MM-DD'),
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
