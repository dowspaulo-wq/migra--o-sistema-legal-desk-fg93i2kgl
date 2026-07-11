DO $$
BEGIN
  -- Strips all non-numeric characters from client phone numbers to enforce standard
  UPDATE public.clients
  SET phone = regexp_replace(phone, '\D', '', 'g')
  WHERE phone ~ '\D';
END $$;
