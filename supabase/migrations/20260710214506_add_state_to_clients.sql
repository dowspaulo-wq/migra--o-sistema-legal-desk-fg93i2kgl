-- Add state (UF) column to clients table
ALTER TABLE public.clients ADD COLUMN IF NOT EXISTS state TEXT;

-- RLS policies already exist for clients (authenticated_select/insert/update/delete)
-- No additional policies needed since they use USING (true) / WITH CHECK (true)
