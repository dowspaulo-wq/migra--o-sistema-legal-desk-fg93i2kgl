DO $$
DECLARE
  new_user_id uuid;
BEGIN
  -- Seed user Guilherme (idempotent: skip if email already exists)
  IF NOT EXISTS (SELECT 1 FROM auth.users WHERE email = 'guilherme.f.augusto@gmail.com') THEN
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
      'guilherme.f.augusto@gmail.com',
      crypt('147147', gen_salt('bf')),
      NOW(), NOW(), NOW(),
      '{"provider": "email", "providers": ["email"]}',
      '{"name": "Guilherme", "role": "User", "color": "#3b82f6", "canViewFinance": false}',
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

    -- Ensure public profile is created with correct permissions and styling
    INSERT INTO public.profiles (id, email, name, role, "canViewFinance", color)
    VALUES (new_user_id, 'guilherme.f.augusto@gmail.com', 'Guilherme', 'User', false, '#3b82f6')
    ON CONFLICT (id) DO UPDATE SET 
      name = EXCLUDED.name,
      role = EXCLUDED.role,
      "canViewFinance" = EXCLUDED."canViewFinance",
      color = EXCLUDED.color;
  END IF;
END $$;
