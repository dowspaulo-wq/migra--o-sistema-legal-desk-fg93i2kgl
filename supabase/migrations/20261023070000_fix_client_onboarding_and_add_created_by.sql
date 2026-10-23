-- ==============================================================================
-- Migration: Corrigir automação de tarefas no cadastro de clientes e adicionar
-- colunas de auditoria "Dedo duro" (created_by) em clients e cases.
-- ==============================================================================
-- 1. Remoção do trigger obsoleto on_client_created e da função handle_new_client_tasks.
--    O cadastro de cliente gera SOMENTE as tarefas do checklist de onboarding configurado.
--    As tarefas "Redigir Inicial ou Defesa" e "Acompanhamento processual" nascem exclusivamente
--    ao cadastrar um processo (mantidas no trigger on_case_created / handle_new_case_task).
-- 2. Adição da coluna "created_by" (UUID FK profiles) nas tabelas public.clients e public.cases.
-- 3. Preenchimento retroativo seguro de created_by com base no responsibleId existente.
-- ==============================================================================

-- 1. Remove trigger e função que geravam indevidamente tarefas de processo no cliente
DROP TRIGGER IF EXISTS on_client_created ON public.clients;
DROP FUNCTION IF EXISTS public.handle_new_client_tasks();

-- 2. Adicionar coluna created_by em public.clients
ALTER TABLE public.clients
    ADD COLUMN IF NOT EXISTS created_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_clients_created_by ON public.clients(created_by);

-- 3. Adicionar coluna created_by em public.cases
ALTER TABLE public.cases
    ADD COLUMN IF NOT EXISTS created_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_cases_created_by ON public.cases(created_by);

-- 4. Preenchimento retroativo inteligente:
-- Se created_by for nulo, herda do responsibleId do registro (ou Douglas/Admin caso responsibleId seja nulo)
DO $$
BEGIN
    UPDATE public.clients
    SET created_by = "responsibleId"
    WHERE created_by IS NULL AND "responsibleId" IS NOT NULL;

    UPDATE public.cases
    SET created_by = "responsibleId"
    WHERE created_by IS NULL AND "responsibleId" IS NOT NULL;
END $$;
