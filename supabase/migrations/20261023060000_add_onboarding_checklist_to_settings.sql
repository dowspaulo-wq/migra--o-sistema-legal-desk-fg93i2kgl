-- Migração: Adicionar coluna "onboardingChecklist" na tabela public.settings
-- Permite configurar o modelo padrão de etapas de Onboarding para novos clientes (com responsável por etapa)

DO $$
BEGIN
    -- 1. Garante que a tabela public.settings existe
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.tables 
        WHERE table_schema = 'public' AND table_name = 'settings'
    ) THEN
        RAISE EXCEPTION 'Tabela public.settings não existe no banco de dados.';
    END IF;

    -- 2. Adiciona a coluna onboardingChecklist (JSONB) caso não exista
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' 
          AND table_name = 'settings' 
          AND column_name = 'onboardingChecklist'
    ) THEN
        ALTER TABLE public.settings ADD COLUMN "onboardingChecklist" JSONB DEFAULT '[
            {"id": "step-1", "title": "Cadastrar cliente", "order": 1},
            {"id": "step-2", "title": "Cadastrar processo(s)", "order": 2},
            {"id": "step-3", "title": "Coletar documentos", "order": 3},
            {"id": "step-4", "title": "Tratar documentos (qualidade/PDFs)", "order": 4},
            {"id": "step-5", "title": "Redigir procuração", "order": 5},
            {"id": "step-6", "title": "Redigir contrato", "order": 6},
            {"id": "step-7", "title": "Redigir declaração de hipossuficiência", "order": 7},
            {"id": "step-8", "title": "Monitorar assinaturas", "order": 8}
        ]'::jsonb;
        RAISE NOTICE 'Coluna onboardingChecklist adicionada com sucesso na tabela public.settings.';
    ELSE
        RAISE NOTICE 'Coluna onboardingChecklist já existe na tabela public.settings.';
    END IF;

    -- 3. Preenche valores padrão se estiver nulo nas linhas existentes
    UPDATE public.settings
    SET "onboardingChecklist" = '[
        {"id": "step-1", "title": "Cadastrar cliente", "order": 1},
        {"id": "step-2", "title": "Cadastrar processo(s)", "order": 2},
        {"id": "step-3", "title": "Coletar documentos", "order": 3},
        {"id": "step-4", "title": "Tratar documentos (qualidade/PDFs)", "order": 4},
        {"id": "step-5", "title": "Redigir procuração", "order": 5},
        {"id": "step-6", "title": "Redigir contrato", "order": 6},
        {"id": "step-7", "title": "Redigir declaração de hipossuficiência", "order": 7},
        {"id": "step-8", "title": "Monitorar assinaturas", "order": 8}
    ]'::jsonb
    WHERE "onboardingChecklist" IS NULL;

    -- 4. Documentação da coluna
    COMMENT ON COLUMN public.settings."onboardingChecklist" IS 'Lista de etapas do modelo padrão de onboarding de novos clientes (id, title, order)';

    -- 5. Garantir políticas RLS
    ALTER TABLE public.settings ENABLE ROW LEVEL SECURITY;

    DROP POLICY IF EXISTS "authenticated_select_settings" ON public.settings;
    CREATE POLICY "authenticated_select_settings" ON public.settings
        FOR SELECT TO authenticated USING (true);

    DROP POLICY IF EXISTS "authenticated_update_settings" ON public.settings;
    CREATE POLICY "authenticated_update_settings" ON public.settings
        FOR UPDATE TO authenticated USING (true) WITH CHECK (true);

END $$;
