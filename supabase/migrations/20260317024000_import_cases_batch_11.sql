-- 1. Ensure `document` column in `clients` table is nullable to allow records without document
ALTER TABLE public.clients ALTER COLUMN document DROP NOT NULL;

-- 2. Insert missing clients automatically associating the correct type based on name
INSERT INTO public.clients (name, type, status)
SELECT DISTINCT v.client_name, 
  CASE 
    WHEN v.client_name ILIKE '%ASSOCIAÇÃO%' 
      OR v.client_name ILIKE '%COMÉRCIO%' 
      OR v.client_name ILIKE '%LTDA%' 
      OR v.client_name ILIKE '%CONDOMINIO%' 
      OR v.client_name ILIKE '%CONDOMÍNIO%' 
      OR v.client_name ILIKE '%COMUNIDADE%' 
      OR v.client_name ILIKE '%SERVIÇO%' 
    THEN 'PJ' 
    ELSE 'PF' 
  END, 
  'Ativo'
FROM (
  VALUES
    ('LUIZ HENRIQUE DE SOUZA SILVA'),
    ('DOUGLAS PAULO DOS SANTOS'),
    ('TATIANE ELIAS SILVEIRA'),
    ('HÉLIO PAULO DOS SANTOS'),
    ('THIAGO FILIPE DE MOR')
) AS v(client_name)
WHERE NOT EXISTS (SELECT 1 FROM public.clients c WHERE c.name = v.client_name);

-- 3. Upsert cases, applying necessary data transformations and constraints
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
  -- Clean up comarca spacing and add missing commas before State abbreviations (e.g. "BELO HORIZONTE MG" to "BELO HORIZONTE, MG")
  NULLIF(REGEXP_REPLACE(TRIM(v.comarca), '\s+([A-Za-z]{2})$', ', \1'), ''),
  -- Clean up monetary values by stripping dots and using a dot as decimal separator
  COALESCE(NULLIF(REPLACE(REPLACE(v.value, '.', ''), ',', '.'), ''), '0')::numeric,
  -- Safely convert dates from DD/MM/YYYY to YYYY-MM-DD
  CASE 
    WHEN v.startDate = '' OR v.startDate IS NULL THEN NULL 
    ELSE to_char(to_date(v.startDate, 'DD/MM/YYYY'), 'YYYY-MM-DD') 
  END
FROM (
  VALUES
    ('0', 'LUIZ HENRIQUE DE SOUZA SILVA', 'Indenizatória', 'aguardando_documentos', 'autor', 'ALAMO PROTEÇÃO VEICULAR', '', '', '', ''),
    ('4', 'DOUGLAS PAULO DOS SANTOS', 'Indenizatória', 'em_andamento', 'autor', 'FIES', '', '', '', ''),
    ('20', 'TATIANE ELIAS SILVEIRA', 'Indenizatória', 'aguardando_documentos', 'autor', '', '', '', '', ''),
    ('22', 'HÉLIO PAULO DOS SANTOS', 'Anulatória', 'em_andamento', 'autor', 'BANCO DO BRASIL SA', '', 'BELO HORIZONTE', '', ''),
    ('78', 'THIAGO FILIPE DE MOR', 'Indenizatória', 'em_andamento', 'autor', '', '', '', '', '')
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
