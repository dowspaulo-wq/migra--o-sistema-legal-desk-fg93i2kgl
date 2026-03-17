DO $$
DECLARE
    item jsonb;
    v_client_id uuid;
    v_normalized_date text;
    v_normalized_value numeric;
    v_client_type text;
    raw_data jsonb := '[
        {"processNumber": "0000001-01.2023.8.26.0001", "clientName": "João da Silva", "type": "Cível", "status": "Em andamento", "position": "Autor", "adverseParty": "Banco do Brasil", "court": "1ª Vara Cível", "comarca": "São Paulo", "state": "SP", "value": "10.500,00", "startDate": "15/01/2023"},
        {"processNumber": "0000002-02.2023.8.26.0001", "clientName": "Maria Oliveira", "type": "Trabalhista", "status": "Pendente", "position": "Reclamante", "adverseParty": "Empresa XPTO", "court": "2ª Vara do Trabalho", "comarca": "São Paulo", "state": "SP", "value": "25.000,50", "startDate": "20/02/2023"},
        {"processNumber": "0000003-03.2023.8.26.0001", "clientName": "Carlos Souza", "type": "Família", "status": "Concluído", "position": "Requerente", "adverseParty": "Ana Souza", "court": "1ª Vara de Família", "comarca": "Campinas", "state": "SP", "value": "0,00", "startDate": "05/03/2023"},
        {"processNumber": "0000004-04.2023.8.26.0001", "clientName": "João da Silva", "type": "Tributário", "status": "Em andamento", "position": "Autor", "adverseParty": "União", "court": "3ª Vara Federal", "comarca": "São Paulo", "state": "SP", "value": "150.000,00", "startDate": "10/04/2023"},
        {"processNumber": "0000005-05.2023.8.26.0001", "clientName": "Empresa ABC Ltda", "type": "Cível", "status": "Pendente", "position": "Réu", "adverseParty": "Fornecedor XYZ", "court": "4ª Vara Cível", "comarca": "Osasco", "state": "SP", "value": "5.320,75", "startDate": "12/05/2023"},
        {"processNumber": "0000006-06.2023.8.26.0001", "clientName": "Lucas Ferreira", "type": "Criminal", "status": "Em andamento", "position": "Réu", "adverseParty": "Ministério Público", "court": "1ª Vara Criminal", "comarca": "Santos", "state": "SP", "value": "0,00", "startDate": "22/06/2023"},
        {"processNumber": "0000007-07.2023.8.26.0001", "clientName": "Fernanda Lima", "type": "Trabalhista", "status": "Arquivado", "position": "Reclamante", "adverseParty": "Loja de Roupas", "court": "1ª Vara do Trabalho", "comarca": "Guarulhos", "state": "SP", "value": "12.000,00", "startDate": "30/07/2023"},
        {"processNumber": "0000008-08.2023.8.26.0001", "clientName": "Roberto Gomes", "type": "Cível", "status": "Em andamento", "position": "Autor", "adverseParty": "Seguradora", "court": "2ª Vara Cível", "comarca": "Ribeirão Preto", "state": "SP", "value": "8.450,20", "startDate": "14/08/2023"},
        {"processNumber": "0000009-09.2023.8.26.0001", "clientName": "Amanda Costa", "type": "Família", "status": "Em andamento", "position": "Requerida", "adverseParty": "Pedro Costa", "court": "2ª Vara de Família", "comarca": "São José dos Campos", "state": "SP", "value": "50.000,00", "startDate": "02/09/2023"},
        {"processNumber": "0000010-10.2023.8.26.0001", "clientName": "Empresa ABC Ltda", "type": "Tributário", "status": "Pendente", "position": "Autora", "adverseParty": "Estado de São Paulo", "court": "1ª Vara da Fazenda Pública", "comarca": "São Paulo", "state": "SP", "value": "500.000,00", "startDate": "18/10/2023"},
        {"processNumber": "0000011-11.2023.8.26.0001", "clientName": "Juliana Martins", "type": "Trabalhista", "status": "Em andamento", "position": "Reclamada", "adverseParty": "Ex-funcionário", "court": "3ª Vara do Trabalho", "comarca": "Campinas", "state": "SP", "value": "35.000,00", "startDate": "01/11/2023"},
        {"processNumber": "0000012-12.2023.8.26.0001", "clientName": "Marcos Silva", "type": "Cível", "status": "Concluído", "position": "Autor", "adverseParty": "Companhia de Energia", "court": "Juizado Especial Cível", "comarca": "São Bernardo do Campo", "state": "SP", "value": "2.500,00", "startDate": "15/11/2023"},
        {"processNumber": "0000013-13.2023.8.26.0001", "clientName": "Camila Alves", "type": "Cível", "status": "Em andamento", "position": "Ré", "adverseParty": "Condomínio", "court": "1ª Vara Cível", "comarca": "Santo André", "state": "SP", "value": "15.000,00", "startDate": "20/12/2023"},
        {"processNumber": "0000014-14.2023.8.26.0001", "clientName": "Paulo Ribeiro", "type": "Família", "status": "Pendente", "position": "Requerente", "adverseParty": "Ex-esposa", "court": "1ª Vara de Família", "comarca": "Sorocaba", "state": "SP", "value": "0,00", "startDate": "10/01/2024"},
        {"processNumber": "0000015-15.2023.8.26.0001", "clientName": "Construtora XYZ", "type": "Cível", "status": "Em andamento", "position": "Autora", "adverseParty": "Cliente inadimplente", "court": "5ª Vara Cível", "comarca": "São Paulo", "state": "SP", "value": "120.000,00", "startDate": "05/02/2024"},
        {"processNumber": "0000016-16.2023.8.26.0001", "clientName": "Tiago Mendes", "type": "Trabalhista", "status": "Arquivado", "position": "Reclamante", "adverseParty": "Indústria", "court": "2ª Vara do Trabalho", "comarca": "Diadema", "state": "SP", "value": "45.000,00", "startDate": "28/02/2024"},
        {"processNumber": "0000017-17.2023.8.26.0001", "clientName": "Letícia Carvalho", "type": "Cível", "status": "Em andamento", "position": "Autora", "adverseParty": "Plano de Saúde", "court": "3ª Vara Cível", "comarca": "Jundiaí", "state": "SP", "value": "30.000,00", "startDate": "15/03/2024"},
        {"processNumber": "0000018-18.2023.8.26.0001", "clientName": "Rafael Nunes", "type": "Criminal", "status": "Pendente", "position": "Réu", "adverseParty": "Justiça Pública", "court": "2ª Vara Criminal", "comarca": "Mauá", "state": "SP", "value": "0,00", "startDate": "02/04/2024"},
        {"processNumber": "0000019-19.2023.8.26.0001", "clientName": "Tatiana Rosa", "type": "Família", "status": "Em andamento", "position": "Requerente", "adverseParty": "Pai do menor", "court": "1ª Vara de Família", "comarca": "Bauru", "state": "SP", "value": "0,00", "startDate": "20/04/2024"},
        {"processNumber": "0000020-20.2023.8.26.0001", "clientName": "Supermercado Boa Compra", "type": "Tributário", "status": "Concluído", "position": "Autor", "adverseParty": "Receita Federal", "court": "2ª Vara Federal", "comarca": "São Paulo", "state": "SP", "value": "80.000,00", "startDate": "10/05/2024"},
        {"processNumber": "0000021-21.2023.8.26.0001", "clientName": "Bruno Moraes", "type": "Cível", "status": "Em andamento", "position": "Autor", "adverseParty": "Companhia Aérea", "court": "Juizado Especial Cível", "comarca": "Campinas", "state": "SP", "value": "10.000,00", "startDate": "25/05/2024"},
        {"processNumber": "0000022-22.2023.8.26.0001", "clientName": "Sofia Vieira", "type": "Trabalhista", "status": "Pendente", "position": "Reclamada", "adverseParty": "Empregada doméstica", "court": "1ª Vara do Trabalho", "comarca": "São Paulo", "state": "SP", "value": "15.000,00", "startDate": "12/06/2024"},
        {"processNumber": "0000023-23.2023.8.26.0001", "clientName": "Eduardo Pinto", "type": "Cível", "status": "Em andamento", "position": "Réu", "adverseParty": "Banco", "court": "4ª Vara Cível", "comarca": "Piracicaba", "state": "SP", "value": "40.000,00", "startDate": "05/07/2024"},
        {"processNumber": "0000024-24.2023.8.26.0001", "clientName": "Aline Castro", "type": "Família", "status": "Em andamento", "position": "Requerente", "adverseParty": "Ex-marido", "court": "3ª Vara de Família", "comarca": "São Paulo", "state": "SP", "value": "0,00", "startDate": "18/08/2024"},
        {"processNumber": "0000025-25.2023.8.26.0001", "clientName": "Transportadora Rápida", "type": "Cível", "status": "Arquivado", "position": "Autora", "adverseParty": "Cliente B", "court": "1ª Vara Cível", "comarca": "Guarulhos", "state": "SP", "value": "22.500,00", "startDate": "02/09/2024"},
        {"processNumber": "0000026-26.2023.8.26.0001", "clientName": "Felipe Barros", "type": "Criminal", "status": "Pendente", "position": "Réu", "adverseParty": "Justiça Pública", "court": "1ª Vara Criminal", "comarca": "Franca", "state": "SP", "value": "0,00", "startDate": "15/10/2024"},
        {"processNumber": "0000027-27.2023.8.26.0001", "clientName": "Bianca Rocha", "type": "Trabalhista", "status": "Em andamento", "position": "Reclamante", "adverseParty": "Clínica Médica", "court": "2ª Vara do Trabalho", "comarca": "Ribeirão Preto", "state": "SP", "value": "60.000,00", "startDate": "01/11/2024"},
        {"processNumber": "0000028-28.2023.8.26.0001", "clientName": "Igor Monteiro", "type": "Cível", "status": "Concluído", "position": "Autor", "adverseParty": "Telefonia", "court": "Juizado Especial Cível", "comarca": "São Paulo", "state": "SP", "value": "5.000,00", "startDate": "20/11/2024"},
        {"processNumber": "0000029-29.2023.8.26.0001", "clientName": "Lívia Farias", "type": "Família", "status": "Em andamento", "position": "Requerida", "adverseParty": "Mãe do menor", "court": "1ª Vara de Família", "comarca": "Santos", "state": "SP", "value": "0,00", "startDate": "10/12/2024"}
    ]';
BEGIN
    FOR item IN SELECT * FROM jsonb_array_elements(raw_data)
    LOOP
        -- 1. Find or create client
        SELECT id INTO v_client_id 
        FROM public.clients 
        WHERE name ILIKE (item->>'clientName') 
        LIMIT 1;

        IF v_client_id IS NULL THEN
            v_client_id := gen_random_uuid();
            
            -- Basic logic to assume client type based on name hints
            IF item->>'clientName' ILIKE '%Ltda%' OR item->>'clientName' ILIKE '%S/A%' OR item->>'clientName' ILIKE '%Construtora%' OR item->>'clientName' ILIKE '%Supermercado%' OR item->>'clientName' ILIKE '%Transportadora%' THEN
                v_client_type := 'PJ';
            ELSE
                v_client_type := 'PF';
            END IF;

            INSERT INTO public.clients (id, name, type, status, "isSpecial", created_at)
            VALUES (v_client_id, item->>'clientName', v_client_type, 'Ativo', false, NOW());
        END IF;

        -- 2. Normalize Date (DD/MM/YYYY to YYYY-MM-DD)
        BEGIN
            v_normalized_date := to_char(to_date(item->>'startDate', 'DD/MM/YYYY'), 'YYYY-MM-DD');
        EXCEPTION WHEN OTHERS THEN
            v_normalized_date := NULL;
        END;

        -- 3. Normalize Value (removing formatting dots and using dot as decimal separator)
        BEGIN
            v_normalized_value := REPLACE(REPLACE(item->>'value', '.', ''), ',', '.')::numeric;
        EXCEPTION WHEN OTHERS THEN
            v_normalized_value := 0;
        END;

        -- 4. Insert or Update case
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
            "isSpecial",
            "isProblematic",
            created_at
        ) VALUES (
            v_client_id,
            item->>'processNumber',
            item->>'position',
            item->>'adverseParty',
            item->>'type',
            item->>'status',
            item->>'court',
            item->>'comarca',
            item->>'state',
            v_normalized_value,
            v_normalized_date,
            false,
            false,
            NOW()
        ) ON CONFLICT (number) DO NOTHING;

    END LOOP;
END $$;
