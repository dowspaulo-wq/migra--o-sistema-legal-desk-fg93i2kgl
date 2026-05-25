DROP POLICY IF EXISTS "authenticated_update_profiles" ON public.profiles;

CREATE POLICY "authenticated_update_profiles" ON public.profiles
  FOR UPDATE TO authenticated
  USING (
    auth.uid() = id OR 
    EXISTS (
      SELECT 1 FROM public.profiles p 
      WHERE p.id = auth.uid() AND p.role = 'Admin'
    )
  )
  WITH CHECK (
    auth.uid() = id OR 
    EXISTS (
      SELECT 1 FROM public.profiles p 
      WHERE p.id = auth.uid() AND p.role = 'Admin'
    )
  );
