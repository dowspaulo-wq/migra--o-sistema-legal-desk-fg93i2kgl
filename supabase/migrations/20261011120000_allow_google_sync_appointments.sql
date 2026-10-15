-- Migração para permitir criação flexível de compromissos vindos da sincronização do Google Calendar
-- 1. Garante cliente padrão para sincronização se não existir
DO $$
DECLARE
    google_sync_client_id uuid;
BEGIN
    SELECT id INTO google_sync_client_id FROM public.clients WHERE name = 'Sincronização Google' LIMIT 1;
    IF google_sync_client_id IS NULL THEN
        INSERT INTO public.clients (name, type, status, "isSpecial", observacoes)
        VALUES ('Sincronização Google', 'PJ', 'Ativo', false, 'Cliente gerado automaticamente para compromissos importados do Google Calendar sem cliente vinculado.')
        RETURNING id INTO google_sync_client_id;
    END IF;

    -- Define o valor padrão da coluna clientId como o ID deste cliente do Google
    EXECUTE format('ALTER TABLE public.appointments ALTER COLUMN "clientId" SET DEFAULT %L', google_sync_client_id);
    -- Torna clientId nullable para máxima resiliência (se algum fluxo tentar inserir null, adota o default ou null)
    ALTER TABLE public.appointments ALTER COLUMN "clientId" DROP NOT NULL;
END $$;

-- 2. Assegura política para service_role e authenticated em appointments
-- A Edge function no VPS que roda com chave do usuário ou com anon precisa conseguir operar
DO $$
BEGIN
    -- Garante que RLS permite operações da Edge Function quando autenticada
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies 
        WHERE tablename = 'appointments' AND policyname = 'appointments_service_role_all'
    ) THEN
        CREATE POLICY appointments_service_role_all ON public.appointments
            FOR ALL TO service_role
            USING (true)
            WITH CHECK (true);
    END IF;
END $$;
