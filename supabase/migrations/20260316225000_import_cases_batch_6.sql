-- Create missing clients first to ensure cases.clientId is not null,
-- which prevents the handle_new_case_task trigger from failing since tasks.clientId is NOT NULL.
INSERT INTO public.clients (name, document, type, status)
SELECT DISTINCT v.client_name, md5(v.client_name || gen_random_uuid()::text), 
  CASE WHEN v.client_name ILIKE '%ASSOCIAÇÃO%' OR v.client_name ILIKE '%COMÉRCIO%' OR v.client_name ILIKE '%LTDA%' THEN 'PJ' ELSE 'PF' END, 
  'Ativo'
FROM (
  VALUES
    ('ASSOCIAÇÃO MAIS VANTAGENS DO BRASIL - AMV BRASIL'),
    ('ALINE TELES MACHADO'),
    ('ALEXANDRE DE BARROS - ALETEC'),
    ('ALEXANDRE AUGUSTO DE SÁ DIAS'),
    ('ADILSON SOUZA'),
    ('ADAIR FONSECA'),
    ('MAYCON HENRIQUE DOS SANTOS'),
    ('MANOEL ALVES BEZERRA')
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
    ('5215993-36.2022.8.13.0024', 'ASSOCIAÇÃO MAIS VANTAGENS DO BRASIL - AMV BRASIL', 'Indenizatória', 'concluido', 'autor', 'RICARDO DE CARVALHO BATISTA e outro', '1ª Vara Cível', 'Belo Horizonte', '428983', '2022-10-06'),
    ('5151433-22.2021.8.13.0024', 'ASSOCIAÇÃO MAIS VANTAGENS DO BRASIL - AMV BRASIL', 'Indenizatória', 'concluido', 'autor', 'SIMAO PEDRO DE SOUZA - ME', '30ª Vara Cível', 'Belo Horizonte', '1100996', '2021-09-30'),
    ('5144290-79.2021.8.13.0024', 'ASSOCIAÇÃO MAIS VANTAGENS DO BRASIL - AMV BRASIL', 'Indenizatória', 'em_andamento', 'autor', 'ADAIR DA COSTA PEREIRA', 'CENTRASE Cível', 'Belo Horizonte', '1430774', '2020-09-20'),
    ('5138208-32.2021.8.13.0024', 'ASSOCIAÇÃO MAIS VANTAGENS DO BRASIL - AMV BRASIL', 'Indenizatória', 'concluido', 'autor', 'ROSILENE PEREIRA ROSA', '1ª Vara Cível', 'Ribeirão das Neves', '70292', '2021-09-03'),
    ('5138190-11.2021.8.13.0024', 'ASSOCIAÇÃO MAIS VANTAGENS DO BRASIL - AMV BRASIL', 'Indenizatória', 'concluido', 'autor', 'ADAIR IZIDORO PEREIRA', '18ª Vara Cível', 'Belo Horizonte', '939521', '2021-08-31'),
    ('5115428-98.2021.8.13.0024', 'ASSOCIAÇÃO MAIS VANTAGENS DO BRASIL - AMV BRASIL', 'Indenizatória', 'concluido', 'autor', 'GLENDA STURZENECKER PINTO', '19ª Vara Cível', 'Belo Horizonte', '134819', '2021-08-03'),
    ('5084082-32.2021.8.13.0024', 'ASSOCIAÇÃO MAIS VANTAGENS DO BRASIL - AMV BRASIL', 'Indenizatória', 'em_andamento', 'autor', 'MADDER MARKETING DIGITAL', '11ª Vara Cível', 'Belo Horizonte', '4945533', '2021-01-10'),
    ('5047120-44.2020.8.13.0024', 'ASSOCIAÇÃO MAIS VANTAGENS DO BRASIL - AMV BRASIL', 'Indenizatória', 'concluido', 'autor', 'BELXO FERREIRA NETO e outro', '21ª Vara Cível', 'Belo Horizonte', '328839', '2020-03-17'),
    ('5046157-36.2020.8.13.0024', 'ASSOCIAÇÃO MAIS VANTAGENS DO BRASIL - AMV BRASIL', 'Indenizatória', 'concluido', 'autor', 'SAO CRISTOVAO TRANSPORTES LTDA', '25ª Vara Cível', 'Belo Horizonte', '35465', '2020-03-18'),
    ('5046136-60.2020.8.13.0024', 'ASSOCIAÇÃO MAIS VANTAGENS DO BRASIL - AMV BRASIL', 'Indenizatória', 'concluido', 'autor', 'RENILDA PIRES BARBOSA', 'CENTRASE Cível', 'Belo Horizonte', '261781', '2020-03-03'),
    ('5044401-89.2020.8.13.0024', 'ASSOCIAÇÃO MAIS VANTAGENS DO BRASIL - AMV BRASIL', 'Indenizatória', 'em_andamento', 'autor', 'IVAIR HERMENEGILDO ALFREDO', 'CENTRASE Cível', 'Belo Horizonte', '110746', '2020-03-16'),
    ('5040269-86.2020.8.13.0024', 'ASSOCIAÇÃO MAIS VANTAGENS DO BRASIL - AMV BRASIL', 'Indenizatória', 'concluido', 'autor', 'JEFFERSON PEREIRA DE ARAUJO', 'CENTRASE Cível', 'Belo Horizonte', '457193', '2020-03-10'),
    ('5037959-10.2020.8.13.0024', 'ASSOCIAÇÃO MAIS VANTAGENS DO BRASIL - AMV BRASIL', 'Indenizatória', 'em_andamento', 'autor', 'ALEX JUNIOR VELOSO DE CARVALHO', '28ª Vara Cível', 'Belo Horizonte', '41284', '2020-03-04'),
    ('5022361-16.2020.8.13.0024', 'ASSOCIAÇÃO MAIS VANTAGENS DO BRASIL - AMV BRASIL', 'Indenizatória', 'concluido', 'autor', 'BENEDITA TAMYRES DE LIMA e outro', '23ª Vara Cível', 'Belo Horizonte', '313895', '2020-02-10'),
    ('5001675-03.2020.8.13.0024', 'ASSOCIAÇÃO MAIS VANTAGENS DO BRASIL - AMV BRASIL', 'Indenizatória', 'em_andamento', 'autor', 'WALDEMIRO CAETANO MONTEIRO FILHO', 'CENTRASE Cível', 'Belo Horizonte', '1476251', '2020-01-08'),
    ('5001625-74.2020.8.13.0024', 'ASSOCIAÇÃO MAIS VANTAGENS DO BRASIL - AMV BRASIL', 'Indenizatória', 'em_andamento', 'autor', 'KATIA SILENE DE FREITAS', 'CENTRASE Cível', 'Belo Horizonte', '1525235', '2020-01-08'),
    ('5167678-79.2019.8.13.0024', 'ASSOCIAÇÃO MAIS VANTAGENS DO BRASIL - AMV BRASIL', 'Indenizatória', 'concluido', 'autor', 'CARLOS ALBERTO PIMENTA', '5ª Vara Cível', 'Belo Horizonte', '273702', '2019-10-11'),
    ('5131651-97.2019.8.13.0024', 'ASSOCIAÇÃO MAIS VANTAGENS DO BRASIL - AMV BRASIL', 'Indenizatória', 'em_andamento', 'autor', 'MUNICIPIO DE BELO HORIZONTE', '3ª Vara Feitos Fazenda Pública', 'Belo Horizonte', '1825159', '2019-09-03'),
    ('5174176-21.2024.8.13.0024', 'ASSOCIAÇÃO MAIS VANTAGENS DO BRASIL - AMV BRASIL', 'Indenizatória', 'concluido', 'autor', 'WANILSON LUZIA DA SILVA BATISTA', '4ª Vara Cível', 'Belo Horizonte', '2.1', '2024-07-15'),
    ('5068536-29.2024.8.13.0024', 'ASSOCIAÇÃO MAIS VANTAGENS DO BRASIL - AMV BRASIL', 'Indenizatória', 'em_andamento', 'autor', 'JOSE MARIA DA COSTA e outro', '20ª Vara Cível', 'Belo Horizonte', '587554', '2024-03-03'),
    ('5062578-62.2024.8.13.0024', 'ASSOCIAÇÃO MAIS VANTAGENS DO BRASIL - AMV BRASIL', 'Indenizatória', 'concluido', 'autor', 'CELIO RODRIGUES DE OLIVEIRA', '12ª Vara Cível', 'Belo Horizonte', '3635', '2024-03-03'),
    ('5054139-62.2024.8.13.0024', 'ASSOCIAÇÃO MAIS VANTAGENS DO BRASIL - AMV BRASIL', 'Indenizatória', 'em_andamento', 'autor', 'ZENEIDE ALVES DA SILVA PAMPLONA', '20ª Vara Cível', 'Belo Horizonte', '4618', '2024-03-03'),
    ('5144280-35.2021.8.13.0024', 'ASSOCIAÇÃO MAIS VANTAGENS DO BRASIL - AMV BRASIL', 'Indenizatória', 'concluido', 'autor', 'RITA DE CASSIA MENDONCA COLUCI', '23ª Vara Cível', 'Belo Horizonte', '0', '2021-09-20'),
    ('5184515-49.2018.8.13.0024', 'ALINE TELES MACHADO', 'Outros', 'em_andamento', 'autor', 'CAIXA ECONOMICA FEDERAL', '4ª Vara de Sucessões', 'Belo Horizonte', '1000', '2018-12-27'),
    ('5140704-97.2022.8.13.0024', 'ALEXANDRE DE BARROS - ALETEC', 'Indenizatória', 'em_andamento', 'autor', 'LIMAQ MAQUINAS E EQUIPAMENTOS', '7ª UJ Cível', 'Belo Horizonte', '40', '2022-06-23'),
    ('5089837-32.2024.8.13.0024', 'ALEXANDRE AUGUSTO DE SÁ DIAS', 'Indenizatória', 'em_andamento', 'autor', '123 VIAGENS E TURISMO LTDA', '2ª UJ Cível', 'Belo Horizonte', '486598', '2024-04-12'),
    ('5005439-65.2018.8.13.0024', 'ADILSON SOUZA', 'Outros', 'em_andamento', 'reu', 'HDI SEGUROS S/A', '5ª Vara Cível', 'Contagem', '677457', '2018-01-16'),
    ('5169226-37.2022.8.13.0024', 'ADAIR FONSECA', 'Inventário', 'concluido', 'autor', '', '1ª Vara Sucessões', 'Belo Horizonte', '1000', '2022-08-08'),
    ('5038985-67.2023.8.13.0079', 'MAYCON HENRIQUE DOS SANTOS', 'Indenizatória', 'suspenso', 'autor', 'HURB', '2ª UJ - JESP', 'CONTAGEM', '1518', '2023-08-08'),
    ('1001976-66.2026.8.13.0231', 'MANOEL ALVES BEZERRA', 'Indenizatória', 'em_andamento', 'autor', 'J.LEMARA', '', '', '0', '2026-01-01')
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
