CREATE TABLE IF NOT EXISTS public.user_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profile_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
  login_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_activity_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  logout_at TIMESTAMPTZ,
  date DATE NOT NULL DEFAULT CURRENT_DATE
);

ALTER TABLE public.user_sessions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "admin_select_user_sessions" ON public.user_sessions;
CREATE POLICY "admin_select_user_sessions" ON public.user_sessions
  FOR SELECT TO authenticated USING (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE profiles.id = auth.uid() AND profiles.role IN ('Admin', 'ADM', 'admin')
    )
  );

DROP POLICY IF EXISTS "users_select_own_sessions" ON public.user_sessions;
CREATE POLICY "users_select_own_sessions" ON public.user_sessions
  FOR SELECT TO authenticated USING (profile_id = auth.uid());

DROP POLICY IF EXISTS "users_insert_own_sessions" ON public.user_sessions;
CREATE POLICY "users_insert_own_sessions" ON public.user_sessions
  FOR INSERT TO authenticated WITH CHECK (profile_id = auth.uid());

DROP POLICY IF EXISTS "users_update_own_sessions" ON public.user_sessions;
CREATE POLICY "users_update_own_sessions" ON public.user_sessions
  FOR UPDATE TO authenticated USING (profile_id = auth.uid());
