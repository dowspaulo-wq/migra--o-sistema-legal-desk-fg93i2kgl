-- Add Aniversário to settings appointmentTypes if not present
UPDATE public.settings
SET "appointmentTypes" = CASE
    WHEN "appointmentTypes" ? 'Aniversário' THEN "appointmentTypes"
    ELSE "appointmentTypes" || '["Aniversário"]'::jsonb
END
WHERE jsonb_typeof("appointmentTypes") = 'array';

-- Create function to manage client birthdays
CREATE OR REPLACE FUNCTION public.handle_client_birthday()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    y int;
    m int;
    d int;
    curr_year int;
    i int;
    bday_date date;
    parsed_date date;
BEGIN
    -- If update and birthday hasn't changed, do nothing
    IF TG_OP = 'UPDATE' AND OLD.birthday = NEW.birthday AND OLD."responsibleId" = NEW."responsibleId" AND OLD.name = NEW.name THEN
        RETURN NEW;
    END IF;

    -- Delete existing future birthday appointments for this client
    DELETE FROM public.appointments
    WHERE "clientId" = NEW.id AND type = 'Aniversário';

    -- If no birthday, return
    IF NEW.birthday IS NULL OR NEW.birthday = '' THEN
        RETURN NEW;
    END IF;

    -- Safely parse the birthday date
    BEGIN
        IF NEW.birthday LIKE '%/%/%' THEN
            parsed_date := to_date(NEW.birthday, 'DD/MM/YYYY');
        ELSE
            parsed_date := NEW.birthday::date;
        END IF;
    EXCEPTION WHEN OTHERS THEN
        RETURN NEW; -- skip if date is invalid
    END;

    -- Extract month and day
    m := extract(month from parsed_date);
    d := extract(day from parsed_date);
    curr_year := extract(year from current_date);

    -- Insert for current year and next 4 years (5 total)
    FOR i IN 0..4 LOOP
        y := curr_year + i;
        -- Handle leap year birthdays
        IF m = 2 AND d = 29 AND NOT ((y % 4 = 0 AND y % 100 != 0) OR y % 400 = 0) THEN
            bday_date := make_date(y, 2, 28);
        ELSE
            bday_date := make_date(y, m, d);
        END IF;

        INSERT INTO public.appointments (
            title,
            date,
            time,
            type,
            priority,
            "responsibleId",
            "clientId"
        ) VALUES (
            'Aniversário: ' || NEW.name,
            to_char(bday_date, 'YYYY-MM-DD'),
            '08:00',
            'Aniversário',
            'Baixa',
            NEW."responsibleId",
            NEW.id
        );
    END LOOP;

    RETURN NEW;
END;
$$;

-- Create trigger
DROP TRIGGER IF EXISTS on_client_birthday_change ON public.clients;
CREATE TRIGGER on_client_birthday_change
AFTER INSERT OR UPDATE ON public.clients
FOR EACH ROW EXECUTE FUNCTION public.handle_client_birthday();

-- Seed existing clients
DO $$
DECLARE
    c record;
    y int;
    m int;
    d int;
    curr_year int;
    i int;
    bday_date date;
    parsed_date date;
BEGIN
    curr_year := extract(year from current_date);

    -- Clear existing to avoid duplicates if re-run
    DELETE FROM public.appointments WHERE type = 'Aniversário';

    FOR c IN SELECT * FROM public.clients WHERE birthday IS NOT NULL AND birthday != '' LOOP
        -- Safely parse the birthday date
        BEGIN
            IF c.birthday LIKE '%/%/%' THEN
                parsed_date := to_date(c.birthday, 'DD/MM/YYYY');
            ELSE
                parsed_date := c.birthday::date;
            END IF;
            
            m := extract(month from parsed_date);
            d := extract(day from parsed_date);

            FOR i IN 0..4 LOOP
                y := curr_year + i;
                IF m = 2 AND d = 29 AND NOT ((y % 4 = 0 AND y % 100 != 0) OR y % 400 = 0) THEN
                    bday_date := make_date(y, 2, 28);
                ELSE
                    bday_date := make_date(y, m, d);
                END IF;

                INSERT INTO public.appointments (
                    title,
                    date,
                    time,
                    type,
                    priority,
                    "responsibleId",
                    "clientId"
                ) VALUES (
                    'Aniversário: ' || c.name,
                    to_char(bday_date, 'YYYY-MM-DD'),
                    '08:00',
                    'Aniversário',
                    'Baixa',
                    c."responsibleId",
                    c.id
                );
            END LOOP;
        EXCEPTION WHEN OTHERS THEN
            -- Skip clients with invalid dates silently
        END;
    END LOOP;
END;
$$;
