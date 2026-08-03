CREATE TABLE IF NOT EXISTS public.document_signatures (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  token TEXT NOT NULL UNIQUE,
  doc_type TEXT NOT NULL,
  client_id UUID REFERENCES public.clients(id) ON DELETE SET NULL,
  case_id UUID REFERENCES public.cases(id) ON DELETE SET NULL,
  document_path TEXT,
  selfie_path TEXT,
  geolocation JSONB,
  ip_address TEXT,
  user_agent TEXT,
  signed_at TIMESTAMPTZ,
  status TEXT NOT NULL DEFAULT 'pending',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_document_signatures_token ON public.document_signatures(token);

ALTER TABLE public.document_signatures ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "authenticated_select_document_signatures" ON public.document_signatures;
CREATE POLICY "authenticated_select_document_signatures" ON public.document_signatures
  FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "authenticated_insert_document_signatures" ON public.document_signatures;
CREATE POLICY "authenticated_insert_document_signatures" ON public.document_signatures
  FOR INSERT TO authenticated WITH CHECK (true);

DROP POLICY IF EXISTS "authenticated_update_document_signatures" ON public.document_signatures;
CREATE POLICY "authenticated_update_document_signatures" ON public.document_signatures
  FOR UPDATE TO authenticated USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "authenticated_delete_document_signatures" ON public.document_signatures;
CREATE POLICY "authenticated_delete_document_signatures" ON public.document_signatures
  FOR DELETE TO authenticated USING (true);

INSERT INTO storage.buckets (id, name, public)
VALUES ('signed_documents', 'signed_documents', true)
ON CONFLICT (id) DO NOTHING;

INSERT INTO storage.buckets (id, name, public)
VALUES ('signature_photos', 'signature_photos', true)
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS "auth_upload_signed_docs" ON storage.objects;
CREATE POLICY "auth_upload_signed_docs" ON storage.objects
  FOR INSERT TO authenticated WITH CHECK (bucket_id = 'signed_documents');

DROP POLICY IF EXISTS "auth_read_signed_docs" ON storage.objects;
CREATE POLICY "auth_read_signed_docs" ON storage.objects
  FOR SELECT USING (bucket_id = 'signed_documents');

DROP POLICY IF EXISTS "auth_delete_signed_docs" ON storage.objects;
CREATE POLICY "auth_delete_signed_docs" ON storage.objects
  FOR DELETE TO authenticated USING (bucket_id = 'signed_documents');

DROP POLICY IF EXISTS "auth_upload_sig_photos" ON storage.objects;
CREATE POLICY "auth_upload_sig_photos" ON storage.objects
  FOR INSERT TO authenticated WITH CHECK (bucket_id = 'signature_photos');

DROP POLICY IF EXISTS "auth_read_sig_photos" ON storage.objects;
CREATE POLICY "auth_read_sig_photos" ON storage.objects
  FOR SELECT USING (bucket_id = 'signature_photos');

DROP POLICY IF EXISTS "auth_delete_sig_photos" ON storage.objects;
CREATE POLICY "auth_delete_sig_photos" ON storage.objects
  FOR DELETE TO authenticated USING (bucket_id = 'signature_photos');
