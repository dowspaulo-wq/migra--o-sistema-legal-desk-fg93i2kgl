-- Create missing clients first to ensure cases.clientId is not null,
-- which prevents the handle_new_case_task trigger from failing since tasks.clientId is NOT NULL.
INSERT INTO public.clients (name, document, type, status)
SELECT DISTINCT v.client_name, md5(v.client_name || gen_random_uuid()::text), 
  CASE WHEN v.client_name ILIKE '%COMÉRCIO%' THEN 'PJ' ELSE 'PF' END, 
  'Ativo'
FROM (
  VALUES
    ('IWI COMÉRCIO'),
    ('ISABELA FERNANDES MOL ROCHA'),
    ('HEDIO RODRIGUES DE ARAUJO'),
    ('GUSTAVO MENDES LOIOLA'),
    ('GUILHERME APARECIDO BATISTA')
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
    ('5206772-58.2024.8.13.0024', 'IWI COMÉRCIO', 'Outros', 'em_andamento', 'autor', 'JUAREZ AUGUSTO SILVEIRA DA SILVA', '7ª Unidade Jurisdicional Cível - 19º JD', 'Belo Horizonte', '860', '2024-08-21'),
    ('5042709-45.2024.8.13.0079', 'IWI COMÉRCIO', 'Outros', 'concluido', 'autor', 'ENI OLIVEIRA DE JESUS RODRIGUES', '1ª Unidade Jurisdicional - JESP - 1º JD', 'Contagem', '278', '2024-08-13'),
    ('5185441-20.2024.8.13.0024', 'IWI COMÉRCIO', 'Outros', 'em_andamento', 'autor', 'ANDREZA FERREIRA AUGUSTO e outro', '7ª Unidade Jurisdicional Cível - 19º JD', 'Belo Horizonte', '2851', '2024-07-26'),
    ('5182227-89.2022.8.13.0024', 'IWI COMÉRCIO', 'Outros', 'concluido', 'autor', 'FRANCISCO DO NASCIMENTO NUNES e outro', '7ª Unidade Jurisdicional Cível - 21º JD', 'Belo Horizonte', '2561', '2022-08-23'),
    ('5005568-31.2022.8.13.0024', 'IWI COMÉRCIO', 'Outros', 'concluido', 'autor', 'KARLA CRISTINA MOREIRA FERNANDES BARBOSA', '7ª Unidade Jurisdicional Cível - 21º JD', 'Belo Horizonte', '2550', '2022-01-13'),
    ('5005531-04.2022.8.13.0024', 'IWI COMÉRCIO', 'Outros', 'concluido', 'autor', 'JULIANA SOUZA SALVADO', '7ª Unidade Jurisdicional Cível - 21º JD', 'Belo Horizonte', '904', '2022-01-13'),
    ('5051336-48.2020.8.13.0024', 'IWI COMÉRCIO', 'Outros', 'em_andamento', 'autor', 'AMANDA NAJLA MURTA RIBEIRO', '7ª Unidade Jurisdicional Cível - 21º JD', 'Belo Horizonte', '1260', '2020-04-02'),
    ('5002665-38.2025.8.13.0567', 'ISABELA FERNANDES MOL ROCHA', 'Indenizatória', 'concluido', 'autor', 'AZUL LINHAS AÉREAS BRASILEIRAS S/A', 'Unidade Jurisdicional', 'Sabará', '15000', '2025-03-27'),
    ('5045365-09.2025.8.13.0024', 'HEDIO RODRIGUES DE ARAUJO', 'Indenizatória', 'em_andamento', 'autor', 'PAULO HENRIQUE RODRIGUES e outro', '4ª Unidade Jurisdicional Cível - 12º JD', 'Belo Horizonte', '59543.93', '2024-02-21'),
    ('5282013-72.2023.8.13.0024', 'HEDIO RODRIGUES DE ARAUJO', 'Indenizatória', 'concluido', 'autor', 'SOLERTIA RISUS SERVICOS ODONTOLOGICOS LTDA E OUTROS', '5ª Unidade Jurisdicional Cível - 15º JD', 'Belo Horizonte', '5154393', '2023-11-14'),
    ('5008020-59.2024.8.13.0148', 'GUSTAVO MENDES LOIOLA', 'Outros', 'concluido', 'autor', 'TAM LINHAS AEREAS S/A.', 'Unidade Jurisdicional', 'Lagoa Santa', '15000', '2024-10-01'),
    ('5057941-05.2023.8.13.0024', 'GUSTAVO MENDES LOIOLA', 'Outros', 'concluido', 'autor', 'CEMIG DISTRIBUIÇÃO S.A.', '5ª Unidade Jurisdicional Cível - 15º JD', 'Belo Horizonte', '1008604', '2023-03-20'),
    ('5259691-92.2022.8.13.0024', 'GUILHERME APARECIDO BATISTA', 'Indenizatória', 'concluido', 'autor', 'TOKIO MARINE SEGURADORA S.A.', '6ª Unidade Jurisdicional Cível - 16º JD', '', '0', '')
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
