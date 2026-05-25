DO $$
BEGIN
  -- Cases policies
  DROP POLICY IF EXISTS "authenticated_select_cases" ON public.cases;
  CREATE POLICY "authenticated_select_cases" ON public.cases FOR SELECT TO authenticated USING (true);
  DROP POLICY IF EXISTS "authenticated_insert_cases" ON public.cases;
  CREATE POLICY "authenticated_insert_cases" ON public.cases FOR INSERT TO authenticated WITH CHECK (true);
  DROP POLICY IF EXISTS "authenticated_update_cases" ON public.cases;
  CREATE POLICY "authenticated_update_cases" ON public.cases FOR UPDATE TO authenticated USING (true) WITH CHECK (true);
  DROP POLICY IF EXISTS "authenticated_delete_cases" ON public.cases;
  CREATE POLICY "authenticated_delete_cases" ON public.cases FOR DELETE TO authenticated 
    USING (EXISTS (SELECT 1 FROM public.profiles WHERE profiles.id = auth.uid() AND profiles.role = 'Admin'));

  -- Clients policies
  DROP POLICY IF EXISTS "authenticated_select_clients" ON public.clients;
  CREATE POLICY "authenticated_select_clients" ON public.clients FOR SELECT TO authenticated USING (true);
  DROP POLICY IF EXISTS "authenticated_insert_clients" ON public.clients;
  CREATE POLICY "authenticated_insert_clients" ON public.clients FOR INSERT TO authenticated WITH CHECK (true);
  DROP POLICY IF EXISTS "authenticated_update_clients" ON public.clients;
  CREATE POLICY "authenticated_update_clients" ON public.clients FOR UPDATE TO authenticated USING (true) WITH CHECK (true);
  DROP POLICY IF EXISTS "authenticated_delete_clients" ON public.clients;
  CREATE POLICY "authenticated_delete_clients" ON public.clients FOR DELETE TO authenticated 
    USING (EXISTS (SELECT 1 FROM public.profiles WHERE profiles.id = auth.uid() AND profiles.role = 'Admin'));

  -- Tasks policies
  DROP POLICY IF EXISTS "authenticated_select_tasks" ON public.tasks;
  CREATE POLICY "authenticated_select_tasks" ON public.tasks FOR SELECT TO authenticated USING (true);
  DROP POLICY IF EXISTS "authenticated_insert_tasks" ON public.tasks;
  CREATE POLICY "authenticated_insert_tasks" ON public.tasks FOR INSERT TO authenticated WITH CHECK (true);
  DROP POLICY IF EXISTS "authenticated_update_tasks" ON public.tasks;
  CREATE POLICY "authenticated_update_tasks" ON public.tasks FOR UPDATE TO authenticated USING (true) WITH CHECK (true);
  DROP POLICY IF EXISTS "authenticated_delete_tasks" ON public.tasks;
  CREATE POLICY "authenticated_delete_tasks" ON public.tasks FOR DELETE TO authenticated 
    USING (EXISTS (SELECT 1 FROM public.profiles WHERE profiles.id = auth.uid() AND profiles.role = 'Admin'));

  -- Appointments policies
  DROP POLICY IF EXISTS "authenticated_select_appointments" ON public.appointments;
  CREATE POLICY "authenticated_select_appointments" ON public.appointments FOR SELECT TO authenticated USING (true);
  DROP POLICY IF EXISTS "authenticated_insert_appointments" ON public.appointments;
  CREATE POLICY "authenticated_insert_appointments" ON public.appointments FOR INSERT TO authenticated WITH CHECK (true);
  DROP POLICY IF EXISTS "authenticated_update_appointments" ON public.appointments;
  CREATE POLICY "authenticated_update_appointments" ON public.appointments FOR UPDATE TO authenticated USING (true) WITH CHECK (true);
  DROP POLICY IF EXISTS "authenticated_delete_appointments" ON public.appointments;
  CREATE POLICY "authenticated_delete_appointments" ON public.appointments FOR DELETE TO authenticated 
    USING (EXISTS (SELECT 1 FROM public.profiles WHERE profiles.id = auth.uid() AND profiles.role = 'Admin'));
END $$;

DO $$
DECLARE
  new_user_id uuid;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM auth.users WHERE email = 'dowspaulo@gmail.com') THEN
    new_user_id := gen_random_uuid();
    INSERT INTO auth.users (
      id, instance_id, email, encrypted_password, email_confirmed_at,
      created_at, updated_at, raw_app_meta_data, raw_user_meta_data,
      is_super_admin, role, aud,
      confirmation_token, recovery_token, email_change_token_new,
      email_change, email_change_token_current,
      phone, phone_change, phone_change_token, reauthentication_token
    ) VALUES (
      new_user_id,
      '00000000-0000-0000-0000-000000000000',
      'dowspaulo@gmail.com',
      crypt('Skip@Pass', gen_salt('bf')),
      NOW(), NOW(), NOW(),
      '{"provider": "email", "providers": ["email"]}',
      '{"name": "Admin", "role": "Admin"}',
      false, 'authenticated', 'authenticated',
      '', '', '', '', '',
      NULL, '', '', ''
    );

    INSERT INTO public.profiles (id, email, name, role, "canViewFinance", color)
    VALUES (new_user_id, 'dowspaulo@gmail.com', 'Administrador', 'Admin', true, '#ef4444')
    ON CONFLICT (id) DO UPDATE SET role = 'Admin';
  ELSE
    UPDATE public.profiles 
    SET role = 'Admin' 
    WHERE email = 'dowspaulo@gmail.com';
  END IF;
END $$;
