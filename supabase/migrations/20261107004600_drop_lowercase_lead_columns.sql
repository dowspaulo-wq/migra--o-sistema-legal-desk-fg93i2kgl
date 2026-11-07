-- Remove colunas criadas erradas (minúsculas) pela primeira versão
-- de 20261107004500 e mantém apenas as camelCase, padrão da tabela.
ALTER TABLE public.settings
  DROP COLUMN IF EXISTS leadorigins,
  DROP COLUMN IF EXISTS leadstages,
  DROP COLUMN IF EXISTS leadinteractiontypes;
