-- Create missing clients first to ensure cases.clientId is not null,
-- which prevents the handle_new_case_task trigger from failing since tasks.clientId is NOT NULL.
INSERT INTO public.clients (name, document, type, status)
SELECT DISTINCT v.client_name, md5(v.client_name || gen_random_uuid()::text), 
  CASE WHEN v.client_name ILIKE '%ASSOCIAÇÃO%' OR v.client_name ILIKE '%COMÉRCIO%' OR v.client_name ILIKE '%LTDA%' OR v.client_name ILIKE '%CONDOMINIO%' OR v.client_name ILIKE '%CONDOMÍNIO%' OR v.client_name ILIKE '%COMUNIDADE%' OR v.client_name ILIKE '%SERVIÇO%' THEN 'PJ' ELSE 'PF' END, 
  'Ativo'
FROM (
  VALUES
    ('DOUGLAS PAULO DOS SANTOS'),
    ('FERNANDO XAVIER VENTURA JUNIOR'),
    ('ADELMA GONCALVES SANTOS'),
    ('INFORCOPY BRASIL COMERCIO E SERVIÇO'),
    ('ISAIAS MORAIS DOS SANTOS'),
    ('GERALDO PASCOAL FILHO'),
    ('LEANDRO DA SILVA GUEDES'),
    ('ILISEA ANDREAS NISSEN'),
    ('MARCIO LUIZ MARTINS JUNIOR'),
    ('ROSILDA FERREIRA NUNES'),
    ('ADILIO VERISSIMO ALTAIR'),
    ('DOMITILA ETELVINA MARTINS DE FREITAS'),
    ('DANIEL LUCAS SILVA LOPES'),
    ('BRENDA DEBOSSAM SILVA ASSIS'),
    ('NAYARA CRISTINA BARROS GONCALVES e outros'),
    ('ROSA MARIA DE ASSIS MAGELA'),
    ('FRANCIMAR APARECIDA CUNHA DA SILVA'),
    ('CLARICE LAGARES ESPINDOLA COSTA'),
    ('WALERSON JOSÉ DA CONCEIÇÃO VALENTIM'),
    ('HERLEY DO CARMO GAMA PEREIRA'),
    ('THALES DA SILVA NOGUEIRA'),
    ('CYNTIA PATRICIA DE LIMA'),
    ('NATALIA DE SOUZA BORGES'),
    ('GIOVANNA MARCELLE PINHEIRO RAMOS'),
    ('AMANDA NATIELLE FERREIRA LOPES'),
    ('VINICIIRA TEIXEIRA VALADARES PALHARES'),
    ('JOSÉ CARLOS AMANCIO DE ALMEIDA')
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
  NULLIF(v.type, ''),
  NULLIF(v.status, ''),
  NULLIF(v.position, ''),
  NULLIF(v.adverseParty, ''),
  NULLIF(v.court, ''),
  NULLIF(v.comarca, ''),
  COALESCE(NULLIF(v.value, ''), '0')::numeric,
  NULLIF(v.startDate, '')
FROM (
  VALUES
    ('5287528-54.2024.8.13.0024', 'DOUGLAS PAULO DOS SANTOS', 'Outros', 'em_andamento', 'autor', '', '2ª VARA EMPRESARIAL', 'BELO HORIZONTE, MG', '1518', '2024-11-08'),
    ('5119003-22.2018.8.13.0024', 'FERNANDO XAVIER VENTURA JUNIOR', 'Indenizatória', 'em_andamento', 'reu', 'IGOR GOMES', '1ª VARA CÍVEL', 'BELO HORIZONTE, MG', '60000', '2018-08-27'),
    ('6035823-96.2025.4.06.3800', 'ADELMA GONCALVES SANTOS', 'Previdenciário', 'em_andamento', 'autor', 'INSS', '19ª VARA CÍVEL E JEF ADJUNTO', 'BELO HORIZONTE, MG', '1518', '2025-05-06'),
    ('5000930-51.2025.8.13.0346', 'ADELMA GONCALVES SANTOS', 'Indenizatória', 'em_andamento', 'autor', 'SANTOS MARCELO FERNANDO PEREIRA DA SILVA e outros', 'VARA ÚNICA', 'ESMERALDAS, MG', '150000', '2025-05-08'),
    ('5015631-71.2025.8.13.0231', 'INFORCOPY BRASIL COMERCIO E SERVIÇO', 'Indenizatória', 'em_andamento', 'autor', 'SPE EMPREENDIMENTO LOTEAMENTO BAIRRO JARDINS LTDA', 'UNIDADE JURISDICIONAL 2º JD', 'RIBEIRÃO DAS NEVES, MG', '30552', '2025-06-07'),
    ('6392997-87.2025.4.06.3800', 'ISAIAS MORAIS DOS SANTOS', 'Previdenciário', 'em_andamento', 'autor', 'INSS', '2ª VARA CÍVEL E JEF ADJUNTO', 'BELO HORIZONTE, MG', '27324', '2025-11-18'),
    ('5101398-87.2023.8.13.0024', 'GERALDO PASCOAL FILHO', 'Indenizatória', 'em_andamento', 'autor', 'UNIMED RIO COOPERATIVA DE TRABALHO MEDICO DO RIO DE JANEIRO LTDA', '2ª VARA CÍVEL', 'BELO HORIZONTE, MG', '30000', '2024-03-26'),
    ('0822901-26.2025.8.19.0202', 'LEANDRO DA SILVA GUEDES', 'Indenizatória', 'em_andamento', '', 'BRADESCO AUTO RE COMPANHIA DE SEGUROS', '15º JUIZADO ESPECIAL CÍVEL', 'MADUREIRA, RJ', '25000', '2025-11-18'),
    ('5014309-10.2023.8.21.0022', 'ILISEA ANDREAS NISSEN', 'Indenizatória', 'em_andamento', 'reu', 'LUIZA JARDIM DA CUNHA SARAIVA', '1º JUÍZO DA 2ª VARA CÍVEL', 'PELOTAS, RS', '30000', '2023-05-05'),
    ('5013452-09.2025.8.13.0024', 'MARCIO LUIZ MARTINS JUNIOR', 'Indenizatória', 'em_andamento', 'autor', 'VINICIUS ARAUJO ANTUNES e outros', '9ª UNIDADE JURISDICIONAL CÍVE- 27º JD', 'BELO HORIZONTE, MG', '60.72', '2025-10-02'),
    ('1000875-95.2025.8.13.0241', 'ROSILDA FERREIRA NUNES', 'Indenizatória', 'em_andamento', 'autor', '58.934.098 EVELYN BIANCA SANTOS RODRIGUES', '1º JUIZADO ESPECIAL CÍVEL', 'ESMERALDAS, MG', '15200', '2025-11-17'),
    ('5035788-07.2023.8.13.0079', 'ADILIO VERISSIMO ALTAIR', 'Indenizatória', 'suspenso', 'autor', 'BANCO BRADESCO S.A.', '2ª UNIDADE JURISDICIONAL - JESP - 3º JD', 'CONTAGEM, MG', '12529.8', '2023-07-20'),
    ('5074162-29.2024.8.13.0024', 'GERALDO PASCOAL FILHO', 'Indenizatória', 'em_andamento', 'autor', 'UNIMED', '2ª VARA CÍVEL', 'BELO HORIZONTE, MG', '30000', '2024-04-26'),
    ('5086082-44.2017.8.13.0024', 'GERALDO PASCOAL FILHO', 'Indenizatória', 'em_andamento', 'exequente', 'UNIMED', 'CENTRASE', 'BELO HORIZONTE, MG', '197514.38', '2017-06-26'),
    ('5308439-24.2023.8.13.0024', 'DOMITILA ETELVINA MARTINS DE FREITAS', 'Indenizatória', 'concluido', 'autor', 'BANCO SOFISA SA', '9ª UNIDADE JURISDICIONAL CÍVE- 26º JD', 'BELO HORIZONTE, MG', '31000', '2023-12-19'),
    ('5038197-53.2025.8.13.0024', 'DANIEL LUCAS SILVA LOPES', 'Indenizatória', 'em_andamento', 'autor', 'GOL LINHAS AEREAS S.A', '15ª VARA CÍVEL', 'BELO HORIZONTE, MG', '13000', '2025-02-14'),
    ('5032743-24.2025.8.13.0079', 'BRENDA DEBOSSAM SILVA ASSIS', 'Indenizatória', 'em_andamento', 'autor', 'QUALICORP ADMINISTRADORA DE BENEFICIOS S.A.', '2ª UNIDADE JURISDICIONAL - JESP - 3º JD', 'CONTAGEM, MG', '10000', '2025-06-17'),
    ('5006092-40.2025.8.13.0471', 'NAYARA CRISTINA BARROS GONCALVES e outros', 'Inventário', 'em_andamento', 'inventariante', 'ESPÓLIO DE SILVANA APARECIDA BARROS', '1ª VARA CÍVEL', 'PARÁ DE MINAS, MG', '1518', '2025-06-05'),
    ('5014978-69.2025.8.13.0231', 'ROSA MARIA DE ASSIS MAGELA', 'Indenizatória', 'em_andamento', 'autor', 'QUALICORP ADMINISTRADORA DE BENEFICIOS S.A.', 'UNIDADE JURISDICIONAL 2º JD', 'RIBEIRÃO DAS NEVES, MG', '12595.54', '2025-06-02'),
    ('5030767-55.2020.8.13.0079', 'FRANCIMAR APARECIDA CUNHA DA SILVA', 'Indenizatória', 'em_andamento', 'autor', 'PROTEAUTO TRUCK', '6ª VARA CÍVEL', 'CONTAGEM, MG', '93322', '2020-12-01'),
    ('5000049-27.2021.8.13.0407', 'CLARICE LAGARES ESPINDOLA COSTA', 'Possessórios e usucapião', 'em_andamento', 'reu', 'JOSE ARMANDO DE CARVALHO', 'VARA ÚNICA', 'JUATUBA, MG', '1000', '2021-01-01'),
    ('5038825-81.2021.8.13.0024', 'WALERSON JOSÉ DA CONCEIÇÃO VALENTIM', 'Inventário', 'em_andamento', 'inventariante', 'ESPÓLIO DE GERSON DA CONCEICAO SOBRINHO', '1ª VARA DE SUCESSÕES E AUSÊNCIA', 'BELO HORIZONTE, MG', '1518', '2021-03-24'),
    ('5000138-55.2021.8.13.0567', 'HERLEY DO CARMO GAMA PEREIRA', 'Inventário', 'em_andamento', 'inventariante', 'EDNIR RAMOS PEREIRA e outros', '2ª VARA CÍVEL', 'SABARÁ', '1518', '2021-01-19'),
    ('5002234-72.2020.8.13.0407', 'CLARICE LAGARES ESPINDOLA COSTA', 'Possessórios e usucapião', 'em_andamento', 'autor', 'JOSE ARMANDO DE CARVALHO', 'VARA ÚNICA', 'JUATUBA, MG', '20000', '2020-09-29'),
    ('5002232-05.2020.8.13.0407', 'CLARICE LAGARES ESPINDOLA COSTA', 'Possessórios e usucapião', 'em_andamento', 'autor', 'CELIA DE MINAS SANTOS SALGADO e outro', 'VARA ÚNICA', 'JUATUBA, MG', '20000', '2020-09-29'),
    ('5001604-16.2020.8.13.0407', 'CLARICE LAGARES ESPINDOLA COSTA', 'Inventário', 'suspenso', 'inventariante', 'ESPÓLIO DE MARIA DE FATIMA LAGARES DOS SANTOS', 'VARA ÚNICA', 'JUATUBA, MG', '1518', '2020-07-27'),
    ('5009483-44.2025.8.13.0231', 'THALES DA SILVA NOGUEIRA', 'Indenizatória', 'em_andamento', 'reu', 'AUTO TRUCK', '1ª VARA CÍVEL', 'RIBEIRÃO DAS NEVES, MG', '5748', '2025-04-08'),
    ('1051356-34.2025.8.13.0024', 'CYNTIA PATRICIA DE LIMA', 'Incidentes', 'em_andamento', 'autor', 'VERSADA PARTICIPACOES LTDA e outros', '4ª UNIDADE JURISDICIONAL CÍVEL - 12º JD', 'BELO HORIZONTE, MG', '1518', '2025-09-16'),
    ('5232353-46.2022.8.13.0024', 'CYNTIA PATRICIA DE LIMA', 'Indenizatória', 'em_andamento', 'reu', 'FULLCORP MAGAZINE DE ARTIGOS PARA CASA E CONSULTORIA DIGITAL LTDA', '4ª UNIDADE JURISDICIONAL CÍVEL - 12º JD', 'BELO HORIZONTE, MG', '14728', '2022-10-26'),
    ('5042478-81.2025.8.13.0079', 'NATALIA DE SOUZA BORGES', 'Divórcio e União Estável', 'em_andamento', 'autor', 'VICTOR HUGO DE SOUZA REZENDE', '3ª VARA DE FAMÍLIA', 'CONTAGEM, MG', '1518', '2025-08-05'),
    ('5039828-61.2025.8.13.0079', 'GIOVANNA MARCELLE PINHEIRO RAMOS', 'Indenizatória', 'em_andamento', 'reu', 'PEDRO LUCAS DE MOURA SILVA', '1ª UNIDADE JURISDICIONAL - JESP - 2º JD', 'CONTAGEM, MG', '16850', '2025-07-23'),
    ('5043524-08.2025.8.13.0079', 'AMANDA NATIELLE FERREIRA LOPES', 'Indenizatória', 'em_andamento', 'autor', 'UNIMED JUIZ DE FORA COOP DE TRABALHO MEDICO LTDA', '1ª UNIDADE JURISDICIONAL - JESP 2º JD', 'CONTAGEM, MG', '30000', '2025-08-11'),
    ('4001729-24.2025.8.26.0161', 'VINICIIRA TEIXEIRA VALADARES PALHARES', 'Indenizatória', 'em_andamento', 'autor', 'BANCO BRADESCO S.A.', '1ª VARA DO JUIZADO ESPECIAL CÍVEL', 'DIADEMA, SP', '', '2025-08-19'),
    ('1085343-18.2008.8.13.0231', 'JOSÉ CARLOS AMANCIO DE ALMEIDA', 'Indenizatória', 'em_andamento', 'reu', 'BANCO DO BRASIL SA', '1ª VARA CÍVEL', 'RIBEIRÃO DAS NEVES, MG', '', NULL)
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
