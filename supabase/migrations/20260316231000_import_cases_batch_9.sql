-- Create missing clients first to ensure cases.clientId is not null,
-- which prevents the handle_new_case_task trigger from failing since tasks.clientId is NOT NULL.
INSERT INTO public.clients (name, document, type, status)
SELECT DISTINCT v.client_name, md5(v.client_name || gen_random_uuid()::text), 
  CASE WHEN v.client_name ILIKE '%ASSOCIAÇÃO%' OR v.client_name ILIKE '%COMÉRCIO%' OR v.client_name ILIKE '%LTDA%' OR v.client_name ILIKE '%CONDOMINIO%' OR v.client_name ILIKE '%CONDOMÍNIO%' OR v.client_name ILIKE '%COMUNIDADE%' THEN 'PJ' ELSE 'PF' END, 
  'Ativo'
FROM (
  VALUES
    ('GUILHERME FILIPPINI AUGUSTO'),
    ('WILLIAM DAS CHAGAS MAGELA'),
    ('EMILSON NOGUEIRA SANTOS'),
    ('THIAGO MILANEZ DA SILVA'),
    ('COMUNIDADE TERAPÊUTICA ESTÂNCIA VIDA'),
    ('THALITA STHER NEPOMUCENO DUNGA'),
    ('GERALDO DONIZETE DA COSTA'),
    ('CONDOMÍNIO DO RESIDENCIAL VALÊNCIA'),
    ('RESIDENCIAL LINDA VISTA'),
    ('CONDOMINIO CITTA MILAO'),
    ('BIANCA GOMES DE FREITAS'),
    ('ANA PAULA DA SILVA'),
    ('ALBERTO LUIZ DA SILVA'),
    ('ISAAC MADUREIRA SILVA'),
    ('EVALDO VIANA PEREIRA'),
    ('FABIANE BARRETO DA CUNHA'),
    ('DOUGLAS PAULO DOS SANTOS'),
    ('PABLO HENRIQUE ALVES BATISTA'),
    ('FRANCIMAR APARECIDA CUNHA DA SILVA'),
    ('CHARLES EDUARDO DE SOUZA ESTACIO DA SILVA'),
    ('MARANATHA CONCEIÇÃO SANTOS LIMA'),
    ('SOPHIA EMANUELE GUIMARÃES CÂNDIDO'),
    ('ANA LETICIA DO NASCIMENTO SIMOES ABREU'),
    ('ANA CAROLINA OLIVEIRA SANTOS')
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
  v.type,
  v.status,
  v.position,
  v.adverseParty,
  v.court,
  v.comarca,
  COALESCE(v.value::numeric, 0),
  v.startDate
FROM (
  VALUES
    ('1017505-93.2024.8.26.0309', 'GUILHERME FILIPPINI AUGUSTO', 'Indenizatória', 'em_andamento', 'autor', 'AMIL ASSISTÊNCIA MÉDICA INTERNACIONAL S.A', '1ª VARA CÍVEL', 'JUNDIAÍ, SP', '23000', '2024-08-05'),
    ('5152682-71.2022.8.13.0024', 'WILLIAM DAS CHAGAS MAGELA', 'Execução ou embargos', 'em_andamento', 'executado', 'AMC INFORMÁTICA', '21ª VARA CÍVEL', 'BELO HORIZONTE, MG', '24000', '2022-07-20'),
    ('5037939-68.2024.8.13.0027', 'EMILSON NOGUEIRA SANTOS', 'Indenizatória', 'em_andamento', 'reu', 'ROGERIO PIERAZOLI e outros', '3ª VARA CÍVEL', 'BETIM, MG', '72198.14', '2024-11-14'),
    ('1008084-53.2026.8.13.0024', 'THIAGO MILANEZ DA SILVA', 'Indenizatória', 'em_andamento', 'autor', 'Associação TripKar', '9ª UNIDADE JURISDICIONAL CÍVE- 27º JD', 'BELO HORIZONTE', '9000', '2026-01-20'),
    ('5120803-75.2024.8.13.0024', 'THIAGO MILANEZ DA SILVA', 'Indenizatória', 'em_andamento', 'reu', 'HDI', '33ª', 'BELO HORIZONTE, MG', '9022', '2024-05-16'),
    ('5005922-32.2017.8.13.0024', 'THIAGO MILANEZ DA SILVA', 'Indenizatória', 'em_andamento', 'autor', 'ROGERIO DE MORAIS SILVA', '2ª VARA CÍVEL', 'BELO HORIZONTE, MG', '30000', '2017-01-20'),
    ('5001129-58.2026.8.13.0372', 'COMUNIDADE TERAPÊUTICA ESTÂNCIA VIDA', 'Execução ou embargos', 'em_andamento', 'autor', 'GABRIELE GIOVANA CARVALHO', '2º JUIZADO ESPECIAL CÍVEL', 'LAGOA DA PRATA', '2300', '2026-03-05'),
    ('5064002-71.2024.8.13.0079', 'THALITA STHER NEPOMUCENO DUNGA', 'Indenizatória', 'em_andamento', 'autor', 'ALAIR NOGUEIRA', '3ª VARA CÍVEL', 'CONTAGEM, MG', '76107.19', '2024-12-04'),
    ('5030151-07.2025.8.13.0079', 'GERALDO DONIZETE DA COSTA', 'Indenizatória', 'em_andamento', 'autor', 'MUSCAPERI ALMEIDA SOARES', '5ª VARA CÍVEL', 'BELO HORIZONTE, MG', '18804', '2025-06-05'),
    ('5295627-13.2024.8.13.0024', 'CONDOMÍNIO DO RESIDENCIAL VALÊNCIA', 'Execução ou embargos', 'suspenso', 'exequente', 'RONAN FRANCA', '6ª VARA CÍVEL', 'BELO HORIZONTE, MG', '9528', '2024-11-19'),
    ('5043949-40.2022.8.13.0079', 'RESIDENCIAL LINDA VISTA', 'Execução ou embargos', 'suspenso', 'exequente', 'BHARBARA CRISTINA DA SILVA', '4ª VARA CÍVEL', 'CONTAGEM, MG', '2600', '2022-10-06'),
    ('5032453-53.2018.8.13.0079', 'RESIDENCIAL LINDA VISTA', 'Execução ou embargos', 'em_andamento', 'autor', 'REINALDO DE SOUZA IZIDIO', '3ª VARA CÍVEL', 'CONTAGEM, MG', '1842', '2018-08-24'),
    ('5006691-12.2024.8.13.0245', 'CONDOMINIO CITTA MILAO', 'Outros', 'em_andamento', 'autor', 'MARIO LUCIO FRANCISCO DE ARAUJO FREITAS', '2ª VARA CÍVEL', 'SANTA LUZIA', '35000', '2024-04-16'),
    ('0005930-19.2024.8.26.0079', 'BIANCA GOMES DE FREITAS', 'Alimentos', 'em_andamento', 'autor', 'ALEX VIEIRA FREITAS', '1ª VARA CÍVEL', 'BOTUCATU, SP', '30000', '2024-01-25'),
    ('5067182-32.2025.8.13.0024', 'ANA PAULA DA SILVA', 'Indenizatória', 'em_andamento', 'autor', 'AGROPOP BH COMERCIO DE PRODUTOS AGROPECUARIOS LTDA', '5ª UNIDADE JURISDICIONAL CÍVEL - 15ª JD', 'BELO HORIZONTE, MG', '10242', '2025-03-18'),
    ('5026221-59.2017.8.13.0079', 'ALBERTO LUIZ DA SILVA', 'Outros', 'em_andamento', 'autor', 'ARNALDO GONCALVES DA SILVA', '4ª VARA CÍVEL', 'CONTAGEM, MG', '18000', '2017-11-23'),
    ('1001446-38.2025.8.26.0586', 'ISAAC MADUREIRA SILVA', 'Tutelas e/ou Curatelas', 'em_andamento', 'autor', 'LUZIA FERREIRA DE MADUREIRA', '1ª VARA DE FAMÍLIA', 'SÃO ROQUE, SP', '1518', '2025-04-15'),
    ('5064814-94.2018.8.13.0024', 'EVALDO VIANA PEREIRA', 'Indenizatória', 'em_andamento', 'reu', 'MVL EMPREENDIMENTOS IMOBILIARIOS LTDA - EPP', '17ª VARA CÍVEL', 'BELO HORIZONTE, MG', '61944.49', '2018-05-17'),
    ('5000942-90.2025.8.13.0079', 'FABIANE BARRETO DA CUNHA', 'Indenizatória', 'em_andamento', 'autor', 'MELO SOARES CONSTRUTORA E INCORPORADORA LTDA - ME', '1ª VARA CÍVEL', 'CONTAGEM, MG', '25000', '2025-01-11'),
    ('4', 'DOUGLAS PAULO DOS SANTOS', 'Indenizatória', 'em_andamento', 'autor', 'FIES', NULL, NULL, '0', NULL),
    ('3', 'PABLO HENRIQUE ALVES BATISTA', 'Indenizatória', 'em_andamento', 'autor', 'FIES', NULL, NULL, '0', NULL),
    ('1031688-43.2026.8.13.0024', 'FRANCIMAR APARECIDA CUNHA DA SILVA', 'Indenizatória', 'em_andamento', 'autor', 'SÓ FIAT', '1ª UNIDADE JURISDICIONAL CÍVEL - 1º JD', 'BELO HORIZONTE', '19000', '2026-02-27'),
    ('0802678-97.2026.8.19.0208', 'CHARLES EDUARDO DE SOUZA ESTACIO DA SILVA', 'Indenizatória', 'concluido', 'autor', 'BANCO PAN S.A', '12º JUIZADO ESPECIAL CÍVEL DA REGIONAL DO MÉIER', 'RIO DE JANEIRO', '9800', '2025-12-10'),
    ('5046151-87.2022.8.13.0079', 'MARANATHA CONCEIÇÃO SANTOS LIMA', 'Indenizatória', 'em_andamento', 'reu', 'JULIO CESAR RODRIGUES SANTANA', '2ª VARA CÍVEL', 'CONTAGEM, MG', '29240', '2024-02-02'),
    ('5005174-82.2024.8.13.0079', 'MARANATHA CONCEIÇÃO SANTOS LIMA', 'Incidentes', 'em_andamento', 'autor', 'MITRA ARQUIDIOCESANA DE BELO HORIZONTE', '3ª VARA CÍVEL', 'CONTAGEM, MG', '1518', '2024-02-02'),
    ('5019587-47.2017.8.13.0079', 'SOPHIA EMANUELE GUIMARÃES CÂNDIDO', 'Indenizatória', 'arquivado', 'autor', 'LÍDER DPVAT', '3ª VARA CÍVEL', 'CONTAGEM, MG', '10000', '2017-09-06'),
    ('5014481-07.2017.8.13.0079', 'ANA LETICIA DO NASCIMENTO SIMOES ABREU', 'Execução ou embargos', 'em_andamento', 'exequente', 'MRV', '5ª VARA CÍVEL', 'CONTAGEM, MG', '35000', '2017-07-25'),
    ('5001915-16.2023.8.13.0079', 'ANA LETICIA DO NASCIMENTO SIMOES ABREU', 'Divórcio e União Estável', 'concluido', 'autor', 'DOUGLAS GERALDO ABREU', '3ª VARA DE FAMÍLIA', 'CONTAGEM', '1518', '2023-01-18'),
    ('5045267-24.2023.8.13.0079', 'ANA CAROLINA OLIVEIRA SANTOS', 'Indenizatória', 'em_andamento', 'autor', 'MRV', '5ª VARA CÍVEL', 'CONTAGEM, MG', '43000', '2023-09-07'),
    ('6024944-30.2025.4.06.3800', 'ANA CAROLINA OLIVEIRA SANTOS', 'Indenizatória', 'em_andamento', 'autor', 'MRV', '5ª VARA DE EXECUÇÃO FISCAL, EXTRAJUDICIAL E JEF ADUNTO', 'BELO HORIZONTE, MG', '1518', '2020-10-26')
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
