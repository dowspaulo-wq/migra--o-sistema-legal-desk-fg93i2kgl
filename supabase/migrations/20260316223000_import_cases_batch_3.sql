DO $$
BEGIN
  -- Create a temporary table to hold raw data
  CREATE TEMP TABLE tmp_batch3_cases (
    number text,
    client_name text,
    type text,
    status text,
    position text,
    adverseParty text,
    court text,
    comarca text,
    value text,
    startDate text
  ) ON COMMIT DROP;

  -- Insert raw data into temporary table
  INSERT INTO tmp_batch3_cases (number, client_name, type, status, position, adverseParty, court, comarca, value, startDate)
  VALUES
    ('1001160-47.2026.8.13.0114', 'ANA FLÁVIA SIQUEIRA NUNES', 'Alimentos', 'em_andamento', 'autor', 'ELI MURILO GONÇALVES RIOS JUNIOR', '2ª VARA DE FAMÍLIA', 'IBIRITÉ', '15480', '12/02/2026'),
    ('100', 'ELVIMAR INACIO DO ROSARIO', 'Incidentes', 'aguardando_documentos', 'autor', NULL, NULL, NULL, NULL, NULL),
    ('1012959-66.2026.8.13.0024', 'KIURY NOGUEIRA MARTINS', 'Indenizatória', 'em_andamento', 'autor', 'NACIONAL AUTO CLUBE DE BENEFICIOS...', '3ª UNIDADE JURISDICIONAL CÍVEL - 9º JD', 'BELO HORIZONTE', '32589', '27/01/2026'),
    ('1004609-89.2026.8.13.0024', 'FREDERICO BRUNO NEVES DE ARAUJO', 'Indenizatória', 'em_andamento', 'autor', 'MG CAR BRASIL CLUBE DE BENEFÍCIOS...', 'JESP - 4ª Unidade Jurisdicional Cível', 'Belo Horizonte', '37983', '20/01/2026'),
    ('1010738-13.2026.8.13.0024', 'RAFAEL DE SOUSA LIMA', 'Indenizatória', 'em_andamento', 'autor', 'BH EXPO HOTEL LTDA', 'JESP 2ª Unidade Jurisdicional Cível', 'Belo Horizonte', '50750', '23/01/2026'),
    ('5003760-77.2025.8.13.0317', 'YASMIM DIAS DE OLIVEIRA', 'Indenizatória', 'em_andamento', 'autor', 'SKY BRASIL SERVICOS LTDA', 'Unidade Jurisdicional Única', 'Itabira', '57128.16', '13/05/2025'),
    ('5054126-63.2024.8.13.0024', 'WTEMBERG MARQUES DE OLIVEIRA', 'Indenizatória', 'concluido', 'autor', 'JOSE DE MACEDO BRITO NETO', '8ª Unidade Jurisdicional Cível - 22º JD', 'Belo Horizonte', '1603', '05/03/2024'),
    ('5001379-89.2023.8.13.0245', 'WTEMBERG MARQUES DE OLIVEIRA', 'Outros', 'em_andamento', 'autor', 'HOME EMPREENDIMENTOS IMOBILIARIOS...', '1ª Vara Cível', 'Santa Luzia', '52792.6', '30/01/2023'),
    ('9052584-49.2018.8.13.0024', 'VIVIANE XAVIER MARTINS MEDEIROS', 'Outros', 'concluido', 'autor', 'MARCOS LUIZ BATISTA MARTINELLI e outro', '6ª Unidade Jurisdicional Cível - 16º JD', 'Belo Horizonte', '19950', '04/05/2022'),
    ('5077049-49.2025.8.13.0024', 'VINICIUS MELO PEDROSA', 'Indenizatória', 'concluido', 'autor', 'AZUL LINHAS AÉREAS BRASILEIRAS S/A', '2ª Unidade Jurisdicional Cível - 6º JD', 'Belo Horizonte', '15000', '27/03/2025'),
    ('5162458-27.2024.8.13.0024', 'VILMA AUGUSTA DE OLIVEIRA DIAS', 'Outros', 'em_andamento', 'autor', 'GENERAL MOTORS DO BRASIL LTDA', '24ª Vara Cível', 'Belo Horizonte', '20000', '02/06/2024'),
    ('5043036-58.2024.8.13.0024', 'VILMA AUGUSTA DE OLIVEIRA DIAS', 'Outros', 'em_andamento', 'autor', 'BRADESCO AUTO/RE COMPANHIA DE SEGUROS', '11ª Vara Cível', 'Belo Horizonte', '38076', '22/02/2024'),
    ('5195551-83.2021.8.13.0024', 'VARLEINE MOREIRA PINTO', 'Indenizatória', 'concluido', 'autor', 'SEARA ALIMENTOS LTDA', '30ª Vara Cível', 'Belo Horizonte', '16528', '03/12/2021'),
    ('5103259-11.2023.8.13.0024', 'VANESSA FERREIRA CAMPOS SERRANO', 'Indenizatória', 'concluido', 'autor', 'IBERIA LINEAS AEREAS DE ESPANA S.A.', '2ª Unidade Jurisdicional Cível - 4º JD', 'Belo Horizonte', '28226', '16/05/2023'),
    ('5013657-14.2018.8.13.0079', 'TYRONE MIRANDA SANTOS', 'Outros', 'em_andamento', 'autor', 'JR CONSTRUCOES E REFORMA LTDA - ME', '1ª Unidade Jurisdicional - JESP - 1º JD', 'Contagem', '37700', '11/05/2018'),
    ('5003496-93.2025.8.13.0209', 'THIAGO JOSE DA ROCHA RIBEIRO', 'Indenizatória', 'em_andamento', 'autor', 'TAM LINHAS AEREAS S/A', 'Unidade Jurisdicional', 'Curvelo', '15000', '08/05/2025'),
    ('5111962-91.2024.8.13.0024', 'TATHIANA ANDREIA MARTINS MESSIAS GUALBERTO', 'Outros', 'em_andamento', 'autor', 'AMERICO GUALBERTO DA CRUZ NETO', '9ª Vara de Família', 'Belo Horizonte', '1000', '07/05/2024'),
    ('5000985-20.2024.8.13.0319', 'SUELI DUARTE MONTEIRO', 'Execução ou embargos', 'em_andamento', 'embargado', 'MILENE BARBOSA DE FREITAS', '1ª Vara Cível', 'Itabirito', '70000', '09/03/2024'),
    ('9047600-22.2018.8.13.0024', 'SILVA & REIS TRANSPORTE DE CARGAS EIRELI - ME', 'Indenizatória', 'em_andamento', 'autor', 'CARIC COMPANHIA AMERICANA...', '7ª Unidade Jurisdicional Cível - 21º JD', 'Belo Horizonte', '37854', '25/04/2022'),
    ('5000099-24.2022.8.13.0567', 'SCHESMAN MARTINS', 'Outros', 'concluido', 'autor', 'YANDRA SANTOS MARTINS e outro', '1ª Vara Cível', 'Sabará', '40645', '10/02/2022'),
    ('5207640-07.2022.8.13.0024', 'SAMUEL MARTINS KANNO', 'Indenizatória', 'em_andamento', 'autor', 'UNIMED BELO HORIZONTE', '5ª Vara Cível', 'Belo Horizonte', '50000', '27/09/2022'),
    ('5149926-84.2025.8.13.0024', 'ROSELYS VELLOSO DE CASTILHO', 'Indenizatória', 'concluido', 'autor', 'AZUL LINHAS AÉREAS BRASILEIRAS S/A', '10ª Unidade Jurisdicional Cível - 30º JD', 'Belo Horizonte', '31550', '02/06/2025'),
    ('5000381-42.2022.8.13.0024', 'RONEGES VITALINO DA SILVA', 'Inventário', 'em_andamento', 'autor', NULL, '4ª Vara de Sucessões e Ausência', 'Belo Horizonte', '1', '03/02/2022'),
    ('5199336-53.2021.8.13.0024', 'RODRIGO HIGINIO DE SOUZA E VALGAS', 'Alimentos', 'concluido', 'autor', 'ISABEL DILLY SCORALICK VALGAS', '5ª Vara de Família', 'Belo Horizonte', '1560', '09/12/2021'),
    ('5117590-95.2023.8.13.0024', 'RAFAELA RODRIGUES DA SILVA', 'Outros', 'em_andamento', 'autor', 'DANIELA RODRIGUES DA SILVA', 'CENTRASE Cível', 'Belo Horizonte', '9469', '31/05/2023'),
    ('5176523-61.2023.8.13.0024', 'RAFAELA RODRIGUES DA SILVA', 'Outros', 'em_andamento', 'autor', 'ALLERGAN PRODUTOS FARMACEUTICOS', '27ª Vara Cível', 'Belo Horizonte', '87884', '09/08/2023'),
    ('5115519-23.2023.8.13.0024', 'RAFAELA RODRIGUES DA SILVA', 'Outros', 'concluido', 'autor', 'TIM CELULAR S.A', '4ª Unidade Jurisdicional Cível - 12º JD', 'Belo Horizonte', '15000', '29/05/2023'),
    ('5077034-80.2025.8.13.0024', 'RAFAEL DO NASCIMENTO GUEDES E SILVA', 'Indenizatória', 'concluido', 'autor', 'AZUL LINHAS AÉREAS BRASILEIRAS S/A', '2ª Unidade Jurisdicional Cível - 4º JD', 'Belo Horizonte', '15000', '27/03/2025'),
    ('5003689-67.2025.8.13.0740', 'PEDRO BERNARDES SILVA FILHO', 'Outros', 'em_andamento', 'autor', 'MARIA HERCILIA DA SILVA GUIMARAES', 'Vara Única', 'Juatuba', '20000', '02/10/2025');

  -- Insert missing clients. 
  -- Creating them as Type: Física and Status: Ativo to ensure relationship exists.
  INSERT INTO public.clients (name, document, type, status, "isSpecial")
  SELECT DISTINCT TRIM(client_name), gen_random_uuid()::text, 'Física', 'Ativo', false
  FROM tmp_batch3_cases
  WHERE client_name IS NOT NULL AND TRIM(client_name) <> ''
  ON CONFLICT (name) DO NOTHING;

  -- Insert or Update cases linking them to their corresponding clients
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
    CASE
      WHEN v.status = 'em_andamento' THEN 'Em andamento'
      WHEN v.status = 'concluido' THEN 'Concluído'
      WHEN v.status = 'aguardando_documentos' THEN 'Aguardando documentos'
      ELSE NULLIF(TRIM(v.status), '')
    END,
    NULLIF(TRIM(v.position), ''),
    NULLIF(TRIM(v.adverseParty), ''),
    NULLIF(TRIM(v.court), ''),
    NULLIF(TRIM(v.comarca), ''),
    COALESCE(NULLIF(TRIM(v.value), ''), '0')::numeric,
    CASE
      WHEN v.startDate IS NOT NULL AND TRIM(v.startDate) <> '' THEN
        to_char(to_date(TRIM(v.startDate), 'DD/MM/YYYY'), 'YYYY-MM-DD')
      ELSE NULL
    END
  FROM tmp_batch3_cases v
  LEFT JOIN public.clients c ON c.name = TRIM(v.client_name)
  ON CONFLICT (number) DO UPDATE SET
    "clientId" = EXCLUDED."clientId",
    type = COALESCE(EXCLUDED.type, public.cases.type),
    status = EXCLUDED.status,
    position = EXCLUDED.position,
    "adverseParty" = EXCLUDED."adverseParty",
    court = EXCLUDED.court,
    comarca = EXCLUDED.comarca,
    value = EXCLUDED.value,
    "startDate" = EXCLUDED."startDate";

END $$;
