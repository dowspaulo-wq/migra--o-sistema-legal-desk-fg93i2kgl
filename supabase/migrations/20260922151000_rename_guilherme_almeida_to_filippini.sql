-- Update Guilherme Almeida's name to Guilherme Filippini in public.profiles and auth.users
DO $$
BEGIN
  -- 1. Update public.profiles
  UPDATE public.profiles
  SET name = 'Guilherme Filippini'
  WHERE email = 'willhelmalmeida@gmail.com' OR id = '4ad65234-19ac-4b8d-aec5-fb0ad9ffdeaf'::uuid;

  -- 2. Update auth.users metadata
  UPDATE auth.users
  SET raw_user_meta_data = jsonb_set(
    COALESCE(raw_user_meta_data, '{}'::jsonb),
    '{name}',
    '"Guilherme Filippini"'
  )
  WHERE email = 'willhelmalmeida@gmail.com' OR id = '4ad65234-19ac-4b8d-aec5-fb0ad9ffdeaf'::uuid;
END $$;
