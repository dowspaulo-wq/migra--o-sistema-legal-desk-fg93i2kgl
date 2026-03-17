DO $$
DECLARE
    process_data jsonb := '[
        {"number": "0", "client": "LUIZ HENRIQUE DE SOUZA SILVA", "type": "Indenizatória", "status": "Pendente", "position": "Autor", "adverseParty": "ALAMO PROTEÇÃO VEICULAR", "court": null, "comarca": null, "value": 0, "startDate": null},
        {"number": "4", "client": "DOUGLAS PAULO DOS SANTOS", "type": "Indenizatória", "status": "Em andamento", "position": "Autor", "adverseParty": "FIES", "court": null, "comarca": null, "value": 0, "startDate": null},
        {"number": "20", "client": "TATIANE ELIAS SILVEIRA", "type": "Indenizatória", "status": "Pendente", "position": "Autor", "adverseParty": null, "court": null, "comarca": null, "value": 0, "startDate": null},
        {"number": "22", "client": "HÉLIO PAULO DOS SANTOS", "type": "Anulatória", "status": "Em andamento", "position": "Autor", "adverseParty": "BANCO DO BRASIL SA", "court": null, "comarca": "BELO HORIZONTE", "value": 0, "startDate": null},
        {"number": "78", "client": "THIAGO FILIPE DE MORAES GOMES", "type": "Indenizatória", "status": "Em andamento", "position": "Autor", "adverseParty": "Petrucci", "court": null, "comarca": "CAMPINAS", "value": 0, "startDate": null},
        {"number": "100", "client": "ELVIMAR INACIO DO ROSARIO", "type": "Incidentes", "status": "Pendente", "position": "Autor", "adverseParty": null, "court": null, "comarca": null, "value": 0, "startDate": null},
        {"number": "153", "client": "VANESSA ESTEVES", "type": "Previdenciário", "status": "Em andamento", "position": "Autor", "adverseParty": "INSS", "court": null, "comarca": null, "value": 0, "startDate": null},
        {"number": "0000278-35.2026.8.26.0084", "client": "LORENZO GAEL DA SILVA MOURA", "type": "Alimentos", "status": "Em andamento", "position": "Autor", "adverseParty": "SAULO EMANUEL DE MOURA", "court": "1ª VARA CÍVEL", "comarca": "GOVERNADOR VALADARES, MG", "value": 9200, "startDate": null},
        {"number": "0004834-96.2025.8.17.8222", "client": "VENCESLAU MORAES DE LIMA FILHO", "type": "Indenizatório", "status": "Em andamento", "position": "Autor", "adverseParty": "ALLIANZ SEGUROS S.A", "court": "2º JUIZADO ESPECIAL CÍVEL", "comarca": "PAULISTA, PE", "value": 282508, "startDate": null},
        {"number": "0010930-07.2025.5.03.0030", "client": "MAYANE DINIZ COSTA DE ABREU", "type": "Reclamatória trabalhista", "status": "Em andamento", "position": "Reclamante", "adverseParty": "ramos & silva solucoes em negocios ltda", "court": "2ª VARA DO TRABALHO", "comarca": "CONTAGEM, MG", "value": 1653177, "startDate": "2025-06-04"},
        {"number": "0011834-27.2025.5.03.0030", "client": "JOAO VITOR SILVA DE CARVALHO", "type": "Reclamatória trabalhista", "status": "Em andamento", "position": "Autor", "adverseParty": "HORTIFARIA COMERCIO ATACADISTA", "court": "2ª VARA DO TRABALHO", "comarca": "BELO HORIZONTE, MG", "value": 163712.77, "startDate": "2025-10-22"},
        {"number": "0825049-89.2025.8.19.0208", "client": "CHARLES EDUARDO DE SOUZA ESTACIO DA SILVA", "type": "Indenizatória", "status": "Em andamento", "position": "Autor", "adverseParty": "UTIL ASSOCIACAO DE PROTECAO VEICULAR", "court": "13º JUIZADO ESPECIAL CÍVEL", "comarca": "RIO DE JANEIRO, RJ", "value": 34923.92, "startDate": null},
        {"number": "1001529-49.2026.8.13.0079", "client": "JOÃO VITOR BATISTA DOS SANTOS", "type": "Anulatória", "status": "Em andamento", "position": "Autor", "adverseParty": "WENDER ANTONIO DOS REIS SANTOS", "court": "6ª VARA CÍVEL", "comarca": "CONTAGEM, MG", "value": 30000, "startDate": "2026-01-20"},
        {"number": "1001930-82.2025.8.13.0079", "client": "ANA CELESTINO DOS SANTOS", "type": "Divórcio e União Estável", "status": "Em andamento", "position": "Autor", "adverseParty": "LUCAS FELLIPY FERREIRA E OUTROS", "court": "2ª VARA DE FAMÍLIA E SUCESSÕES", "comarca": "CONTAGEM, MG", "value": 1518, "startDate": "2025-10-14"},
        {"number": "1002537-03.2025.8.26.0704", "client": "LUIS GUILHERME TILLIER", "type": "Indenizatória", "status": "Em andamento", "position": "Autor", "adverseParty": "AMIL ASSISTÊNCIA MÉDICA INTERNACIONAL S.A", "court": "COMARCA DE SÃO PAULO FORO REGIONAL XV", "comarca": "SÃO PAULO", "value": 46.6, "startDate": "2025-02-10"},
        {"number": "1004446-75.2025.8.13.0079", "client": "ANDRE LUIZ CHAVES BARBOSA", "type": "Indenizatória", "status": "Em andamento", "position": "Autor", "adverseParty": "EVO TECNOLOGIA DA INFORMACAO LTDA", "court": "1ª UNIDADE JURISDICIONAL", "comarca": "CONTAGEM, MG", "value": 16788, "startDate": "2025-11-04"},
        {"number": "1010485-93.2018.4.01.3800", "client": "ISAIAS MORAIS DOS SANTOS", "type": "Anulatória", "status": "Em andamento", "position": "Autor", "adverseParty": "CEF", "court": "2ª VARA CÍVEL E JEF ADJUNTO", "comarca": "BELO HORIZONTE", "value": 98000, "startDate": "2018-09-01"},
        {"number": "1013749-84.2025.8.13.0024", "client": "GABRIEL MELO MENEZES", "type": "Alimentos", "status": "Concluído", "position": "Autor", "adverseParty": "JOSÉ RICARDO DA CRUZ MENEZES", "court": "10ª VARA DE FAMÍLIA", "comarca": "BELO HORIZONTE, MG", "value": 21600, "startDate": null},
        {"number": "1014567-90.2022.4.06.3800", "client": "ALEXANDRE BARBOSA SILVA", "type": "Indenizatória", "status": "Em andamento", "position": "Autor", "adverseParty": "CEF", "court": null, "comarca": "BELO HORIZONTE", "value": 94000, "startDate": "2022-11-29"},
        {"number": "1029763-46.2025.8.13.0024", "client": "ANA CELESTINO DOS SANTOS", "type": "Inventário", "status": "Em andamento", "position": "Inventariante", "adverseParty": "ESPÓLIO DE JOSÉ MARIA DE FREITAS FERREIRA", "court": "3ª VARA DE SUCESSÕES E AUSÊNCIA", "comarca": "BELO HORIZONTE, MG", "value": 1518, "startDate": "2025-07-17"},
        {"number": "1037580-64.2025.8.13.0024", "client": "NAYARA NUNES ALMEIDA", "type": "Divórcio", "status": "Em andamento", "position": "Autor", "adverseParty": "MARCELO DA ROCHA LOPES", "court": "3ª VARA DE FAMÍLIA", "comarca": "BELO HORIZONTE, MG", "value": 1518, "startDate": "2025-08-05"},
        {"number": "1037764-20.2025.8.13.0024", "client": "MATHEUS DIAS VIVEIROS", "type": "Indenizatória", "status": "Em andamento", "position": "Réu", "adverseParty": "ASSEGURAR CLUBE DE BENEFICIOS", "court": "8ª VARA CÍVEL", "comarca": "BELO HORIZONTE, MG", "value": 1497, "startDate": null},
        {"number": "1071037-87.2025.8.13.0024", "client": "ELIENE MADUREIRA PEREIRA LIMA", "type": "Tutelas e/ou Curatelas", "status": "Em andamento", "position": "Autor", "adverseParty": "ELISANGELO MADUREIRA PEREIRA", "court": "4ª VARA DE FAMÍLIA", "comarca": "BELO HORIZONTE, MG", "value": 1518, "startDate": "2025-11-04"},
        {"number": "1085627-69.2025.8.13.0024", "client": "THANUS MARIO TORRES CUNHA", "type": "Indenizatória", "status": "Em andamento", "position": "Autor", "adverseParty": "ZURICH MINAS BRASIL SEGUROS S.A", "court": "8ª UNIDADE JURISDICIONAL CÍVEL", "comarca": "BELO HORIZONTE, MG", "value": 34878.22, "startDate": "2025-11-10"},
        {"number": "1106295-61.2025.8.13.0024", "client": "ISABEL APARECIDA PEREIRA DE FREITAS", "type": "Inventário", "status": "Em andamento", "position": "Autor", "adverseParty": "HAELIS", "court": "3ª VARA DE SUCESSÕES E AUSÊNCIA", "comarca": "BELO HORIZONTE, MG", "value": 1518, "startDate": null},
        {"number": "2841909-89.2013.8.13.0024", "client": "ROBERTO CARLOS CABRAL", "type": "Execução ou embargos", "status": "Em andamento", "position": "Executado", "adverseParty": "HÉLIO GAMA", "court": "CENTRASE", "comarca": "BELO HORIZONTE", "value": 50000, "startDate": "2021-09-17"},
        {"number": "2852985-18.2010.8.13.0024", "client": "THANUS MARIO TORRES CUNHA", "type": "Indenizatória", "status": "Concluído", "position": "Réu", "adverseParty": "RUBEM JOSE POLETTO e outros", "court": "11ª VARA CÍVEL", "comarca": "BELO HORIZONTE", "value": 12524, "startDate": "2010-11-29"},
        {"number": "4001241-87.2026.8.26.0176", "client": "GUSTAVO SALGUEIRO SANTOS", "type": "Indenizatória", "status": "Em andamento", "position": "Autor", "adverseParty": "Zurich Santander Brasil Seguros S.A.", "court": "JUÍZO TITULAR I", "comarca": "EMBU DAS ARTES", "value": 12000, "startDate": null},
        {"number": "4001885-64.2026.8.26.0003", "client": "OLAVO CÉSAR DE FREITAS PULTINI", "type": "Indenizatória", "status": "Em andamento", "position": "Autor", "adverseParty": "ANHANGUERA", "court": "1ª VARA DO JUIZADO ESPECIAL CÍVEL", "comarca": "SÃO PAULO", "value": 23020, "startDate": "2026-01-27"}
    ]';
    rec jsonb;
    current_client_id uuid;
BEGIN
    FOR rec IN SELECT * FROM jsonb_array_elements(process_data)
    LOOP
        -- Insert or Update Client
        INSERT INTO public.clients (name, type, status)
        VALUES (rec->>'client', 'PF', 'Ativo')
        ON CONFLICT (name) DO UPDATE SET name = EXCLUDED.name
        RETURNING id INTO current_client_id;
        
        -- Insert or Update Case
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
        ) VALUES (
            rec->>'number',
            current_client_id,
            rec->>'type',
            rec->>'status',
            rec->>'position',
            rec->>'adverseParty',
            rec->>'court',
            rec->>'comarca',
            COALESCE((rec->>'value')::numeric, 0),
            rec->>'startDate'
        )
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
            
    END LOOP;
END $$;
