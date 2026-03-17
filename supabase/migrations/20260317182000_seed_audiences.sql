DO $$
DECLARE
  v_user_id uuid;
BEGIN
  -- Find an active user to assign the test appointments
  SELECT id INTO v_user_id FROM public.profiles LIMIT 1;

  IF v_user_id IS NOT NULL THEN
    INSERT INTO public.appointments (title, date, time, type, priority, modality, "responsibleId", description)
    VALUES
      ('Audiência de Conciliação - Caso Silva', to_char(now() + interval '1 day', 'YYYY-MM-DD'), '14:00', 'Aud.conciliação', 'Alta', 'Virtual', v_user_id, 'Link do Teams: https://meet.google.com/...'),
      ('AIJ - Testemunhas Oliveira', to_char(now() + interval '3 days', 'YYYY-MM-DD'), '09:30', 'AIJ', 'Urgente', 'Presencial', v_user_id, 'Levar os documentos impressos originais.'),
      ('Reunião de Alinhamento Inicial', to_char(now() + interval '2 days', 'YYYY-MM-DD'), '10:00', 'Reunião', 'Média', 'Virtual', v_user_id, 'Discutir honorários e estratégia com o cliente.'),
      ('Despacho com Juiz', to_char(now() + interval '4 days', 'YYYY-MM-DD'), '15:00', 'Outro', 'Alta', 'Presencial', v_user_id, 'No Fórum Central.');
  END IF;
END $$;
