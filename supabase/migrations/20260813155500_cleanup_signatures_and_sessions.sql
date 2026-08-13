-- Remove document_signatures table if exists
DROP TABLE IF EXISTS public.document_signatures CASCADE;

-- Clean up any lingering open sessions in user_sessions that have been inactive for more than 10 minutes or from previous days
-- Note: Do not touch storage schema or storage.buckets as per instructions
DO $$
BEGIN
  UPDATE public.user_sessions
  SET logout_at = COALESCE(last_activity_at, login_at)
  WHERE logout_at IS NULL
    AND (
      date < CURRENT_DATE
      OR last_activity_at < NOW() - INTERVAL '10 minutes'
    );
END $$;
