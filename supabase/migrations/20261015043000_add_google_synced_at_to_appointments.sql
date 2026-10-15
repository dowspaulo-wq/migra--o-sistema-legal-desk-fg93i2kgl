-- Migração para suporte à sincronização bidirecional inteligente com o Google Calendar
-- Adiciona a coluna google_synced_at para rastrear quando um compromisso foi sincronizado pela última vez com o Google Agenda.
-- Com essa coluna e a coluna updated_at existente, o algoritmo de sincronização detecta se o compromisso local
-- sofreu edições após a última sincronização (updated_at > google_synced_at). Nesse caso, a alteração local
-- vence e é exportada (PATCH/UPDATE) para o Google Calendar, impedindo que o evento antigo do Google reverta a edição.

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'appointments'
      AND column_name = 'google_synced_at'
  ) THEN
    ALTER TABLE public.appointments ADD COLUMN google_synced_at TIMESTAMPTZ;
  END IF;
END $$;

-- Atualiza compromissos que já possuem googleEventId para ter google_synced_at = updated_at (ou created_at)
-- como baseline inicial seguro, a menos que tenham sido editados recentemente
UPDATE public.appointments
SET google_synced_at = COALESCE(updated_at, created_at, NOW())
WHERE "googleEventId" IS NOT NULL AND google_synced_at IS NULL;

-- Garante índice para consultas eficientes na sincronização
CREATE INDEX IF NOT EXISTS idx_appointments_google_synced_at ON public.appointments(google_synced_at);
