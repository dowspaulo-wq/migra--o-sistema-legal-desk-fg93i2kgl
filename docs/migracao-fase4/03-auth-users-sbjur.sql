-- ==============================================================================
-- DPSjur - Restauração de Usuários no Schema auth (com senhas preservadas)
-- Gerado para: Fase 4 da Migração para Supabase Self-Hosted (EasyPanel)
-- Origem: Projeto SBJur (cpcafthwnqazopqftemj)
-- Data: 2026-10-06 / 2026-10-07
-- Contém: 7 usuários com hashes bcrypt reais e identidades email sincronizadas.
-- As senhas atuais continuarão funcionando sem necessidade de redefinição!
-- ==============================================================================

-- 1. Garante a existência do schema auth e da extensão pgcrypto
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 2. Inserção / Upsert dos 7 usuários em auth.users
-- NOTA: O campo encrypted_password contém os hashes bcrypt exatos exportados do banco live.
INSERT INTO auth.users (
    instance_id,
    id,
    aud,
    role,
    email,
    encrypted_password,
    email_confirmed_at,
    raw_app_meta_data,
    raw_user_meta_data,
    is_super_admin,
    created_at,
    updated_at,
    phone,
    confirmed_at,
    is_sso_user,
    is_anonymous
) VALUES
-- 1. Douglas (Admin)
(
    '00000000-0000-0000-0000-000000000000',
    '6501af65-cd6c-43c3-958a-3091ce93ba78',
    'authenticated',
    'authenticated',
    'advdouglaspsantos@gmail.com',
    '$2a$06$PVpB62WcDkA0N9YNkeSzN.q0eQRFxMKfk.xTCRF6zYhZxeD5b6fhC',
    '2026-03-16 19:38:21.851522+00',
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{"name":"Douglas","role":"User","color":"#09f118","canViewFinance":true,"email_verified":true}'::jsonb,
    false,
    '2026-03-16 19:38:21.787388+00',
    '2026-10-06 23:23:19.810813+00',
    NULL,
    '2026-03-16 19:38:21.851522+00',
    false,
    false
),
-- 2. Mestre (Admin)
(
    '00000000-0000-0000-0000-000000000000',
    '2e196060-0c7f-4eaa-8764-3ac94e9e756f',
    'authenticated',
    'authenticated',
    'admin@sbjur.com',
    '$2a$06$ouPPXo.frJL5uyIEoG4QsuGSswgk7V5vmQWFFAzE3A80ytC9kCw.O',
    '2026-03-15 21:36:21.478311+00',
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{"name":"Douglas","role":"Admin","color":"#10b981","canViewFinance":true}'::jsonb,
    false,
    '2026-03-15 21:36:21.478311+00',
    '2026-03-17 03:48:15.069735+00',
    NULL,
    '2026-03-15 21:36:21.478311+00',
    false,
    false
),
-- 3. Guilherme Almeida
(
    '00000000-0000-0000-0000-000000000000',
    '4ad65234-19ac-4b8d-aec5-fb0ad9ffdeaf',
    'authenticated',
    'authenticated',
    'willhelmalmeida@gmail.com',
    '$2a$10$ytpaJL8AwTFujAj5xUk64.Mk.lqfuRptIVQL56vaoTwGftNU04Zri',
    '2026-09-21 14:18:55.317099+00',
    '{"provider":"email","providers":[]}'::jsonb,
    '{"name":"Guilherme Almeida","role":"User","color":"#3b82f6","canViewFinance":false}'::jsonb,
    false,
    '2026-09-21 14:18:55.317099+00',
    '2026-10-06 19:39:47.249003+00',
    NULL,
    '2026-09-21 14:18:55.317099+00',
    false,
    false
),
-- 4. Guilherme Filippini
(
    '00000000-0000-0000-0000-000000000000',
    '97971288-d3cf-4d66-a48f-8691ab0b40a4',
    'authenticated',
    'authenticated',
    'guilherme.f.augusto@gmail.com',
    '$2a$06$MUItoOmohDX848XmxoV4KeQNQK8lcKTefKA7Kc4VSUQQrM/kbDzS2',
    '2026-05-25 17:58:47.714768+00',
    '{"provider":"email","providers":[]}'::jsonb,
    '{"name":"Guilherme Filippini","role":"User","color":"#3b82f6","canViewFinance":false}'::jsonb,
    false,
    '2026-05-25 17:58:47.714768+00',
    '2026-10-06 20:01:09.082649+00',
    NULL,
    '2026-05-25 17:58:47.714768+00',
    false,
    false
),
-- 5. Heitor Paulinho
(
    '00000000-0000-0000-0000-000000000000',
    'fce63d37-a440-49b2-9efd-e820b0ed3ac0',
    'authenticated',
    'authenticated',
    'heitorpaulodossantos@gmail.com',
    '$2a$10$hxilBiSvpgysEp0P.3.57OssJiZEoo6W3mKq5Xt8Ew7rMGs/hvbpK',
    '2026-06-20 21:30:04.02017+00',
    '{"provider":"email","providers":[]}'::jsonb,
    '{"name":"Heitor Paulinho"}'::jsonb,
    false,
    '2026-06-20 21:30:04.02017+00',
    '2026-07-27 15:39:47.508189+00',
    NULL,
    '2026-06-20 21:30:04.02017+00',
    false,
    false
),
-- 6. Fernanda Regis
(
    '00000000-0000-0000-0000-000000000000',
    'b700846f-fc9e-4f3c-a48e-86a8e5e83f12',
    'authenticated',
    'authenticated',
    'fe.nandaregiss@gmail.com',
    '$2a$10$ZWeEHz9FLhJ9TykbRF9x/eaJSHnlMIt93gsTIPrrXwOeSUx6vl80q',
    '2026-07-10 11:11:11.660991+00',
    '{"provider":"email","providers":[]}'::jsonb,
    '{"name":"Fernanda Regis"}'::jsonb,
    false,
    '2026-07-10 11:11:11.660991+00',
    '2026-09-23 14:29:16.065485+00',
    NULL,
    '2026-07-10 11:11:11.660991+00',
    false,
    false
),
-- 7. Eduardo Augusto
(
    '00000000-0000-0000-0000-000000000000',
    '8914e17d-64ce-4acc-88ab-5fc04f11ac24',
    'authenticated',
    'authenticated',
    'adveduardoaugustobarbosa@gmail.com',
    '$2a$10$yBjGw84KhRA8YmYJko.zCum5jPq1yXBIagLf/hcmWnuLrY9AoE7c.',
    '2026-03-17 13:43:18.294451+00',
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{"email_verified":true}'::jsonb,
    false,
    '2026-03-17 13:43:18.243608+00',
    '2026-04-15 13:39:49.29259+00',
    NULL,
    '2026-03-17 13:43:18.294451+00',
    false,
    false
)
ON CONFLICT (id) DO UPDATE SET
    email = EXCLUDED.email,
    encrypted_password = EXCLUDED.encrypted_password,
    email_confirmed_at = EXCLUDED.email_confirmed_at,
    raw_app_meta_data = EXCLUDED.raw_app_meta_data,
    raw_user_meta_data = EXCLUDED.raw_user_meta_data,
    confirmed_at = EXCLUDED.confirmed_at,
    updated_at = EXCLUDED.updated_at;

-- 3. Inserção / Upsert em auth.identities (necessário para o Supabase Auth / GoTrue permitir login com e-mail e senha)
INSERT INTO auth.identities (
    id,
    user_id,
    identity_data,
    provider,
    last_sign_in_at,
    created_at,
    updated_at
) VALUES
-- Douglas
(
    '189ce30b-b2e7-4e2f-9f81-bb81cc1a6b10',
    '6501af65-cd6c-43c3-958a-3091ce93ba78',
    '{"sub":"6501af65-cd6c-43c3-958a-3091ce93ba78","email":"advdouglaspsantos@gmail.com","email_verified":true,"phone_verified":false}'::jsonb,
    'email',
    '2026-03-16 19:38:21.839175+00',
    '2026-03-16 19:38:21.839234+00',
    '2026-03-16 19:38:21.839234+00'
),
-- Mestre
(
    '2e196060-0c7f-4eaa-8764-3ac94e9e756f',
    '2e196060-0c7f-4eaa-8764-3ac94e9e756f',
    '{"sub":"2e196060-0c7f-4eaa-8764-3ac94e9e756f","email":"admin@sbjur.com","email_verified":true,"phone_verified":false}'::jsonb,
    'email',
    '2026-03-15 21:36:21.478311+00',
    '2026-03-15 21:36:21.478311+00',
    '2026-03-15 21:36:21.478311+00'
),
-- Guilherme Almeida
(
    '4ad65234-19ac-4b8d-aec5-fb0ad9ffdeaf',
    '4ad65234-19ac-4b8d-aec5-fb0ad9ffdeaf',
    '{"sub":"4ad65234-19ac-4b8d-aec5-fb0ad9ffdeaf","email":"willhelmalmeida@gmail.com","email_verified":true,"phone_verified":false}'::jsonb,
    'email',
    '2026-09-21 14:18:55.317099+00',
    '2026-09-21 14:18:55.317099+00',
    '2026-09-21 14:18:55.317099+00'
),
-- Guilherme Filippini
(
    '97971288-d3cf-4d66-a48f-8691ab0b40a4',
    '97971288-d3cf-4d66-a48f-8691ab0b40a4',
    '{"sub":"97971288-d3cf-4d66-a48f-8691ab0b40a4","email":"guilherme.f.augusto@gmail.com","email_verified":true,"phone_verified":false}'::jsonb,
    'email',
    '2026-05-25 17:58:47.714768+00',
    '2026-05-25 17:58:47.714768+00',
    '2026-05-25 17:58:47.714768+00'
),
-- Heitor Paulinho
(
    'fce63d37-a440-49b2-9efd-e820b0ed3ac0',
    'fce63d37-a440-49b2-9efd-e820b0ed3ac0',
    '{"sub":"fce63d37-a440-49b2-9efd-e820b0ed3ac0","email":"heitorpaulodossantos@gmail.com","email_verified":true,"phone_verified":false}'::jsonb,
    'email',
    '2026-06-20 21:30:04.02017+00',
    '2026-06-20 21:30:04.02017+00',
    '2026-06-20 21:30:04.02017+00'
),
-- Fernanda Regis
(
    'b700846f-fc9e-4f3c-a48e-86a8e5e83f12',
    'b700846f-fc9e-4f3c-a48e-86a8e5e83f12',
    '{"sub":"b700846f-fc9e-4f3c-a48e-86a8e5e83f12","email":"fe.nandaregiss@gmail.com","email_verified":true,"phone_verified":false}'::jsonb,
    'email',
    '2026-07-10 11:11:11.660991+00',
    '2026-07-10 11:11:11.660991+00',
    '2026-07-10 11:11:11.660991+00'
),
-- Eduardo Augusto
(
    'c3887fd2-e83d-49ed-9803-d9247cf1461f',
    '8914e17d-64ce-4acc-88ab-5fc04f11ac24',
    '{"sub":"8914e17d-64ce-4acc-88ab-5fc04f11ac24","email":"adveduardoaugustobarbosa@gmail.com","email_verified":true,"phone_verified":false}'::jsonb,
    'email',
    '2026-03-17 13:43:18.279321+00',
    '2026-03-17 13:43:18.279375+00',
    '2026-03-17 13:43:18.279375+00'
)
ON CONFLICT (id) DO UPDATE SET
    user_id = EXCLUDED.user_id,
    identity_data = EXCLUDED.identity_data,
    provider = EXCLUDED.provider,
    updated_at = EXCLUDED.updated_at;

-- 4. Confirmação e verificação
SELECT id, email, role, confirmed_at, created_at FROM auth.users ORDER BY created_at ASC;
