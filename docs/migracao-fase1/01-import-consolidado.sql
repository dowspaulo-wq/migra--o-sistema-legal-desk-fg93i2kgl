-- ==============================================================================
-- DPSjur - Script de Importação Consolidado (PostgreSQL 16 - EasyPanel / VPS Hostinger)
-- Kit de Migração - Fase 1 / Fase 2
-- Gerado a partir dos artefatos oficiais da Fase 0 (Projeto dagtlwojkqyivnjgveda)
-- Ambiente de Destino: Container Docker EasyPanel (dpsjur-db) / Banco "dpsjur"
-- ==============================================================================
-- ORDEM DE EXECUÇÃO:
--   ETAPA 0: Configurações de sessão, extensões e roles auxiliares do Supabase
--   ETAPA 1: Estrutura de tabelas (DDL) e índices (17 tabelas do schema public)
--   ETAPA 2: Dados cadastrais estruturais (Seed: profiles, settings, case_systems,
--            document_templates, backup_export_config)
--   ETAPA 3: [PONTO DE INGESTÃO DO DUMP COMPLETO]: Tabelas transacionais e operacionais
--            (clients, cases, appointments, tasks, transactions, transaction_cases,
--            suppliers, petitions, logs, user_sessions, whatsapp_messages, backup_logs)
--   ETAPA 4: Funções auxiliares e triggers de automação
--   ETAPA 5: Políticas de RLS (Row Level Security) e ativação de RLS
-- ==============================================================================

SET statement_timeout = 0;
SET lock_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SET check_function_bodies = false;
SET client_min_messages = warning;
SET row_security = off;

-- ==============================================================================
-- ETAPA 0: EXTENSÕES, SCHEMA AUTH & ROLES AUXILIARES (Compatibilidade Supabase)
-- ==============================================================================

-- 0.1 Extensões essenciais
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- 0.2 Roles auxiliares (anon, authenticated, service_role)
-- No PostgreSQL nativo fora do Supabase, essas roles não existem por padrão.
-- As policies de RLS referenciam "TO authenticated" e "TO service_role".
-- Criamos as roles com NOLOGIN para que as regras de segurança compilem perfeitamente.
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
        CREATE ROLE anon NOLOGIN;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
        CREATE ROLE authenticated NOLOGIN;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
        CREATE ROLE service_role NOLOGIN;
    END IF;
END
$$;

-- 0.3 Schema auth e função auth.uid() mínima (compatibilidade com triggers e RLS)
CREATE SCHEMA IF NOT EXISTS auth;

CREATE OR REPLACE FUNCTION auth.uid()
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
    SELECT COALESCE(
        current_setting('request.jwt.claim.sub', true),
        (current_setting('request.jwt.claims', true)::jsonb ->> 'sub')
    )::uuid;
$$;

CREATE OR REPLACE FUNCTION auth.role()
RETURNS text
LANGUAGE sql
STABLE
AS $$
    SELECT COALESCE(
        current_setting('request.jwt.claim.role', true),
        (current_setting('request.jwt.claims', true)::jsonb ->> 'role'),
        'authenticated'
    )::text;
$$;

GRANT USAGE ON SCHEMA auth TO PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA auth TO PUBLIC, anon, authenticated, service_role;

-- ==============================================================================
-- ETAPA 1: TABELAS E ÍNDICES (DDL DO SCHEMA PUBLIC - 17 TABELAS)
-- ==============================================================================

-- 1.1 PROFILES (Usuários e advogados do escritório)
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

-- 1.2 SETTINGS (Configurações gerais, categorias e listas em JSONB)
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

-- 1.3 CASE_SYSTEMS (Sistemas judiciais dos tribunais: PJe, Projudi, e-SAJ, etc.)
CREATE TABLE IF NOT EXISTS public.case_systems (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL UNIQUE,
    image_url TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 1.4 SUPPLIERS (Fornecedores e parceiros cadastrados)
CREATE TABLE IF NOT EXISTS public.suppliers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    document TEXT,
    email TEXT,
    phone TEXT,
    status TEXT DEFAULT 'Ativo',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 1.5 CLIENTS (Cadastro completo de clientes PF/PJ)
CREATE TABLE IF NOT EXISTS public.clients (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    document TEXT UNIQUE NOT NULL,
    type TEXT NOT NULL,
    email TEXT,
    phone TEXT,
    address TEXT,
    birthday TEXT,
    "responsibleId" UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    status TEXT NOT NULL DEFAULT 'Ativo',
    "isSpecial" BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
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
    phone_na BOOLEAN NOT NULL DEFAULT false,
    no_phone BOOLEAN NOT NULL DEFAULT false,
    email_na BOOLEAN NOT NULL DEFAULT false,
    no_email BOOLEAN NOT NULL DEFAULT false,
    hide_birthday BOOLEAN NOT NULL DEFAULT false,
    classification TEXT,
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
    "feeValue" NUMERIC,
    "feeType" TEXT,
    "feeInstallments" INTEGER,
    "internalNotes" TEXT,
    description TEXT,
    alerts TEXT,
    "isSpecial" BOOLEAN NOT NULL DEFAULT false,
    "parentId" UUID REFERENCES public.cases(id) ON DELETE SET NULL,
    "isProblematic" BOOLEAN NOT NULL DEFAULT false,
    process_name TEXT,
    classification TEXT,
    "isRestricted" BOOLEAN NOT NULL DEFAULT false,
    last_movement TEXT,
    last_sync_at TIMESTAMPTZ,
    court_details JSONB
);

CREATE INDEX IF NOT EXISTS idx_cases_client_id ON public.cases("clientId");
CREATE INDEX IF NOT EXISTS idx_cases_number ON public.cases(number);
CREATE INDEX IF NOT EXISTS idx_cases_responsible ON public.cases("responsibleId");

-- 1.7 APPOINTMENTS (Agenda de audiências e compromissos)
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

-- 1.8 TASKS (Tarefas, prazos e automações processuais)
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
    type TEXT NOT NULL DEFAULT 'Geral',
    "clientId" UUID REFERENCES public.clients(id) ON DELETE CASCADE,
    "internalNotes" TEXT,
    created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    completed_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_tasks_due_date ON public.tasks("dueDate");
CREATE INDEX IF NOT EXISTS idx_tasks_responsible ON public.tasks("responsibleId");
CREATE INDEX IF NOT EXISTS idx_tasks_case ON public.tasks("relatedProcessId");

-- 1.9 TRANSACTIONS (Lançamentos financeiros)
CREATE TABLE IF NOT EXISTS public.transactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    description TEXT NOT NULL,
    amount NUMERIC NOT NULL DEFAULT 0,
    type TEXT NOT NULL,
    category TEXT NOT NULL,
    status TEXT NOT NULL,
    date TEXT,
    "clientId" UUID REFERENCES public.clients(id) ON DELETE SET NULL,
    "processId" UUID REFERENCES public.cases(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    "supplierId" UUID REFERENCES public.suppliers(id) ON DELETE SET NULL,
    "sendToFinance" BOOLEAN DEFAULT true,
    "bankAccount" TEXT,
    asaas_id TEXT UNIQUE,
    payment_method TEXT,
    origem TEXT DEFAULT 'manual',
    recurring_id TEXT,
    percentage NUMERIC,
    pendente_vinculo BOOLEAN NOT NULL DEFAULT false
);

CREATE INDEX IF NOT EXISTS idx_transactions_client ON public.transactions("clientId");
CREATE INDEX IF NOT EXISTS idx_transactions_process ON public.transactions("processId");
CREATE INDEX IF NOT EXISTS idx_transactions_asaas_id ON public.transactions(asaas_id);

-- 1.10 TRANSACTION_CASES (Relacionamento N:M lançamentos x múltiplos processos)
CREATE TABLE IF NOT EXISTS public.transaction_cases (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    transaction_id UUID NOT NULL REFERENCES public.transactions(id) ON DELETE CASCADE,
    case_id UUID NOT NULL REFERENCES public.cases(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_tx_cases_tx ON public.transaction_cases(transaction_id);
CREATE INDEX IF NOT EXISTS idx_tx_cases_case ON public.transaction_cases(case_id);

-- 1.11 DOCUMENT_TEMPLATES (Modelos em Word/DOCX para peças)
CREATE TABLE IF NOT EXISTS public.document_templates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    file_path TEXT NOT NULL,
    category TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 1.12 PETITIONS (Modelos de petições em texto puro)
CREATE TABLE IF NOT EXISTS public.petitions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title TEXT NOT NULL,
    content TEXT NOT NULL,
    category TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 1.13 LOGS (Trilha de auditoria, eventos de sistema e webhooks)
CREATE TABLE IF NOT EXISTS public.logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    action TEXT NOT NULL,
    entity TEXT NOT NULL,
    "user" TEXT NOT NULL,
    date TEXT NOT NULL,
    details TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_logs_created_at ON public.logs(created_at DESC);

-- 1.14 USER_SESSIONS (Rastreamento de acessos dos usuários)
CREATE TABLE IF NOT EXISTS public.user_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profile_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    date TEXT NOT NULL,
    login_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_activity_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    logout_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_user_sessions_profile ON public.user_sessions(profile_id);
CREATE INDEX IF NOT EXISTS idx_user_sessions_date ON public.user_sessions(date);

-- 1.15 WHATSAPP_MESSAGES (Mensagens trocadas via WhatsApp)
CREATE TABLE IF NOT EXISTS public.whatsapp_messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    phone TEXT NOT NULL,
    message TEXT NOT NULL,
    direction TEXT NOT NULL,
    contact_name TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 1.16 BACKUP_LOGS (Registro histórico de backups)
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

-- 1.17 BACKUP_EXPORT_CONFIG (Chave secreta interna para exportação via Edge Function)
CREATE TABLE IF NOT EXISTS public.backup_export_config (
    id SERIAL PRIMARY KEY,
    value TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Permissões básicas para as roles
GRANT USAGE ON SCHEMA public TO PUBLIC, anon, authenticated, service_role;
GRANT ALL ON ALL TABLES IN SCHEMA public TO PUBLIC, anon, authenticated, service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO PUBLIC, anon, authenticated, service_role;

-- ==============================================================================
-- ETAPA 2: DADOS CADASTRAIS ESSENCIAIS (SEED DA FASE 0)
-- ==============================================================================

-- 2.1 PROFILES (7 registros de operadores/advogados do escritório)
INSERT INTO public.profiles (id, name, email, role, "canViewFinance", color, is_active, created_at, avatar_url) VALUES
('6501af65-cd6c-43c3-958a-3091ce93ba78', 'Douglas', 'advdouglaspsantos@gmail.com', 'Admin', true, '#3b82f6', true, '2026-03-16 19:38:21.787039+00', 'https://cpcafthwnqazopqftemj.supabase.co/storage/v1/object/public/avatars/6501af65-cd6c-43c3-958a-3091ce93ba78-0.3970545073819589.jpg'),
('2e196060-0c7f-4eaa-8764-3ac94e9e756f', 'Mestre', 'admin@sbjur.com', 'Admin', true, '#10b981', true, '2026-03-15 21:36:21.478311+00', NULL),
('4ad65234-19ac-4b8d-aec5-fb0ad9ffdeaf', 'Guilherme Almeida', 'willhelmalmeida@gmail.com', 'User', false, '#8b5cf6', true, '2026-09-21 14:18:55.317099+00', 'https://cpcafthwnqazopqftemj.supabase.co/storage/v1/object/public/avatars/4ad65234-19ac-4b8d-aec5-fb0ad9ffdeaf-0.25634000655999467.jpeg'),
('97971288-d3cf-4d66-a48f-8691ab0b40a4', 'Guilherme Filippini', 'guilherme.f.augusto@gmail.com', 'User', false, '#10b981', true, '2026-05-25 17:58:47.714768+00', 'https://cpcafthwnqazopqftemj.supabase.co/storage/v1/object/public/avatars/97971288-d3cf-4d66-a48f-8691ab0b40a4-0.009296859819198255.jpeg'),
('fce63d37-a440-49b2-9efd-e820b0ed3ac0', 'Heitor Paulinho', 'heitorpaulodossantos@gmail.com', 'User', false, '#06b6d4', true, '2026-06-20 21:30:04.02017+00', NULL),
('8914e17d-64ce-4acc-88ab-5fc04f11ac24', 'Eduardo', 'adveduardoaugustobarbosa@gmail.com', 'User', false, '#f59e0b', false, '2026-03-17 13:43:18.241952+00', 'https://cpcafthwnqazopqftemj.supabase.co/storage/v1/object/public/avatars/8914e17d-64ce-4acc-88ab-5fc04f11ac24-0.6034897410318099.png'),
('b700846f-fc9e-4f3c-a48e-86a8e5e83f12', 'Fernanda Regis', 'fe.nandaregiss@gmail.com', 'User', false, '#ec4899', false, '2026-07-10 11:11:11.660991+00', 'https://cpcafthwnqazopqftemj.supabase.co/storage/v1/object/public/avatars/b700846f-fc9e-4f3c-a48e-86a8e5e83f12-0.7322693909650941.jpeg')
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  email = EXCLUDED.email,
  role = EXCLUDED.role,
  "canViewFinance" = EXCLUDED."canViewFinance",
  color = EXCLUDED.color,
  is_active = EXCLUDED.is_active,
  avatar_url = EXCLUDED.avatar_url;

-- 2.2 CASE_SYSTEMS (8 registros de sistemas de tribunais)
INSERT INTO public.case_systems (id, name, image_url) VALUES
('b3c8f8b8-2a91-4cf1-8a71-61b7f2da5201', 'PJe', 'https://cpcafthwnqazopqftemj.supabase.co/storage/v1/object/public/case-systems/0.9744052893612097.bmp'),
('b3c8f8b8-2a91-4cf1-8a71-61b7f2da5202', 'Projudi', 'https://cpcafthwnqazopqftemj.supabase.co/storage/v1/object/public/case-systems/0.7792231130266362.bmp'),
('b3c8f8b8-2a91-4cf1-8a71-61b7f2da5203', 'e-SAJ', 'https://cpcafthwnqazopqftemj.supabase.co/storage/v1/object/public/case-systems/0.7340156072577102.bmp'),
('b3c8f8b8-2a91-4cf1-8a71-61b7f2da5204', 'Eproc', 'https://cpcafthwnqazopqftemj.supabase.co/storage/v1/object/public/case-systems/0.8777420576239596.bmp'),
('b3c8f8b8-2a91-4cf1-8a71-61b7f2da5205', 'JPE', 'https://cpcafthwnqazopqftemj.supabase.co/storage/v1/object/public/case-systems/0.38107057149783896.bmp'),
('b3c8f8b8-2a91-4cf1-8a71-61b7f2da5206', 'SEEU', 'https://cpcafthwnqazopqftemj.supabase.co/storage/v1/object/public/case-systems/0.1710385136882614.bmp'),
('b3c8f8b8-2a91-4cf1-8a71-61b7f2da5207', 'Creta', 'https://cpcafthwnqazopqftemj.supabase.co/storage/v1/object/public/case-systems/0.9756833351919669.bmp'),
('b3c8f8b8-2a91-4cf1-8a71-61b7f2da5208', 'Outro', 'https://cpcafthwnqazopqftemj.supabase.co/storage/v1/object/public/case-systems/0.584555652725446.bmp')
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  image_url = EXCLUDED.image_url;

-- 2.3 DOCUMENT_TEMPLATES (1 registro inicial de modelo de contrato)
INSERT INTO public.document_templates (id, name, file_path, category) VALUES
('fa80720a-605e-44d4-9541-616147d3372c', 'Contrato Indenizatoria', '1783792994284_Contrato prestacao de servicos INDENIZATORIA 2025.08.08.docx', 'Contratos')
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  file_path = EXCLUDED.file_path,
  category = EXCLUDED.category;

-- 2.4 BACKUP_EXPORT_CONFIG (Token de segurança interno)
INSERT INTO public.backup_export_config (id, value, created_at) VALUES
(1, 'sbjur_backup_export_secret_token_2026', NOW())
ON CONFLICT (id) DO UPDATE SET value = EXCLUDED.value;

-- ==============================================================================
-- ETAPA 3: INSTRUÇÕES PARA INGESTÃO DO DUMP COMPLETO DE DADOS
-- ==============================================================================
-- NOTA CRÍTICA PARA A RESTAURAÇÃO:
-- As tabelas de produção com o volume completo (345 clients, 550 cases, 941 transactions,
-- 834 tasks, 258 appointments, 471 transaction_cases, 26 suppliers, 11 petitions,
-- 522 logs, 3718 user_sessions, 2 whatsapp_messages, 1 settings) estão salvas no
-- arquivo SQL gerado pela rotina oficial do sistema no Supabase Storage:
--   Arquivo: backup-2026-10-06-2026-10-06T13-05-03-120Z.sql (1,7 MB)
--   (ou backup-2026-10-01-2026-10-01T11-50-12-166Z.sql)
--
-- O Douglas executará este arquivo consolidado que cria a estrutura limpa e sem triggers.
-- Em seguida, executa o dump de dados SQL (via comando psql do guia).
-- Por fim, as funções, triggers e políticas RLS abaixo são aplicadas com segurança.
-- ==============================================================================

-- ==============================================================================
-- ETAPA 4: FUNÇÕES E TRIGGERS DE BANCO DE DADOS
-- ==============================================================================

-- 4.1 Atualização de timestamp em appointments
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

-- 4.2 Forçar comarca em maiúsculas em cases
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

-- 4.3 Criar tarefa de acompanhamento quando novo processo é criado
CREATE OR REPLACE FUNCTION public.handle_new_case_task()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
    due_date text;
    douglas_id uuid;
BEGIN
    -- Calcula o dia 25 do mês subsequente
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

-- 4.4 Automação de revisão/protocolo quando colaborador conclui petição/recurso
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

-- 4.5 Correção de Mojibake (acentuação corrompida em importações)
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

-- ==============================================================================
-- ETAPA 5: POLÍTICAS DE RLS (ROW LEVEL SECURITY)
-- ==============================================================================

-- 5.1 APPOINTMENTS
ALTER TABLE public.appointments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "appointments_authenticated_all" ON public.appointments;
CREATE POLICY "appointments_authenticated_all" ON public.appointments
    FOR ALL TO authenticated
    USING (true)
    WITH CHECK (true);

DROP POLICY IF EXISTS "authenticated_select_appointments" ON public.appointments;
CREATE POLICY "authenticated_select_appointments" ON public.appointments
    FOR SELECT TO authenticated
    USING (EXISTS (SELECT 1 FROM public.profiles WHERE profiles.id = auth.uid() AND profiles.role = 'Admin'));

DROP POLICY IF EXISTS "authenticated_insert_appointments" ON public.appointments;
CREATE POLICY "authenticated_insert_appointments" ON public.appointments
    FOR INSERT TO authenticated
    WITH CHECK (EXISTS (SELECT 1 FROM public.profiles WHERE profiles.id = auth.uid() AND profiles.role = 'Admin'));

DROP POLICY IF EXISTS "authenticated_update_appointments" ON public.appointments;
CREATE POLICY "authenticated_update_appointments" ON public.appointments
    FOR UPDATE TO authenticated
    USING (EXISTS (SELECT 1 FROM public.profiles WHERE profiles.id = auth.uid() AND profiles.role = 'Admin'))
    WITH CHECK (EXISTS (SELECT 1 FROM public.profiles WHERE profiles.id = auth.uid() AND profiles.role = 'Admin'));

DROP POLICY IF EXISTS "authenticated_delete_appointments" ON public.appointments;
CREATE POLICY "authenticated_delete_appointments" ON public.appointments
    FOR DELETE TO authenticated
    USING (EXISTS (SELECT 1 FROM public.profiles WHERE profiles.id = auth.uid() AND profiles.role = 'Admin'));

-- 5.2 BACKUP_LOGS
ALTER TABLE public.backup_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "service_role_all_backup_logs" ON public.backup_logs;
CREATE POLICY "service_role_all_backup_logs" ON public.backup_logs
    FOR ALL TO service_role
    USING (true)
    WITH CHECK (true);

DROP POLICY IF EXISTS "admin_select_backup_logs" ON public.backup_logs;
CREATE POLICY "admin_select_backup_logs" ON public.backup_logs
    FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.profiles
            WHERE profiles.id = auth.uid()
            AND (profiles.role = 'Admin' OR profiles.email IN ('advdouglaspsantos@gmail.com', 'dowspaulo@gmail.com'))
        )
    );

-- 5.3 CASE_SYSTEMS
ALTER TABLE public.case_systems ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "authenticated_select_case_systems" ON public.case_systems;
CREATE POLICY "authenticated_select_case_systems" ON public.case_systems
    FOR SELECT TO authenticated
    USING (true);

DROP POLICY IF EXISTS "authenticated_insert_case_systems" ON public.case_systems;
CREATE POLICY "authenticated_insert_case_systems" ON public.case_systems
    FOR INSERT TO authenticated
    WITH CHECK (true);

DROP POLICY IF EXISTS "authenticated_update_case_systems" ON public.case_systems;
CREATE POLICY "authenticated_update_case_systems" ON public.case_systems
    FOR UPDATE TO authenticated
    USING (true);

DROP POLICY IF EXISTS "authenticated_delete_case_systems" ON public.case_systems;
CREATE POLICY "authenticated_delete_case_systems" ON public.case_systems
    FOR DELETE TO authenticated
    USING (true);

-- 5.4 CASES
ALTER TABLE public.cases ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "cases_authenticated_all" ON public.cases;
CREATE POLICY "cases_authenticated_all" ON public.cases
    FOR ALL TO authenticated
    USING (true)
    WITH CHECK (true);

DROP POLICY IF EXISTS "authenticated_select_cases" ON public.cases;
CREATE POLICY "authenticated_select_cases" ON public.cases
    FOR SELECT TO authenticated
    USING (true);

DROP POLICY IF EXISTS "authenticated_insert_cases" ON public.cases;
CREATE POLICY "authenticated_insert_cases" ON public.cases
    FOR INSERT TO authenticated
    WITH CHECK (true);

DROP POLICY IF EXISTS "authenticated_update_cases" ON public.cases;
CREATE POLICY "authenticated_update_cases" ON public.cases
    FOR UPDATE TO authenticated
    USING (true)
    WITH CHECK (true);

DROP POLICY IF EXISTS "authenticated_delete_cases" ON public.cases;
CREATE POLICY "authenticated_delete_cases" ON public.cases
    FOR DELETE TO authenticated
    USING (EXISTS (SELECT 1 FROM public.profiles WHERE profiles.id = auth.uid() AND profiles.role = 'Admin'));

-- 5.5 CLIENTS
ALTER TABLE public.clients ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "clients_authenticated_all" ON public.clients;
CREATE POLICY "clients_authenticated_all" ON public.clients
    FOR ALL TO authenticated
    USING (true)
    WITH CHECK (true);

DROP POLICY IF EXISTS "authenticated_select_clients" ON public.clients;
CREATE POLICY "authenticated_select_clients" ON public.clients
    FOR SELECT TO authenticated
    USING (true);

DROP POLICY IF EXISTS "authenticated_insert_clients" ON public.clients;
CREATE POLICY "authenticated_insert_clients" ON public.clients
    FOR INSERT TO authenticated
    WITH CHECK (true);

DROP POLICY IF EXISTS "authenticated_update_clients" ON public.clients;
CREATE POLICY "authenticated_update_clients" ON public.clients
    FOR UPDATE TO authenticated
    USING (true)
    WITH CHECK (true);

DROP POLICY IF EXISTS "authenticated_delete_clients" ON public.clients;
CREATE POLICY "authenticated_delete_clients" ON public.clients
    FOR DELETE TO authenticated
    USING (EXISTS (SELECT 1 FROM public.profiles WHERE profiles.id = auth.uid() AND profiles.role = 'Admin'));

-- 5.6 DOCUMENT_TEMPLATES
ALTER TABLE public.document_templates ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "authenticated_select_document_templates" ON public.document_templates;
CREATE POLICY "authenticated_select_document_templates" ON public.document_templates
    FOR SELECT TO authenticated
    USING (true);

DROP POLICY IF EXISTS "authenticated_insert_document_templates" ON public.document_templates;
CREATE POLICY "authenticated_insert_document_templates" ON public.document_templates
    FOR INSERT TO authenticated
    WITH CHECK (true);

DROP POLICY IF EXISTS "authenticated_delete_document_templates" ON public.document_templates;
CREATE POLICY "authenticated_delete_document_templates" ON public.document_templates
    FOR DELETE TO authenticated
    USING (true);

-- 5.7 LOGS
ALTER TABLE public.logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "authenticated_select_logs" ON public.logs;
CREATE POLICY "authenticated_select_logs" ON public.logs
    FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.profiles
            WHERE profiles.id = auth.uid()
            AND profiles.role = ANY (ARRAY['Admin'::text, 'ADM'::text, 'admin'::text])
        )
    );

DROP POLICY IF EXISTS "authenticated_insert_logs" ON public.logs;
CREATE POLICY "authenticated_insert_logs" ON public.logs
    FOR INSERT TO authenticated
    WITH CHECK (true);

DROP POLICY IF EXISTS "authenticated_update_logs" ON public.logs;
CREATE POLICY "authenticated_update_logs" ON public.logs
    FOR UPDATE TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.profiles
            WHERE profiles.id = auth.uid()
            AND profiles.role = ANY (ARRAY['Admin'::text, 'ADM'::text, 'admin'::text])
        )
    );

DROP POLICY IF EXISTS "authenticated_delete_logs" ON public.logs;
CREATE POLICY "authenticated_delete_logs" ON public.logs
    FOR DELETE TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.profiles
            WHERE profiles.id = auth.uid()
            AND profiles.role = ANY (ARRAY['Admin'::text, 'ADM'::text, 'admin'::text])
        )
    );

-- 5.8 PETITIONS
ALTER TABLE public.petitions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "petitions_authenticated_all" ON public.petitions;
CREATE POLICY "petitions_authenticated_all" ON public.petitions
    FOR ALL TO authenticated
    USING (true)
    WITH CHECK (true);

-- 5.9 PROFILES
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "authenticated_select_profiles" ON public.profiles;
CREATE POLICY "authenticated_select_profiles" ON public.profiles
    FOR SELECT TO authenticated
    USING (true);

DROP POLICY IF EXISTS "authenticated_update_profiles" ON public.profiles;
CREATE POLICY "authenticated_update_profiles" ON public.profiles
    FOR UPDATE TO authenticated
    USING (
        auth.uid() = id
        OR EXISTS (
            SELECT 1 FROM public.profiles p
            WHERE p.id = auth.uid()
            AND p.role = 'Admin'
        )
    )
    WITH CHECK (
        auth.uid() = id
        OR EXISTS (
            SELECT 1 FROM public.profiles p
            WHERE p.id = auth.uid()
            AND p.role = 'Admin'
        )
    );

-- 5.10 SETTINGS
ALTER TABLE public.settings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "authenticated_select_settings" ON public.settings;
CREATE POLICY "authenticated_select_settings" ON public.settings
    FOR SELECT TO authenticated
    USING (true);

DROP POLICY IF EXISTS "authenticated_insert_settings" ON public.settings;
CREATE POLICY "authenticated_insert_settings" ON public.settings
    FOR INSERT TO authenticated
    WITH CHECK (true);

DROP POLICY IF EXISTS "authenticated_update_settings" ON public.settings;
CREATE POLICY "authenticated_update_settings" ON public.settings
    FOR UPDATE TO authenticated
    USING (true)
    WITH CHECK (true);

DROP POLICY IF EXISTS "authenticated_delete_settings" ON public.settings;
CREATE POLICY "authenticated_delete_settings" ON public.settings
    FOR DELETE TO authenticated
    USING (true);

-- 5.11 SUPPLIERS
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "authenticated_select_suppliers" ON public.suppliers;
CREATE POLICY "authenticated_select_suppliers" ON public.suppliers
    FOR SELECT TO authenticated
    USING (true);

DROP POLICY IF EXISTS "authenticated_insert_suppliers" ON public.suppliers;
CREATE POLICY "authenticated_insert_suppliers" ON public.suppliers
    FOR INSERT TO authenticated
    WITH CHECK (true);

DROP POLICY IF EXISTS "authenticated_update_suppliers" ON public.suppliers;
CREATE POLICY "authenticated_update_suppliers" ON public.suppliers
    FOR UPDATE TO authenticated
    USING (true)
    WITH CHECK (true);

DROP POLICY IF EXISTS "authenticated_delete_suppliers" ON public.suppliers;
CREATE POLICY "authenticated_delete_suppliers" ON public.suppliers
    FOR DELETE TO authenticated
    USING (true);

-- 5.12 TASKS
ALTER TABLE public.tasks ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "tasks_authenticated_all" ON public.tasks;
CREATE POLICY "tasks_authenticated_all" ON public.tasks
    FOR ALL TO authenticated
    USING (true)
    WITH CHECK (true);

DROP POLICY IF EXISTS "authenticated_select_tasks" ON public.tasks;
CREATE POLICY "authenticated_select_tasks" ON public.tasks
    FOR SELECT TO authenticated
    USING (true);

DROP POLICY IF EXISTS "authenticated_insert_tasks" ON public.tasks;
CREATE POLICY "authenticated_insert_tasks" ON public.tasks
    FOR INSERT TO authenticated
    WITH CHECK (true);

DROP POLICY IF EXISTS "authenticated_update_tasks" ON public.tasks;
CREATE POLICY "authenticated_update_tasks" ON public.tasks
    FOR UPDATE TO authenticated
    USING (true)
    WITH CHECK (true);

DROP POLICY IF EXISTS "authenticated_delete_tasks" ON public.tasks;
CREATE POLICY "authenticated_delete_tasks" ON public.tasks
    FOR DELETE TO authenticated
    USING (EXISTS (SELECT 1 FROM public.profiles WHERE profiles.id = auth.uid() AND profiles.role = 'Admin'));

-- 5.13 TRANSACTION_CASES
ALTER TABLE public.transaction_cases ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "authenticated_select_transaction_cases" ON public.transaction_cases;
CREATE POLICY "authenticated_select_transaction_cases" ON public.transaction_cases
    FOR SELECT TO authenticated
    USING (true);

DROP POLICY IF EXISTS "authenticated_insert_transaction_cases" ON public.transaction_cases;
CREATE POLICY "authenticated_insert_transaction_cases" ON public.transaction_cases
    FOR INSERT TO authenticated
    WITH CHECK (true);

DROP POLICY IF EXISTS "authenticated_update_transaction_cases" ON public.transaction_cases;
CREATE POLICY "authenticated_update_transaction_cases" ON public.transaction_cases
    FOR UPDATE TO authenticated
    USING (true)
    WITH CHECK (true);

DROP POLICY IF EXISTS "authenticated_delete_transaction_cases" ON public.transaction_cases;
CREATE POLICY "authenticated_delete_transaction_cases" ON public.transaction_cases
    FOR DELETE TO authenticated
    USING (true);

-- 5.14 TRANSACTIONS
ALTER TABLE public.transactions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "transactions_authenticated_all" ON public.transactions;
CREATE POLICY "transactions_authenticated_all" ON public.transactions
    FOR ALL TO authenticated
    USING (true)
    WITH CHECK (true);

-- 5.15 USER_SESSIONS
ALTER TABLE public.user_sessions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "admin_select_user_sessions" ON public.user_sessions;
CREATE POLICY "admin_select_user_sessions" ON public.user_sessions
    FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.profiles
            WHERE profiles.id = auth.uid()
            AND profiles.role = ANY (ARRAY['Admin'::text, 'ADM'::text, 'admin'::text])
        )
    );

DROP POLICY IF EXISTS "users_select_own_sessions" ON public.user_sessions;
CREATE POLICY "users_select_own_sessions" ON public.user_sessions
    FOR SELECT TO authenticated
    USING (profile_id = auth.uid());

DROP POLICY IF EXISTS "users_insert_own_sessions" ON public.user_sessions;
CREATE POLICY "users_insert_own_sessions" ON public.user_sessions
    FOR INSERT TO authenticated
    WITH CHECK (profile_id = auth.uid());

DROP POLICY IF EXISTS "users_update_own_sessions" ON public.user_sessions;
CREATE POLICY "users_update_own_sessions" ON public.user_sessions
    FOR UPDATE TO authenticated
    USING (profile_id = auth.uid());

DROP POLICY IF EXISTS "authenticated_insert_user_sessions" ON public.user_sessions;
CREATE POLICY "authenticated_insert_user_sessions" ON public.user_sessions
    FOR INSERT TO authenticated
    WITH CHECK (true);

DROP POLICY IF EXISTS "authenticated_update_user_sessions" ON public.user_sessions;
CREATE POLICY "authenticated_update_user_sessions" ON public.user_sessions
    FOR UPDATE TO authenticated
    USING (true);

-- 5.16 WHATSAPP_MESSAGES
ALTER TABLE public.whatsapp_messages ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "whatsapp_messages_authenticated_all" ON public.whatsapp_messages;
CREATE POLICY "whatsapp_messages_authenticated_all" ON public.whatsapp_messages
    FOR ALL TO authenticated
    USING (true)
    WITH CHECK (true);

DROP POLICY IF EXISTS "authenticated_select_whatsapp_messages" ON public.whatsapp_messages;
CREATE POLICY "authenticated_select_whatsapp_messages" ON public.whatsapp_messages
    FOR SELECT TO authenticated
    USING (true);

DROP POLICY IF EXISTS "authenticated_insert_whatsapp_messages" ON public.whatsapp_messages;
CREATE POLICY "authenticated_insert_whatsapp_messages" ON public.whatsapp_messages
    FOR INSERT TO authenticated
    WITH CHECK (true);

DROP POLICY IF EXISTS "authenticated_update_whatsapp_messages" ON public.whatsapp_messages;
CREATE POLICY "authenticated_update_whatsapp_messages" ON public.whatsapp_messages
    FOR UPDATE TO authenticated
    USING (true);

DROP POLICY IF EXISTS "authenticated_delete_whatsapp_messages" ON public.whatsapp_messages;
CREATE POLICY "authenticated_delete_whatsapp_messages" ON public.whatsapp_messages
    FOR DELETE TO authenticated
    USING (true);

-- Conclusão da compilação DDL + RLS
