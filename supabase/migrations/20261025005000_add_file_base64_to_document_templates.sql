-- Migration: Adicionar coluna file_base64 à tabela public.document_templates
-- Permite armazenamento resiliente dos modelos DOCX mesmo em caso de instabilidade ou timeout do Supabase Storage / Kong

DO $$
BEGIN
    ALTER TABLE public.document_templates ADD COLUMN IF NOT EXISTS file_base64 text;
    ALTER TABLE public.document_templates ADD COLUMN IF NOT EXISTS file_size_bytes bigint DEFAULT 0;
END $$;
