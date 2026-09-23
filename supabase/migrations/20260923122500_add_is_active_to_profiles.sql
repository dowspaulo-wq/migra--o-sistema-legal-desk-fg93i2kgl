-- Migration: add is_active to public.profiles
-- Idempotent: adds is_active column with default true and updates handle_new_user trigger function.

ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS is_active BOOLEAN NOT NULL DEFAULT true;

-- Ensure all existing profiles are active
UPDATE public.profiles SET is_active = true WHERE is_active IS NULL;

-- Update handle_new_user trigger to preserve is_active default or metadata
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
BEGIN
  INSERT INTO public.profiles (id, email, name, role, "canViewFinance", color, is_active)
  VALUES (
    NEW.id,
    NEW.email,
    COALESCE(NEW.raw_user_meta_data->>'name', 'Usuário'),
    COALESCE(NEW.raw_user_meta_data->>'role', 'User'),
    COALESCE((NEW.raw_user_meta_data->>'canViewFinance')::boolean, false),
    COALESCE(NEW.raw_user_meta_data->>'color', '#3b82f6'),
    COALESCE((NEW.raw_user_meta_data->>'is_active')::boolean, true)
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
