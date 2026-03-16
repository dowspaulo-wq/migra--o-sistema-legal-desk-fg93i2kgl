-- Create missing clients first to ensure cases.clientId is not null,
-- which prevents the handle_new_case_task trigger from failing since tasks.clientId is NOT NULL.
INSERT INTO public.clients (name, document, type, status)
SELECT DISTINCT v.client_name, md5(v.client_name || gen_random_uuid()::text), 'PF', 'Ativo'
FROM (
  VALUES
    ('MAYCON HENRIQUE DOS SANTOS'),
    ('VANESSA ESTEVES'),
    ('JULLY FELIX VIEIRA'),
    ('FERNANDO XAVIER VENTURA'),
    ('ROSANE ALVES DE OLIVEIRA CARNEIRO'),
    ('ROSA MARIA DE ASSIS MAGELA'),
    ('JHOM HENRICKY PEREIRA DA SILVA'),
    ('ANA PAULA CARDOSO DA SILVA'),
    ('THIAGO FILIPE DE MORAES GOMES'),
    ('GISELE DA SILVA MARIANO'),
    ('PEDRO HENRIQUE PAIVA DA SILVA'),
    ('ANA LUCIA DE OLIVEIRA'),
    ('THIAGO DA SILVA BRAGA'),
    ('ROSEANE ALEXSSANDRA BATISTA ASSIS DOS SANTOS'),
    ('MAYCON ALMEIDA DE OLIVEIRA'),
    ('LUCIANE DO CARMO DE FREITAS SANTOS'),
    ('JULIANA APARECIDA DOS SANTOS'),
    ('JUNIO ALVES MARTINS'),
    ('RAFAEL FROIS DA SILVA'),
    ('JUNIO GLEISON SOUZA'),
    ('MÁRIO COELHO DA SILVA'),
    ('PRISCILA RODRIGUES TEÓFILO'),
    ('ARNALDO GONÇALVES DA SILVA'),
    ('JORGE LUIZ BARBOSA'),
    ('ANA FLAVIA DA SILVA'),
    ('MULLER FRANCISCO PEREIRA'),
    ('MARCIA FÁTIMA PINHEIRO RAMOS'),
    ('GUILHERME GOMES DE SOUZA')
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
    ('5038989-07.2023.8.13.0079', 'MAYCON HENRIQUE DOS SANTOS', 'Indenizatória', 'em_andamento', 'autor', 'HURB', '1ª UNIDADE JURISDICIONAL - JESP - 2º JD', 'CONTAGEM', '1', '2023-08-08'),
    ('153', 'VANESSA ESTEVES', 'Previdenciário', 'em_andamento', 'autor', 'INSS', '', '', '', ''),
    ('1023322-62.2026.8.26.0053', 'VANESSA ESTEVES', 'Anulatória', 'em_andamento', 'autor', 'PREFEITURA DE SÃO PAULO', '', 'SÃO PAULO', '55000', '2026-02-27'),
    ('1032073-88.2026.8.13.0024', 'JULLY FELIX VIEIRA', 'Indenizatória', 'em_andamento', 'autor', 'GLEYCIELE DEANE GALDINA DA SILVA', '7ª Unidade Jurisdicional Cível', 'BELO HORIZONTE', '7300', '2026-02-27'),
    ('1000433-70.2026.8.13.0411', 'FERNANDO XAVIER VENTURA', 'Outros', 'em_andamento', 'impetrante', 'DELEGADO DE POLICIA CIVIL DE MATOZINHOS', '2ª Vara Cível', 'MATOZINHOS', '43751', '2026-02-26'),
    ('1002853-06.2026.8.13.0231', 'ROSANE ALVES DE OLIVEIRA CARNEIRO', 'Divórcio e União Estável', 'aguardando_documentos', 'autor', 'DOMICIO DIAS CARNEIRO', '1ª VARA DE FAMÍLIA E SUCESSÕES', 'RIBEIRÃO DAS NEVES', '54000', '2026-03-16'),
    ('1002519-69.2026.8.13.0231', 'ROSA MARIA DE ASSIS MAGELA', 'Indenizatória', 'em_andamento', 'autor', 'QUALICORP ADMINISTRADORA DE BENEFICIOS S.A.', 'UNIDADE JURISDICIONAL ÚNICA - 1º JD', 'RIBEIRÃO DAS NEVES', '16000', '2026-03-07'),
    ('5001012-04.2026.8.08.0050', 'JHOM HENRICKY PEREIRA DA SILVA', 'Indenizatória', 'aguardando_documentos', 'autor', 'ROTA BRASIL BENEFICIOS', 'COMARCA DA CAPITAL - 1º JUIZADO ESPECIAL CÍVEL', 'VIANA', '15000', '2026-02-26'),
    ('1000980-26.2026.8.13.0148', 'ANA PAULA CARDOSO DA SILVA', 'Anulatória', 'em_andamento', 'autor', 'PARTNERS PARTICIPAÇÕES E EMPREENDIMENTOS IMOBILIÁRIOS LTDA', '1ª VARA CÍVEL', 'LAGOA SANTA', '250000', '2026-03-02'),
    ('78', 'THIAGO FILIPE DE MORAES GOMES', 'Indenizatória', 'em_andamento', 'autor', 'Petrucci', '', 'CAMPINAS', '', ''),
    ('4004430-06.2026.8.26.0554', 'GISELE DA SILVA MARIANO', 'Indenizatória', 'em_andamento', 'autor', 'AZUL SEGUROS', '2ª VARA CÍVEL', 'SANTO ANDRÉ', '80000', '2026-03-02'),
    ('4005728-25.2026.8.26.0007', 'PEDRO HENRIQUE PAIVA DA SILVA', 'Indenizatória', 'aguardando_documentos', 'autor', 'PRR CONSULTORIA LTDA', 'JUÍZO TITULAR II - VARA DO JUIZADO ESPECIAL CÍVEL, REGIONAL VII - ITAQUERA', 'SÃO PAULO', '34985', '2026-02-26'),
    ('5001724-30.2025.8.13.0554', 'ANA LUCIA DE OLIVEIRA', 'Possessórios e usucapião', 'em_andamento', 'reu', 'LUCIANO DA CUNHA', 'VARA ÚNICA', 'RIO NOVO', '2000', '2025-11-19'),
    ('1027268-92.2026.8.13.0024', 'THIAGO DA SILVA BRAGA', 'Possessórios e usucapião', 'em_andamento', 'autor', 'GUSTAVO AUGUSTO GOMES DOS SANTOS', '29ª VARA CÍVEL', 'BELO HORIZONTE', '173244.64', '2026-02-20'),
    ('1003118-38.2026.8.13.0027', 'ROSEANE ALEXSSANDRA BATISTA ASSIS DOS SANTOS', 'Indenizatória', 'em_andamento', 'autor', 'WILL FINANCEIRA S.A. CREDITO', '3º JD', 'BETIM', '10180', '2026-02-21'),
    ('0809148-72.2026.8.19.0038', 'MAYCON ALMEIDA DE OLIVEIRA', 'Indenizatória', 'em_andamento', 'autor', 'ASSOCIACAO PODIUM CLUBE DE BENEFICIOS', '1º JUIZADO ESPECIAL CÍVEL', 'NOVA IGUAÇU', '26326', '2026-03-05'),
    ('4001569-83.2026.8.26.0348', 'LUCIANE DO CARMO DE FREITAS SANTOS', 'Indenizatória', 'em_andamento', 'autor', 'ASSOCIACAO GESTAO VEICULAR UNIVERSO', '', 'MAUÁ', '15000', '2026-02-21'),
    ('5003012-71.2026.8.24.0004', 'JULIANA APARECIDA DOS SANTOS', 'Indenizatória', 'em_andamento', 'autor', 'TOKIO MARINE', '1ª VARA CÍVEL', 'ARARANGUÁ', '101000', '2026-02-26'),
    ('1022719-39.2026.8.13.0024', 'JUNIO ALVES MARTINS', 'Alimentos', 'em_andamento', 'autor', 'VICTÓRIA ALVES MARTINS', '12ª VARA DE FAMÍLIA', 'BELO HORIZONTE', '2400', '2026-02-11'),
    ('1023242-51.2026.8.13.0024', 'RAFAEL FROIS DA SILVA', 'Alimentos', 'em_andamento', 'autor', '', '', 'Belo Horizonte', '', ''),
    ('5003828-96.2026.8.13.0024', 'RAFAEL FROIS DA SILVA', 'Outros', 'em_andamento', 'reu', 'KAMILA OLIVEIRA MARTINS DUARTE', '1º Juizado de Violência Doméstica e Familiar contra a Mulher', 'Belo Horizonte', '', ''),
    ('5039102-58.2023.8.13.0079', 'JUNIO GLEISON SOUZA', 'Indenizatória', 'em_andamento', 'autor', 'MRV', '5ª VARA CÍVEL', 'CONTAGEM', '20000', '2023-08-08'),
    ('4001561-09.2026.8.26.0348', 'MÁRIO COELHO DA SILVA', 'Indenizatória', 'em_andamento', 'autor', '', '', '', '', ''),
    ('1027548-63.2026.8.13.0024', 'PRISCILA RODRIGUES TEÓFILO', 'Indenizatória', 'em_andamento', 'autor', 'BMB PROTEGE BENEFICIOS PROTECAO PATRIMONIAL MUTUALISTA', 'JUIZADO ESPECIAL CÍVEL - 15º JD', 'BELO HORIZONTE', '20000', '2026-02-21'),
    ('1065494-06.2025.8.13.0024', 'ARNALDO GONÇALVES DA SILVA', 'Indenizatória', 'em_andamento', 'reu', 'GLAYDSON SILVA MARTINS', '8ª UNIDADE JURISDICIONAL CÍVEL - 24º JD', 'BELO HORIZONTE', '4500', '2025-10-08'),
    ('0001621-50.2011.5.03.0030', 'JORGE LUIZ BARBOSA', 'Reclamatória trabalhista', 'em_andamento', 'executado', 'UNIÃO', '2ª VARA DO TRABALHO', 'CONTAGEM', '11000', '2011-07-04'),
    ('1002719-47.2026.8.13.0079', 'ANA FLAVIA DA SILVA', 'Divórcio e União Estável', 'concluido', 'autor', 'MARLON IGOR', '3ª VARA DE FAMÍLIA', 'CONTAGEM', '1621', '2026-01-30'),
    ('5008550-07.2025.8.13.0317', 'MULLER FRANCISCO PEREIRA', 'Indenizatória', 'em_andamento', 'autor', 'UNIMED BH', '2ª Vara Cível', 'Itabira', '50000', '2025-09-27'),
    ('13', 'MARCIA FÁTIMA PINHEIRO RAMOS', 'Previdenciário', 'aguardando_documentos', 'autor', 'INSS', '', '', '', ''),
    ('1014144-42.2026.8.13.0024', 'GUILHERME GOMES DE SOUZA', 'Indenizatória', 'em_andamento', 'autor', 'SANTANDER CORRETORA DE SEGUROS, INVESTIMENTOS E SERVICOS S.A.', '5ª UNIDADE JURISDICIONAL CÍVEL - 13ª JD', 'BELO HORIZONTE', '6000', '2026-01-29')
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
