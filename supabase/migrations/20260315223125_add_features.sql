CREATE TABLE IF NOT EXISTS public.whatsapp_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  phone TEXT NOT NULL,
  contact_name TEXT NOT NULL,
  message TEXT NOT NULL,
  direction TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Seed some mock WhatsApp messages
INSERT INTO public.whatsapp_messages (phone, contact_name, message, direction)
VALUES 
('5511999999999', 'Empresa Alpha Ltda', 'Olá, gostaria de saber o andamento do meu processo.', 'inbound'),
('5511999999999', 'Empresa Alpha Ltda', 'Olá! O seu processo 0001234-56.2023.8.26.0100 encontra-se Em andamento. Última atualização: 2023-10-01.', 'outbound');
