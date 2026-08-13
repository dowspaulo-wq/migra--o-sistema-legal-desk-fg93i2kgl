-- Remove the internal document-signature system (selfie, rubric, geolocation,
-- public sign link). ZapSign/Asaas integrations are intentionally untouched.
--
-- This migration ONLY drops the public.document_signatures table. It does NOT
-- touch the storage schema (storage.buckets / storage.objects) in any way —
-- those are guarded by Supabase and touching them causes "permission denied".
-- The signature buckets (if any) remain as-is; they are simply unused now.

-- 1. Drop the table. CASCADE removes its RLS policies, indexes and constraints.
DROP TABLE IF EXISTS public.document_signatures CASCADE;

-- 2. Repair user_sessions rows corrupted by the Acessos bug: a heartbeat kept
--    writing last_activity_at AFTER the session had already been closed, so
--    some rows have last_activity_at > logout_at. Normalise last_activity_at
--    back to the logout time so the Acessos timeline is coherent again.
UPDATE public.user_sessions
SET last_activity_at = logout_at
WHERE logout_at IS NOT NULL
  AND last_activity_at > logout_at;
