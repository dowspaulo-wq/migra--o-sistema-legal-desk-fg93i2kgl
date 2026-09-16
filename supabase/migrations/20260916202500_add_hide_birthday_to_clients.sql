-- Add hide_birthday column to public.clients table
ALTER TABLE public.clients
  ADD COLUMN IF NOT EXISTS hide_birthday BOOLEAN NOT NULL DEFAULT false;

COMMENT ON COLUMN public.clients.hide_birthday IS 'When true, client birthday is not displayed on calendars/agenda.';
