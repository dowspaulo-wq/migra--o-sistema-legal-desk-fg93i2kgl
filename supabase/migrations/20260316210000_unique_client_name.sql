-- Add unique index for client names to prevent duplicates
CREATE UNIQUE INDEX IF NOT EXISTS clients_name_key ON public.clients (name);

ALTER TABLE public.clients DROP CONSTRAINT IF EXISTS clients_name_key;
ALTER TABLE public.clients ADD CONSTRAINT clients_name_key UNIQUE USING INDEX clients_name_key;

-- Ensure RLS policies are enabled and basic policies exist for clients and cases
ALTER TABLE public.clients ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cases ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'clients' AND policyname = 'authenticated_select_clients') THEN
        CREATE POLICY "authenticated_select_clients" ON public.clients FOR SELECT TO authenticated USING (true);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'clients' AND policyname = 'authenticated_insert_clients') THEN
        CREATE POLICY "authenticated_insert_clients" ON public.clients FOR INSERT TO authenticated WITH CHECK (true);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'clients' AND policyname = 'authenticated_update_clients') THEN
        CREATE POLICY "authenticated_update_clients" ON public.clients FOR UPDATE TO authenticated USING (true) WITH CHECK (true);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'clients' AND policyname = 'authenticated_delete_clients') THEN
        CREATE POLICY "authenticated_delete_clients" ON public.clients FOR DELETE TO authenticated USING (true);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'cases' AND policyname = 'authenticated_select_cases') THEN
        CREATE POLICY "authenticated_select_cases" ON public.cases FOR SELECT TO authenticated USING (true);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'cases' AND policyname = 'authenticated_insert_cases') THEN
        CREATE POLICY "authenticated_insert_cases" ON public.cases FOR INSERT TO authenticated WITH CHECK (true);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'cases' AND policyname = 'authenticated_update_cases') THEN
        CREATE POLICY "authenticated_update_cases" ON public.cases FOR UPDATE TO authenticated USING (true) WITH CHECK (true);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'cases' AND policyname = 'authenticated_delete_cases') THEN
        CREATE POLICY "authenticated_delete_cases" ON public.cases FOR DELETE TO authenticated USING (true);
    END IF;
END
$$;
