-- Add phone_na, email_na, no_phone, no_email columns to clients table
ALTER TABLE public.clients
  ADD COLUMN IF NOT EXISTS phone_na BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS email_na BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS no_phone BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS no_email BOOLEAN NOT NULL DEFAULT false;

-- Comment describing purpose
COMMENT ON COLUMN public.clients.phone_na IS 'Indicates phone is not applicable (e.g. for PJ clients)';
COMMENT ON COLUMN public.clients.email_na IS 'Indicates email is not applicable (e.g. for PJ clients)';
COMMENT ON COLUMN public.clients.no_phone IS 'Indicates client has no phone';
COMMENT ON COLUMN public.clients.no_email IS 'Indicates client has no email';

-- Requirement 2: Mark 'não se aplica' (phone_na = true, email_na = true) on all existing PJ clients
UPDATE public.clients
SET phone_na = true, email_na = true
WHERE type = 'PJ';
