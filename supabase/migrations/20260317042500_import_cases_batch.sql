DO $$
BEGIN

-- 1. Insert any missing clients
WITH new_clients (name) AS (
  VALUES 
    ('COMUNIDADE TERAPÊUTICA ESTÂNCIA VIDA'),
    ('ALINE OLIVEIRA VIANA DINIZ'),
    ('DOUGLAS NEVES SIQUEIRA'),
    ('MICHAEL STARLEY DA FONSECA'),
    ('WESLEI DE CASTRO PEDROZA'),
    ('BELIANI DE BARROS FERREIRA SILVA'),
    ('SOPHIA EMANUELE GUIMARÃES CÂNDIDO'),
    ('ISRAEL MOREIRA DA ROCHA'),
    ('RODRIGO CORREA LOPES'),
    ('CARLOS LUCIO ROMANO NETO'),
    ('GUSTAVO HENRIQUE DE SOUZA ALVES'),
    ('EMANOEL DA SILVA ALVES DE OLIVEIRA'),
    ('MAICOM FILIPE DE ALMEIDA MORAIS'),
    ('LORRANA CAMILA OZOLIO BAHIENSE CAMINHAS'),
    ('RICARDO AUGUSTO DE SOUZA FIGUEIREDO'),
    ('HÉLIO PAULO DOS SANTOS'),
    ('ANA FLAVIA DA SILVA'),
    ('CONDOMINIO CITTA MILAO'),
    ('NAIARA GONCALVES DA SILVA'),
    ('TIAGO HENRIQUE CAMPOS DE SOUZA'),
    ('GABRIELA FONSECA AREDES'),
    ('PABLO HENRIQUE ALVES BATISTA'),
    ('JULIANE APARECIDA MENEGUITE SOUZA'),
    ('DAVIDSON JUNIO SILVA'),
    ('MAYCON HENRIQUE DOS SANTOS'),
    ('PABLO WENDER DE JESUS RODRIGUES')
)
INSERT INTO public.clients (name, type, status, "isSpecial")
SELECT DISTINCT name, 'Física', 'Ativo', false
FROM new_clients nc
WHERE NOT EXISTS (SELECT 1 FROM public.clients c WHERE c.name = nc.name)
ON CONFLICT (name) DO NOTHING;

-- 2. Insert cases
WITH new_cases (number, client_name, type, status, position, adverseParty, court, comarca, value, startDate) AS (
  VALUES
    ('5006110-04.2024.8.13.0372', 'COMUNIDADE TERAPÊUTICA ESTÂNCIA VIDA', 'Indenizatória', 'Em andamento', 'autor', 'PATRICIA DO CARMO MELO DE AVILA', '2ª VARA CÍVEL', 'LAGOA DA PRATA', 1412::numeric, NULL),
    ('5006162-19.2024.8.13.0301', 'ALINE OLIVEIRA VIANA DINIZ', 'Inventário', 'Em andamento', 'inventariante', 'ESPÓLIO DE RICARDO AUGUSTO DE SOUZA FIGUEIREDO', '1ª VARA CÍVEL', 'IGARAPÉ', 1518::numeric, NULL),
    ('5006293-44.2026.8.08.0048', 'DOUGLAS NEVES SIQUEIRA', 'Indenizatória', 'Em andamento', 'autor', 'CONFIAUTO', '5ª VARA CÍVEL', 'SERRA', 81107::numeric, '2026-02-21'),
    ('5006409-63.2025.8.13.0301', 'MICHAEL STARLEY DA FONSECA', 'Outros', 'Em andamento', 'autor', 'EXPRESSO RAQUEL LTDA - ME', 'Juizado Especial Cível', 'Igarapé', 2500::numeric, '2025-08-12'),
    ('5007335-65.2025.8.08.0048', 'WESLEI DE CASTRO PEDROZA', 'Alimentos', 'Em andamento', 'autor', 'GABRIEL DE MIRANDA MACHADO PEDROZA', '1ª VARA DE FAMÍLIA', 'SERRA', 1518::numeric, NULL),
    ('5007497-26.2023.8.13.0231', 'BELIANI DE BARROS FERREIRA SILVA', 'Divórcio e União Estável', 'Em andamento', 'autor', 'LINDOMAR DA SILVA VIEGA', '1ª VARA DE FAMÍLIA', 'RIBEIRÃO DAS NEVES', 1518::numeric, NULL),
    ('5008475-81.2017.8.13.0079', 'SOPHIA EMANUELE GUIMARÃES CÂNDIDO', 'Indenizatória', 'Em andamento', 'autor', 'JEAN FARLEY GONÇALVES DE FREITAS', '2ª VARA CÍVEL', 'CONTAGEM', 1000000::numeric, '2017-05-15'),
    ('5008569-77.2025.8.13.0231', 'ISRAEL MOREIRA DA ROCHA', 'Indenizatória', 'Em andamento', 'autor', 'GUSTAVO PEREIRA DE BARROS', 'UNIDADE JURISDICIONAL 2º JD', 'RIBEIRÃO DAS NEVES', 20000::numeric, NULL),
    ('5008594-33.2022.8.13.0090', 'RODRIGO CORREA LOPES', 'Indenizatória', 'Em andamento', 'autor', 'DANIELA CRISTINA CARDOSO ROCHA', '1º JUIZADO ESPECIAL CÍVEL', 'BRUMADINHO', 5280::numeric, NULL),
    ('5009240-92.2024.8.13.0148', 'CARLOS LUCIO ROMANO NETO', 'Indenizatória', 'Em andamento', 'autor', 'PEFISA SA CREDITO FINANCIAMENTO E INVESTIMENTO', 'Unidade Jurisdicional', 'Lagoa Santa', 1073074::numeric, '2024-11-13'),
    ('5009353-54.2025.8.13.0231', 'GUSTAVO HENRIQUE DE SOUZA ALVES', 'Inventário', 'Em andamento', 'inventariante', 'ESPÓLIO DE MARCOS ANTONIO DA SILVA', '1ª VARA DE FAMÍLIA E SUCESSÕES', 'RIBEIRÃO DAS NEVES', 1518::numeric, NULL),
    ('5010576-15.2019.8.13.0114', 'EMANOEL DA SILVA ALVES DE OLIVEIRA', 'Indenizatória', 'Em andamento', 'autor', 'LEANDRA SPIAZZI DA SILVA SANTOS e outro', '1ª Vara Cível', 'Ibirité', 3831916::numeric, '2019-12-16'),
    ('5010780-18.2022.8.13.0223', 'MAICOM FILIPE DE ALMEIDA MORAIS', 'Indenizatória', 'Em andamento', 'exequente', 'CENTRO DE ENSINO SUPERIOR INAP', 'UNIDADE JURISDICIONAL - 2º JD', 'DIVINÓPOLIS', 1000::numeric, '2022-07-11'),
    ('5010851-59.2025.8.13.0079', 'LORRANA CAMILA OZOLIO BAHIENSE CAMINHAS', 'Outros', 'Em andamento', 'autor', 'BANCO BRADESCO FINANCIAMENTOS S.A.', '2ª Unidade Jurisdicional - JESP - 4º JD', 'Contagem', 50272::numeric, '2025-02-27'),
    ('5011551-35.2025.8.13.0079', 'ALINE OLIVEIRA VIANA DINIZ', 'Alimentos', 'Em andamento', 'autor', 'GILBERT ROCHA DINIZ TORRES', '3ª VARA DE FAMÍLIA', 'CONTAGEM', 1518::numeric, NULL),
    ('5012109-07.2025.8.13.0079', 'RICARDO AUGUSTO DE SOUZA FIGUEIREDO', 'Indenizatória', 'Em andamento', 'autor', 'AVANTE', '2ª UNIDADE JURISDICIONAL - JESP - 3º JD', 'CONTAGEM', 10000::numeric, NULL),
    ('5012274-35.2017.8.13.0079', 'HÉLIO PAULO DOS SANTOS', 'Indenizatória', 'Em andamento', 'autor', 'CHUBB SEGUROS BRASIL S.A.', '3ª VARA CÍVEL', 'CONTAGEM', 60000::numeric, '2017-06-28'),
    ('5014881-11.2023.8.13.0079', 'ANA FLAVIA DA SILVA', 'Indenizatória', 'Em andamento', 'autor', 'PAULO CESAR DE CASTRO FLORENCIO e outros', '6ª VARA CÍVEL', 'CONTAGEM', 57292.56::numeric, NULL),
    ('5015786-66.2024.8.13.0245', 'CONDOMINIO CITTA MILAO', 'Indenizatória', 'Em andamento', 'autor', 'ALLIANZ SEGUROS S/A', '1ª VARA CÍVEL', 'SANTA LUZIA', 7000::numeric, '2024-07-03'),
    ('5017692-51.2019.8.13.0024', 'NAIARA GONCALVES DA SILVA', 'Indenizatória', 'Em andamento', 'autor', 'ASSOCIACAO DE PROTECAO E ASSISTENCIA VEICULAR - FOCAR e outro', 'CENTRASE Cível de Belo Horizonte', 'Belo Horizonte', 9392::numeric, '2019-02-08'),
    ('5018250-63.2024.8.13.0245', 'TIAGO HENRIQUE CAMPOS DE SOUZA', 'Indenizatória', 'Em andamento', 'autor', 'EB & J EDUCACAO PROFISSIONAL LTDA - ME', '2ª VARA CÍVEL', 'SANTA LUZIA', 23750::numeric, NULL),
    ('5018496-43.2024.8.13.0024', 'GABRIELA FONSECA AREDES', 'Inventário', 'Em andamento', 'inventariante', 'ESPÓLIO DE AFONSO GREGORIO MORAIS AREDES', '4ª VARA DE FAMÍLIA E SUCESSÕES', 'BELO HORIZONTE', 1518::numeric, NULL),
    ('5021176-55.2025.8.13.0027', 'PABLO HENRIQUE ALVES BATISTA', 'Indenizatória', 'Concluído', 'autor', 'TAM LINHAS AEREAS S/A', 'UNIDADE JURISDICIONAL ÚNICA - 1º JD', 'BETIM', 10000::numeric, NULL),
    ('5021430-66.2025.8.13.0079', 'JULIANE APARECIDA MENEGUITE SOUZA', 'Busca e apreensão', 'Em andamento', 'autor', 'VITOR HUGO DOS REIS SILVA e OUTROS', '1ª VARA CÍVEL', 'ESMERALDAS', 1518::numeric, NULL),
    ('5024376-70.2025.8.13.0027', 'PABLO HENRIQUE ALVES BATISTA', 'Indenizatória', 'Em andamento', 'autor', 'BRAULIO CHARLES FERREIRA MALTA', 'UNIDADE JURISDICIONAL ÚNICA - 3º JD', 'BETIM', 3600::numeric, NULL),
    ('5025890-62.2024.8.13.0231', 'DAVIDSON JUNIO SILVA', 'Possessórios', 'Em andamento', 'reu', 'RAIMUNDO DE FATIMA DE JESUS', '1ª VARA CÍVEL', 'RIBEIRÃO DAS NEVES', 150000::numeric, NULL),
    ('5026154-16.2025.8.13.0079', 'JULIANE APARECIDA MENEGUITE SOUZA', 'Anulatória', 'Em andamento', 'autor', 'VITOR HUGO DOS REIS SILVA e OUTROS', '1ª VARA CÍVEL', 'ESMERALDAS', 85714::numeric, NULL),
    ('5026396-38.2024.8.13.0231', 'MAYCON HENRIQUE DOS SANTOS', 'Incidentes', 'Em andamento', 'autor', 'EMPRESA BELO HORIZONTE DE IMOVEIS GERAIS SA', '4ª VARA CÍVEL', 'CONTAGEM', 1518::numeric, NULL),
    ('5027218-66.2024.8.13.0024', 'PABLO WENDER DE JESUS RODRIGUES', 'Indenizatória', 'Suspenso', 'autor', 'CLUBE PLENA DE BENEFICIOS', '2ª UNIDADE JURISDICIONAL CÍVEL - 6ª JD', 'BELO HORIZONTE', 19241::numeric, NULL)
)
INSERT INTO public.cases (
  "clientId",
  number,
  position,
  "adverseParty",
  type,
  status,
  court,
  comarca,
  value,
  "startDate"
)
SELECT 
  c.id,
  nc.number,
  nc.position,
  nc.adverseParty,
  nc.type,
  nc.status,
  nc.court,
  nc.comarca,
  nc.value,
  nc.startDate
FROM new_cases nc
LEFT JOIN public.clients c ON c.name = nc.client_name
ON CONFLICT (number) DO UPDATE SET
  "clientId" = EXCLUDED."clientId",
  position = EXCLUDED.position,
  "adverseParty" = EXCLUDED."adverseParty",
  type = EXCLUDED.type,
  status = EXCLUDED.status,
  court = EXCLUDED.court,
  comarca = EXCLUDED.comarca,
  value = EXCLUDED.value,
  "startDate" = EXCLUDED."startDate";

END $$;
