CREATE TABLE IF NOT EXISTS public.suppliers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  document TEXT,
  email TEXT,
  phone TEXT,
  status TEXT DEFAULT 'Ativo',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Make name unique to allow idempotent seed inserts
CREATE UNIQUE INDEX IF NOT EXISTS suppliers_name_key ON public.suppliers (name);

-- Setup RLS
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "authenticated_select_suppliers" ON public.suppliers;
CREATE POLICY "authenticated_select_suppliers" ON public.suppliers FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "authenticated_insert_suppliers" ON public.suppliers;
CREATE POLICY "authenticated_insert_suppliers" ON public.suppliers FOR INSERT TO authenticated WITH CHECK (true);

DROP POLICY IF EXISTS "authenticated_update_suppliers" ON public.suppliers;
CREATE POLICY "authenticated_update_suppliers" ON public.suppliers FOR UPDATE TO authenticated USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "authenticated_delete_suppliers" ON public.suppliers;
CREATE POLICY "authenticated_delete_suppliers" ON public.suppliers FOR DELETE TO authenticated USING (true);

-- Pre-seed predefined suppliers
INSERT INTO public.suppliers (name) VALUES 
('SICOOB'),
('ASAAS'),
('SEGUROCRED'),
('ADAPTA'),
('SKIP'),
('CONTABILIDADE'),
('ZENO'),
('QUALITYCERT'),
('TJMG'),
('TRIBUTOS FEDERAIS')
ON CONFLICT (name) DO NOTHING;

-- Tie suppliers to transactions
ALTER TABLE public.transactions ADD COLUMN IF NOT EXISTS "supplierId" UUID REFERENCES public.suppliers(id) ON DELETE SET NULL;
