-- ==============================================================================
-- Migration: Adicionar coluna "automationRules" (JSONB) na tabela public.settings
-- Motor de regras de geração de tarefas automáticas adicionais.
-- Idempotente e não-destrutivo.
-- ==============================================================================

DO $$
BEGIN
    -- 1. Garante que a tabela public.settings existe
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.tables 
        WHERE table_schema = 'public' AND table_name = 'settings'
    ) THEN
        RAISE EXCEPTION 'Tabela public.settings não existe no banco de dados.';
    END IF;

    -- 2. Adiciona a coluna automationRules (JSONB) caso não exista
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' 
          AND table_name = 'settings' 
          AND column_name = 'automationRules'
    ) THEN
        ALTER TABLE public.settings ADD COLUMN "automationRules" JSONB DEFAULT '[]'::jsonb;
        RAISE NOTICE 'Coluna automationRules adicionada com sucesso na tabela public.settings.';
    ELSE
        RAISE NOTICE 'Coluna automationRules já existe na tabela public.settings.';
    END IF;

    -- 3. Se estiver NULL em linhas existentes, inicializa como array vazio '[]'
    UPDATE public.settings
    SET "automationRules" = '[]'::jsonb
    WHERE "automationRules" IS NULL;

    -- 4. Garantir que RLS permita leitura e atualização para usuários autenticados
    ALTER TABLE public.settings ENABLE ROW LEVEL SECURITY;

    DROP POLICY IF EXISTS "authenticated_select_settings" ON public.settings;
    CREATE POLICY "authenticated_select_settings" ON public.settings
        FOR SELECT TO authenticated USING (true);

    DROP POLICY IF EXISTS "authenticated_update_settings" ON public.settings;
    CREATE POLICY "authenticated_update_settings" ON public.settings
        FOR UPDATE TO authenticated USING (true) WITH CHECK (true);

END $$;
