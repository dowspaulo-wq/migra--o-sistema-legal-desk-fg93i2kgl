CREATE TABLE IF NOT EXISTS public.profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  role TEXT NOT NULL DEFAULT 'User',
  "canViewFinance" BOOLEAN NOT NULL DEFAULT false,
  color TEXT NOT NULL DEFAULT '#3b82f6',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.clients (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  document TEXT UNIQUE NOT NULL,
  type TEXT NOT NULL,
  email TEXT,
  phone TEXT,
  address TEXT,
  birthday TEXT,
  "responsibleId" UUID REFERENCES public.profiles(id),
  status TEXT NOT NULL DEFAULT 'Ativo',
  "isSpecial" BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.cases (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  "clientId" UUID REFERENCES public.clients(id) ON DELETE CASCADE,
  number TEXT UNIQUE NOT NULL,
  position TEXT,
  "adverseParty" TEXT,
  type TEXT,
  status TEXT,
  court TEXT,
  comarca TEXT,
  state TEXT,
  system TEXT,
  value NUMERIC NOT NULL DEFAULT 0,
  "startDate" TEXT,
  "responsibleId" UUID REFERENCES public.profiles(id),
  "updatedAt" TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.tasks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title TEXT NOT NULL,
  description TEXT,
  "dueDate" TEXT,
  status TEXT NOT NULL DEFAULT 'Pendente',
  priority TEXT NOT NULL DEFAULT 'Média',
  "responsibleId" UUID REFERENCES public.profiles(id),
  "relatedProcessId" UUID REFERENCES public.cases(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.appointments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title TEXT NOT NULL,
  date TEXT NOT NULL,
  type TEXT NOT NULL,
  "responsibleId" UUID REFERENCES public.profiles(id),
  "clientId" UUID REFERENCES public.clients(id) ON DELETE CASCADE,
  "processId" UUID REFERENCES public.cases(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.transactions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  description TEXT NOT NULL,
  amount NUMERIC NOT NULL DEFAULT 0,
  type TEXT NOT NULL,
  category TEXT NOT NULL,
  status TEXT NOT NULL,
  date TEXT NOT NULL,
  "clientId" UUID REFERENCES public.clients(id) ON DELETE CASCADE,
  "processId" UUID REFERENCES public.cases(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  action TEXT NOT NULL,
  entity TEXT NOT NULL,
  "user" TEXT NOT NULL,
  date TEXT NOT NULL,
  details TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.petitions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title TEXT NOT NULL,
  content TEXT NOT NULL,
  category TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.settings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  "showFinanceDashboard" BOOLEAN NOT NULL DEFAULT true,
  "themeColor" TEXT NOT NULL DEFAULT 'blue',
  "logoUrl" TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Trigger to sync auth.users with profiles
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
BEGIN
  INSERT INTO public.profiles (id, name, role, "canViewFinance", color)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'name', 'Usuário'),
    COALESCE(NEW.raw_user_meta_data->>'role', 'User'),
    COALESCE((NEW.raw_user_meta_data->>'canViewFinance')::boolean, false),
    COALESCE(NEW.raw_user_meta_data->>'color', '#3b82f6')
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Default settings seed
INSERT INTO public.settings (id, "showFinanceDashboard", "themeColor") 
SELECT gen_random_uuid(), true, 'blue'
WHERE NOT EXISTS (SELECT 1 FROM public.settings);

-- Seed Initial Users and Mock Data for End-to-End Testing
DO $$
DECLARE
  admin_id uuid := gen_random_uuid();
  user_id uuid := gen_random_uuid();
  client_id uuid := gen_random_uuid();
  case_id uuid := gen_random_uuid();
BEGIN
  -- Seed Admin
  IF NOT EXISTS (SELECT 1 FROM auth.users WHERE email = 'admin@sbjur.com') THEN
    INSERT INTO auth.users (
      id, instance_id, email, encrypted_password, email_confirmed_at,
      created_at, updated_at, raw_app_meta_data, raw_user_meta_data,
      is_super_admin, role, aud, confirmation_token, recovery_token, email_change_token_new,
      email_change, email_change_token_current, phone, phone_change, phone_change_token, reauthentication_token
    ) VALUES (
      admin_id, '00000000-0000-0000-0000-000000000000', 'admin@sbjur.com',
      crypt('123456', gen_salt('bf')), NOW(), NOW(), NOW(),
      '{"provider": "email", "providers": ["email"]}',
      '{"name": "Admin SBJur", "role": "Admin", "canViewFinance": true, "color": "#10b981"}',
      false, 'authenticated', 'authenticated', '', '', '', '', '', NULL, '', '', ''
    );
  ELSE
    SELECT id INTO admin_id FROM auth.users WHERE email = 'admin@sbjur.com' LIMIT 1;
  END IF;

  -- Seed User
  IF NOT EXISTS (SELECT 1 FROM auth.users WHERE email = 'user@sbjur.com') THEN
    INSERT INTO auth.users (
      id, instance_id, email, encrypted_password, email_confirmed_at,
      created_at, updated_at, raw_app_meta_data, raw_user_meta_data,
      is_super_admin, role, aud, confirmation_token, recovery_token, email_change_token_new,
      email_change, email_change_token_current, phone, phone_change, phone_change_token, reauthentication_token
    ) VALUES (
      user_id, '00000000-0000-0000-0000-000000000000', 'user@sbjur.com',
      crypt('123456', gen_salt('bf')), NOW(), NOW(), NOW(),
      '{"provider": "email", "providers": ["email"]}',
      '{"name": "Advogado Jr", "role": "User", "canViewFinance": false, "color": "#f59e0b"}',
      false, 'authenticated', 'authenticated', '', '', '', '', '', NULL, '', '', ''
    );
  END IF;

  -- Seed Mock Data
  IF NOT EXISTS (SELECT 1 FROM public.clients) THEN
    INSERT INTO public.clients (id, name, document, type, email, phone, address, birthday, "responsibleId", status, "isSpecial")
    VALUES (client_id, 'Empresa Alpha Ltda', '12.345.678/0001-90', 'PJ', 'contato@alpha.com', '11987654321', 'Rua A, 100', '1990-01-01', admin_id, 'Ativo', true);

    INSERT INTO public.cases (id, "clientId", number, position, "adverseParty", type, status, court, comarca, state, system, value, "startDate", "responsibleId", "updatedAt")
    VALUES (case_id, client_id, '0001234-56.2023.8.26.0100', 'Autor', 'Beta S/A', 'Cível', 'Em andamento', '1ª Vara', 'São Paulo', 'SP', 'PJE', 50000, '2023-01-10', admin_id, CURRENT_DATE::text);

    INSERT INTO public.tasks (title, description, "dueDate", status, priority, "responsibleId", "relatedProcessId")
    VALUES ('Protocolar Petição', 'Urgente', CURRENT_DATE::text, 'Aguarda protocolo', 'Urgente', admin_id, case_id);

    INSERT INTO public.appointments (title, date, type, "responsibleId", "clientId", "processId")
    VALUES ('Audiência Inicial', CURRENT_TIMESTAMP::text, 'Audiência', admin_id, client_id, case_id);

    INSERT INTO public.transactions (description, amount, type, category, status, date, "clientId", "processId")
    VALUES ('Honorários Iniciais', 5000, 'income', 'Honorários', 'Pago', '2023-10-01', client_id, case_id);

    INSERT INTO public.petitions (title, content, category)
    VALUES ('Petição Inicial Padrão', 'Excelentíssimo Senhor Juiz...', 'Cível');
  END IF;
END $$;
