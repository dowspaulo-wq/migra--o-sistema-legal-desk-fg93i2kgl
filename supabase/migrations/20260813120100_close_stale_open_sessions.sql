-- Repair the Acessos tracking: close every user_sessions row that is still
-- marked "open" (logout_at IS NULL) from before today. This clears the stale
-- sessions that prevented new logins from creating their own row (the dedup
-- logic reused the first open session it found), so the fix in use-auth can
-- take effect and new accesses start being recorded again.
UPDATE public.user_sessions
SET
  logout_at = COALESCE(logout_at, last_activity_at, now()),
  last_activity_at = COALESCE(last_activity_at, now())
WHERE logout_at IS NULL
  AND date < CURRENT_DATE;
