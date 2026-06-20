DO $$
DECLARE
  batch_size INT := 1000;
  affected INT;
BEGIN
  LOOP
    UPDATE public.tasks
    SET priority = 'BAIXA'
    WHERE id IN (
      SELECT id FROM public.tasks 
      WHERE status ILIKE '%ATUALIZAÇÃO%' 
        AND (priority IS NULL OR priority != 'BAIXA')
      LIMIT batch_size
    );
    
    GET DIAGNOSTICS affected = ROW_COUNT;
    EXIT WHEN affected = 0;
    
    -- Small delay to prevent locking issues on large tables
    PERFORM pg_sleep(0.05);
  END LOOP;
END $$;
