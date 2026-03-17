DO $$
DECLARE
    row record;
    v_client_id uuid;
    v_process_id uuid;
    v_responsible_id uuid;
    v_date text;
    v_time text;
    v_description text;
BEGIN
    -- Drop NOT NULL constraint from clientId and processId in appointments table
    -- to allow holidays to be inserted without associated clients/cases
    ALTER TABLE public.appointments ALTER COLUMN "clientId" DROP NOT NULL;
    ALTER TABLE public.appointments ALTER COLUMN "processId" DROP NOT NULL;

    FOR row IN 
        SELECT * FROM (VALUES 
            ('AIJ', 'audiencia', '13/04/2026', '14:20', 'pendente', 'alta', 'THIAGO MILANEZ DA SILVA', '5120803-75.2024.8.13.0024', 'Douglas Santos', 'virtual'),
            ('AIJ', 'audiencia', '27/03/2026', '12:40', 'pendente', 'urgente', 'MAYCON ALMEIDA DE OLIVEIRA', '0809148-72.2026.8.19.0038', 'Douglas Santos', 'presencial'),
            ('AIJ', 'audiencia', '09/03/2026', '14:10', 'pendente', 'urgente', 'CHARLES EDUARDO DE SOUZA ESTACIO DA SILVA', '0825049-89.2025.8.19.0208', 'Douglas Santos', 'presencial'),
            ('Aud.Conciliação', 'audiencia', '06/07/2026', '10:00', 'pendente', 'media', 'ANA FLÁVIA SIQUEIRA NUNES', '1001160-47.2026.8.13.0114', 'Douglas Santos', 'virtual'),
            ('Aud.Conciliação', 'audiencia', '14/04/2026', '17:00', 'pendente', 'media', 'MULLER FRANCISCO PEREIRA', '5008550-07.2025.8.13.0317', 'adveduardoaugustobarbosa', 'presencial'),
            ('Aud.Conciliação', 'audiencia', '07/04/2026', '09:00', 'pendente', 'urgente', 'RAFAEL FROIS DA SILVA', '1023242-51.2026.8.13.0024', 'Douglas Santos', 'virtual'),
            ('Aud.Conciliação', 'audiencia', '05/11/2026', '10:30', 'pendente', 'baixa', 'JULIANE APARECIDA MENEGUITE SOUZA', '5021430-66.2025.8.13.0079', 'Douglas Santos', 'presencial'),
            ('Aud.Conciliação', 'audiencia', '04/05/2026', '14:00', 'pendente', 'alta', 'PATRÍCIA SILVA MARIA', '0803660-23.2026.8.19.0205', 'Douglas Santos', 'presencial'),
            ('Aud.Conciliação', 'audiencia', '10/08/2026', '14:30', 'pendente', 'media', 'SUELI DUARTE MONTEIRO', '5000985-20.2024.8.13.0319', 'adveduardoaugustobarbosa', ''),
            ('Aud.Conciliação', 'audiencia', '06/05/2026', '15:00', 'pendente', 'media', 'ESPÓLIO VANDEIR RODRIGUES FERREIRA', '5129337-42.2023.8.13.0024', 'adveduardoaugustobarbosa', 'presencial'),
            ('Aud.Conciliação', 'audiencia', '01/06/2026', '15:30', 'pendente', 'media', 'JULLY FELIX VIEIRA', '1032073-88.2026.8.13.0024', 'adveduardoaugustobarbosa', 'virtual'),
            ('Aud.Conciliação', 'audiencia', '09/06/2026', '09:00', 'pendente', 'baixa', 'FRANCIMAR APARECIDA CUNHA DA SILVA', '1031688-43.2026.8.13.0024', 'Douglas Santos', 'virtual'),
            ('Aud.Conciliação', 'audiencia', '15/05/2026', '15:00', 'pendente', 'alta', 'JHOM HENRICKY PEREIRA DA SILVA', '5001012-04.2026.8.08.0050', 'Douglas Santos', 'presencial'),
            ('Aud.Conciliação', 'audiencia', '12/06/2026', '11:00', 'pendente', 'alta', 'PRISCILA RODRIGUES TEÓFILO', '1027548-63.2026.8.13.0024', 'Douglas Santos', 'virtual'),
            ('Aud.Conciliação', 'audiencia', '01/07/2026', '16:00', 'pendente', 'alta', 'ROSEANE ALEXSSANDRA BATISTA ASSIS DOS SANTOS', '1003118-38.2026.8.13.0027', 'Douglas Santos', 'virtual'),
            ('Aud.Conciliação', 'audiencia', '18/05/2026', '15:10', 'pendente', 'alta', 'CHARLES EDUARDO DE SOUZA ESTACIO DA SILVA', '0802678-97.2026.8.19.0208', 'Douglas Santos', 'presencial'),
            ('Aud.Conciliação', 'audiencia', '12/06/2026', '13:00', 'pendente', 'alta', 'OLAVO CÉSAR DE FREITAS PULTINI', '4001885-64.2026.8.26.0003', 'Douglas Santos', 'presencial'),
            ('Aud.Conciliação', 'audiencia', '22/04/2026', '08:45', 'pendente', 'media', 'JOAO VITOR SILVA DE CARVALHO', '0011834-27.2025.5.03.0030', 'adveduardoaugustobarbosa', 'virtual'),
            ('Aud.Conciliação', 'audiencia', '19/02/2026', '08:10', 'pendente', 'baixa', 'ARNALDO GONÇALVES DA SILVA', '1065494-06.2025.8.13.0024', 'adveduardoaugustobarbosa', 'presencial'),
            ('Aud.Conciliação', 'audiencia', '23/03/2026', '14:00', 'pendente', 'alta', 'ANA CELESTINO DOS SANTOS', '1029763-46.2025.8.13.0024', 'Douglas Santos', 'virtual'),
            ('Aud.Conciliação', 'audiencia', '29/04/2026', '13:00', 'pendente', 'alta', 'GUILHERME GOMES DE SOUZA', '1014144-42.2026.8.13.0024', 'Douglas Santos', 'virtual'),
            ('Aud.Conciliação', 'audiencia', '16/04/2026', '14:30', 'pendente', 'alta', 'VINICIUS TEIXEIRA VALADARES PALHARES', '4001729-24.2025.8.26.0161', 'Douglas Santos', 'virtual'),
            ('Aud.Conciliação', 'audiencia', '14/04/2026', '17:00', 'pendente', 'media', 'MULLER FRANCISCO PEREIRA', '5008550-07.2025.8.13.0317', 'adveduardoaugustobarbosa', 'presencial'),
            ('Aud.Conciliação', 'audiencia', '20/08/2026', '15:45', 'pendente', 'alta', 'KIURY NOGUEIRA MARTINS', '1012959-66.2026.8.13.0024', 'Douglas Santos', 'virtual'),
            ('Aud.Conciliação', 'audiencia', '25/05/2026', '16:00', 'pendente', 'media', 'FREDERICO BRUNO NEVES DE ARAUJO', '1004609-89.2026.8.13.0024', 'adveduardoaugustobarbosa', 'virtual'),
            ('Aud.Conciliação', 'audiencia', '08/04/2026', '15:00', 'pendente', 'media', 'RAFAEL DE SOUSA LIMA', '1010738-13.2026.8.13.0024', 'adveduardoaugustobarbosa', 'virtual'),
            ('Aud.Conciliação', 'audiencia', '25/03/2026', '08:00', 'pendente', 'alta', 'THIAGO MILANEZ DA SILVA', '1008084-53.2026.8.13.0024', 'Douglas Santos', 'virtual'),
            ('Aud.Conciliação', 'audiencia', '03/06/2026', '09:30', 'pendente', 'alta', 'CLEITON BRANDÃO ANDRADE', '5004509-08.2025.8.13.0572', 'Douglas Santos', 'presencial'),
            ('Aud.Conciliação', 'audiencia', '10/02/2026', '09:30', 'pendente', 'alta', 'LUCAS BATISTA DE OLIVEIRA', '5053970-70.2025.8.13.0079', 'adveduardoaugustobarbosa', 'presencial'),
            ('Aud.Conciliação', 'audiencia', '23/01/2026', '13:00', 'pendente', 'alta', 'LEANDRO DA SILVA GUEDES', '0822901-26.2025.8.19.0202', 'Douglas Santos', 'presencial'),
            ('Aud.Conciliação', 'audiencia', '16/06/2026', '09:40', 'pendente', 'alta', 'ROSILDA FERREIRA NUNES', '1000875-95.2025.8.13.0241', 'Douglas Santos', 'presencial'),
            ('Aud.Conciliação', 'audiencia', '10/02/2026', '10:30', 'pendente', 'alta', 'ANA CELESTINO DOS SANTOS', '1001930-82.2025.8.13.0079', 'adveduardoaugustobarbosa', 'presencial'),
            ('Aud.Conciliação', 'audiencia', '11/02/2026', '09:30', 'pendente', 'alta', 'ANDRE LUIZ CHAVES BARBOSA', '1004446-75.2025.8.13.0079', 'Douglas Santos', 'virtual'),
            ('Feriado Carnaval', 'feriado', '17/02/2026', '', 'pendente', 'baixa', '', '', '', ''),
            ('Feriado Carnaval', 'feriado', '16/02/2026', '', 'pendente', 'baixa', '', '', '', ''),
            ('Feriado Confraternização Universal', 'feriado', '01/01/2026', '', 'pendente', 'baixa', '', '', '', ''),
            ('Feriado Corpus Christi', 'feriado', '04/06/2026', '', 'pendente', 'baixa', '', '', '', ''),
            ('Feriado dia do trabalho', 'feriado', '01/05/2026', '', 'pendente', 'baixa', '', '', '', ''),
            ('Feriado finados', 'feriado', '02/11/2026', '', 'pendente', 'baixa', '', '', '', ''),
            ('Feriado Independência', 'feriado', '07/09/2026', '', 'pendente', 'baixa', '', '', '', ''),
            ('Feriado Natal', 'feriado', '25/12/2025', '', 'pendente', 'baixa', '', '', '', ''),
            ('Feriado Nossa Sr.a Aparecida', 'feriado', '12/10/2026', '', 'pendente', 'baixa', '', '', '', ''),
            ('Feriado Paixão de Cristo', 'feriado', '03/04/2026', '', 'pendente', 'baixa', '', '', '', ''),
            ('Feriado Tiradentes', 'feriado', '21/04/2026', '', 'pendente', 'baixa', '', '', '', ''),
            ('Feriado Proclamação da República', 'feriado', '15/11/2026', '', 'pendente', 'baixa', '', '', '', ''),
            ('Feriado Dia das Mães', 'feriado', '10/05/2026', '', 'pendente', 'baixa', '', '', '', ''),
            ('Feriado Dia dos Pais', 'feriado', '09/08/2026', '', 'pendente', 'baixa', '', '', '', ''),
            ('Recesso Judiciário', 'feriado', '20/12/2026', '', 'pendente', 'baixa', '', '', '', '')
        ) AS t(titulo, tipo, data_str, horario, status, prioridade, cliente_nome, processo_numero, responsavel_nome, modalidade)
    LOOP
        -- Reset variables
        v_client_id := NULL;
        v_process_id := NULL;
        v_responsible_id := NULL;
        v_time := '00:00';
        v_description := '';
        
        -- Date conversion (DD/MM/YYYY to YYYY-MM-DD)
        v_date := substr(row.data_str, 7, 4) || '-' || substr(row.data_str, 4, 2) || '-' || substr(row.data_str, 1, 2);
        
        -- Time default
        IF row.horario IS NOT NULL AND row.horario <> '' THEN
            v_time := row.horario;
        END IF;

        -- Description mapping (modalidade + status -> description)
        IF row.modalidade IS NOT NULL AND row.modalidade <> '' THEN
            v_description := 'Modalidade: ' || row.modalidade || '. Status: ' || row.status;
        ELSE
            v_description := 'Status: ' || row.status;
        END IF;

        -- Lookups
        IF row.cliente_nome IS NOT NULL AND row.cliente_nome <> '' THEN
            SELECT id INTO v_client_id FROM public.clients WHERE name = row.cliente_nome LIMIT 1;
        END IF;

        IF row.processo_numero IS NOT NULL AND row.processo_numero <> '' THEN
            SELECT id INTO v_process_id FROM public.cases WHERE number = row.processo_numero LIMIT 1;
        END IF;

        IF row.responsavel_nome IS NOT NULL AND row.responsavel_nome <> '' THEN
            SELECT id INTO v_responsible_id FROM public.profiles WHERE name = row.responsavel_nome LIMIT 1;
        END IF;

        -- Insert into appointments
        INSERT INTO public.appointments (
            title, 
            type, 
            date, 
            time, 
            priority, 
            description, 
            "clientId", 
            "processId", 
            "responsibleId"
        ) VALUES (
            row.titulo, 
            row.tipo, 
            v_date, 
            v_time, 
            row.prioridade, 
            v_description, 
            v_client_id, 
            v_process_id, 
            v_responsible_id
        );
    END LOOP;
END $$;
