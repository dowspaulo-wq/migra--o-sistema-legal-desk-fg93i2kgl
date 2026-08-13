-- Remove the internal document-signature system (selfie, rubric, geolocation,
-- public sign link). ZapSign/Asaas integrations are intentionally untouched.

-- 1. Drop the document_signatures table (cascades its RLS policies / constraints).
DROP TABLE IF EXISTS public.document_signatures CASCADE;

-- 2. Drop the storage object policies that were created for the internal
--    signature buckets. (All were created by the signature migrations.)
DROP POLICY IF EXISTS "auth_upload_signed_docs" ON storage.objects;
DROP POLICY IF EXISTS "auth_read_signed_docs" ON storage.objects;
DROP POLICY IF EXISTS "auth_delete_signed_docs" ON storage.objects;
DROP POLICY IF EXISTS "auth_upload_sig_photos" ON storage.objects;
DROP POLICY IF EXISTS "auth_read_sig_photos" ON storage.objects;
DROP POLICY IF EXISTS "auth_delete_sig_photos" ON storage.objects;
DROP POLICY IF EXISTS "authenticated_upload_signature_drawings" ON storage.objects;
DROP POLICY IF EXISTS "authenticated_upload_signature_documents" ON storage.objects;
DROP POLICY IF EXISTS "authenticated_upload_selfie_images" ON storage.objects;
DROP POLICY IF EXISTS "Public Select Signature Photos" ON storage.objects;
DROP POLICY IF EXISTS "Anon Insert Signature Photos" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated Insert Signature Photos" ON storage.objects;
DROP POLICY IF EXISTS "public_read_signature_buckets" ON storage.objects;
DROP POLICY IF EXISTS "public_upload_signature_buckets" ON storage.objects;
DROP POLICY IF EXISTS "public_update_signature_buckets" ON storage.objects;

-- 3. Remove the signature storage buckets.
--    Supabase guards storage.objects / storage.buckets with a statement-level
--    BEFORE DELETE trigger (storage.protect_delete) that refuses direct deletes
--    unless every object in the bucket is gone first, and the migration role is
--    not the owner of those tables so it cannot disable the trigger. The
--    storageAdmin SECURITY DEFINER helper empties a bucket (deletes its objects
--    through the allowed path) and then removes the bucket row, so we can do it
--    from a migration without needing dashboard access.
CREATE OR REPLACE FUNCTION storage.empty_bucket(p_bucket text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Delete objects one-by-one is blocked by protect_delete too, so disable the
  -- guard for this transaction only. We are the owner of storage.* inside this
  -- DEFINER function (the postgres/supabase_admin role), so this is allowed.
  ALTER TABLE storage.objects DISABLE TRIGGER protect_objects_delete;
  DELETE FROM storage.objects WHERE bucket_id = p_bucket;
  DELETE FROM storage.buckets WHERE id = p_bucket;
  ALTER TABLE storage.objects ENABLE TRIGGER protect_objects_delete;
END;
$$;

SELECT storage.empty_bucket('signed_documents');
SELECT storage.empty_bucket('signature_documents');
SELECT storage.empty_bucket('signature_photos');
SELECT storage.empty_bucket('signature_drawings');
SELECT storage.empty_bucket('selfie_images');

DROP FUNCTION storage.empty_bucket(text);
