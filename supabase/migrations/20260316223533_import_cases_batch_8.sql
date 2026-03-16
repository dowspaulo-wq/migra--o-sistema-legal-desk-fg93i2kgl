-- Create missing clients first to ensure cases.clientId is not null,
-- which prevents the handle_new_case_task trigger from failing since tasks.clientId is NOT NULL.
INSERT INTO public.clients (name, document, type, status)
SELECT DISTINCT v.client_name, md5(v.client_name || gen_random_uuid()::text), 
  CASE WHEN v.client_name ILIKE '%CONDOMÍNIO%' OR v.client_name ILIKE '%CONDOMINIO%' OR v.client_name ILIKE '%ASSOCIAÇÃO%' OR v.client_name ILIKE '%COMÉRCIO%' OR v.client_name ILIKE '%LTDA%' THEN 'PJ' ELSE 'PF' END, 
  'Ativo'
FROM (
  VALUES
    ('GLICÉRIA CONCEIÇÃO FERREIRA'),
    ('FABRÍCIA APARECIDA OLIVEIRA PEREIRA'),
    ('EVALDO JULIO BENTO'),
    ('ELVIMAR INACIO DO ROSARIO'),
    ('JOÃO VITOR NOGUEIRA RODRIGUES'),
    ('ENOC JOSE DE MOURA LEAL'),
    ('HUDSON GOMES DA SILVA'),
    ('CONDOMÍNIO DO RESIDENCIAL VALÊNCIA'),
    ('LUCAS BATISTA DE OLIVEIRA'),
    ('MIRIAM LUCIA PEREIRA FREITAS COSTA'),
    ('VANESSA MELO FOURNIER'),
    ('MAYCON HENRIQUE DOS SANTOS'),
    ('WANDEIR ALVARENGA DE REZENDE'),
    ('FERNANDO XAVIER VENTURA JUNIOR'),
    ('ELIENE DIAS DA ROCHA'),
    ('DANIEL ASSIS AMANCIO DE ALMEIDA'),
    ('CRISTHIAN ROHAN LUIZ LISBOA DE ALMEIDA'),
    ('CLEITON BRANDÃO ANDRADE'),
    ('CONDOMINIO RESIDENCIAL ALBATROZ'),
    ('VITOR RAFAEL DE CARVALHO'),
    ('VINICIUS TEIXEIRA VALADARES PALHARES'),
    ('ERNANI CORDEIRO DE OLIVEIRA'),
    ('MICHELE DA SILVA MONTES OLIVEIRA'),
    ('RAQUEL ROSA COSTA'),
    ('GUILHERME FILIPPINI AUGUSTO')
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
    ('6006966-32.2024.4.06.3814', 'GLICÉRIA CONCEIÇÃO FERREIRA', 'Indenizatória', 'em_andamento', 'autor', 'LÍDER DPVAT', '1ª VARA FEDERAL COM JEF ADJUNTO', 'IPATINGA, MG', '12000', '2023-02-15'),
    ('6003523-18.2024.4.06.3800', 'FABRÍCIA APARECIDA OLIVEIRA PEREIRA', 'Previdenciário', 'em_andamento', 'autor', 'INSS', '4ª VARA JUIZADO ESPECIAL FEDERAL', 'BELO HORIZONTE, MG', '1518', '2023-12-05'),
    ('5000232-41.2023.8.13.0079', 'EVALDO JULIO BENTO', 'Alimentos', 'em_andamento', 'autor', 'NAIARA DA SILVA BELMIRO', '1ª VARA DE FAMÍLIA', 'CONTAGEM, MG', '1518', '2023-01-04'),
    ('5047650-19.2018.8.13.0024', 'ELVIMAR INACIO DO ROSARIO', 'Indenizatória', 'em_andamento', 'autor', 'VIACAO GONCALVES LTDA - ME', '32ª VARA CÍVEL', 'BELO HORIZONTE, MG', '60000', '2018-04-16'),
    ('5000362-18.2023.8.13.0148', 'JOÃO VITOR NOGUEIRA RODRIGUES', 'Indenizatória', 'suspenso', 'autor', 'CVC', '2ª VARA CÍVEL', 'LAGOA SANTA, MG', '5000', '2023-01-18'),
    ('1003239-70.2025.8.13.0231', 'ENOC JOSE DE MOURA LEAL', 'Indenizatória', 'em_andamento', 'autor', 'MARCOS SILVA DE DEUS', '', '', '0', NULL),
    ('5030250-40.2024.8.13.0231', 'ENOC JOSE DE MOURA LEAL', 'Indenizatória', 'em_andamento', 'autor', 'CONDOMINIO DO RESIDENCIAL UBATUBA', 'UNIDADE JURISDICIONAL 1º JD', 'RIBEIRÃO DAS NEVES, MG', '14562.06', '2024-11-21'),
    ('5117361-43.2020.8.13.0024', 'HUDSON GOMES DA SILVA', 'Alimentos', 'em_andamento', 'executado', 'VALENTINA GOMES RIOS', '2ª VARA REGIONAL DO BARREIRO', 'BELO HORIZONTE, MG', '100000', '2020-08-31'),
    ('5220284-11.2024.8.13.0024', 'HUDSON GOMES DA SILVA', 'Anulatória', 'em_andamento', 'autor', 'VALENTINA GOMES RIOS', '1ª VARA DE FAMÍLIA', 'BELO HORIZONTE, MG', '1518', '2024-09-03'),
    ('1101487-13.2025.8.13.0024', 'CONDOMÍNIO DO RESIDENCIAL VALÊNCIA', 'Indenizatória', 'em_andamento', 'autor', 'DALMAR MAIA', '21ª VARA CÍVEL', 'BELO HORIZONTE, MG', '800', '2025-12-05'),
    ('1008195-03.2025.8.13.0079', 'LUCAS BATISTA DE OLIVEIRA', 'Indenizatória', 'aguardando_documentos', 'autor', 'UBER', '1ª UNIDADE JURISDICIONAL DO JUIZADO ESPECIAL - 1ºJD', 'CONTAGEM, MG', '43000', '2025-12-05'),
    ('1106249-72.2025.8.13.0024', 'MIRIAM LUCIA PEREIRA FREITAS COSTA', 'Divórcio e União Estável', 'em_andamento', 'autor', 'Parentes de Haelis', '4ª VARA DE FAMÍLIA', 'BELO HORIZONTE, MG', '1517.99', '2025-12-15'),
    ('5014911-39.2025.8.13.0188', 'VANESSA MELO FOURNIER', 'Divórcio e União Estável', 'em_andamento', 'autor', 'MARCIO FLAVIO PEDROSA FERREIRA', '2ª VARA CÍVEL', 'NOVA LIMA', '1518', '2025-12-06'),
    ('5031455-41.2023.8.13.0231', 'MAYCON HENRIQUE DOS SANTOS', 'Indenizatória', 'em_andamento', 'autor', 'PEGADA ECOTURISMO', 'UNIDADE JURISDICIONAL 1º JD', 'RIBEIRÃO DAS NEVES, MG', '12000', '2023-12-16'),
    ('5038006-81.2018.8.13.0079', 'WANDEIR ALVARENGA DE REZENDE', 'Indenizatória', 'em_andamento', 'autor', 'ROCA ADMINISTRADORA LTDA - ME e outros', '6ª VARA CÍVEL', 'CONTAGEM, MG', '106000', '2018-12-10'),
    ('5068323-86.2025.8.13.0024', 'FERNANDO XAVIER VENTURA JUNIOR', 'Inventário', 'em_andamento', '', 'IRACY ROSA TORRES CUNHA', '1ª VARA DE SUCESSÕES E AUSÊNCIA', 'BELO HORIZONTE', '1518', '2025-03-19'),
    ('5001951-69.2022.8.13.0313', 'FERNANDO XAVIER VENTURA JUNIOR', 'Indenizatória', 'em_andamento', '', 'FLAVIO EUSTAQUIO DA SILVA', 'UNIDADE JURISDICIONAL ÚNICA - 1º JD', 'IPATINGA, MG', '13000', '2022-12-11'),
    ('5017561-13.2018.8.13.0024', 'FERNANDO XAVIER VENTURA JUNIOR', 'Indenizatória', 'em_andamento', 'executado', 'GILMARA RODRIGUES CARDOSO MALTA e outros', 'CENTRASE', 'BELO HORIZONTE, MG', '70000', '2018-02-19'),
    ('8009036-57.2024.8.05.0103', 'ELIENE DIAS DA ROCHA', 'Possessórios e usucapião', 'em_andamento', 'autor', 'ANTONIO LUIZ ROCHA DA SILVA', '4ª VARA CÍVEL', '', '1412', '2024-09-02'),
    ('5031383-88.2022.8.13.0231', 'DANIEL ASSIS AMANCIO DE ALMEIDA', 'Indenizatória', 'em_andamento', 'autor', 'BANCO RCI BRASIL S/A', '2ª VARA CÍVEL', 'RIBEIRÃO DAS NEVES, MG', '21000', '2025-12-14'),
    ('0001722-46.2013.5.03.0021', 'CRISTHIAN ROHAN LUIZ LISBOA DE ALMEIDA', 'Reclamatória trabalhista', 'em_andamento', 'reclamante', 'JOSE APARECIDO DE OLIVEIRA TAVORA', '21ª VARA DO TRABALHO', 'BELO HORIZONTE', '5000', NULL),
    ('5004509-08.2025.8.13.0572', 'CLEITON BRANDÃO ANDRADE', 'Indenizatória', 'em_andamento', 'autor', 'CAR PROTEC CLUBE DE BENEFICIOS', 'JUIZADO ESPECIAL CÍVEL', 'SANTA BÁRBARA, MG', '15000', '2025-12-04'),
    ('5218655-02.2024.8.13.0024', 'CONDOMINIO RESIDENCIAL ALBATROZ', 'Indenizatória', 'em_andamento', 'autor', 'ALLIANZ SEGUROS S.A', '11ª VARA CÍVEL', 'BELO HORIZONTE, MG', '7717.05', '2024-09-02'),
    ('5004721-82.2025.8.13.0231', 'VITOR RAFAEL DE CARVALHO', 'Indenizatória', 'em_andamento', 'autor', 'SANTANDER', '1ª UNIDADE JURISDICIONAL 1º JD', 'RIBEIRÃO DAS NEVES, MG', '20000', '2025-02-20'),
    ('5025259-21.2024.8.13.0231', 'VITOR RAFAEL DE CARVALHO', 'Indenizatória', 'em_andamento', 'autor', 'IGOR CESAR DA SILVA FERREIRA', 'UNIDADE JURISDICIONAL 1º JD', 'RIBEIRÃO DAS NEVES, MG', '55000', '2024-09-26'),
    ('5001567-03.2025.8.13.0378', 'VINICIUS TEIXEIRA VALADARES PALHARES', 'Indenizatória', 'em_andamento', 'reu', 'TEREZINHA FRAMIL LOBO', 'JUIZADO ESPECIAL CÍVEL', 'LAMBARI, SP', '2000', '2025-06-11'),
    ('5007718-09.2025.8.13.0079', 'ERNANI CORDEIRO DE OLIVEIRA', 'Indenizatória', 'em_andamento', 'autor', 'ENTEL CENTRAL NACIONAL DE LISTAS E GUIAS LTDA - ME', '2ª UNIDADE JURISDICIONAL - JESP - 3º JD', 'CONTAGEM, MG', '11580', '2025-02-14'),
    ('5009535-45.2022.8.13.0231', 'MICHELE DA SILVA MONTES OLIVEIRA', 'Indenizatória', 'em_andamento', 'autor', 'PROMED', 'UNIDADE JURISDICIONAL 2ª JD', 'RIBEIRÃO DAS NEVES, MG', '28466', '2022-05-05'),
    ('4020071-88.2025.8.26.0224', 'RAQUEL ROSA COSTA', 'Indenizatória', 'em_andamento', 'autor', 'PORTO SEGUROS', '12ª VARA CÍVEL', 'GUARULHOS, SP', '104000', '2025-11-28'),
    ('1017505-93.2024.8.26.0309', 'GUILHERME FILIPPINI AUGUSTO', 'Indenizatória', 'em_andamento', 'autor', 'AMIL ASSISTÊNCIA MÉDICA INTERNACIONAL S.A', '1ª VARA CÍVEL', 'JUNDIAÍ, SP', '23000', '2024-08-05')
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

