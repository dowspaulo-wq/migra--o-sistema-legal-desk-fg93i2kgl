-- ==============================================================================
-- DPSjur - DDL Schema Completo (PostgreSQL 15+ / Supabase Self-Hosted)
-- Gerado para: Fase 4 da Migração para VPS Hostinger (EasyPanel + Supabase)
-- Origem: Projeto SBJur (cpcafthwnqazopqftemj)
-- Data: 2026-10-06 / 2026-10-07
-- Contém: Extensões, 17 Tabelas do schema public com tipos e defaults exatos,
--         Triggers e Funções de automação em plpgsql.
-- ==============================================================================

-- 0. Extensões Essenciais
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ==============================================================================
-- 1. TABELAS DO SCHEMA PUBLIC (17 Tabelas)
-- ==============================================================================

-- 1.1 PROFILES (Usuários do sistema vinculados ao auth.users)
CREATE TABLE IF NOT EXISTS public.profiles (
    id UUID PRIMARY KEY,
    name TEXT NOT NULL,
    role TEXT NOT NULL DEFAULT 'User',
    "canViewFinance" BOOLEAN NOT NULL DEFAULT false,
    color TEXT NOT NULL DEFAULT '#3b82f6',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    email TEXT,
    avatar_url TEXT,
    is_active BOOLEAN NOT NULL DEFAULT true
);

-- 1.2 SETTINGS (Configurações globais e listas auxiliares em JSONB)
CREATE TABLE IF NOT EXISTS public.settings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    "showFinanceDashboard" BOOLEAN NOT NULL DEFAULT true,
    "themeColor" TEXT NOT NULL DEFAULT 'blue',
    "logoUrl" TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    "googleCalendarTokens" JSONB,
    "caseTypes" JSONB,
    "caseStatuses" JSONB,
    "taskTypes" JSONB,
    "taskStatuses" JSONB,
    "appointmentTypes" JSONB,
    "captacaoOptions" JSONB,
    "transactionCategories" JSONB,
    "clientPositions" JSONB,
    "subprocessTypes" JSONB,
    "bankAccounts" JSONB
);

-- 1.3 CASE_SYSTEMS (Sistemas judiciais: PJe, Projudi, e-SAJ, etc.)
CREATE TABLE IF NOT EXISTS public.case_systems (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL UNIQUE,
    image_url TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 1.4 SUPPLIERS (Fornecedores cadastrados no módulo financeiro)
CREATE TABLE IF NOT EXISTS public.suppliers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    document TEXT,
    email TEXT,
    phone TEXT,
    status TEXT DEFAULT 'Ativo',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 1.5 CLIENTS (Cadastro de clientes)
CREATE TABLE IF NOT EXISTS public.clients (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    document TEXT UNIQUE,
    type TEXT NOT NULL DEFAULT 'PF',
    email TEXT,
    phone TEXT,
    address TEXT,
    birthday TEXT,
    "responsibleId" UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    status TEXT DEFAULT 'Ativo',
    "isSpecial" BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    captacao TEXT,
    asaas_id TEXT UNIQUE,
    street TEXT,
    number TEXT,
    complement TEXT,
    neighborhood TEXT,
    city TEXT,
    cep TEXT,
    state TEXT,
    marital_status TEXT,
    phone_na BOOLEAN DEFAULT false,
    no_phone BOOLEAN DEFAULT false,
    email_na BOOLEAN DEFAULT false,
    no_email BOOLEAN DEFAULT false,
    hide_birthday BOOLEAN DEFAULT false,
    classification TEXT DEFAULT 'SB',
    observacoes TEXT
);

CREATE INDEX IF NOT EXISTS idx_clients_name ON public.clients(name);
CREATE INDEX IF NOT EXISTS idx_clients_document ON public.clients(document);
CREATE INDEX IF NOT EXISTS idx_clients_asaas_id ON public.clients(asaas_id);

-- 1.6 CASES (Processos jurídicos)
CREATE TABLE IF NOT EXISTS public.cases (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    "clientId" UUID REFERENCES public.clients(id) ON DELETE CASCADE,
    number TEXT UNIQUE NOT NULL,
    position TEXT,
    "adverseParty" TEXT,
    type TEXT,
    status TEXT,
    court TEXT,
    comarca TEXT,
    state TEXT,
    system TEXT,
    value NUMERIC NOT NULL DEFAULT 0,
    "startDate" TEXT,
    "responsibleId" UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    "updatedAt" TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    "feeValue" NUMERIC DEFAULT 0,
    "feeType" TEXT,
    "feeInstallments" INTEGER DEFAULT 1,
    "internalNotes" TEXT,
    description TEXT,
    alerts TEXT,
    "isSpecial" BOOLEAN NOT NULL DEFAULT false,
    "parentId" UUID REFERENCES public.cases(id) ON DELETE SET NULL,
    "isProblematic" BOOLEAN NOT NULL DEFAULT false,
    process_name TEXT,
    classification TEXT DEFAULT 'SB',
    "isRestricted" BOOLEAN NOT NULL DEFAULT false,
    last_movement TEXT,
    last_sync_at TIMESTAMPTZ,
    court_details JSONB
);

CREATE INDEX IF NOT EXISTS idx_cases_client_id ON public.cases("clientId");
CREATE INDEX IF NOT EXISTS idx_cases_number ON public.cases(number);
CREATE INDEX IF NOT EXISTS idx_cases_responsible ON public.cases("responsibleId");

-- 1.7 APPOINTMENTS (Agenda e compromissos)
CREATE TABLE IF NOT EXISTS public.appointments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title TEXT NOT NULL,
    date TEXT NOT NULL,
    type TEXT NOT NULL,
    "responsibleId" UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    "clientId" UUID NOT NULL REFERENCES public.clients(id) ON DELETE CASCADE,
    "processId" UUID REFERENCES public.cases(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    modality TEXT,
    time TEXT NOT NULL DEFAULT '00:00',
    priority TEXT NOT NULL DEFAULT 'Média',
    status TEXT NOT NULL DEFAULT 'Pendente',
    description TEXT,
    "googleEventId" TEXT,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_appointments_client ON public.appointments("clientId");
CREATE INDEX IF NOT EXISTS idx_appointments_date ON public.appointments(date);

-- 1.8 TASKS (Tarefas e prazos)
CREATE TABLE IF NOT EXISTS public.tasks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title TEXT NOT NULL,
    description TEXT,
    "dueDate" TEXT,
    status TEXT NOT NULL DEFAULT 'Pendente',
    priority TEXT NOT NULL DEFAULT 'Média',
    "responsibleId" UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    "relatedProcessId" UUID REFERENCES public.cases(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    type TEXT NOT NULL DEFAULT 'Outro',
    "clientId" UUID REFERENCES public.clients(id) ON DELETE CASCADE,
    "internalNotes" TEXT,
    created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    completed_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_tasks_due_date ON public.tasks("dueDate");
CREATE INDEX IF NOT EXISTS idx_tasks_responsible ON public.tasks("responsibleId");
CREATE INDEX IF NOT EXISTS idx_tasks_case ON public.tasks("relatedProcessId");
CREATE INDEX IF NOT EXISTS idx_tasks_created_by ON public.tasks(created_by);
CREATE INDEX IF NOT EXISTS idx_tasks_completed_by ON public.tasks(completed_by);

-- 1.9 TRANSACTIONS (Lançamentos financeiros)
CREATE TABLE IF NOT EXISTS public.transactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    description TEXT NOT NULL,
    amount NUMERIC NOT NULL DEFAULT 0,
    type TEXT NOT NULL,
    category TEXT,
    status TEXT,
    date TEXT,
    "clientId" UUID REFERENCES public.clients(id) ON DELETE SET NULL,
    "processId" UUID REFERENCES public.cases(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    "supplierId" UUID REFERENCES public.suppliers(id) ON DELETE SET NULL,
    "sendToFinance" BOOLEAN DEFAULT true,
    "bankAccount" TEXT,
    asaas_id TEXT UNIQUE,
    payment_method TEXT DEFAULT 'PIX',
    origem TEXT DEFAULT 'MANUAL',
    recurring_id UUID,
    percentage NUMERIC,
    pendente_vinculo BOOLEAN NOT NULL DEFAULT false
);

CREATE INDEX IF NOT EXISTS idx_transactions_client ON public.transactions("clientId");
CREATE INDEX IF NOT EXISTS idx_transactions_process ON public.transactions("processId");
CREATE INDEX IF NOT EXISTS idx_transactions_asaas_id ON public.transactions(asaas_id);
CREATE INDEX IF NOT EXISTS idx_transactions_pendente_vinculo ON public.transactions(pendente_vinculo);
CREATE INDEX IF NOT EXISTS idx_transactions_recurring_id ON public.transactions(recurring_id);

-- 1.10 TRANSACTION_CASES (N:M entre transações financeiras e processos)
CREATE TABLE IF NOT EXISTS public.transaction_cases (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    transaction_id UUID NOT NULL REFERENCES public.transactions(id) ON DELETE CASCADE,
    case_id UUID NOT NULL REFERENCES public.cases(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT idx_transaction_cases_unique UNIQUE (transaction_id, case_id)
);

CREATE INDEX IF NOT EXISTS idx_transaction_cases_transaction_id ON public.transaction_cases(transaction_id);
CREATE INDEX IF NOT EXISTS idx_transaction_cases_case_id ON public.transaction_cases(case_id);

-- 1.11 DOCUMENT_TEMPLATES (Modelos Word/DOCX para peças jurídicas)
CREATE TABLE IF NOT EXISTS public.document_templates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    file_path TEXT NOT NULL,
    category TEXT DEFAULT 'Geral',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 1.12 PETITIONS (Modelos de petições)
CREATE TABLE IF NOT EXISTS public.petitions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title TEXT NOT NULL,
    content TEXT,
    category TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 1.13 LOGS (Registro de auditoria e webhooks)
CREATE TABLE IF NOT EXISTS public.logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    action TEXT NOT NULL,
    entity TEXT NOT NULL,
    "user" TEXT NOT NULL,
    date TEXT NOT NULL,
    details TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_logs_action ON public.logs(action);
CREATE INDEX IF NOT EXISTS idx_logs_created_at ON public.logs(created_at DESC);

-- 1.14 USER_SESSIONS (Sessões e atividade dos operadores)
CREATE TABLE IF NOT EXISTS public.user_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profile_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    login_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_activity_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    logout_at TIMESTAMPTZ,
    date DATE DEFAULT CURRENT_DATE
);

CREATE INDEX IF NOT EXISTS idx_user_sessions_profile_id ON public.user_sessions(profile_id);
CREATE INDEX IF NOT EXISTS idx_user_sessions_logout_at ON public.user_sessions(logout_at);

-- 1.15 WHATSAPP_MESSAGES (Mensagens via WhatsApp)
CREATE TABLE IF NOT EXISTS public.whatsapp_messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    phone TEXT NOT NULL,
    contact_name TEXT NOT NULL,
    message TEXT NOT NULL,
    direction TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 1.16 BACKUP_LOGS (Auditoria de backups)
CREATE TABLE IF NOT EXISTS public.backup_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    file_name TEXT NOT NULL,
    format TEXT NOT NULL,
    file_size_bytes BIGINT NOT NULL DEFAULT 0,
    tables_included TEXT[] NOT NULL DEFAULT '{}',
    total_records INTEGER NOT NULL DEFAULT 0,
    status TEXT NOT NULL DEFAULT 'completed',
    error_message TEXT,
    trigger_type TEXT NOT NULL DEFAULT 'auto',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 1.17 BACKUP_EXPORT_CONFIG (Chave secreta interna)
CREATE TABLE IF NOT EXISTS public.backup_export_config (
    id INTEGER PRIMARY KEY DEFAULT 1,
    value TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ==============================================================================
-- 2. FUNÇÕES E TRIGGERS DE BANCO DE DADOS
-- ==============================================================================

-- 2.1 Atualização de timestamp em appointments
CREATE OR REPLACE FUNCTION public.update_appointments_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_appointments_updated ON public.appointments;
CREATE TRIGGER on_appointments_updated
    BEFORE UPDATE ON public.appointments
    FOR EACH ROW EXECUTE FUNCTION public.update_appointments_updated_at();

-- 2.2 Forçar comarca em maiúsculas em cases
CREATE OR REPLACE FUNCTION public.enforce_uppercase_comarca()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.comarca IS NOT NULL THEN
        NEW.comarca = UPPER(NEW.comarca);
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_uppercase_comarca ON public.cases;
CREATE TRIGGER trg_uppercase_comarca
    BEFORE INSERT OR UPDATE ON public.cases
    FOR EACH ROW EXECUTE FUNCTION public.enforce_uppercase_comarca();

-- 2.3 Criar tarefa de acompanhamento mensal quando novo processo é cadastrado
CREATE OR REPLACE FUNCTION public.handle_new_case_task()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
    due_date text;
    douglas_id uuid;
BEGIN
    SELECT to_char((CURRENT_DATE + INTERVAL '1 month')::date, 'YYYY-MM-25') INTO due_date;
    
    SELECT id INTO douglas_id FROM public.profiles 
    WHERE email ILIKE 'advdouglaspsantos@gmail.com' OR email ILIKE 'dowspaulo@gmail.com' 
    LIMIT 1;

    IF douglas_id IS NULL THEN
        SELECT id INTO douglas_id FROM public.profiles WHERE role = 'Admin' LIMIT 1;
    END IF;

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
        'Acompanhamento processual mensal',
        'Verificar andamento do processo no tribunal e atualizar cliente se houver novidades.',
        due_date,
        'Pendente',
        'Baixa',
        douglas_id,
        NEW.id,
        'Atualização processual',
        NEW."clientId",
        ''
    );

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_case_created ON public.cases;
CREATE TRIGGER on_case_created
    AFTER INSERT ON public.cases
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_case_task();

-- 2.4 Automação de revisão/protocolo quando colaborador conclui petição/recurso
CREATE OR REPLACE FUNCTION public.handle_task_completion_automation_v2()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
    v_user_role text;
    v_douglas_id uuid;
    v_client_name text;
    v_process_number text;
    v_new_title text;
    v_task_exists boolean;
BEGIN
    IF NEW.status ILIKE 'concluíd%' AND OLD.status NOT ILIKE 'concluíd%' THEN
        IF NEW.type ILIKE 'recorrer' OR NEW.type ILIKE 'redigir inicial' OR NEW.type ILIKE 'petições' THEN
            SELECT role INTO v_user_role FROM public.profiles WHERE id = auth.uid();
            
            IF v_user_role ILIKE 'User' OR v_user_role ILIKE 'Colaborador' THEN
                SELECT id INTO v_douglas_id FROM public.profiles 
                WHERE email ILIKE 'advdouglaspsantos@gmail.com' OR email ILIKE 'dowspaulo@gmail.com' 
                LIMIT 1;
                
                IF v_douglas_id IS NULL THEN
                    SELECT id INTO v_douglas_id FROM public.profiles WHERE name ILIKE '%douglas%' LIMIT 1;
                END IF;

                IF v_douglas_id IS NOT NULL THEN
                    SELECT name INTO v_client_name FROM public.clients WHERE id = NEW."clientId";
                    SELECT number INTO v_process_number FROM public.cases WHERE id = NEW."relatedProcessId";
                    v_new_title := COALESCE(v_client_name, 'Sem Cliente') || ' - ' || COALESCE(v_process_number, 'Sem Processo');
                    
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
$$;

DROP TRIGGER IF EXISTS on_task_completed_v2 ON public.tasks;
CREATE TRIGGER on_task_completed_v2
    AFTER UPDATE ON public.tasks
    FOR EACH ROW EXECUTE FUNCTION public.handle_task_completion_automation_v2();

-- 2.5 Correção de Mojibake (acentuação corrompida)
CREATE OR REPLACE FUNCTION public.fix_pt_mojibake(txt text)
RETURNS text LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
    res text;
BEGIN
    IF txt IS NULL THEN RETURN NULL; END IF;
    res := txt;
    res := replace(res, 'Ã¡', 'á');
    res := replace(res, 'Ã ', 'à');
    res := replace(res, 'Ã£', 'ã');
    res := replace(res, 'Ã¢', 'â');
    res := replace(res, 'Ã©', 'é');
    res := replace(res, 'Ãª', 'ê');
    res := replace(res, 'Ã­', 'í');
    res := replace(res, 'Ã³', 'ó');
    res := replace(res, 'Ãµ', 'õ');
    res := replace(res, 'Ã´', 'ô');
    res := replace(res, 'Ãº', 'ú');
    res := replace(res, 'Ã§', 'ç');
    res := replace(res, 'Ã', 'Á');
    res := replace(res, 'Ã€', 'À');
    res := replace(res, 'Ãƒ', 'Ã');
    res := replace(res, 'Ã‚', 'Â');
    res := replace(res, 'Ã‰', 'É');
    res := replace(res, 'ÃŠ', 'Ê');
    res := replace(res, 'Ã', 'Í');
    res := replace(res, 'Ã“', 'Ó');
    res := replace(res, 'Ã•', 'Õ');
    res := replace(res, 'Ã”', 'Ô');
    res := replace(res, 'Ãš', 'Ú');
    res := replace(res, 'Ã‡', 'Ç');
    RETURN res;
END;
$$;
