-- Enable public SELECT and UPDATE on document_signatures for unauthenticated signers
DROP POLICY IF EXISTS "public_select_document_signatures" ON public.document_signatures;
DROP POLICY IF EXISTS "authenticated_select_document_signatures" ON public.document_signatures;
CREATE POLICY "public_select_document_signatures" ON public.document_signatures
  FOR SELECT TO anon, authenticated USING (true);

DROP POLICY IF EXISTS "public_update_document_signatures" ON public.document_signatures;
DROP POLICY IF EXISTS "authenticated_update_document_signatures" ON public.document_signatures;
CREATE POLICY "public_update_document_signatures" ON public.document_signatures
  FOR UPDATE TO anon, authenticated USING (true) WITH CHECK (true);

-- Ensure storage buckets exist
INSERT INTO storage.buckets (id, name, public)
VALUES
  ('signed_documents', 'signed_documents', true),
  ('signature_photos', 'signature_photos', true),
  ('signature_drawings', 'signature_drawings', true),
  ('signature_documents', 'signature_documents', true),
  ('selfie_images', 'selfie_images', true)
ON CONFLICT (id) DO NOTHING;

-- Public storage permissions for signature attachments
DROP POLICY IF EXISTS "public_upload_signature_buckets" ON storage.objects;
CREATE POLICY "public_upload_signature_buckets" ON storage.objects
  FOR INSERT TO anon, authenticated
  WITH CHECK (bucket_id IN ('signed_documents', 'signature_photos', 'signature_drawings', 'signature_documents', 'selfie_images'));

DROP POLICY IF EXISTS "public_read_signature_buckets" ON storage.objects;
CREATE POLICY "public_read_signature_buckets" ON storage.objects
  FOR SELECT TO anon, authenticated
  USING (bucket_id IN ('signed_documents', 'signature_photos', 'signature_drawings', 'signature_documents', 'selfie_images'));
