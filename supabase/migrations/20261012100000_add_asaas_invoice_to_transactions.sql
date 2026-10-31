-- Adiciona colunas para controle de Nota Fiscal (NFS-e) do Asaas em public.transactions
ALTER TABLE public.transactions ADD COLUMN IF NOT EXISTS asaas_invoice_id text;
ALTER TABLE public.transactions ADD COLUMN IF NOT EXISTS asaas_invoice_status text;
ALTER TABLE public.transactions ADD COLUMN IF NOT EXISTS asaas_invoice_url text;
ALTER TABLE public.transactions ADD COLUMN IF NOT EXISTS asaas_invoice_number text;

-- Concede permissões necessárias
GRANT SELECT, INSERT, UPDATE, DELETE ON public.transactions TO authenticated;
GRANT ALL ON public.transactions TO service_role;
