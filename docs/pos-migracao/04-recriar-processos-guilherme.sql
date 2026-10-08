-- ==============================================================================
-- DPSjur / SBJur - Kit Pós-Migração VPS (Hostinger KVM 1)
-- Script: docs/pos-migracao/04-recriar-processos-guilherme.sql
-- Versão: v0.0.527
-- ==============================================================================
-- Finalidade:
-- Recriar no banco do VPS oficial (Supabase self-hosted) os 3 processos judiciais
-- cadastrados pelo colaborador Guilherme Almeida no ambiente de preview (nuvem)
-- em 07/10/2026, com preservação dos timestamps reais de criação, metadados e
-- inserção dos respectivos logs de auditoria na tabela public.logs.
--
-- Idempotência:
-- O script pode ser executado múltiplas vezes com segurança. Usa ON CONFLICT (number)
-- DO NOTHING e checagens NOT EXISTS para evitar duplicações.
-- ==============================================================================

\echo '====================================================================='
\echo '  DPSjur - Recriação de Processos de Guilherme Almeida no VPS        '
\echo '  Versão: v0.0.527'
\echo '====================================================================='
\echo ''

-- ------------------------------------------------------------------------------
-- 1. SEÇÃO DE VERIFICAÇÃO PRÉVIA (CLIENTES E RESPONSÁVEL NO VPS)
-- ------------------------------------------------------------------------------
\echo '🔍 [1/4] Verificando existência dos clientes e do responsável no banco local...'
\echo 'Nota: Como o VPS foi migrado via dump integral da mesma base de dados,'
\echo 'os UUIDs e documentos dos clientes e do perfil devem coincidir perfeitamente.'
\echo ''

-- Verificação 1.1: Perfil de Guilherme Almeida
\echo '>> Checando perfil de Guilherme Almeida (id: 4ad65234-19ac-4b8d-aec5-fb0ad9ffdeaf):'
SELECT id, name, email, role, is_active
FROM public.profiles
WHERE id = '4ad65234-19ac-4b8d-aec5-fb0ad9ffdeaf';

-- Verificação 1.2: Clientes envolvidos (Adílio Veríssimo e Ana Letícia)
\echo '>> Checando clientes vinculados (documentos 055.925.496-28 e 069.241.976-47):'
SELECT id, name, document, classification, status
FROM public.clients
WHERE document IN ('055.925.496-28', '069.241.976-47')
   OR id IN ('69ee6ee6-f82a-41bb-acf8-fcbda6467a36', 'a2884994-0e57-4d10-81ef-df7230cc9710')
ORDER BY name;

-- Validação de segurança em bloco anônimo antes de prosseguir
DO $$
DECLARE
    v_guilherme_exists boolean;
    v_adilio_exists boolean;
    v_ana_exists boolean;
BEGIN
    SELECT EXISTS (SELECT 1 FROM public.profiles WHERE id = '4ad65234-19ac-4b8d-aec5-fb0ad9ffdeaf') INTO v_guilherme_exists;
    IF NOT v_guilherme_exists THEN
        RAISE EXCEPTION 'Perfil de Guilherme Almeida (4ad65234-19ac-4b8d-aec5-fb0ad9ffdeaf) não encontrado no banco local! Abortando.';
    END IF;

    SELECT EXISTS (SELECT 1 FROM public.clients WHERE id = '69ee6ee6-f82a-41bb-acf8-fcbda6467a36' OR document = '055.925.496-28') INTO v_adilio_exists;
    IF NOT v_adilio_exists THEN
        RAISE EXCEPTION 'Cliente ADILIO VERISSIMO ALTAIR (055.925.496-28) não encontrado no banco local! Abortando.';
    END IF;

    SELECT EXISTS (SELECT 1 FROM public.clients WHERE id = 'a2884994-0e57-4d10-81ef-df7230cc9710' OR document = '069.241.976-47') INTO v_ana_exists;
    IF NOT v_ana_exists THEN
        RAISE EXCEPTION 'Cliente ANA LETICIA DO NASCIMENTO SIMOES ABREU (069.241.976-47) não encontrada no banco local! Abortando.';
    END IF;
END
$$;

\echo '✅ Verificação prévia aprovada! Clientes e responsável existem no banco local.'
\echo ''

-- ------------------------------------------------------------------------------
-- 2. INSERÇÃO IDEMPOTENTE DOS 3 PROCESSOS EM public.cases
-- ------------------------------------------------------------------------------
\echo '🚀 [2/4] Inserindo os 3 processos judiciais em public.cases...'

BEGIN;

-- Processo 1: Adílio x Kasa Bella (indenizatória)
-- Cliente: ADILIO VERISSIMO ALTAIR (69ee6ee6-f82a-41bb-acf8-fcbda6467a36)
-- Data original de criação: 2026-10-07 14:25:34.896102+00
INSERT INTO public.cases (
    id,
    number,
    position,
    "adverseParty",
    type,
    status,
    court,
    comarca,
    state,
    system,
    value,
    "startDate",
    "responsibleId",
    "clientId",
    "isSpecial",
    classification,
    description,
    "isProblematic",
    "isRestricted",
    "feeValue",
    "feeInstallments",
    "updatedAt",
    created_at
)
SELECT
    gen_random_uuid(),
    'Adílio x Kasa Bella (indenizatória)',
    'AUTOR',
    '',
    'Indenizatória',
    'Aguardando documentos',
    '',
    '',
    '',
    'PJE',
    0,
    '2026-10-07',
    '4ad65234-19ac-4b8d-aec5-fb0ad9ffdeaf'::uuid,
    c.id,
    false,
    'DPS',
    '',
    false,
    false,
    0,
    1,
    '2026-10-07',
    '2026-10-07 14:25:34.896102+00'::timestamptz
FROM public.clients c
WHERE c.id = '69ee6ee6-f82a-41bb-acf8-fcbda6467a36'
   OR c.document = '055.925.496-28'
ORDER BY (c.id = '69ee6ee6-f82a-41bb-acf8-fcbda6467a36') DESC
LIMIT 1
ON CONFLICT (number) DO NOTHING;

-- Processo 2: Indenizatória contra a WX
-- Cliente: ANA LETICIA DO NASCIMENTO SIMOES ABREU (a2884994-0e57-4d10-81ef-df7230cc9710)
-- Data original de criação: 2026-10-07 18:04:06.037049+00
INSERT INTO public.cases (
    id,
    number,
    position,
    "adverseParty",
    type,
    status,
    court,
    comarca,
    state,
    system,
    value,
    "startDate",
    "responsibleId",
    "clientId",
    "isSpecial",
    classification,
    description,
    "isProblematic",
    "isRestricted",
    "feeValue",
    "feeInstallments",
    "updatedAt",
    created_at
)
SELECT
    gen_random_uuid(),
    'Indenizatória contra a WX',
    'AUTOR',
    '',
    'Indenizatória',
    'Aguardando documentos',
    '',
    '',
    '',
    'PJE',
    0,
    '2026-10-07',
    '4ad65234-19ac-4b8d-aec5-fb0ad9ffdeaf'::uuid,
    c.id,
    false,
    'DPS',
    '',
    false,
    false,
    0,
    1,
    '2026-10-07',
    '2026-10-07 18:04:06.037049+00'::timestamptz
FROM public.clients c
WHERE c.id = 'a2884994-0e57-4d10-81ef-df7230cc9710'
   OR c.document = '069.241.976-47'
ORDER BY (c.id = 'a2884994-0e57-4d10-81ef-df7230cc9710') DESC
LIMIT 1
ON CONFLICT (number) DO NOTHING;

-- Processo 3: Indenizatória contra Zurich
-- Cliente: ANA LETICIA DO NASCIMENTO SIMOES ABREU (a2884994-0e57-4d10-81ef-df7230cc9710)
-- Data original de criação: 2026-10-07 18:07:19.19065+00
INSERT INTO public.cases (
    id,
    number,
    position,
    "adverseParty",
    type,
    status,
    court,
    comarca,
    state,
    system,
    value,
    "startDate",
    "responsibleId",
    "clientId",
    "isSpecial",
    classification,
    description,
    "isProblematic",
    "isRestricted",
    "feeValue",
    "feeInstallments",
    "updatedAt",
    created_at
)
SELECT
    gen_random_uuid(),
    'Indenizatória contra Zurich',
    'AUTOR',
    '',
    'Indenizatória',
    'Aguardando documentos',
    '',
    '',
    '',
    'PJE',
    0,
    '2026-10-07',
    '4ad65234-19ac-4b8d-aec5-fb0ad9ffdeaf'::uuid,
    c.id,
    false,
    'DPS',
    '',
    false,
    false,
    0,
    1,
    '2026-10-07',
    '2026-10-07 18:07:19.19065+00'::timestamptz
FROM public.clients c
WHERE c.id = 'a2884994-0e57-4d10-81ef-df7230cc9710'
   OR c.document = '069.241.976-47'
ORDER BY (c.id = 'a2884994-0e57-4d10-81ef-df7230cc9710') DESC
LIMIT 1
ON CONFLICT (number) DO NOTHING;

COMMIT;

\echo '✅ Inserção em public.cases concluída com sucesso!'
\echo ''

-- ------------------------------------------------------------------------------
-- 3. INSERÇÃO DOS REGISTROS EM public.logs (ESPELHANDO AUDITORIA DO APP)
-- ------------------------------------------------------------------------------
\echo '📝 [3/4] Registrando eventos na tabela public.logs (auditoria de criação)...'

BEGIN;

-- Log Processo 1
INSERT INTO public.logs (
    id,
    action,
    entity,
    "user",
    date,
    details,
    created_at
)
SELECT
    gen_random_uuid(),
    'CREATE',
    'case',
    'Guilherme Almeida',
    '2026-10-07',
    'Processo Adílio x Kasa Bella (indenizatória) criado',
    '2026-10-07 14:25:34.896102+00'::timestamptz
WHERE NOT EXISTS (
    SELECT 1 FROM public.logs
    WHERE action = 'CREATE'
      AND entity = 'case'
      AND details ILIKE '%Adílio x Kasa Bella%'
);

-- Log Processo 2
INSERT INTO public.logs (
    id,
    action,
    entity,
    "user",
    date,
    details,
    created_at
)
SELECT
    gen_random_uuid(),
    'CREATE',
    'case',
    'Guilherme Almeida',
    '2026-10-07',
    'Processo Indenizatória contra a WX criado',
    '2026-10-07 18:04:06.037049+00'::timestamptz
WHERE NOT EXISTS (
    SELECT 1 FROM public.logs
    WHERE action = 'CREATE'
      AND entity = 'case'
      AND details ILIKE '%Indenizatória contra a WX%'
);

-- Log Processo 3
INSERT INTO public.logs (
    id,
    action,
    entity,
    "user",
    date,
    details,
    created_at
)
SELECT
    gen_random_uuid(),
    'CREATE',
    'case',
    'Guilherme Almeida',
    '2026-10-07',
    'Processo Indenizatória contra Zurich criado',
    '2026-10-07 18:07:19.19065+00'::timestamptz
WHERE NOT EXISTS (
    SELECT 1 FROM public.logs
    WHERE action = 'CREATE'
      AND entity = 'case'
      AND details ILIKE '%Indenizatória contra Zurich%'
);

COMMIT;

\echo '✅ Registros em public.logs inseridos com sucesso!'
\echo ''

-- ------------------------------------------------------------------------------
-- 4. CONFERÊNCIA FINAL COM EXIBIÇÃO FORMATADA
-- ------------------------------------------------------------------------------
\echo '🔎 [4/4] Conferência final dos processos recriados no banco local:'
\echo ''

SELECT
    c.id AS processo_id,
    c.number AS numero_processo,
    cl.name AS cliente_nome,
    cl.document AS cliente_documento,
    p.name AS responsavel_nome,
    c.type AS tipo,
    c.status AS status,
    c.system AS sistema,
    c.classification AS classificacao,
    c."startDate" AS data_inicio,
    c.created_at AS criado_em
FROM public.cases c
JOIN public.clients cl ON cl.id = c."clientId"
LEFT JOIN public.profiles p ON p.id = c."responsibleId"
WHERE c.number IN (
    'Adílio x Kasa Bella (indenizatória)',
    'Indenizatória contra a WX',
    'Indenizatória contra Zurich'
)
ORDER BY c.created_at;

\echo ''
\echo 'Logs de auditoria registrados para os 3 processos:'
SELECT
    l.id AS log_id,
    l.action AS acao,
    l.entity AS entidade,
    l."user" AS usuario,
    l.date AS data_log,
    l.details AS detalhes,
    l.created_at AS registrado_em
FROM public.logs l
WHERE l.entity = 'case'
  AND (
      l.details ILIKE '%Adílio x Kasa Bella%' OR
      l.details ILIKE '%Indenizatória contra a WX%' OR
      l.details ILIKE '%Indenizatória contra Zurich%'
  )
ORDER BY l.created_at;

\echo ''
\echo '====================================================================='
\echo '🎉 Processos de Guilherme Almeida recriados com sucesso no VPS!'
\echo '====================================================================='
