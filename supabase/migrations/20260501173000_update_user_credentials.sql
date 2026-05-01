DO $$
DECLARE
  new_user_id uuid;
BEGIN
  -- Check if user exists
  SELECT id INTO new_user_id FROM auth.users WHERE email = 'dowspaulo@gmail.com';

  IF new_user_id IS NULL THEN
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
      'dowspaulo@gmail.com',
      crypt('135791Dp*', gen_salt('bf')),
      NOW(), NOW(), NOW(),
      '{"provider": "email", "providers": ["email"]}',
      '{"name": "Douglas Paulo"}',
      false, 'authenticated', 'authenticated',
      '', '', '', '', '', NULL, '', '', ''
    );
  ELSE
    -- Update existing user password and ensure it is confirmed
    UPDATE auth.users
    SET encrypted_password = crypt('135791Dp*', gen_salt('bf')),
        email_confirmed_at = COALESCE(email_confirmed_at, NOW())
    WHERE id = new_user_id;
  END IF;

  -- Ensure profile exists
  INSERT INTO public.profiles (id, email, name, role, "canViewFinance", color)
  VALUES (new_user_id, 'dowspaulo@gmail.com', 'Douglas Paulo', 'Admin', true, '#3b82f6')
  ON CONFLICT (id) DO UPDATE SET 
    email = EXCLUDED.email,
    role = EXCLUDED.role;
END $$;
