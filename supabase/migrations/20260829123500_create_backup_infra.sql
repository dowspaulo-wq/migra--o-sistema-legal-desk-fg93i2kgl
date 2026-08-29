-- Migration: Setup Database Backup Bucket, Metadata Table, and Stored Procedures
-- Date: 2026-08-29

-- 1. Create Private Storage Bucket for Backups
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'backups',
  'backups',
  false,
  52428800, -- 50MB limit
  ARRAY['application/json', 'application/sql', 'text/plain', 'text/x-sql']
)
ON CONFLICT (id) DO UPDATE SET
  public = false,
  file_size_limit = 52428800,
  allowed_mime_types = ARRAY['application/json', 'application/sql', 'text/plain', 'text/x-sql'];

-- 2. Storage Policies for backups bucket (Strict access: service_role / authenticated admins)
DROP POLICY IF EXISTS "service_role_manage_backups" ON storage.objects;
CREATE POLICY "service_role_manage_backups" ON storage.objects
  FOR ALL
  TO service_role
  USING (bucket_id = 'backups')
  WITH CHECK (bucket_id = 'backups');

DROP POLICY IF EXISTS "admin_read_backups" ON storage.objects;
CREATE POLICY "admin_read_backups" ON storage.objects
  FOR SELECT
  TO authenticated
  USING (
    bucket_id = 'backups' AND
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE profiles.id = auth.uid()
      AND (profiles.role = 'Admin' OR profiles.email = 'dowspaulo@gmail.com')
    )
  );

-- 3. Backup History/Logs Table
CREATE TABLE IF NOT EXISTS public.backup_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  file_name TEXT NOT NULL,
  format TEXT NOT NULL, -- 'json' | 'sql'
  file_size_bytes BIGINT NOT NULL DEFAULT 0,
  tables_included TEXT[] NOT NULL DEFAULT '{}',
  total_records INTEGER NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'completed', -- 'completed' | 'failed' | 'in_progress'
  error_message TEXT,
  trigger_type TEXT NOT NULL DEFAULT 'auto', -- 'auto' | 'manual'
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- RLS for backup_logs
ALTER TABLE public.backup_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "service_role_all_backup_logs" ON public.backup_logs;
CREATE POLICY "service_role_all_backup_logs" ON public.backup_logs
  FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

DROP POLICY IF EXISTS "admin_select_backup_logs" ON public.backup_logs;
CREATE POLICY "admin_select_backup_logs" ON public.backup_logs
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE profiles.id = auth.uid()
      AND (profiles.role = 'Admin' OR profiles.email = 'dowspaulo@gmail.com')
    )
  );

-- 4. Stored Procedure to extract full schema data as JSON
CREATE OR REPLACE FUNCTION public.export_database_backup_json()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $$
DECLARE
  v_result JSONB;
  v_appointments JSONB;
  v_case_systems JSONB;
  v_cases JSONB;
  v_clients JSONB;
  v_document_templates JSONB;
  v_logs JSONB;
  v_petitions JSONB;
  v_profiles JSONB;
  v_settings JSONB;
  v_suppliers JSONB;
  v_tasks JSONB;
  v_transaction_cases JSONB;
  v_transactions JSONB;
  v_user_sessions JSONB;
  v_whatsapp_messages JSONB;
  v_counts JSONB;
BEGIN
  -- Extract each table from public schema
  SELECT COALESCE(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_appointments FROM public.appointments t;
  SELECT COALESCE(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_case_systems FROM public.case_systems t;
  SELECT COALESCE(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_cases FROM public.cases t;
  SELECT COALESCE(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_clients FROM public.clients t;
  SELECT COALESCE(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_document_templates FROM public.document_templates t;
  SELECT COALESCE(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_logs FROM public.logs t;
  SELECT COALESCE(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_petitions FROM public.petitions t;
  SELECT COALESCE(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_profiles FROM public.profiles t;
  SELECT COALESCE(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_settings FROM public.settings t;
  SELECT COALESCE(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_suppliers FROM public.suppliers t;
  SELECT COALESCE(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_tasks FROM public.tasks t;
  SELECT COALESCE(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_transaction_cases FROM public.transaction_cases t;
  SELECT COALESCE(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_transactions FROM public.transactions t;
  SELECT COALESCE(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_user_sessions FROM public.user_sessions t;
  SELECT COALESCE(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_whatsapp_messages FROM public.whatsapp_messages t;

  v_counts := jsonb_build_object(
    'appointments', jsonb_array_length(v_appointments),
    'case_systems', jsonb_array_length(v_case_systems),
    'cases', jsonb_array_length(v_cases),
    'clients', jsonb_array_length(v_clients),
    'document_templates', jsonb_array_length(v_document_templates),
    'logs', jsonb_array_length(v_logs),
    'petitions', jsonb_array_length(v_petitions),
    'profiles', jsonb_array_length(v_profiles),
    'settings', jsonb_array_length(v_settings),
    'suppliers', jsonb_array_length(v_suppliers),
    'tasks', jsonb_array_length(v_tasks),
    'transaction_cases', jsonb_array_length(v_transaction_cases),
    'transactions', jsonb_array_length(v_transactions),
    'user_sessions', jsonb_array_length(v_user_sessions),
    'whatsapp_messages', jsonb_array_length(v_whatsapp_messages)
  );

  v_result := jsonb_build_object(
    'version', '1.0',
    'exported_at', NOW(),
    'schema', 'public',
    'record_counts', v_counts,
    'tables', jsonb_build_object(
      'appointments', v_appointments,
      'case_systems', v_case_systems,
      'cases', v_cases,
      'clients', v_clients,
      'document_templates', v_document_templates,
      'logs', v_logs,
      'petitions', v_petitions,
      'profiles', v_profiles,
      'settings', v_settings,
      'suppliers', v_suppliers,
      'tasks', v_tasks,
      'transaction_cases', v_transaction_cases,
      'transactions', v_transactions,
      'user_sessions', v_user_sessions,
      'whatsapp_messages', v_whatsapp_messages
    )
  );

  RETURN v_result;
END;
$$;

-- Grant execution to authenticated users and service_role
GRANT EXECUTE ON FUNCTION public.export_database_backup_json() TO service_role;
GRANT EXECUTE ON FUNCTION public.export_database_backup_json() TO authenticated;
