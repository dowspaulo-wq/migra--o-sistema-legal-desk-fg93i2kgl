-- Adiciona as colunas camelCase (padrão da tabela settings) para as
-- listas configuráveis do módulo de Leads. A versão original de
-- 20261107004500 criou as colunas em minúsculas, que foram removidas
-- pela migration 20261107004600.
ALTER TABLE public.settings
  ADD COLUMN IF NOT EXISTS "leadOrigins" jsonb DEFAULT
    '["Meta Ads — Facebook","Meta Ads — Instagram","Google Ads","Site institucional","WhatsApp","Indicação","Contato orgânico","Outros"]'::jsonb;

ALTER TABLE public.settings
  ADD COLUMN IF NOT EXISTS "leadStages" jsonb DEFAULT
    '[{"id":"novo","label":"Novo"},{"id":"aguardando","label":"Aguardando contato"},{"id":"atendimento","label":"Em atendimento"},{"id":"qualificado","label":"Qualificado"},{"id":"proposta","label":"Proposta enviada"},{"id":"contratado","label":"Contratado"},{"id":"perdido","label":"Perdido"},{"id":"nao-qualificado","label":"Não qualificado"}]'::jsonb;

ALTER TABLE public.settings
  ADD COLUMN IF NOT EXISTS "leadInteractionTypes" jsonb DEFAULT
    '["Ligação","Mensagem","Reunião","Tentativa de contato","Observação","Proposta","Mudança de etapa","Retorno agendado"]'::jsonb;
