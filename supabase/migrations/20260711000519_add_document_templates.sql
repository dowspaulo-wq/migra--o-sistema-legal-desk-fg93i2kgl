CREATE TABLE IF NOT EXISTS public.document_templates (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  file_path TEXT NOT NULL,
  category TEXT DEFAULT 'Geral',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.document_templates ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "authenticated_select_document_templates" ON public.document_templates;
CREATE POLICY "authenticated_select_document_templates" ON public.document_templates
  FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "authenticated_insert_document_templates" ON public.document_templates;
CREATE POLICY "authenticated_insert_document_templates" ON public.document_templates
  FOR INSERT TO authenticated WITH CHECK (true);

DROP POLICY IF EXISTS "authenticated_delete_document_templates" ON public.document_templates;
CREATE POLICY "authenticated_delete_document_templates" ON public.document_templates
  FOR DELETE TO authenticated USING (true);

INSERT INTO storage.buckets (id, name, public)
VALUES ('document_templates', 'document_templates', true)
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS "authenticated_upload_document_templates_bucket" ON storage.objects;
CREATE POLICY "authenticated_upload_document_templates_bucket" ON storage.objects
  FOR INSERT TO authenticated WITH CHECK (bucket_id = 'document_templates');

DROP POLICY IF EXISTS "authenticated_read_document_templates_bucket" ON storage.objects;
CREATE POLICY "authenticated_read_document_templates_bucket" ON storage.objects
  FOR SELECT TO authenticated USING (bucket_id = 'document_templates');

DROP POLICY IF EXISTS "authenticated_delete_document_templates_bucket" ON storage.objects;
CREATE POLICY "authenticated_delete_document_templates_bucket" ON storage.objects
  FOR DELETE TO authenticated USING (bucket_id = 'document_templates');
