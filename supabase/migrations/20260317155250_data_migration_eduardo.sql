-- Migrate Eduardo's user data completely and establish virtual birthdays safely
DO $$
DECLARE
    old_id uuid := 'c48d2037-9cd0-49c3-bd3c-f9b9abc2188e'::uuid;
    new_id uuid := '8914e17d-64ce-4acc-88ab-5fc04f11ac24'::uuid;
BEGIN
    -- Update all foreign keys mapped to the old profile
    UPDATE public.tasks SET "responsibleId" = new_id WHERE "responsibleId" = old_id;
    UPDATE public.appointments SET "responsibleId" = new_id WHERE "responsibleId" = old_id;
    UPDATE public.cases SET "responsibleId" = new_id WHERE "responsibleId" = old_id;
    UPDATE public.clients SET "responsibleId" = new_id WHERE "responsibleId" = old_id;

    -- Ensure the display name correctly reflects the identity
    UPDATE public.profiles SET name = 'Eduardo' WHERE id = new_id;
END $$;

-- Drop legacy triggers and functions related to physical creation of birthday appointments
-- This ensures the client profile data drives virtual calendar rendering via frontend logic.
DROP TRIGGER IF EXISTS on_client_birthday_change ON public.clients;
DROP FUNCTION IF EXISTS public.handle_client_birthday();

-- Remove any old explicit physical appointments representing birthdays
DELETE FROM public.appointments WHERE type = 'Aniversário';
