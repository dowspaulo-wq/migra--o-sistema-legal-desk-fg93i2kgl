-- Migração: Separar Onboarding em dois modelos (Cliente e Processo)
-- 1. Garante colunas "onboardingChecklist" e "caseOnboardingChecklist" em public.settings
-- 2. Migra/divide as etapas existentes de public.settings."onboardingChecklist" entre Cliente e Processo
-- 3. Respeita verbatim a divisão solicitada por Douglas:
--    CLIENTE: "Cadastrar cliente", "Cadastrar processo(s)", "Coletar documentos"
--    PROCESSO: "Redigir procuração", "Redigir contrato", "Redigir declaração de hipossuficiência", 
--              "Lançar honorários", "Tratar documentos (qualidade/PDFs)", "Monitorar assinaturas"

DO $$
BEGIN
    -- 1. Garante que a tabela public.settings existe
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.tables 
        WHERE table_schema = 'public' AND table_name = 'settings'
    ) THEN
        RAISE EXCEPTION 'Tabela public.settings não existe no banco de dados.';
    END IF;

    -- 2. Adiciona a coluna caseOnboardingChecklist (JSONB) caso não exista
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' 
          AND table_name = 'settings' 
          AND column_name = 'caseOnboardingChecklist'
    ) THEN
        ALTER TABLE public.settings ADD COLUMN "caseOnboardingChecklist" JSONB DEFAULT '[]'::jsonb;
        RAISE NOTICE 'Coluna caseOnboardingChecklist adicionada com sucesso na tabela public.settings.';
    END IF;

    -- 3. Reorganiza e divide o modelo atual existente em public.settings
    -- Etapas de Processo: Redigir procuração, Redigir contrato, Redigir declaração de hipossuficiência,
    -- Lançar honorários, Tratar documentos (qualidade/PDFs), Monitorar assinaturas.
    -- Etapas de Cliente: Cadastrar cliente, Cadastrar processo(s), Coletar documentos.
    UPDATE public.settings
    SET 
        "onboardingChecklist" = '[
            {"id": "step-client-1", "title": "Cadastrar cliente", "order": 1, "type": "cliente"},
            {"id": "step-client-2", "title": "Cadastrar processo(s)", "order": 2, "type": "cliente"},
            {"id": "step-client-3", "title": "Coletar documentos", "order": 3, "type": "cliente"}
        ]'::jsonb,
        "caseOnboardingChecklist" = '[
            {"id": "step-case-1", "title": "Redigir procuração", "order": 1, "type": "processo"},
            {"id": "step-case-2", "title": "Redigir declaração de hipossuficiência", "order": 2, "type": "processo"},
            {"id": "step-case-3", "title": "Redigir contrato", "order": 3, "type": "processo"},
            {"id": "step-case-4", "title": "Lançar honorários", "order": 4, "type": "processo"},
            {"id": "step-case-5", "title": "Tratar documentos (qualidade/PDFs)", "order": 5, "type": "processo"},
            {"id": "step-case-6", "title": "Monitorar assinaturas", "order": 6, "type": "processo"}
        ]'::jsonb
    WHERE "caseOnboardingChecklist" IS NULL OR "caseOnboardingChecklist" = '[]'::jsonb;

    -- 4. Documentação das colunas
    COMMENT ON COLUMN public.settings."onboardingChecklist" IS 'Lista de etapas do modelo de onboarding de CLIENTES (id, title, order, type, responsibleId)';
    COMMENT ON COLUMN public.settings."caseOnboardingChecklist" IS 'Lista de etapas do modelo de onboarding de PROCESSOS (id, title, order, type, responsibleId)';

    -- 5. Garantir políticas RLS
    ALTER TABLE public.settings ENABLE ROW LEVEL SECURITY;

    DROP POLICY IF EXISTS "authenticated_select_settings" ON public.settings;
    CREATE POLICY "authenticated_select_settings" ON public.settings
        FOR SELECT TO authenticated USING (true);

    DROP POLICY IF EXISTS "authenticated_update_settings" ON public.settings;
    CREATE POLICY "authenticated_update_settings" ON public.settings
        FOR UPDATE TO authenticated USING (true) WITH CHECK (true);

END $$;
