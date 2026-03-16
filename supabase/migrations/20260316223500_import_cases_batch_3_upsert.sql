-- Create missing clients first to ensure cases.clientId is not null,
-- which prevents the handle_new_case_task trigger from failing since tasks.clientId is NOT NULL.
INSERT INTO public.clients (name, document, type, status)
SELECT DISTINCT v.client_name, md5(v.client_name || gen_random_uuid()::text), 'PF', 'Ativo'
FROM (
  VALUES
    ('ELAINE MENDES LOIOLA'),
    ('LUIZ HENRIQUE DE SOUZA SILVA'),
    ('LUCAS BLEME POLICARPO'),
    ('FERNANDA ANTONIO RAMALHO FERNANDES'),
    ('FABIO SAMPAIO ALVES SOARES'),
    ('LUIZ OTÁVIO OLIVEIRA SILVA'),
    ('DANIEL MARTINS DA SILVA'),
    ('BRUNO MARCOS DE SÁ DIAS'),
    ('SILVESTRE DIAS'),
    ('SIRVANIL LUCIANO DA CONCEIÇÃO'),
    ('JULIANA MARIA DA CRUZ PEREIRA'),
    ('CONDOMÍNIO DO EDIFÍCIO SÃO PEDRO RESIDENCE'),
    ('ROSILENE TEODORO'),
    ('RENATO ALVES VALADARES'),
    ('SARA CHRISTINA DA SILVA LEMOS'),
    ('GABRIEL LÁZARO GONÇALVES DA SILVA'),
    ('FABIO ALVIM FERREIRA'),
    ('GUSTAVO FERREIRA GOSLING'),
    ('DENISE REGINA FARIA XAVIER'),
    ('CONDOMÍNIO DO EDIFÍCIO PAULO VI'),
    ('CLEBER PEREIRA MARTINS'),
    ('BRUNO SGROMO VIEIRA'),
    ('AVENINA ALEXANDRA DOS SANTOS ROCH'),
    ('ESPÓLIO VANDEIR RODRIGUES FERREIRA'),
    ('PATRÍCIA SILVA MARIA')
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
    ('1001239-21.2026.8.13.0148', 'ELAINE MENDES LOIOLA', 'Indenizatória', 'em_andamento', 'autor', 'RODRIGO CONSTANTINO ABDALA', 'JUIZADO ESPECIAL CIVEL', 'Lagoa Santa', '11306.32', '2026-03-13'),
    ('0', 'LUIZ HENRIQUE DE SOUZA SILVA', 'Indenizatória', 'aguardando_documentos', 'autor', 'ALAMO PROTEÇÃO VEICULAR', '', '', '', ''),
    ('2041989', 'LUCAS BLEME POLICARPO', 'Divórcio e União Estável', 'aguardando_documentos', 'autor', '', 'EXTRAJUDICIAL - CART. JAGUARÃO + CART. 2º Subsdistrito', 'Belo Horizonte', '0', '2026-03-12'),
    ('5010663-72.2025.8.13.0271', 'FERNANDA ANTONIO RAMALHO FERNANDES', 'Indenizatória', 'em_andamento', 'reu', 'TOKIO MARINE SEGURADORA S.A.', '1ª Vara Cível', 'Frutal', '52322.54', '2025-10-23'),
    ('AT01191787', 'FABIO SAMPAIO ALVES SOARES', 'Outros', 'em_andamento', 'autor', 'DETRAN-MG', '', 'Vespasiano', '', '2025-09-23'),
    ('AT01186163', 'LUIZ OTÁVIO OLIVEIRA SILVA', 'Outros', 'em_andamento', 'autor', 'DETRAN-MG', '', 'Vespasiano', '', '2025-10-03'),
    ('AT01269570', 'DANIEL MARTINS DA SILVA', 'Outros', 'em_andamento', 'autor', 'DETRAN-MG', '', 'Vespasiano', '', '2026-02-13'),
    ('C40361826', 'BRUNO MARCOS DE SÁ DIAS', 'Outros', 'em_andamento', 'autor', 'DETRAN-RJ', '', 'MACAÉ', '', '2024-01-08'),
    ('3801282-26.2013.8.13.0024', 'SILVESTRE DIAS', 'Inventário', 'em_andamento', 'inventariante', 'ALBINO COSTA DIAS', '3ª Vara de Sucessões', 'Belo Horizonte', '1000', '2013-11-12'),
    ('5010156-19.2024.8.13.0313', 'SIRVANIL LUCIANO DA CONCEIÇÃO', 'Inventário', 'em_andamento', 'inventariante', 'AGUINALDO FIRMO DA CONCEIÇÃO', '1ª VARA DE FAMÍLIA E SUCESSÕES', 'Ipatinga', '1000', '2024-05-10'),
    ('1008059-69.2026.8.13.0079', 'JULIANA MARIA DA CRUZ PEREIRA', 'Alimentos', 'em_andamento', 'autor', 'PEDRO HENRIQUE XAVIER LOPES', '1ª VARA DE FAMÍLIA', 'CONTAGEM', '1621', '2026-03-11'),
    ('1039714-30.2026.8.13.0024', 'CONDOMÍNIO DO EDIFÍCIO SÃO PEDRO RESIDENCE', 'Outros', 'em_andamento', 'autor', 'RICARDO RIOS PINHEIRO', '24ª VARA CÍVEL', 'BELO HORIZONTE', '10000', '2026-03-11'),
    ('5027974-51.2017.8.13.0079', 'ROSILENE TEODORO', 'Alimentos', 'em_andamento', 'autor', 'THIAGO AMORIM', '2ª Vara de Família', 'Belo Horizonte', '1000', '2017-12-11'),
    ('5090344-66.2019.8.13.0024', 'RENATO ALVES VALADARES', 'Divórcio e União Estável', 'em_andamento', 'reu', 'JANAINA FATIMA SOTTE', '2ª VARA DE FAMÍLIA', 'Belo Horizonte', '1000', '2019-05-22'),
    ('1060017-02.2025.8.13.0024', 'SARA CHRISTINA DA SILVA LEMOS', 'Alimentos', 'em_andamento', 'autor', 'MATHEUS DE ALMEIDA', '2ª VARA DE FAMÍLIA', 'Belo Horizonte', '1000', '2025-09-30'),
    ('5205743-41.2022.8.13.0024', 'GABRIEL LÁZARO GONÇALVES DA SILVA', 'Anulatória', 'em_andamento', 'reu', 'JULIANO NUNES DE PAULA', '27ª Vara Cível', 'Belo Horizonte', '40000', '2022-09-26'),
    ('1077168-78.2025.8.13.0024', 'FABIO ALVIM FERREIRA', 'Inventário', 'em_andamento', 'inventariante', 'ESPOLIO DE ZAIRA MARQUEZANI', '4 VARA DE SUCESSÕES', 'Belo Horizonte', '1000', '2025-10-27'),
    ('6367849-74.2025.4.06.3800', 'FABIO ALVIM FERREIRA', 'Indenizatória', 'em_andamento', 'autor', 'CAIXA ECONOMICA FEDERAL', '6 VARA CÍVEL JUIZADO ESPECIAL FEDERAL', 'Belo Horizonte', '47400', '2025-10-02'),
    ('1012506-08.2025.8.13.0024', 'FABIO ALVIM FERREIRA', 'Inventário', 'em_andamento', 'inventariante', 'ESPÓLIO DE JOSÉ ISAIAS FERREIRA', '3ª Vara de Sucessões', 'Belo Horizonte', '1000', '2025-05-23'),
    ('0024797-43.2023.8.27.2706', 'GUSTAVO FERREIRA GOSLING', 'Indenizatória', 'concluído', 'autor', 'PROVI', 'JUIZADO ESPECIAL CIVEL', 'ARAGUAINA', '15534.85', '2023-11-28'),
    ('0001500-70.2024.8.27.2706', 'GUSTAVO FERREIRA GOSLING', 'Indenizatória', 'concluído', 'autor', 'MUNICIPIO DE ARAGUAINA', 'JUIZADO ESPECIAL DA FAZENDA', 'ARAGUAINA', '1173', '2024-01-26'),
    ('0017122-9.2023.8.27.2706', 'GUSTAVO FERREIRA GOSLING', 'Indenizatória', 'em_andamento', 'autor', 'C6 BANK', 'JUIZADO ESPECIAL CIVEL', 'ARAGUAINA', '22073.17', '2023-08-15'),
    ('1002505-61.2025.8.13.0024', 'DENISE REGINA FARIA XAVIER', 'Indenizatória', 'em_andamento', 'autor', 'HURB', '13 VARA CIVEL', 'Belo Horizonte', '17700.4', '2025-07-16'),
    ('1015939-20.2025.8.13.0024', 'CONDOMÍNIO DO EDIFÍCIO PAULO VI', 'Indenizatória', 'concluído', 'autor', 'Copasa', 'JUIZADO ESPECIAL DA FAZENDA', 'Belo Horizonte', '4055.46', '2025-06-04'),
    ('0010639-93.2018.5.03.0016', 'CLEBER PEREIRA MARTINS', 'Reclamatória trabalhista', 'concluído', 'reclamante', 'SPINEA DO BRASIL', '16 VARA DO TRABALHO', 'Belo Horizonte', '30721.18', '2018-08-06'),
    ('0709741-09.2023.8.07.0014', 'BRUNO SGROMO VIEIRA', 'Indenizatória', 'concluído', 'autor', '123 milhas', 'JUIZADO ESPECIAL CIVEL', 'GUARÁ', '31058.1', '2023-10-03'),
    ('0750661-19.2023.8.07.0016', 'BRUNO SGROMO VIEIRA', 'Indenizatória', 'concluído', 'autor', '123 milhas', 'JUIZADO ESPECIAL CIVEL', 'GUARÁ', '5832', '2023-08-17'),
    ('0011008-92.2024.5.03.0108', 'AVENINA ALEXANDRA DOS SANTOS ROCH', 'Reclamatória trabalhista', 'concluído', 'autor', 'MARISTA', '29ª VARA DO TRABALHO', 'BELO HORIZONTE', '123724.51', '2024-11-05'),
    ('5129337-42.2023.8.13.0024', 'ESPÓLIO VANDEIR RODRIGUES FERREIRA', 'Inventário', 'em_andamento', 'autor', '', '3ª Vara de Sucessões', 'Belo Horizonte', '1000', '2023-06-15'),
    ('0803660-23.2026.8.19.0205', 'PATRÍCIA SILVA MARIA', 'Outros', 'aguardando_documentos', 'autor', 'AZUL SEGUROS', '26º JUIZADO ESPECIAL CÍVEL DA REGIONAL DE CAMPO GRANDE', 'RIO DE JANEIRO', '16805', '2026-03-04')
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
