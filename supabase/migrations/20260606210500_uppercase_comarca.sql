DO $$
BEGIN
  UPDATE public.cases
  SET comarca = UPPER(comarca)
  WHERE comarca IS NOT NULL;
END $$;

CREATE OR REPLACE FUNCTION public.enforce_uppercase_comarca()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  IF NEW.comarca IS NOT NULL THEN
    NEW.comarca = UPPER(NEW.comarca);
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_uppercase_comarca ON public.cases;
CREATE TRIGGER trg_uppercase_comarca
 BEFORE INSERT OR UPDATE ON public.cases
 FOR EACH ROW EXECUTE FUNCTION public.enforce_uppercase_comarca();
