-- Adiciona colunas de credenciais OAuth do Google na tabela settings
-- Permite que o usuário configure o Client ID e Client Secret pelo painel (Configurações > Integrações),
-- eliminando a dependência obrigatória de variáveis de ambiente no container edge-runtime do VPS.

ALTER TABLE public.settings
  ADD COLUMN IF NOT EXISTS "googleClientId" text,
  ADD COLUMN IF NOT EXISTS "googleClientSecret" text;

COMMENT ON COLUMN public.settings."googleClientId" IS 'Client ID OAuth 2.0 do Google Cloud Console para sincronização da agenda';
COMMENT ON COLUMN public.settings."googleClientSecret" IS 'Client Secret OAuth 2.0 do Google Cloud Console para sincronização da agenda';
