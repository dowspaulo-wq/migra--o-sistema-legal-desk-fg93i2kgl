-- ==============================================================================
-- DPSjur - Fase 3: Script de Preparação de Roles e Schema de Autenticação
-- Ambiente: PostgreSQL 16 no EasyPanel (Serviço dpsjur-db / Banco dpsjur)
-- ==============================================================================
-- Este script garante:
-- 1. As roles 'anon', 'authenticated', 'service_role' e 'authenticator'
-- 2. As permissões de acesso ao schema public para essas roles
-- 3. A estrutura do schema auth com a tabela auth.users compatível com GoTrue
-- 4. O provisionamento seguro dos usuários iniciais com senhas criptografadas
-- ==============================================================================

SET client_encoding = 'UTF8';

-- 1. Criação das roles padrão do Supabase/PostgREST
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
        CREATE ROLE anon NOLOGIN;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
        CREATE ROLE authenticated NOLOGIN;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
        CREATE ROLE service_role NOLOGIN;
    END IF;
    -- Role 'authenticator' é usada pelo PostgREST para se autenticar no Postgres
    -- e depois assumir o papel 'anon' ou 'authenticated'
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticator') THEN
        CREATE ROLE authenticator NOINHERIT LOGIN PASSWORD '4585d780134654a88ae7';
    ELSE
        ALTER ROLE authenticator WITH PASSWORD '4585d780134654a88ae7';
    END IF;
END
$$;

-- Conceder transição de papéis para o authenticator
GRANT anon TO authenticator;
GRANT authenticated TO authenticator;
GRANT service_role TO authenticator;

-- Conceder permissões no schema public
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role, authenticator;
GRANT ALL ON ALL TABLES IN SCHEMA public TO anon, authenticated, service_role, authenticator;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO anon, authenticated, service_role, authenticator;
GRANT ALL ON ALL ROUTINES IN SCHEMA public TO anon, authenticated, service_role, authenticator;

ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO anon, authenticated, service_role, authenticator;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO anon, authenticated, service_role, authenticator;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON ROUTINES TO anon, authenticated, service_role, authenticator;

-- 2. Garantir schema auth
CREATE SCHEMA IF NOT EXISTS auth;
GRANT USAGE ON SCHEMA auth TO anon, authenticated, service_role, authenticator;

-- Tabela auth.users básica (compatível com GoTrue e RLS auth.uid())
CREATE TABLE IF NOT EXISTS auth.users (
    instance_id UUID,
    id UUID PRIMARY KEY,
    aud VARCHAR(255) DEFAULT 'authenticated',
    role VARCHAR(255) DEFAULT 'authenticated',
    email VARCHAR(255) UNIQUE,
    encrypted_password VARCHAR(255),
    email_confirmed_at TIMESTAMPTZ DEFAULT NOW(),
    invited_at TIMESTAMPTZ,
    confirmation_token VARCHAR(255),
    confirmation_sent_at TIMESTAMPTZ,
    recovery_token VARCHAR(255),
    recovery_sent_at TIMESTAMPTZ,
    email_change_token_new VARCHAR(255),
    email_change VARCHAR(255),
    email_change_sent_at TIMESTAMPTZ,
    last_sign_in_at TIMESTAMPTZ,
    raw_app_meta_data JSONB DEFAULT '{"provider":"email","providers":["email"]}',
    raw_user_meta_data JSONB DEFAULT '{}',
    is_super_admin BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    phone VARCHAR(255) DEFAULT NULL,
    phone_confirmed_at TIMESTAMPTZ,
    phone_change VARCHAR(255) DEFAULT '',
    phone_change_token VARCHAR(255) DEFAULT '',
    phone_change_sent_at TIMESTAMPTZ,
    confirmed_at TIMESTAMPTZ DEFAULT NOW(),
    email_change_token_current VARCHAR(255) DEFAULT '',
    email_change_confirm_status SMALLINT DEFAULT 0,
    banned_until TIMESTAMPTZ,
    reauthentication_token VARCHAR(255) DEFAULT '',
    reauthentication_sent_at TIMESTAMPTZ,
    is_sso_user BOOLEAN DEFAULT false NOT NULL,
    deleted_at TIMESTAMPTZ
);

GRANT ALL ON TABLE auth.users TO anon, authenticated, service_role, authenticator;

-- 3. Sincronizar os 7 perfis existentes de public.profiles para auth.users
-- Senha inicial temporária gerada: 'DPSjur@2026' (criptografada em bcrypt com crypt/gen_salt)
-- Douglas e operadores podem trocar imediatamente via tela /login ou /update-password
INSERT INTO auth.users (
    id,
    email,
    encrypted_password,
    email_confirmed_at,
    confirmed_at,
    raw_app_meta_data,
    raw_user_meta_data,
    created_at,
    updated_at
)
SELECT 
    p.id,
    p.email,
    crypt('DPSjur@2026', gen_salt('bf', 10)),
    NOW(),
    NOW(),
    jsonb_build_object('provider', 'email', 'providers', jsonb_build_array('email')),
    jsonb_build_object('name', p.name, 'role', p.role),
    p.created_at,
    NOW()
FROM public.profiles p
WHERE p.email IS NOT NULL
ON CONFLICT (id) DO UPDATE SET
    email = EXCLUDED.email,
    raw_user_meta_data = EXCLUDED.raw_user_meta_data;

-- 4. Funções de compatibilidade auth.uid() e auth.role()
CREATE OR REPLACE FUNCTION auth.uid()
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
    SELECT COALESCE(
        nullif(current_setting('request.jwt.claim.sub', true), ''),
        (nullif(current_setting('request.jwt.claims', true), ''))::jsonb ->> 'sub'
    )::uuid;
$$;

CREATE OR REPLACE FUNCTION auth.role()
RETURNS text
LANGUAGE sql
STABLE
AS $$
    SELECT COALESCE(
        nullif(current_setting('request.jwt.claim.role', true), ''),
        (nullif(current_setting('request.jwt.claims', true), ''))::jsonb ->> 'role',
        'anon'
    )::text;
$$;

CREATE OR REPLACE FUNCTION auth.email()
RETURNS text
LANGUAGE sql
STABLE
AS $$
    SELECT COALESCE(
        nullif(current_setting('request.jwt.claim.email', true), ''),
        (nullif(current_setting('request.jwt.claims', true), ''))::jsonb ->> 'email'
    )::text;
$$;

GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA auth TO anon, authenticated, service_role, authenticator;
