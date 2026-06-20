DO $do$
BEGIN
  -- Rename task status
  UPDATE public.tasks
  SET status = 'Revisão/protocolo'
  WHERE status ILIKE 'revisão/protocolo';

  -- Rename task type
  UPDATE public.tasks
  SET type = 'Revisão/protocolo'
  WHERE type ILIKE 'revisão/protocolo';

  -- Normalize taskStatuses
  UPDATE public.settings
  SET "taskStatuses" = (
    SELECT jsonb_agg(val)
    FROM (
      SELECT DISTINCT 
        CASE 
          WHEN value::text ILIKE '"revisão/protocolo"' THEN '"Revisão/protocolo"'::jsonb 
          ELSE value 
        END AS val
      FROM jsonb_array_elements("taskStatuses")
    ) t
  )
  WHERE "taskStatuses" IS NOT NULL;

  -- Normalize taskTypes
  UPDATE public.settings
  SET "taskTypes" = (
    SELECT jsonb_agg(val)
    FROM (
      SELECT DISTINCT 
        CASE 
          WHEN value::text ILIKE '"revisão/protocolo"' THEN '"Revisão/protocolo"'::jsonb 
          ELSE value 
        END AS val
      FROM jsonb_array_elements("taskTypes")
    ) t
  )
  WHERE "taskTypes" IS NOT NULL;
END $do$;
