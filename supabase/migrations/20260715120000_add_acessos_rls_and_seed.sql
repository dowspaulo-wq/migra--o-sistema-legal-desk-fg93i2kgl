-- Enable RLS on logs (idempotent)
ALTER TABLE public.logs ENABLE ROW LEVEL SECURITY;

-- Drop existing policies (idempotent)
DROP POLICY IF EXISTS "authenticated_select_logs" ON public.logs;
DROP POLICY IF EXISTS "authenticated_insert_logs" ON public.logs;
DROP POLICY IF EXISTS "authenticated_update_logs" ON public.logs;
DROP POLICY IF EXISTS "authenticated_delete_logs" ON public.logs;

-- SELECT: admin-only (role IN ('Admin', 'ADM', 'admin'))
CREATE POLICY "authenticated_select_logs" ON public.logs
  FOR SELECT TO authenticated USING (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE profiles.id = auth.uid()
        AND profiles.role IN ('Admin', 'ADM', 'admin')
    )
  );

-- INSERT: all authenticated users (so login/logout events can be recorded)
CREATE POLICY "authenticated_insert_logs" ON public.logs
  FOR INSERT TO authenticated WITH CHECK (true);

-- UPDATE: admin-only
CREATE POLICY "authenticated_update_logs" ON public.logs
  FOR UPDATE TO authenticated USING (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE profiles.id = auth.uid()
        AND profiles.role IN ('Admin', 'ADM', 'admin')
    )
  );

-- DELETE: admin-only
CREATE POLICY "authenticated_delete_logs" ON public.logs
  FOR DELETE TO authenticated USING (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE profiles.id = auth.uid()
        AND profiles.role IN ('Admin', 'ADM', 'admin')
    )
  );

-- Index for filtering by action (idempotent)
CREATE INDEX IF NOT EXISTS idx_logs_action ON public.logs (action);

-- Ensure douspaulo@gmail.com has Admin role (idempotent)
UPDATE public.profiles
SET role = 'Admin'
WHERE email = 'dowspaulo@gmail.com' AND role NOT IN ('Admin', 'ADM', 'admin');
