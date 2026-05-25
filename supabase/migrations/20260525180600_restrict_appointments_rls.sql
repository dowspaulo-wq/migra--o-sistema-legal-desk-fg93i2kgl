DO $$
BEGIN
  -- Restrict SELECT on appointments to Admins only
  DROP POLICY IF EXISTS "authenticated_select_appointments" ON public.appointments;
  CREATE POLICY "authenticated_select_appointments" ON public.appointments
    FOR SELECT TO authenticated 
    USING (
      EXISTS (SELECT 1 FROM profiles WHERE profiles.id = auth.uid() AND profiles.role = 'Admin')
    );

  -- Restrict INSERT on appointments to Admins only
  DROP POLICY IF EXISTS "authenticated_insert_appointments" ON public.appointments;
  CREATE POLICY "authenticated_insert_appointments" ON public.appointments
    FOR INSERT TO authenticated 
    WITH CHECK (
      EXISTS (SELECT 1 FROM profiles WHERE profiles.id = auth.uid() AND profiles.role = 'Admin')
    );

  -- Restrict UPDATE on appointments to Admins only
  DROP POLICY IF EXISTS "authenticated_update_appointments" ON public.appointments;
  CREATE POLICY "authenticated_update_appointments" ON public.appointments
    FOR UPDATE TO authenticated 
    USING (
      EXISTS (SELECT 1 FROM profiles WHERE profiles.id = auth.uid() AND profiles.role = 'Admin')
    )
    WITH CHECK (
      EXISTS (SELECT 1 FROM profiles WHERE profiles.id = auth.uid() AND profiles.role = 'Admin')
    );
END $$;
