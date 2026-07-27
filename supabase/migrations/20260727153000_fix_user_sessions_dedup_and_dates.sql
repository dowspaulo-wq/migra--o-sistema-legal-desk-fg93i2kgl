-- Clean up duplicate session entries created within 10 seconds for the same profile
DO $$
BEGIN
  WITH ranked_sessions AS (
    SELECT
      id,
      profile_id,
      login_at,
      logout_at,
      ROW_NUMBER() OVER (
        PARTITION BY profile_id, date_trunc('minute', login_at), floor(EXTRACT(SECOND FROM login_at) / 10)
        ORDER BY 
          CASE WHEN logout_at IS NULL THEN 0 ELSE 1 END,
          last_activity_at DESC,
          id DESC
      ) AS rn
    FROM public.user_sessions
  )
  DELETE FROM public.user_sessions
  WHERE id IN (
    SELECT id FROM ranked_sessions WHERE rn > 1
  );
END $$;

-- Ensure date column matches the local Brazilian timezone date derived from login_at
UPDATE public.user_sessions
SET date = (login_at AT TIME ZONE 'America/Sao_Paulo')::date
WHERE date != (login_at AT TIME ZONE 'America/Sao_Paulo')::date;
