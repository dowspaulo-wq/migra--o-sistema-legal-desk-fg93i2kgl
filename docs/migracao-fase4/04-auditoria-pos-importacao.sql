-- ==============================================================================
-- DPSjur - Auditoria Completa Pós-Importação (Schema, Contagens, RLS, FKs e Índices)
-- Gerado para: Fase 4 da Migração para Supabase Self-Hosted (EasyPanel)
-- Alvo de Validação: Comparação direta com os dados vivos do SBJur
-- ==============================================================================

\echo '====================================================================='
\echo '  DPSJUR - AUDITORIA PÓS-IMPORTAÇÃO NO SUPABASE SELF-HOSTED'
\echo '====================================================================='
\echo ''

-- 1. CONFERÊNCIA DE CONTAGEM DAS TABELAS
\echo '---------------------------------------------------------------------'
\echo '1. CONTAGEM DAS TABELAS (Valores esperados vs encontrados)'
\echo '---------------------------------------------------------------------'

WITH expected(table_name, expected_count) AS (
    VALUES
        ('auth.users', 7),
        ('public.profiles', 7),
        ('public.clients', 345),
        ('public.cases', 550),
        ('public.tasks', 836),
        ('public.appointments', 258),
        ('public.transactions', 941),
        ('public.transaction_cases', 471),
        ('public.suppliers', 26),
        ('public.case_systems', 8),
        ('public.petitions', 11),
        ('public.document_templates', 1),
        ('public.settings', 1),
        ('public.logs', 527),
        ('public.user_sessions', 3722),
        ('public.whatsapp_messages', 0),
        ('public.backup_logs', 0)
),
actual AS (
    SELECT 'auth.users'::text AS table_name, count(*) AS actual_count FROM auth.users
    UNION ALL SELECT 'public.profiles', count(*) FROM public.profiles
    UNION ALL SELECT 'public.clients', count(*) FROM public.clients
    UNION ALL SELECT 'public.cases', count(*) FROM public.cases
    UNION ALL SELECT 'public.tasks', count(*) FROM public.tasks
    UNION ALL SELECT 'public.appointments', count(*) FROM public.appointments
    UNION ALL SELECT 'public.transactions', count(*) FROM public.transactions
    UNION ALL SELECT 'public.transaction_cases', count(*) FROM public.transaction_cases
    UNION ALL SELECT 'public.suppliers', count(*) FROM public.suppliers
    UNION ALL SELECT 'public.case_systems', count(*) FROM public.case_systems
    UNION ALL SELECT 'public.petitions', count(*) FROM public.petitions
    UNION ALL SELECT 'public.document_templates', count(*) FROM public.document_templates
    UNION ALL SELECT 'public.settings', count(*) FROM public.settings
    UNION ALL SELECT 'public.logs', count(*) FROM public.logs
    UNION ALL SELECT 'public.user_sessions', count(*) FROM public.user_sessions
    UNION ALL SELECT 'public.whatsapp_messages', count(*) FROM public.whatsapp_messages
    UNION ALL SELECT 'public.backup_logs', count(*) FROM public.backup_logs
)
SELECT 
    e.table_name AS "Tabela",
    e.expected_count AS "Esperado",
    COALESCE(a.actual_count, 0) AS "Atual",
    CASE 
        -- logs e user_sessions podem ter pequenos desvios normais se houver atividade
        WHEN e.table_name IN ('public.logs', 'public.user_sessions', 'public.backup_logs') 
             AND COALESCE(a.actual_count, 0) >= (e.expected_count * 0.95) THEN 'OK (Atividade Contínua)'
        WHEN e.expected_count = COALESCE(a.actual_count, 0) THEN 'OK EXATO'
        WHEN COALESCE(a.actual_count, 0) > e.expected_count THEN 'OK (+ Registros Novos)'
        ELSE '⚠️ DIVERGÊNCIA'
    END AS "Status"
FROM expected e
LEFT JOIN actual a ON e.table_name = a.table_name
ORDER BY e.table_name;

\echo ''
\echo '---------------------------------------------------------------------'
\echo '2. AUDITORIA DE RLS (Row Level Security) NAS 17 TABELAS DO SCHEMA PUBLIC'
\echo '---------------------------------------------------------------------'

SELECT 
    tablename AS "Tabela",
    CASE WHEN rowsecurity THEN 'ATIVO (OK)' ELSE '⚠️ DESATIVADO' END AS "RLS Status"
FROM pg_tables 
WHERE schemaname = 'public'
ORDER BY tablename;

\echo ''
\echo '---------------------------------------------------------------------'
\echo '3. AUDITORIA DE POLÍTICAS DE RLS (Esperado: 57 Políticas)'
\echo '---------------------------------------------------------------------'

SELECT 
    tablename AS "Tabela",
    count(*) AS "Qtd Políticas Ativas"
FROM pg_policies 
WHERE schemaname = 'public'
GROUP BY tablename
ORDER BY tablename;

SELECT 
    count(*) AS "Total Políticas Encontradas",
    CASE WHEN count(*) >= 57 THEN 'OK (Todas as 57 presentes)' ELSE '⚠️ INCOMPLETO' END AS "Diagnóstico"
FROM pg_policies 
WHERE schemaname = 'public';

\echo ''
\echo '---------------------------------------------------------------------'
\echo '4. AUDITORIA DE FOREIGN KEYS (Integridade Referencial)'
\echo '---------------------------------------------------------------------'

SELECT
    tc.table_name AS "Tabela Origem",
    kcu.column_name AS "Coluna FK",
    ccu.table_name AS "Tabela Destino",
    ccu.column_name AS "Coluna PK"
FROM information_schema.table_constraints AS tc
JOIN information_schema.key_column_usage AS kcu
  ON tc.constraint_name = kcu.constraint_name
  AND tc.table_schema = kcu.table_schema
JOIN information_schema.constraint_column_usage AS ccu
  ON ccu.constraint_name = tc.constraint_name
  AND ccu.table_schema = tc.table_schema
WHERE tc.constraint_type = 'FOREIGN KEY'
  AND tc.table_schema = 'public'
ORDER BY tc.table_name, kcu.column_name;

SELECT 
    count(*) AS "Total de Foreign Keys no Schema Public"
FROM pg_constraint con 
JOIN pg_namespace nsp ON nsp.oid = con.connamespace 
WHERE con.contype = 'f' AND nsp.nspname = 'public';

\echo ''
\echo '---------------------------------------------------------------------'
\echo '5. AUDITORIA DE ÍNDICES DE PERFORMANCE'
\echo '---------------------------------------------------------------------'

SELECT 
    tablename AS "Tabela",
    indexname AS "Índice",
    indexdef AS "Definição"
FROM pg_indexes 
WHERE schemaname = 'public'
ORDER BY tablename, indexname;

SELECT 
    count(*) AS "Total de Índices no Schema Public",
    CASE WHEN count(*) >= 33 THEN 'OK (Performance Otimizada)' ELSE '⚠️ Faltam Índices' END AS "Diagnóstico"
FROM pg_indexes 
WHERE schemaname = 'public';

\echo ''
\echo '---------------------------------------------------------------------'
\echo '6. AUDITORIA DE USUÁRIOS E SENHAS (auth.users vs public.profiles)'
\echo '---------------------------------------------------------------------'

SELECT 
    u.id AS "ID do Usuário",
    u.email AS "E-mail de Login",
    p.name AS "Nome no Perfil",
    p.role AS "Perfil de Acesso",
    CASE 
        WHEN u.encrypted_password LIKE '$2a$%' OR u.encrypted_password LIKE '$2b$%' THEN 'BCRYPT VÁLIDO (OK)'
        ELSE '⚠️ SENHA INVÁLIDA'
    END AS "Status Hash da Senha",
    CASE WHEN u.confirmed_at IS NOT NULL THEN 'CONFIRMADO' ELSE 'PENDENTE' END AS "E-mail Confirmado",
    CASE WHEN i.id IS NOT NULL THEN 'IDENTIDADE OK' ELSE '⚠️ SEM IDENTIDADE' END AS "Identidade GoTrue"
FROM auth.users u
LEFT JOIN public.profiles p ON u.id = p.id
LEFT JOIN auth.identities i ON u.id = i.user_id
ORDER BY u.created_at ASC;

\echo ''
\echo '---------------------------------------------------------------------'
\echo '7. AUDITORIA DE STORAGE BUCKETS (Supabase Storage)'
\echo '---------------------------------------------------------------------'

SELECT 
    id AS "Bucket",
    public AS "Público?",
    file_size_limit AS "Limite (Bytes)",
    created_at AS "Criado em"
FROM storage.buckets
ORDER BY id;

\echo ''
\echo '====================================================================='
\echo '  FIM DA AUDITORIA'
\echo '====================================================================='
