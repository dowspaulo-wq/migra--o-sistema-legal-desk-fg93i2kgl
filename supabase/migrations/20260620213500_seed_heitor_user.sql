DO $$
DECLARE
  new_user_id uuid;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM auth.users WHERE email = 'heitorpaulodossantos@gmail.com') THEN
    new_user_id := gen_random_uuid();
    
    INSERT INTO auth.users (
      id, instance_id, email, encrypted_password, email_confirmed_at,
      created_at, updated_at, raw_app_meta_data, raw_user_meta_data,
      is_super_admin, role, aud,
      confirmation_token, recovery_token, email_change_token_new,
      email_change, email_change_token_current,
      phone, phone_change, phone_change_token, reauthentication_token
    ) VALUES (
      new_user_id,
      '00000000-0000-0000-0000-000000000000',
      'heitorpaulodossantos@gmail.com',
      crypt('senha 135791Dp*', gen_salt('bf')),
      NOW(), NOW(), NOW(),
      '{"provider": "email", "providers": ["email"]}',
      '{"name": "Heitor Paulinho"}',
      false, 'authenticated', 'authenticated',
      '',    -- confirmation_token: MUST be '' not NULL
      '',    -- recovery_token: MUST be '' not NULL
      '',    -- email_change_token_new: MUST be '' not NULL
      '',    -- email_change: MUST be '' not NULL
      '',    -- email_change_token_current: MUST be '' not NULL
      NULL,  -- phone: MUST be NULL (not '') due to UNIQUE constraint
      '',    -- phone_change: MUST be '' not NULL
      '',    -- phone_change_token: MUST be '' not NULL
      ''     -- reauthentication_token: MUST be '' not NULL
    );

    INSERT INTO public.profiles (id, email, name, role, "canViewFinance", color)
    VALUES (new_user_id, 'heitorpaulodossantos@gmail.com', 'Heitor Paulinho', 'COLABORADOR', false, '#10b981')
    ON CONFLICT (id) DO NOTHING;
    
    -- In case the profile was auto-created by a database trigger, ensure the fields match the acceptance criteria
    UPDATE public.profiles
    SET 
      name = 'Heitor Paulinho',
      role = 'COLABORADOR',
      "canViewFinance" = false
    WHERE id = new_user_id;
  END IF;
END $$;
