DO $$
DECLARE
    default_client_id uuid;
BEGIN
    -- Check if there are any appointments missing a clientId
    IF EXISTS (SELECT 1 FROM public.appointments WHERE "clientId" IS NULL) THEN
        -- Try to find an existing active client to assign them to
        SELECT id INTO default_client_id FROM public.clients LIMIT 1;
        
        -- If no clients exist at all, create a generic one
        IF default_client_id IS NULL THEN
            INSERT INTO public.clients (name, type, status, "isSpecial")
            VALUES ('Cliente Genérico', 'PF', 'Ativo', false)
            RETURNING id INTO default_client_id;
        END IF;

        -- Update orphaned appointments with the selected client
        UPDATE public.appointments
        SET "clientId" = default_client_id
        WHERE "clientId" IS NULL;
    END IF;
END $$;

-- Enforce the constraint ensuring future appointments are securely linked
ALTER TABLE public.appointments ALTER COLUMN "clientId" SET NOT NULL;
