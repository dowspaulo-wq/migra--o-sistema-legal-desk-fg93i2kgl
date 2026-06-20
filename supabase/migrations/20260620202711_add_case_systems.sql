CREATE TABLE IF NOT EXISTS public.case_systems (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL UNIQUE,
  image_url TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.case_systems ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "authenticated_select_case_systems" ON public.case_systems;
CREATE POLICY "authenticated_select_case_systems" ON public.case_systems FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "authenticated_insert_case_systems" ON public.case_systems;
CREATE POLICY "authenticated_insert_case_systems" ON public.case_systems FOR INSERT TO authenticated WITH CHECK (true);

DROP POLICY IF EXISTS "authenticated_update_case_systems" ON public.case_systems;
CREATE POLICY "authenticated_update_case_systems" ON public.case_systems FOR UPDATE TO authenticated USING (true);

DROP POLICY IF EXISTS "authenticated_delete_case_systems" ON public.case_systems;
CREATE POLICY "authenticated_delete_case_systems" ON public.case_systems FOR DELETE TO authenticated USING (true);

INSERT INTO public.case_systems (name) VALUES
  ('E-PROC'),
  ('PJE'),
  ('PROJUDI'),
  ('DETRAN')
ON CONFLICT (name) DO NOTHING;

-- Storage
INSERT INTO storage.buckets (id, name, public) 
VALUES ('case-systems', 'case-systems', true)
ON CONFLICT (id) DO UPDATE SET public = EXCLUDED.public;

DROP POLICY IF EXISTS "case_systems_public_read" ON storage.objects;
CREATE POLICY "case_systems_public_read" ON storage.objects FOR SELECT USING (bucket_id = 'case-systems');

DROP POLICY IF EXISTS "case_systems_auth_insert" ON storage.objects;
CREATE POLICY "case_systems_auth_insert" ON storage.objects FOR INSERT TO authenticated WITH CHECK (bucket_id = 'case-systems');

DROP POLICY IF EXISTS "case_systems_auth_update" ON storage.objects;
CREATE POLICY "case_systems_auth_update" ON storage.objects FOR UPDATE TO authenticated USING (bucket_id = 'case-systems');

DROP POLICY IF EXISTS "case_systems_auth_delete" ON storage.objects;
CREATE POLICY "case_systems_auth_delete" ON storage.objects FOR DELETE TO authenticated USING (bucket_id = 'case-systems');
