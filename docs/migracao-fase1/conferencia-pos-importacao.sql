-- ==============================================================================
-- DPSjur - Script de Conferência e Auditoria Pós-Importação
-- Kit de Migração - Fase 1 / Fase 2 (Ambiente EasyPanel PostgreSQL 16)
-- Banco Alvo: "dpsjur"
-- ==============================================================================
-- INSTRUÇÕES PARA O DOUGLAS:
-- 1. Abra o terminal do container do banco de dados (dpsjur-db).
-- 2. Conecte ao psql:
--      psql -U Doug -d dpsjur
-- 3. Cole todo o bloco abaixo e aperte ENTER.
-- 4. O resultado mostrará tabela por tabela se a contagem está "OK" ou com "DIVERGENCIA".
-- 5. Copie e cole a tabela final exibida de volta no chat.
-- ==============================================================================

\x off
\pset border 2
\pset null '(vazio)'

WITH contagens_atuais AS (
    SELECT 'clients'::text AS tabela, count(*)::bigint AS registros_encontrados, 345::bigint AS registros_esperados FROM public.clients
    UNION ALL
    SELECT 'cases', count(*), 550 FROM public.cases
    UNION ALL
    SELECT 'transactions', count(*), 941 FROM public.transactions
    UNION ALL
    SELECT 'tasks', count(*), 834 FROM public.tasks
    UNION ALL
    SELECT 'user_sessions', count(*), 3718 FROM public.user_sessions
    UNION ALL
    SELECT 'logs', count(*), 521 FROM public.logs
    UNION ALL
    SELECT 'transaction_cases', count(*), 471 FROM public.transaction_cases
    UNION ALL
    SELECT 'appointments', count(*), 258 FROM public.appointments
    UNION ALL
    SELECT 'backup_logs', count(*), 31 FROM public.backup_logs
    UNION ALL
    SELECT 'suppliers', count(*), 26 FROM public.suppliers
    UNION ALL
    SELECT 'petitions', count(*), 11 FROM public.petitions
    UNION ALL
    SELECT 'case_systems', count(*), 8 FROM public.case_systems
    UNION ALL
    SELECT 'profiles', count(*), 7 FROM public.profiles
    UNION ALL
    SELECT 'whatsapp_messages', count(*), 2 FROM public.whatsapp_messages
    UNION ALL
    SELECT 'document_templates', count(*), 1 FROM public.document_templates
    UNION ALL
    SELECT 'settings', count(*), 1 FROM public.settings
    UNION ALL
    SELECT 'backup_export_config', count(*), 1 FROM public.backup_export_config
)
SELECT 
    tabela AS "Tabela",
    registros_esperados AS "Esperado (Fase 0)",
    registros_encontrados AS "Encontrado no Novo Banco",
    (registros_encontrados - registros_esperados) AS "Diferença",
    CASE 
        WHEN registros_encontrados = registros_esperados THEN '✅ OK'
        WHEN tabela = 'logs' AND registros_encontrados >= registros_esperados THEN '✅ OK (com logs novos)'
        WHEN tabela = 'backup_logs' AND registros_encontrados >= registros_esperados THEN '✅ OK (com backups novos)'
        WHEN registros_encontrados > registros_esperados THEN '⚠️ MAIOR QUE O ESPERADO (Verificar)'
        ELSE '❌ DIVERGÊNCIA (Faltando dados)'
    END AS "Status da Auditoria"
FROM contagens_atuais
ORDER BY 
    CASE 
        WHEN registros_encontrados = registros_esperados THEN 2
        ELSE 1
    END,
    registros_esperados DESC;

-- ------------------------------------------------------------------------------
-- VERIFICAÇÕES COMPLEMENTARES DE INTEGRIDADE
-- ------------------------------------------------------------------------------

-- 1. Conferência dos 7 usuários do escritório em public.profiles:
SELECT 
    name AS "Nome do Operador",
    email AS "E-mail",
    role AS "Perfil",
    is_active AS "Ativo",
    "canViewFinance" AS "Ver Finanças"
FROM public.profiles
ORDER BY name;

-- 2. Conferência dos sistemas judiciais em public.case_systems:
SELECT 
    id,
    name AS "Sistema",
    (image_url IS NOT NULL) AS "Possui Logo"
FROM public.case_systems
ORDER BY name;

-- 3. Conferência de extensões instaladas:
SELECT 
    extname AS "Extensão",
    extversion AS "Versão Instalada"
FROM pg_extension
WHERE extname IN ('uuid-ossp', 'pgcrypto');

-- 4. Conferência de triggers ativas:
SELECT 
    relname AS "Tabela",
    tgname AS "Trigger"
FROM pg_trigger t
JOIN pg_class c ON t.tgrelid = c.oid
WHERE c.relnamespace = 'public'::regnamespace
  AND NOT t.tgisinternal
ORDER BY relname, tgname;
