-- ============================================================
-- MÓDULO DE GESTÃO DE LEADS (aditivo — não altera tabelas existentes)
-- 1) leads: prospecção comercial. Só vira cliente por conversão MANUAL.
-- 2) lead_interactions: timeline de contato de cada lead.
-- 3) Opções Globais: áreas e assuntos jurídicos do módulo (settings.*Options jsonb).
-- RLS: mesmas políticas authenticated das demais tabelas — leads visível para toda a equipe.
-- ============================================================

-- ---------- Tabela leads ----------
CREATE TABLE IF NOT EXISTS public.leads (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  phone text,
  email text,
  city text,
  state text,
  "entryDate" text,
  origin text,
  campaign text,
  adset text,
  ad text,
  "formId" text,
  "externalId" text,
  area text,
  subject text,
  summary text,
  "factDate" text,
  "internalNotes" text,
  stage text NOT NULL DEFAULT 'Novo',
  "responsibleId" uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  "lastContactAt" timestamptz,
  "nextContactAt" text,
  priority text,
  "lostReason" text,
  "convertedClientId" uuid REFERENCES public.clients(id) ON DELETE SET NULL,
  "convertedAt" timestamptz,
  created_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- ---------- Tabela lead_interactions ----------
CREATE TABLE IF NOT EXISTS public.lead_interactions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "leadId" uuid NOT NULL REFERENCES public.leads(id) ON DELETE CASCADE,
  type text NOT NULL,
  description text,
  "fromStage" text,
  "toStage" text,
  "occurredAt" timestamptz NOT NULL DEFAULT now(),
  "userId" uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- ---------- Índices ----------
CREATE INDEX IF NOT EXISTS idx_leads_stage ON public.leads (stage);
CREATE INDEX IF NOT EXISTS idx_leads_next_contact ON public.leads ("nextContactAt");
CREATE INDEX IF NOT EXISTS idx_leads_responsible ON public.leads ("responsibleId");
CREATE INDEX IF NOT EXISTS idx_leads_created_at ON public.leads (created_at);
CREATE INDEX IF NOT EXISTS idx_lead_interactions_lead ON public.lead_interactions ("leadId");
CREATE INDEX IF NOT EXISTS idx_lead_interactions_occurred ON public.lead_interactions ("occurredAt");

-- Índices ÚNICOS PARCIAIS: prevenção de duplicidade por telefone e e-mail
-- (apenas quando não nulos e não vazios)
CREATE UNIQUE INDEX IF NOT EXISTS uq_leads_phone_not_empty
  ON public.leads (phone)
  WHERE phone IS NOT NULL AND btrim(phone) <> '';

CREATE UNIQUE INDEX IF NOT EXISTS uq_leads_email_not_empty
  ON public.leads (email)
  WHERE email IS NOT NULL AND btrim(email) <> '';

-- ---------- updated_at automático ----------
CREATE OR REPLACE FUNCTION public.handle_leads_updated_at()
RETURNS trigger AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_leads_updated_at ON public.leads;
CREATE TRIGGER trg_leads_updated_at
  BEFORE UPDATE ON public.leads
  FOR EACH ROW EXECUTE FUNCTION public.handle_leads_updated_at();

-- ---------- RLS (mesmo padrão authenticated das demais tabelas) ----------
ALTER TABLE public.leads ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lead_interactions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "authenticated_select_leads" ON public.leads;
CREATE POLICY "authenticated_select_leads" ON public.leads
  FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "authenticated_insert_leads" ON public.leads;
CREATE POLICY "authenticated_insert_leads" ON public.leads
  FOR INSERT TO authenticated WITH CHECK (true);

DROP POLICY IF EXISTS "authenticated_update_leads" ON public.leads;
CREATE POLICY "authenticated_update_leads" ON public.leads
  FOR UPDATE TO authenticated USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "authenticated_delete_leads" ON public.leads;
CREATE POLICY "authenticated_delete_leads" ON public.leads
  FOR DELETE TO authenticated USING (true);

DROP POLICY IF EXISTS "authenticated_select_lead_interactions" ON public.lead_interactions;
CREATE POLICY "authenticated_select_lead_interactions" ON public.lead_interactions
  FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "authenticated_insert_lead_interactions" ON public.lead_interactions;
CREATE POLICY "authenticated_insert_lead_interactions" ON public.lead_interactions
  FOR INSERT TO authenticated WITH CHECK (true);

DROP POLICY IF EXISTS "authenticated_update_lead_interactions" ON public.lead_interactions;
CREATE POLICY "authenticated_update_lead_interactions" ON public.lead_interactions
  FOR UPDATE TO authenticated USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "authenticated_delete_lead_interactions" ON public.lead_interactions;
CREATE POLICY "authenticated_delete_lead_interactions" ON public.lead_interactions
  FOR DELETE TO authenticated USING (true);

-- ---------- Opções Globais (padrão settings.*Options em jsonb) ----------
-- Áreas e assuntos jurídicos do módulo de Leads. Nada fixo no código.
ALTER TABLE public.settings ADD COLUMN IF NOT EXISTS "leadAreas" jsonb;
ALTER TABLE public.settings ADD COLUMN IF NOT EXISTS "leadSubjects" jsonb;

UPDATE public.settings
SET
  "leadAreas" = COALESCE("leadAreas", '["Previdenciário", "Cível", "Trabalhista", "Família", "Criminal", "Consumidor", "Tributário", "Outros"]'::jsonb),
  "leadSubjects" = COALESCE("leadSubjects", '["Aposentadoria", "Auxílio-doença", "BPC/LOAS", "Revisão de benefício", "Divórcio", "Alimentos", "Inventário", "Indenização", "Reclamação trabalhista", "Consultoria", "Outros"]'::jsonb)
WHERE "leadAreas" IS NULL OR "leadSubjects" IS NULL;
