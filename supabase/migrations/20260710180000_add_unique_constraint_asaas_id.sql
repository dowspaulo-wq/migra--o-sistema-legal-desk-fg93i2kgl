-- Clean up duplicate asaas_id entries (keep the most recent by created_at)
DELETE FROM public.transactions t1
USING public.transactions t2
WHERE t1.asaas_id IS NOT NULL
  AND t1.asaas_id = t2.asaas_id
  AND t1.created_at < t2.created_at;

-- Create unique partial index on asaas_id (allows multiple NULLs)
CREATE UNIQUE INDEX IF NOT EXISTS transactions_asaas_id_key
ON public.transactions (asaas_id)
WHERE asaas_id IS NOT NULL;
