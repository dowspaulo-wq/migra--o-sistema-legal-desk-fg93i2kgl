ALTER TABLE public.document_signatures ADD COLUMN IF NOT EXISTS signature_path TEXT;

INSERT INTO storage.buckets (id, name, public)
VALUES ('signature_drawings', 'signature_drawings', true)
ON CONFLICT (id) DO NOTHING;

INSERT INTO storage.buckets (id, name, public)
VALUES ('signature_documents', 'signature_documents', true)
ON CONFLICT (id) DO NOTHING;

INSERT INTO storage.buckets (id, name, public)
VALUES ('selfie_images', 'selfie_images', true)
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS "authenticated_upload_signature_drawings" ON storage.objects;
CREATE POLICY "authenticated_upload_signature_drawings" ON storage.objects
  FOR INSERT TO authenticated WITH CHECK (bucket_id = 'signature_drawings');

DROP POLICY IF EXISTS "authenticated_upload_signature_documents" ON storage.objects;
CREATE POLICY "authenticated_upload_signature_documents" ON storage.objects
  FOR INSERT TO authenticated WITH CHECK (bucket_id = 'signature_documents');

DROP POLICY IF EXISTS "authenticated_upload_selfie_images" ON storage.objects;
CREATE POLICY "authenticated_upload_selfie_images" ON storage.objects
  FOR INSERT TO authenticated WITH CHECK (bucket_id = 'selfie_images');
