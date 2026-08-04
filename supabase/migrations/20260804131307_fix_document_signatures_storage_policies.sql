-- Enable RLS policies on public.document_signatures for anon and authenticated users
DROP POLICY IF EXISTS "public_select_document_signatures" ON public.document_signatures;
DROP POLICY IF EXISTS "authenticated_select_document_signatures" ON public.document_signatures;
CREATE POLICY "public_select_document_signatures" ON public.document_signatures
  FOR SELECT TO anon, authenticated USING (true);

DROP POLICY IF EXISTS "public_update_document_signatures" ON public.document_signatures;
DROP POLICY IF EXISTS "authenticated_update_document_signatures" ON public.document_signatures;
CREATE POLICY "public_update_document_signatures" ON public.document_signatures
  FOR UPDATE TO anon, authenticated USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "authenticated_insert_document_signatures" ON public.document_signatures;
CREATE POLICY "authenticated_insert_document_signatures" ON public.document_signatures
  FOR INSERT TO anon, authenticated WITH CHECK (true);

-- Ensure storage buckets exist and are marked as public
INSERT INTO storage.buckets (id, name, public)
VALUES
  ('signed_documents', 'signed_documents', true),
  ('signature_photos', 'signature_photos', true),
  ('signature_drawings', 'signature_drawings', true),
  ('signature_documents', 'signature_documents', true),
  ('selfie_images', 'selfie_images', true),
  ('documents', 'documents', true)
ON CONFLICT (id) DO UPDATE SET public = true;

-- Storage object policies for signature and document buckets
DROP POLICY IF EXISTS "public_read_signature_buckets" ON storage.objects;
CREATE POLICY "public_read_signature_buckets" ON storage.objects
  FOR SELECT TO anon, authenticated
  USING (bucket_id IN ('signed_documents', 'signature_photos', 'signature_drawings', 'signature_documents', 'selfie_images', 'documents'));

DROP POLICY IF EXISTS "public_upload_signature_buckets" ON storage.objects;
CREATE POLICY "public_upload_signature_buckets" ON storage.objects
  FOR INSERT TO anon, authenticated
  WITH CHECK (bucket_id IN ('signed_documents', 'signature_photos', 'signature_drawings', 'signature_documents', 'selfie_images', 'documents'));

DROP POLICY IF EXISTS "public_update_signature_buckets" ON storage.objects;
CREATE POLICY "public_update_signature_buckets" ON storage.objects
  FOR UPDATE TO anon, authenticated
  USING (bucket_id IN ('signed_documents', 'signature_photos', 'signature_drawings', 'signature_documents', 'selfie_images', 'documents'));
