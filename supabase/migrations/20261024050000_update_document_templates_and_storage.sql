-- Migration: Adicionar campos manuais e metadados a public.document_templates
-- e assegurar bucket e policies de storage para document-templates e document_templates

DO $$
BEGIN
    -- 1. Colunas adicionais em public.document_templates
    ALTER TABLE public.document_templates ADD COLUMN IF NOT EXISTS manual_fields jsonb DEFAULT '[]'::jsonb;
    ALTER TABLE public.document_templates ADD COLUMN IF NOT EXISTS description text;
    ALTER TABLE public.document_templates ADD COLUMN IF NOT EXISTS updated_at timestamptz DEFAULT now();

    -- Garantir permissões
    GRANT SELECT, INSERT, UPDATE, DELETE ON public.document_templates TO authenticated;
    GRANT ALL ON public.document_templates TO service_role;
END $$;

-- 2. Garantir RLS em public.document_templates
ALTER TABLE public.document_templates ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "authenticated_select_document_templates" ON public.document_templates;
CREATE POLICY "authenticated_select_document_templates" ON public.document_templates
    FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "authenticated_insert_document_templates" ON public.document_templates;
CREATE POLICY "authenticated_insert_document_templates" ON public.document_templates
    FOR INSERT TO authenticated WITH CHECK (true);

DROP POLICY IF EXISTS "authenticated_update_document_templates" ON public.document_templates;
CREATE POLICY "authenticated_update_document_templates" ON public.document_templates
    FOR UPDATE TO authenticated USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "authenticated_delete_document_templates" ON public.document_templates;
CREATE POLICY "authenticated_delete_document_templates" ON public.document_templates
    FOR DELETE TO authenticated USING (true);

-- 3. Garantir buckets de storage ('document_templates' e 'document-templates')
INSERT INTO storage.buckets (id, name, public)
VALUES ('document_templates', 'document_templates', true)
ON CONFLICT (id) DO UPDATE SET public = true;

INSERT INTO storage.buckets (id, name, public)
VALUES ('document-templates', 'document-templates', true)
ON CONFLICT (id) DO UPDATE SET public = true;

-- Garantir bucket documents para anexos gerados
INSERT INTO storage.buckets (id, name, public)
VALUES ('documents', 'documents', true)
ON CONFLICT (id) DO UPDATE SET public = true;

-- 4. Políticas de Storage para document_templates e document-templates
DROP POLICY IF EXISTS "authenticated_read_document_templates_bucket" ON storage.objects;
CREATE POLICY "authenticated_read_document_templates_bucket" ON storage.objects
    FOR SELECT TO authenticated
    USING (bucket_id IN ('document_templates', 'document-templates', 'documents'));

DROP POLICY IF EXISTS "authenticated_upload_document_templates_bucket" ON storage.objects;
CREATE POLICY "authenticated_upload_document_templates_bucket" ON storage.objects
    FOR INSERT TO authenticated
    WITH CHECK (bucket_id IN ('document_templates', 'document-templates', 'documents'));

DROP POLICY IF EXISTS "authenticated_update_document_templates_bucket" ON storage.objects;
CREATE POLICY "authenticated_update_document_templates_bucket" ON storage.objects
    FOR UPDATE TO authenticated
    USING (bucket_id IN ('document_templates', 'document-templates', 'documents'))
    WITH CHECK (bucket_id IN ('document_templates', 'document-templates', 'documents'));

DROP POLICY IF EXISTS "authenticated_delete_document_templates_bucket" ON storage.objects;
CREATE POLICY "authenticated_delete_document_templates_bucket" ON storage.objects
    FOR DELETE TO authenticated
    USING (bucket_id IN ('document_templates', 'document-templates', 'documents'));
