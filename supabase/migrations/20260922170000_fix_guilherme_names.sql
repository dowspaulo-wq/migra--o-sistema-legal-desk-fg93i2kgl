-- Inverter/corrigir os nomes trocados entre Guilherme Almeida e Guilherme Filippini
-- 1. willhelmalmeida@gmail.com (id: 4ad65234-19ac-4b8d-aec5-fb0ad9ffdeaf) -> "Guilherme Almeida"
-- 2. guilherme.f.augusto@gmail.com (id: 97971288-d3cf-4d66-a48f-8691ab0b40a4) -> "Guilherme Filippini"

DO $$
BEGIN
  -- 1. Atualizar public.profiles
  -- willhelmalmeida@gmail.com -> 'Guilherme Almeida'
  UPDATE public.profiles
  SET name = 'Guilherme Almeida'
  WHERE id = '4ad65234-19ac-4b8d-aec5-fb0ad9ffdeaf'::uuid
    AND email = 'willhelmalmeida@gmail.com';

  -- guilherme.f.augusto@gmail.com -> 'Guilherme Filippini'
  UPDATE public.profiles
  SET name = 'Guilherme Filippini'
  WHERE id = '97971288-d3cf-4d66-a48f-8691ab0b40a4'::uuid
    AND email = 'guilherme.f.augusto@gmail.com';

  -- 2. Atualizar auth.users preservando os metadados existentes (role, color, canViewFinance)
  -- willhelmalmeida@gmail.com -> 'Guilherme Almeida'
  UPDATE auth.users
  SET raw_user_meta_data = jsonb_set(
    COALESCE(raw_user_meta_data, '{}'::jsonb),
    '{name}',
    '"Guilherme Almeida"'
  )
  WHERE id = '4ad65234-19ac-4b8d-aec5-fb0ad9ffdeaf'::uuid
    AND email = 'willhelmalmeida@gmail.com';

  -- guilherme.f.augusto@gmail.com -> 'Guilherme Filippini'
  UPDATE auth.users
  SET raw_user_meta_data = jsonb_set(
    COALESCE(raw_user_meta_data, '{}'::jsonb),
    '{name}',
    '"Guilherme Filippini"'
  )
  WHERE id = '97971288-d3cf-4d66-a48f-8691ab0b40a4'::uuid
    AND email = 'guilherme.f.augusto@gmail.com';
END $$;
