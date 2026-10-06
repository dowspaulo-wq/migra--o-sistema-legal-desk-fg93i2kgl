-- ==============================================================================
-- DPSjur - Políticas de RLS (Row Level Security) Consolidadas (57 Políticas)
-- Gerado para: Fase 4 da Migração para Supabase Self-Hosted (EasyPanel)
-- Origem: Projeto SBJur (cpcafthwnqazopqftemj)
-- Data: 2026-10-06 / 2026-10-07
-- Contém: Ativação de RLS nas 17 tabelas do schema public e recriação das 57 políticas.
-- ==============================================================================

-- 1. APPOINTMENTS (5 políticas)
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

-- 2. BACKUP_LOGS (2 políticas)
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

-- 3. CASE_SYSTEMS (4 políticas)
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

-- 4. CASES (5 políticas)
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

-- 5. CLIENTS (5 políticas)
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

-- 6. DOCUMENT_TEMPLATES (3 políticas)
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

-- 7. LOGS (4 políticas)
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

-- 8. PETITIONS (1 política)
ALTER TABLE public.petitions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "petitions_authenticated_all" ON public.petitions;
CREATE POLICY "petitions_authenticated_all" ON public.petitions
    FOR ALL TO authenticated
    USING (true)
    WITH CHECK (true);

-- 9. PROFILES (2 políticas)
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

-- 10. SETTINGS (4 políticas)
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

-- 11. SUPPLIERS (4 políticas)
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

-- 12. TASKS (5 políticas)
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

-- 13. TRANSACTION_CASES (4 políticas)
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

-- 14. TRANSACTIONS (1 política)
ALTER TABLE public.transactions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "transactions_authenticated_all" ON public.transactions;
CREATE POLICY "transactions_authenticated_all" ON public.transactions
    FOR ALL TO authenticated
    USING (true)
    WITH CHECK (true);

-- 15. USER_SESSIONS (4 políticas)
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

-- 16. WHATSAPP_MESSAGES (4 políticas)
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
