-- ============================================================
-- MÓDULO DE LEADS: listas configuráveis pelo usuário.
-- Aditivo: apenas novas colunas jsonb em settings, mesmo padrão
-- de leadAreas/leadSubjects. Defaults = listas usadas até hoje
-- pelo módulo. Leads/interações já gravados continuam com seus
-- rótulos em texto e seguem exibidos mesmo fora da lista.
-- ============================================================

-- Correção: primeira versão desta migration criou as colunas em
-- minúsculas (leadorigins etc.); drop para recriar em camelCase,
-- padrão das demais colunas da tabela settings.
ALTER TABLE public.settings
  DROP COLUMN IF EXISTS leadorigins,
  DROP COLUMN IF EXISTS leadstages,
  DROP COLUMN IF EXISTS leadinteractiontypes;

ALTER TABLE public.settings
  ADD COLUMN IF NOT EXISTS "leadOrigins" jsonb DEFAULT
    '["Meta Ads — Facebook","Meta Ads — Instagram","Google Ads","Site institucional","WhatsApp","Indicação","Contato orgânico","Outros"]'::jsonb;

ALTER TABLE public.settings
  ADD COLUMN IF NOT EXISTS "leadStages" jsonb DEFAULT
    '[{"id":"novo","label":"Novo"},{"id":"aguardando","label":"Aguardando contato"},{"id":"atendimento","label":"Em atendimento"},{"id":"qualificado","label":"Qualificado"},{"id":"proposta","label":"Proposta enviada"},{"id":"contratado","label":"Contratado"},{"id":"perdido","label":"Perdido"},{"id":"nao-qualificado","label":"Não qualificado"}]'::jsonb;

ALTER TABLE public.settings
  ADD COLUMN IF NOT EXISTS "leadInteractionTypes" jsonb DEFAULT
    '["Ligação","Mensagem","Reunião","Tentativa de contato","Observação","Proposta","Mudança de etapa","Retorno agendado"]'::jsonb;
