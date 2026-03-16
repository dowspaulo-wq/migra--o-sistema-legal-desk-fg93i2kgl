-- Create missing clients first to ensure cases.clientId is not null
INSERT INTO public.clients (name, document, type, status)
SELECT DISTINCT v.client_name, md5(v.client_name || gen_random_uuid()::text), 'PF', 'Ativo'
FROM (
  VALUES
    -- REPLACE WITH YOUR 29 CLIENT NAMES HERE
    ('CLIENTE MOCK LOTE 4')
) AS v(client_name)
WHERE NOT EXISTS (SELECT 1 FROM public.clients c WHERE c.name = v.client_name);

-- Insert or update cases with correct date format and ON CONFLICT handling
INSERT INTO public.cases (
  number,
  "clientId",
  type,
  status,
  position,
  "adverseParty",
  court,
  comarca,
  value,
  "startDate"
)
SELECT
  v.number,
  c.id,
  NULLIF(TRIM(v.type), ''),
  NULLIF(TRIM(v.status), ''),
  NULLIF(TRIM(v.position), ''),
  NULLIF(TRIM(v.adverseParty), ''),
  NULLIF(TRIM(v.court), ''),
  NULLIF(TRIM(v.comarca), ''),
  COALESCE(NULLIF(TRIM(v.value), ''), '0')::numeric,
  NULLIF(TRIM(v.startDate), '')
FROM (
  VALUES
    -- REPLACE WITH YOUR 29 CASES HERE
    -- Format: (number, client_name, type, status, position, adverseParty, court, comarca, value, startDate)
    ('0000000-00.2026.8.00.0000', 'CLIENTE MOCK LOTE 4', 'Indenizatória', 'em_andamento', 'autor', 'PARTE ADVERSA MOCK', 'VARA MOCK', 'COMARCA MOCK', '15000', '2026-03-16')
) AS v(number, client_name, type, status, position, adverseParty, court, comarca, value, startDate)
LEFT JOIN public.clients c ON c.name = v.client_name
ON CONFLICT (number) DO UPDATE SET
  "clientId" = EXCLUDED."clientId",
  type = EXCLUDED.type,
  status = EXCLUDED.status,
  position = EXCLUDED.position,
  "adverseParty" = EXCLUDED."adverseParty",
  court = EXCLUDED.court,
  comarca = EXCLUDED.comarca,
  value = EXCLUDED.value,
  "startDate" = EXCLUDED."startDate";

