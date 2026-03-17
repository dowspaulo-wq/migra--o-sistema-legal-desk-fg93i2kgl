-- Migrate Eduardo's user data
DO $$
DECLARE
    old_id uuid := 'c48d2037-9cd0-49c3-bd3c-f9b9abc2188e'::uuid;
    new_id uuid := '8914e17d-64ce-4acc-88ab-5fc04f11ac24'::uuid;
BEGIN
    -- Update tasks
    UPDATE public.tasks SET "responsibleId" = new_id WHERE "responsibleId" = old_id;
    -- Update appointments
    UPDATE public.appointments SET "responsibleId" = new_id WHERE "responsibleId" = old_id;
    -- Update cases
    UPDATE public.cases SET "responsibleId" = new_id WHERE "responsibleId" = old_id;
    -- Update clients
    UPDATE public.clients SET "responsibleId" = new_id WHERE "responsibleId" = old_id;

    -- Update profile name for the new account
    UPDATE public.profiles SET name = 'Eduardo' WHERE id = new_id;
END $$;

-- Drop trigger and function related to physical birthday appointments creation
DROP TRIGGER IF EXISTS on_client_birthday_change ON public.clients;
DROP FUNCTION IF EXISTS public.handle_client_birthday();

-- Remove any existing physical 'Aniversário' appointments as they will now be virtualized
DELETE FROM public.appointments WHERE type = 'Aniversário';
