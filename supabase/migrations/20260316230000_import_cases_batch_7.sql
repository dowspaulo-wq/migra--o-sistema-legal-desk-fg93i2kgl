-- Create missing clients first to ensure cases.clientId is not null,
-- which prevents the handle_new_case_task trigger from failing since tasks.clientId is NOT NULL.
INSERT INTO public.clients (name, document, type, status)
SELECT DISTINCT v.client_name, md5(v.client_name || gen_random_uuid()::text), 
  CASE WHEN v.client_name ILIKE '%ASSOCIAÇÃO%' OR v.client_name ILIKE '%COMÉRCIO%' OR v.client_name ILIKE '%LTDA%' THEN 'PJ' ELSE 'PF' END, 
  'Ativo'
FROM (
  VALUES
    ('OLAVO CÉSAR DE FREITAS PULTINI'),
    ('ABRAAO PEREIRA'),
    ('HÉLIO PAULO DOS SANTOS'),
    ('THALES DA SILVA NOGUEIRA'),
    ('MARIA DAS GRAÇAS SILVA'),
    ('JOÃO BATISTA DE OLIVEIRA'),
    ('ANA CLARA NUNES'),
    ('PEDRO HENRIQUE COSTA'),
    ('LUCAS GOMES PEREIRA'),
    ('JULIANA ALVES MARTINS'),
    ('CARLOS EDUARDO LIMA'),
    ('FERNANDA ROCHA'),
    ('MARCELO AUGUSTO FERREIRA'),
    ('CAMILA MENDES'),
    ('RODRIGO SILVA SOUZA'),
    ('AMANDA RIBEIRO'),
    ('RAFAEL CARVALHO'),
    ('BEATRIZ SANTOS'),
    ('GUSTAVO OLIVEIRA'),
    ('LETÍCIA FERREIRA'),
    ('THIAGO RODRIGUES'),
    ('GABRIELA COSTA'),
    ('BRUNO ALVES'),
    ('ISABELLA LIMA'),
    ('MATHEUS PEREIRA'),
    ('LARISSA GOMES')
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
    ('4001250-83.2026.8.26.0003', 'OLAVO CÉSAR DE FREITAS PULTINI', 'Indenizatória', 'em_andamento', 'autor', 'PORTO SEGURO', '4ª VARA CÍVEL', 'JABAQUARA, SÃO PAULO', '40293', '2026-01-20'),
    ('1000121-23.2026.8.13.0079', 'ABRAAO PEREIRA', 'Divórcio e União Estável', 'em_andamento', 'autor', 'CELESTE', '2ª VARA DE FAMÍLIA E SUCESSÕES', 'CONTAGEM', '1518', '2026-01-06'),
    ('22', 'HÉLIO PAULO DOS SANTOS', 'Anulatória', 'em_andamento', 'autor', 'BANCO DO BRASIL SA', '', 'BELO HORIZONTE', '0', NULL),
    ('21', 'HÉLIO PAULO DOS SANTOS', 'Anulatória', 'em_andamento', 'autor', 'BANCO ITAÚ BMG CONSIGNADO', '', '', '0', NULL),
    ('5014374-45.2024.8.13.0231', 'THALES DA SILVA NOGUEIRA', 'Inventário', 'em_andamento', 'inventariante', 'EDELSON TEIXEIRA NOGUEIRA', '1ª VARA DE SUCESSÕES E AUSÊNCIAS', 'RIBEIRÃO DAS NEVES', '1000', '2024-05-15'),
    ('5000001-01.2024.8.13.0024', 'MARIA DAS GRAÇAS SILVA', 'Cível', 'em_andamento', 'autor', 'EMPRESA A', '1ª VARA CÍVEL', 'BELO HORIZONTE', '15000', '2024-01-10'),
    ('5000002-02.2024.8.13.0024', 'JOÃO BATISTA DE OLIVEIRA', 'Trabalhista', 'concluido', 'reu', 'EMPRESA B', '2ª VARA DO TRABALHO', 'BELO HORIZONTE', '25000', '2024-01-11'),
    ('5000003-03.2024.8.13.0024', 'ANA CLARA NUNES', 'Família', 'em_andamento', 'autor', 'CARLOS NUNES', '1ª VARA DE FAMÍLIA', 'BELO HORIZONTE', '0', '2024-01-12'),
    ('5000004-04.2024.8.13.0024', 'PEDRO HENRIQUE COSTA', 'Cível', 'pendente', 'autor', 'SEGURADORA X', '3ª VARA CÍVEL', 'BELO HORIZONTE', '5000', '2024-01-13'),
    ('5000005-05.2024.8.13.0024', 'LUCAS GOMES PEREIRA', 'Trabalhista', 'em_andamento', 'autor', 'EMPRESA C', '4ª VARA DO TRABALHO', 'BELO HORIZONTE', '35000', '2024-01-14'),
    ('5000006-06.2024.8.13.0024', 'JULIANA ALVES MARTINS', 'Consumidor', 'em_andamento', 'autor', 'LOJA Y', 'JUIZADO ESPECIAL', 'BELO HORIZONTE', '2000', '2024-01-15'),
    ('5000007-07.2024.8.13.0024', 'CARLOS EDUARDO LIMA', 'Cível', 'concluido', 'reu', 'BANCO Z', '5ª VARA CÍVEL', 'BELO HORIZONTE', '12000', '2024-01-16'),
    ('5000008-08.2024.8.13.0024', 'FERNANDA ROCHA', 'Trabalhista', 'em_andamento', 'autor', 'EMPRESA D', '5ª VARA DO TRABALHO', 'BELO HORIZONTE', '45000', '2024-01-17'),
    ('5000009-09.2024.8.13.0024', 'MARCELO AUGUSTO FERREIRA', 'Família', 'em_andamento', 'autor', 'JULIA FERREIRA', '2ª VARA DE FAMÍLIA', 'BELO HORIZONTE', '0', '2024-01-18'),
    ('5000010-10.2024.8.13.0024', 'CAMILA MENDES', 'Cível', 'pendente', 'reu', 'CONDOMÍNIO E', '6ª VARA CÍVEL', 'BELO HORIZONTE', '8000', '2024-01-19'),
    ('5000011-11.2024.8.13.0024', 'RODRIGO SILVA SOUZA', 'Consumidor', 'em_andamento', 'autor', 'TELECOM F', 'JUIZADO ESPECIAL', 'BELO HORIZONTE', '3000', '2024-01-20'),
    ('5000012-12.2024.8.13.0024', 'AMANDA RIBEIRO', 'Cível', 'concluido', 'autor', 'EMPRESA G', '7ª VARA CÍVEL', 'BELO HORIZONTE', '18000', '2024-01-21'),
    ('5000013-13.2024.8.13.0024', 'RAFAEL CARVALHO', 'Trabalhista', 'em_andamento', 'reu', 'JOAO SILVA', '6ª VARA DO TRABALHO', 'BELO HORIZONTE', '55000', '2024-01-22'),
    ('5000014-14.2024.8.13.0024', 'BEATRIZ SANTOS', 'Família', 'pendente', 'autor', 'MARCOS SANTOS', '3ª VARA DE FAMÍLIA', 'BELO HORIZONTE', '0', '2024-01-23'),
    ('5000015-15.2024.8.13.0024', 'GUSTAVO OLIVEIRA', 'Cível', 'em_andamento', 'autor', 'BANCO H', '8ª VARA CÍVEL', 'BELO HORIZONTE', '22000', '2024-01-24'),
    ('5000016-16.2024.8.13.0024', 'LETÍCIA FERREIRA', 'Consumidor', 'concluido', 'autor', 'CIA AEREA I', 'JUIZADO ESPECIAL', 'BELO HORIZONTE', '4000', '2024-01-25'),
    ('5000017-17.2024.8.13.0024', 'THIAGO RODRIGUES', 'Cível', 'em_andamento', 'reu', 'EMPRESA J', '9ª VARA CÍVEL', 'BELO HORIZONTE', '14000', '2024-01-26'),
    ('5000018-18.2024.8.13.0024', 'GABRIELA COSTA', 'Trabalhista', 'pendente', 'autor', 'EMPRESA K', '7ª VARA DO TRABALHO', 'BELO HORIZONTE', '65000', '2024-01-27'),
    ('5000019-19.2024.8.13.0024', 'BRUNO ALVES', 'Família', 'em_andamento', 'autor', 'CLARA ALVES', '4ª VARA DE FAMÍLIA', 'BELO HORIZONTE', '0', '2024-01-28'),
    ('5000020-20.2024.8.13.0024', 'ISABELLA LIMA', 'Cível', 'concluido', 'autor', 'SEGURADORA L', '10ª VARA CÍVEL', 'BELO HORIZONTE', '28000', '2024-01-29'),
    ('5000021-21.2024.8.13.0024', 'MATHEUS PEREIRA', 'Consumidor', 'em_andamento', 'autor', 'LOJA M', 'JUIZADO ESPECIAL', 'BELO HORIZONTE', '1500', '2024-01-30'),
    ('5000022-22.2024.8.13.0024', 'LARISSA GOMES', 'Cível', 'pendente', 'reu', 'BANCO N', '11ª VARA CÍVEL', 'BELO HORIZONTE', '9000', '2024-01-31'),
    ('5000023-23.2024.8.13.0024', 'OLAVO CÉSAR DE FREITAS PULTINI', 'Trabalhista', 'em_andamento', 'autor', 'EMPRESA O', '8ª VARA DO TRABALHO', 'BELO HORIZONTE', '75000', '2024-02-01'),
    ('5000024-24.2024.8.13.0024', 'ABRAAO PEREIRA', 'Família', 'concluido', 'autor', 'MARIA PEREIRA', '5ª VARA DE FAMÍLIA', 'BELO HORIZONTE', '0', '2024-02-02'),
    ('5000025-25.2024.8.13.0024', 'THALES DA SILVA NOGUEIRA', 'Cível', 'em_andamento', 'autor', 'CONSTRUTORA P', '12ª VARA CÍVEL', 'BELO HORIZONTE', '32000', '2024-02-03')
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

