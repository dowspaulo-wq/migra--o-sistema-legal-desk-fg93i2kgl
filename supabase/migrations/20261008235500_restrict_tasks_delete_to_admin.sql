-- ==============================================================================
-- Migração: Restringir Exclusão de Tarefas (public.tasks) Exclusivamente a Admin
-- Data: 2026-10-08
-- Descrição:
--   Remove a política permissiva legada 'tasks_authenticated_all' (que concedia ALL/USING true,
--   permitindo DELETE por qualquer usuário autenticado e anulando a restrição de authenticated_delete_tasks).
--   Garante as 4 políticas granulares em public.tasks:
--     1) authenticated_select_tasks -> SELECT para authenticated (USING true)
--     2) authenticated_insert_tasks -> INSERT para authenticated (WITH CHECK true)
--     3) authenticated_update_tasks -> UPDATE para authenticated (USING true WITH CHECK true)
--     4) authenticated_delete_tasks -> DELETE restrito a perfis com role = 'Admin'
-- ==============================================================================

-- 1. Garantir RLS ativo na tabela tasks
ALTER TABLE public.tasks ENABLE ROW LEVEL SECURITY;

-- 2. Remover a política ALL permissiva que permitia DELETE indevido por não-Admin
DROP POLICY IF EXISTS "tasks_authenticated_all" ON public.tasks;

-- 3. Garantir SELECT liberado para todos os usuários autenticados
DROP POLICY IF EXISTS "authenticated_select_tasks" ON public.tasks;
CREATE POLICY "authenticated_select_tasks" ON public.tasks
    FOR SELECT TO authenticated
    USING (true);

-- 4. Garantir INSERT liberado para todos os usuários autenticados (criar tarefas normais e automáticas)
DROP POLICY IF EXISTS "authenticated_insert_tasks" ON public.tasks;
CREATE POLICY "authenticated_insert_tasks" ON public.tasks
    FOR INSERT TO authenticated
    WITH CHECK (true);

-- 5. Garantir UPDATE liberado para todos os usuários autenticados (concluir, alterar status, observações)
DROP POLICY IF EXISTS "authenticated_update_tasks" ON public.tasks;
CREATE POLICY "authenticated_update_tasks" ON public.tasks
    FOR UPDATE TO authenticated
    USING (true)
    WITH CHECK (true);

-- 6. Garantir DELETE restrito exclusivamente a perfis com role = 'Admin'
DROP POLICY IF EXISTS "authenticated_delete_tasks" ON public.tasks;
CREATE POLICY "authenticated_delete_tasks" ON public.tasks
    FOR DELETE TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.profiles 
            WHERE profiles.id = auth.uid() 
              AND profiles.role = 'Admin'
        )
    );
