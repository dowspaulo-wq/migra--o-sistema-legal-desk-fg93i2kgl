-- Ensure signature_photos bucket exists in storage.buckets
INSERT INTO storage.buckets (id, name, public)
VALUES ('signature_photos', 'signature_photos', true)
ON CONFLICT (id) DO UPDATE SET public = true;

-- Ensure signature_drawings bucket exists
INSERT INTO storage.buckets (id, name, public)
VALUES ('signature_drawings', 'signature_drawings', true)
ON CONFLICT (id) DO UPDATE SET public = true;

-- Ensure signature_documents bucket exists
INSERT INTO storage.buckets (id, name, public)
VALUES ('signature_documents', 'signature_documents', true)
ON CONFLICT (id) DO UPDATE SET public = true;

-- Storage policies for signature_photos
DROP POLICY IF EXISTS "Public Select Signature Photos" ON storage.objects;
CREATE POLICY "Public Select Signature Photos" ON storage.objects
  FOR SELECT TO public USING (bucket_id = 'signature_photos');

DROP POLICY IF EXISTS "Anon Insert Signature Photos" ON storage.objects;
CREATE POLICY "Anon Insert Signature Photos" ON storage.objects
  FOR INSERT TO public WITH CHECK (bucket_id = 'signature_photos');

DROP POLICY IF EXISTS "Authenticated Insert Signature Photos" ON storage.objects;
CREATE POLICY "Authenticated Insert Signature Photos" ON storage.objects
  FOR INSERT TO authenticated WITH CHECK (bucket_id = 'signature_photos');
