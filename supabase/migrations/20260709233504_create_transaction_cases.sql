CREATE TABLE IF NOT EXISTS public.transaction_cases (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  transaction_id UUID NOT NULL REFERENCES public.transactions(id) ON DELETE CASCADE,
  case_id UUID NOT NULL REFERENCES public.cases(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_transaction_cases_transaction_id ON public.transaction_cases(transaction_id);
CREATE INDEX IF NOT EXISTS idx_transaction_cases_case_id ON public.transaction_cases(case_id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_transaction_cases_unique ON public.transaction_cases(transaction_id, case_id);

ALTER TABLE public.transaction_cases ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "authenticated_select_transaction_cases" ON public.transaction_cases;
CREATE POLICY "authenticated_select_transaction_cases" ON public.transaction_cases
  FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "authenticated_insert_transaction_cases" ON public.transaction_cases;
CREATE POLICY "authenticated_insert_transaction_cases" ON public.transaction_cases
  FOR INSERT TO authenticated WITH CHECK (true);

DROP POLICY IF EXISTS "authenticated_update_transaction_cases" ON public.transaction_cases;
CREATE POLICY "authenticated_update_transaction_cases" ON public.transaction_cases
  FOR UPDATE TO authenticated USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "authenticated_delete_transaction_cases" ON public.transaction_cases;
CREATE POLICY "authenticated_delete_transaction_cases" ON public.transaction_cases
  FOR DELETE TO authenticated USING (true);
