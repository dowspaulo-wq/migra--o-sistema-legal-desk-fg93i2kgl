-- Fix RLS for settings
DROP POLICY IF EXISTS "authenticated_select_settings" ON public.settings;
CREATE POLICY "authenticated_select_settings" ON public.settings
  FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "authenticated_insert_settings" ON public.settings;
CREATE POLICY "authenticated_insert_settings" ON public.settings
  FOR INSERT TO authenticated WITH CHECK (true);

DROP POLICY IF EXISTS "authenticated_update_settings" ON public.settings;
CREATE POLICY "authenticated_update_settings" ON public.settings
  FOR UPDATE TO authenticated USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "authenticated_delete_settings" ON public.settings;
CREATE POLICY "authenticated_delete_settings" ON public.settings
  FOR DELETE TO authenticated USING (true);

-- Fix RLS for whatsapp_messages
DROP POLICY IF EXISTS "authenticated_select_whatsapp_messages" ON public.whatsapp_messages;
CREATE POLICY "authenticated_select_whatsapp_messages" ON public.whatsapp_messages
  FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "authenticated_insert_whatsapp_messages" ON public.whatsapp_messages;
CREATE POLICY "authenticated_insert_whatsapp_messages" ON public.whatsapp_messages
  FOR INSERT TO authenticated WITH CHECK (true);

DROP POLICY IF EXISTS "authenticated_update_whatsapp_messages" ON public.whatsapp_messages;
CREATE POLICY "authenticated_update_whatsapp_messages" ON public.whatsapp_messages
  FOR UPDATE TO authenticated USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "authenticated_delete_whatsapp_messages" ON public.whatsapp_messages;
CREATE POLICY "authenticated_delete_whatsapp_messages" ON public.whatsapp_messages
  FOR DELETE TO authenticated USING (true);

-- Update caseTypes in settings based on user request to fix missing types
DO $$
DECLARE
  settings_id uuid;
  default_case_types jsonb := '[
    {"label": "Previdenciário", "color": "#eab308"},
    {"label": "Tutelas e/ou Curatelas", "color": "#92400e"},
    {"label": "Alimentos", "color": "#ec4899"},
    {"label": "Possessórios e usucapião", "color": "#ef4444"},
    {"label": "Incidentes", "color": "#f97316"},
    {"label": "Busca e apreensão", "color": "#14b8a6"},
    {"label": "Anulatória", "color": "#14b8a6"},
    {"label": "Execução ou embargos", "color": "#8b5cf6"},
    {"label": "Reclamatória trabalhista", "color": "#eab308"},
    {"label": "Outros", "color": "#64748b"},
    {"label": "Divórcio e União Estável", "color": "#ec4899"},
    {"label": "Indenizatória", "color": "#22c55e"},
    {"label": "Inventário", "color": "#3b82f6"}
  ]'::jsonb;
BEGIN
  -- Check if there's any setting row
  SELECT id INTO settings_id FROM public.settings LIMIT 1;
  
  IF settings_id IS NULL THEN
    INSERT INTO public.settings ("caseTypes") VALUES (default_case_types);
  ELSE
    UPDATE public.settings SET "caseTypes" = default_case_types WHERE id = settings_id;
  END IF;
END $$;
