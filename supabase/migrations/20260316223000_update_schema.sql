-- Add avatar_url to profiles
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS avatar_url TEXT;

-- Update settings caseTypes to be an array of objects for coloring
UPDATE public.settings
SET "caseTypes" = '[{"label": "Cível", "color": "#3b82f6"}, {"label": "Trabalhista", "color": "#ef4444"}, {"label": "Tributário", "color": "#10b981"}, {"label": "Criminal", "color": "#f59e0b"}, {"label": "Família", "color": "#8b5cf6"}]'::jsonb
WHERE jsonb_typeof("caseTypes") = 'array' AND jsonb_array_length("caseTypes") > 0 AND jsonb_typeof("caseTypes"->0) = 'string';

-- Enable RLS update for profiles so users can update their avatar
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'profiles' AND policyname = 'authenticated_update_profiles') THEN
        CREATE POLICY "authenticated_update_profiles" ON public.profiles FOR UPDATE TO authenticated USING (auth.uid() = id) WITH CHECK (auth.uid() = id);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'profiles' AND policyname = 'authenticated_select_profiles') THEN
        CREATE POLICY "authenticated_select_profiles" ON public.profiles FOR SELECT TO authenticated USING (true);
    END IF;
END $$;

-- Storage buckets for avatars
INSERT INTO storage.buckets (id, name, public) VALUES ('avatars', 'avatars', true) ON CONFLICT DO NOTHING;

-- Policies for avatars bucket
DROP POLICY IF EXISTS "Avatar Select" ON storage.objects;
DROP POLICY IF EXISTS "Avatar Insert" ON storage.objects;
DROP POLICY IF EXISTS "Avatar Update" ON storage.objects;
DROP POLICY IF EXISTS "Avatar Delete" ON storage.objects;

CREATE POLICY "Avatar Select" ON storage.objects FOR SELECT USING (bucket_id = 'avatars');
CREATE POLICY "Avatar Insert" ON storage.objects FOR INSERT WITH CHECK (bucket_id = 'avatars');
CREATE POLICY "Avatar Update" ON storage.objects FOR UPDATE USING (bucket_id = 'avatars');
CREATE POLICY "Avatar Delete" ON storage.objects FOR DELETE USING (bucket_id = 'avatars');
