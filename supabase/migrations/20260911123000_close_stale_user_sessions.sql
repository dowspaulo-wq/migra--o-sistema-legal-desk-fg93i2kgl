-- Encerrar sessões da tabela user_sessions que estejam com status "Em andamento" (logout_at IS NULL)
-- mas sem heartbeat/atividade recente (mais de 2 horas sem atividade ou de dias anteriores).
-- Isso libera Douglas, Fernanda e todos os demais usuários cujas sessões tenham ficado presas.

DO $$
BEGIN
  UPDATE public.user_sessions
  SET logout_at = COALESCE(last_activity_at, login_at, NOW())
  WHERE logout_at IS NULL
    AND (
      date < CURRENT_DATE
      OR last_activity_at < NOW() - INTERVAL '2 hours'
      OR login_at < NOW() - INTERVAL '2 hours'
    );
END $$;
