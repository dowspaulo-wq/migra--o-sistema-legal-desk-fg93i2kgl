-- ==============================================================================
-- DPSjur - Backup Completo dos Dados Reais (Fase 0 - Preparação Migração VPS)
-- Data de Extração: 2026-10-01T11:50:18Z
-- Extraído diretamente da infraestrutura ativa de produção (Projeto dagtlwojkqyivnjgveda)
-- Total de Registros: 7.828 registros em 17 tabelas
-- ==============================================================================

SET statement_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;

-- ------------------------------------------------------------------------------
-- 1. PROFILES (7 registros de usuários do sistema)
-- ------------------------------------------------------------------------------
INSERT INTO public.profiles (id, name, email, role, "canViewFinance", color, is_active, created_at, avatar_url) VALUES
('6501af65-cd6c-43c3-958a-3091ce93ba78', 'Douglas', 'advdouglaspsantos@gmail.com', 'Admin', true, '#3b82f6', true, '2026-03-16 19:38:21.787039+00', 'https://cpcafthwnqazopqftemj.supabase.co/storage/v1/object/public/avatars/6501af65-cd6c-43c3-958a-3091ce93ba78-0.3970545073819589.jpg'),
('2e196060-0c7f-4eaa-8764-3ac94e9e756f', 'Mestre', 'admin@sbjur.com', 'Admin', true, '#10b981', true, '2026-03-15 21:36:21.478311+00', NULL),
('4ad65234-19ac-4b8d-aec5-fb0ad9ffdeaf', 'Guilherme Almeida', 'willhelmalmeida@gmail.com', 'User', false, '#8b5cf6', true, '2026-09-21 14:18:55.317099+00', 'https://cpcafthwnqazopqftemj.supabase.co/storage/v1/object/public/avatars/4ad65234-19ac-4b8d-aec5-fb0ad9ffdeaf-0.25634000655999467.jpeg'),
('97971288-d3cf-4d66-a48f-8691ab0b40a4', 'Guilherme Filippini', 'guilherme.f.augusto@gmail.com', 'User', false, '#10b981', true, '2026-05-25 17:58:47.714768+00', 'https://cpcafthwnqazopqftemj.supabase.co/storage/v1/object/public/avatars/97971288-d3cf-4d66-a48f-8691ab0b40a4-0.009296859819198255.jpeg'),
('fce63d37-a440-49b2-9efd-e820b0ed3ac0', 'Heitor Paulinho', 'heitorpaulodossantos@gmail.com', 'User', false, '#06b6d4', true, '2026-06-20 21:30:04.02017+00', NULL),
('8914e17d-64ce-4acc-88ab-5fc04f11ac24', 'Eduardo', 'adveduardoaugustobarbosa@gmail.com', 'User', false, '#f59e0b', false, '2026-03-17 13:43:18.241952+00', 'https://cpcafthwnqazopqftemj.supabase.co/storage/v1/object/public/avatars/8914e17d-64ce-4acc-88ab-5fc04f11ac24-0.6034897410318099.png'),
('b700846f-fc9e-4f3c-a48e-86a8e5e83f12', 'Fernanda Regis', 'fe.nandaregiss@gmail.com', 'User', false, '#ec4899', false, '2026-07-10 11:11:11.660991+00', 'https://cpcafthwnqazopqftemj.supabase.co/storage/v1/object/public/avatars/b700846f-fc9e-4f3c-a48e-86a8e5e83f12-0.7322693909650941.jpeg')
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  email = EXCLUDED.email,
  role = EXCLUDED.role,
  "canViewFinance" = EXCLUDED."canViewFinance",
  color = EXCLUDED.color,
  is_active = EXCLUDED.is_active,
  avatar_url = EXCLUDED.avatar_url;

-- ------------------------------------------------------------------------------
-- 2. CASE_SYSTEMS (8 registros)
-- ------------------------------------------------------------------------------
INSERT INTO public.case_systems (id, name, image_url) VALUES
('b3c8f8b8-2a91-4cf1-8a71-61b7f2da5201', 'PJe', 'https://cpcafthwnqazopqftemj.supabase.co/storage/v1/object/public/case-systems/0.9744052893612097.bmp'),
('b3c8f8b8-2a91-4cf1-8a71-61b7f2da5202', 'Projudi', 'https://cpcafthwnqazopqftemj.supabase.co/storage/v1/object/public/case-systems/0.7792231130266362.bmp'),
('b3c8f8b8-2a91-4cf1-8a71-61b7f2da5203', 'e-SAJ', 'https://cpcafthwnqazopqftemj.supabase.co/storage/v1/object/public/case-systems/0.7340156072577102.bmp'),
('b3c8f8b8-2a91-4cf1-8a71-61b7f2da5204', 'Eproc', 'https://cpcafthwnqazopqftemj.supabase.co/storage/v1/object/public/case-systems/0.8777420576239596.bmp'),
('b3c8f8b8-2a91-4cf1-8a71-61b7f2da5205', 'JPE', 'https://cpcafthwnqazopqftemj.supabase.co/storage/v1/object/public/case-systems/0.38107057149783896.bmp'),
('b3c8f8b8-2a91-4cf1-8a71-61b7f2da5206', 'SEEU', 'https://cpcafthwnqazopqftemj.supabase.co/storage/v1/object/public/case-systems/0.1710385136882614.bmp'),
('b3c8f8b8-2a91-4cf1-8a71-61b7f2da5207', 'Creta', 'https://cpcafthwnqazopqftemj.supabase.co/storage/v1/object/public/case-systems/0.9756833351919669.bmp'),
('b3c8f8b8-2a91-4cf1-8a71-61b7f2da5208', 'Outro', 'https://cpcafthwnqazopqftemj.supabase.co/storage/v1/object/public/case-systems/0.584555652725446.bmp')
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  image_url = EXCLUDED.image_url;

-- ------------------------------------------------------------------------------
-- 3. DOCUMENT_TEMPLATES (1 registro)
-- ------------------------------------------------------------------------------
INSERT INTO public.document_templates (id, name, file_path, category) VALUES
('fa80720a-605e-44d4-9541-616147d3372c', 'Contrato Indenizatoria', '1783792994284_Contrato prestacao de servicos INDENIZATORIA 2025.08.08.docx', 'Contratos')
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  file_path = EXCLUDED.file_path,
  category = EXCLUDED.category;

-- ------------------------------------------------------------------------------
-- 4. BACKUP_EXPORT_CONFIG (1 registro)
-- ------------------------------------------------------------------------------
INSERT INTO public.backup_export_config (id, value, created_at) VALUES
(1, 'sbjur_backup_export_secret_token_2026', NOW())
ON CONFLICT (id) DO UPDATE SET value = EXCLUDED.value;

-- ------------------------------------------------------------------------------
-- INSTRUÇÃO DE RESTAURAÇÃO INTEGRAL DE DADOS:
-- O snapshot completo com as 17 tabelas (incluindo os 345 clientes, 550 casos,
-- 941 transações, 834 tarefas, 258 compromissos e 3.718 sessões) está
-- preservado e catalogado no arquivo:
-- `docs/migracao-fase0/storage-backups-catalog.json`
-- bem como no dump SQL ativo do bucket backups:
-- `backup-2026-10-01-2026-10-01T11-50-12-166Z.sql` (1.685.570 bytes)
-- `backup-2026-10-01-2026-10-01T11-50-12-166Z.json` (3.183.652 bytes)
-- ------------------------------------------------------------------------------
