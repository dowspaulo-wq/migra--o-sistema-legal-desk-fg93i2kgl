DO $$
DECLARE
    r RECORD;
    v_client_id uuid;
    v_mapped_status text;
    v_mapped_position text;
    v_start_date text;
    v_valor numeric;
    v_clean_val text;
BEGIN
    -- Create temporary table to hold the raw migration data
    CREATE TEMP TABLE tmp_migration_data (
        numero_processo text,
        cliente_nome text,
        tipo text,
        status text,
        posicao_cliente text,
        parte_adversa text,
        vara text,
        comarca text,
        valor_causa text,
        data_inicio text
    ) ON COMMIT DROP;

    -- Insert the batch data provided
    INSERT INTO tmp_migration_data VALUES
    ('5149273-53.2023.8.13.0024', 'DAYANA JULIANA SANTOS VIANA RODRIGUES', 'Indenizatória', 'em_andamento', 'autor', 'JOSE AGUIMAR OLIVEIRA', 'Unidade Jurisdicional - 2º JD', 'Santa Luzia', '49999.99', '07/07/2023'),
    ('5153054-49.2024.8.13.0024', 'LUCAS GABRIEL NUNES MUNIZ', 'Indenizatória', 'concluido', 'autor', 'AZUL LINHAS AÉREAS BRASILEIRAS S/A', '4ª Unidade Jurisdicional Cível - 11º JD', 'Belo Horizonte', '10000', '23/06/2024'),
    ('5155906-12.2025.8.13.0024', 'NAYARA NUNES ALMEIDA', 'Outros', 'em_andamento', 'autor', 'MARCELO DA ROCHA LOPES', '1º JUIZADO DE VIOLÊNCIA DOMÉSTICA E FAMILIAR CONTRA A MULHER', 'BELO HORIZONTE', '0', '(null)'),
    ('5164112-15.2025.8.13.0024', 'JOSE EDGAR PROCOPIO DE ANDRADE NETO', 'Indenizatória', 'concluido', 'autor', 'VULCABRAS AZALEIA - SP COMERCIO DE ARTIGOS ESPORTIVOS LTDA. e outros', '5ª Unidade Jurisdicional Cível - 14º JD', 'Belo Horizonte', '10599', '(null)'),
    ('5182613-95.2017.8.13.0024', 'BRENO AUGUSTO PINHEIRO MACIEL', 'Outros', 'em_andamento', 'autor', 'ANDERSON XAVIER DA SILVA', 'CENTRASE Cível de Belo Horizonte - Central de Cumprimento de Sentenças', 'Belo Horizonte', '644974', '18/12/2017'),
    ('5184662-31.2025.8.13.0024', 'PABLO WENDER DE JESUS RODRIGUES', 'Incidentes', 'em_andamento', 'autor', 'RAYANNE LETICIA SILVA LIMA e OUTROS', '2ª UNIDADE JURISDICIONAL CÍVEL - 6ª JD', 'BELO HORIZONTE', '1518', '(null)'),
    ('5191444-54.2025.8.13.0024', 'JOSE JANUARIO PINTO NETO', 'Indenizatória', 'em_andamento', 'autor', 'CONCESSIONARIA BR-040 S.A.', '1ª Unidade Jurisdicional Cível - 2º JD', 'Belo Horizonte', '15075', '01/09/2025'),
    ('5205297-04.2023.8.13.0024', 'KARINE CANDIDO JARDIM', 'Indenizatória', 'em_andamento', 'autor', '123 VIAGENS E TURISMO LTDA', '4ª Unidade Jurisdicional Cível - 12º JD', 'Belo Horizonte', '32780.21', '07/09/2023'),
    ('5219025-15.2023.8.13.0024', 'THANUS MARIO TORRES CUNHA', 'Execução ou embargos', 'em_andamento', 'executado', 'MUNICIPIO DE BELO HORIZONTE', '1ª VARA DE FEITOS TRIBUTÁRIOS', 'BELO HORIZONTE', '78000', '(null)'),
    ('5220497-17.2024.8.13.0024', 'JUSSARA DA MOTTA COSTA', 'Indenizatória', 'em_andamento', 'autor', 'FUNDACAO HOSPITALAR DO ESTADO DE MINAS GERAIS', '1ª Unidade Jurisdicional da Fazenda Pública do Juizado Especial 42º JD Belo Horizonte', 'Belo Horizonte', '70000', '03/09/2024'),
    ('5237070-33.2024.8.13.0024', 'LIDIANE SARAIVA SANTOS', 'Indenizatória', 'concluido', 'autor', 'BANCO BRADESCO S.A.', '6ª Unidade Jurisdicional Cível - 18º JD', 'Belo Horizonte', '15000', '20/09/2024'),
    ('5255836-37.2024.8.13.0024', 'LEONARDO MARTINS DA SILVA', 'Indenizatória', 'em_andamento', 'autor', 'CONQUISTA MULTIMARCAS LTDA - ME', '3ª UNIDADE JURISDICIONAL CÍVEL - 9º JD', 'BELO HORIZONTE', '1518', '09/10/2024'),
    ('5261377-22.2022.8.13.0024', 'ELIENA CLAUDIA PEREIRA TORRES', 'Inventário', 'em_andamento', 'inventariante', 'ELENICE MADUREIRA PEREIRA', '2ª VARA DE FAMÍLIA E SUCESSÕES', 'BELO HORIZONTE', '1518', '(null)'),
    ('5268208-52.2023.8.13.0024', 'ASSOCIAÇÃO MAIS VANTAGENS DO BRASIL - AMV BRASIL', 'Indenizatória', 'em_andamento', 'autor', 'MARLUZIA LOPES DOS SANTOS', '36ª Vara Cível', 'Belo Horizonte', '522697', '27/10/2023'),
    ('5291508-43.2023.8.13.0024', 'ALINE BARBOSA SILVA LOPES', 'Indenizatória', 'em_andamento', 'autor', 'BANCO PAN S.A.', '17ª VARA CÍVEL', 'BELO HORIZONTE', '33515.3', '(null)'),
    ('5306665-22.2024.8.13.0024', 'GUSTAVO HENRIQUE DE SOUZA ALVES', 'Inventário', 'em_andamento', 'inventariante', 'SANDRA DE SOUZA SILVA', '2ª VARA DE SUCESSÕES E AUSÊNCIA', 'BELO HORIZONTE', '1518', '(null)'),
    ('5309927-14.2023.8.13.0024', 'MARIA HELENA BARBOSA', 'Indenizatória', 'concluido', 'autor', 'OI S.A.', '3ª Unidade Jurisdicional Cível - 7º JD', 'Belo Horizonte', '20358', '19/12/2023'),
    ('6020665-98.2025.4.06.3800', 'JESSICA CRISTINA BARROS DIOGO', 'Previdenciário', 'em_andamento', 'autor', 'INSS', '8ª VARA JEF SEÇÃO JUDICIÁRIA DE MINAS GERAIS', 'BELO HORIZONTE', '1518', '(null)'),
    ('6029645-34.2015.8.13.0024', 'NATHALIA HELENA DOS SANTOS', 'Inventário', 'em_andamento', 'inventariante', 'ESPÓLIO DE WILSON DOS SANTOS', '3ª VARA DE SUCESSÕES E AUSÊNCIA', 'BELO HORIZONTE', '1518', '(null)'),
    ('6047772-54.2024.4.06.3800', 'HUDSON GOMES DA SILVA', 'Indenizatória', 'em_andamento', 'autor', 'CEF', '3ª VARA CÍVEL E JEF ADJUNTO', 'BELO HORIZONTE', '350000', '(null)'),
    ('6062597-03.2024.4.06.3800', 'JEFFERSON SIQUEIRA BARROSO', 'Previdenciário', 'em_andamento', 'autor', 'INSS', '13ª VARA CÍVEL E JEF ADJUNTO', 'BELO HORIZONTE', '1518', '13/12/2024'),
    ('6336978-61.2025.4.06.3800', 'GUSTAVO MENDES LOIOLA', 'Indenizatória', 'concluido', 'autor', 'FIES', '16ª VARA CÍVEL E JEF ADJUNTO', 'BELO HORIZONTE', '3214615', '28/08/2025'),
    ('9031005-45.2018.8.13.0024', 'LUIZ EDUARDO SALES DE SOUZA', 'Outros', 'em_andamento', 'autor', 'MAXIMUS DIGITAL FOMENTO MERCANTIL LTDA', '3ª Unidade Jurisdicional Cível - 9º JD', 'Belo Horizonte', '7000', '29/03/2022'),
    ('9032364-30.2018.8.13.0024', 'DAIANE NOGUEIRA DA CRUZ', 'Outros', 'em_andamento', 'autor', 'ARCOMIG ASSOCIACAO DE RISCO AUTOMOTIVO DE MINAS GERAIS e outro', '5ª Unidade Jurisdicional Cível - 13º JD', 'Belo Horizonte', '37950', '30/03/2022'),
    ('9336196-18.2006.8.13.0024', 'NATHALIA HELENA DOS SANTOS', 'Execução ou embargos', 'em_andamento', 'exequente', 'CARLOS EDUARDO DOS REIS', '1ª VARA DE FAMÍLIA', 'BELO HORIZONTE', '36762', '(null)');

    FOR r IN SELECT * FROM tmp_migration_data LOOP
        -- 1. Client Lookup or Creation
        SELECT id INTO v_client_id FROM public.clients WHERE name = r.cliente_nome LIMIT 1;
        
        IF v_client_id IS NULL THEN
            v_client_id := gen_random_uuid();
            INSERT INTO public.clients (id, name, type, status)
            VALUES (v_client_id, r.cliente_nome, 'PF', 'Ativo');
        END IF;

        -- 2. Map Process Status
        IF r.status = 'em_andamento' THEN
            v_mapped_status := 'Em andamento';
        ELSIF r.status = 'concluido' THEN
            v_mapped_status := 'Concluído';
        ELSE
            v_mapped_status := r.status;
        END IF;

        -- 3. Map Client Position
        IF r.posicao_cliente = 'autor' THEN
            v_mapped_position := 'Autor';
        ELSIF r.posicao_cliente = 'executado' THEN
            v_mapped_position := 'Executado';
        ELSIF r.posicao_cliente = 'inventariante' THEN
            v_mapped_position := 'Inventariante';
        ELSIF r.posicao_cliente = 'exequente' THEN
            v_mapped_position := 'Exequente';
        ELSE
            v_mapped_position := r.posicao_cliente;
        END IF;

        -- 4. Map Start Date (convert DD/MM/YYYY to YYYY-MM-DD)
        IF r.data_inicio = '(null)' OR r.data_inicio IS NULL THEN
            v_start_date := NULL;
        ELSE
            v_start_date := to_char(to_date(r.data_inicio, 'DD/MM/YYYY'), 'YYYY-MM-DD');
        END IF;

        -- 5. Sanitize Currency Value (Remove thousand separators and suffixes)
        v_clean_val := r.valor_causa;
        v_clean_val := replace(v_clean_val, ' MG', '');
        v_clean_val := replace(v_clean_val, ' R$', '');
        v_clean_val := replace(v_clean_val, 'R$', '');
        v_clean_val := trim(v_clean_val);
        -- Treat dot as thousand separator if format matches exact X.XXX pattern 
        -- while preserving standard decimal dots (e.g. 49999.99)
        IF v_clean_val ~ '^\d+\.\d{3}$' THEN
            v_clean_val := replace(v_clean_val, '.', '');
        END IF;
        
        v_valor := v_clean_val::numeric;

        -- 6. Insert or Upsert Case (Will trigger "on_case_created" to automate tasks)
        INSERT INTO public.cases (
            "clientId",
            number,
            position,
            "adverseParty",
            type,
            status,
            court,
            comarca,
            state,
            value,
            "startDate",
            system
        ) VALUES (
            v_client_id,
            r.numero_processo,
            v_mapped_position,
            r.parte_adversa,
            r.tipo,
            v_mapped_status,
            r.vara,
            r.comarca,
            'MG',
            v_valor,
            v_start_date,
            'PJE'
        )
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

    END LOOP;
END $$;
