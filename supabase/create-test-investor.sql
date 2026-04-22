-- ============================================================
--  OVC — Créer un compte investisseur de test
--  À exécuter UNE SEULE FOIS dans Supabase → SQL Editor
--  Identifiants : investisseur@ovc.test / OVC_Invest_2026!
-- ============================================================

-- 1. Créer l'utilisateur Auth
DO $$
DECLARE
  new_uid uuid := gen_random_uuid();
BEGIN
  -- Evite les doublons
  IF NOT EXISTS (SELECT 1 FROM auth.users WHERE email = 'investisseur@ovc.test') THEN

    INSERT INTO auth.users (
      instance_id, id, aud, role,
      email, encrypted_password,
      email_confirmed_at, last_sign_in_at,
      raw_app_meta_data, raw_user_meta_data,
      created_at, updated_at,
      confirmation_token, email_change,
      email_change_token_new, recovery_token
    ) VALUES (
      '00000000-0000-0000-0000-000000000000',
      new_uid,
      'authenticated', 'authenticated',
      'investisseur@ovc.test',
      crypt('OVC_Invest_2026!', gen_salt('bf')),
      now(), now(),
      '{"provider":"email","providers":["email"]}',
      '{"full_name":"Investisseur Test","role":"subscriber"}',
      now(), now(),
      '', '', '', ''
    );

    -- 2. Lier l'identité email (provider_id = email pour le provider 'email')
    INSERT INTO auth.identities (
      id, user_id, provider_id, identity_data, provider,
      last_sign_in_at, created_at, updated_at
    ) VALUES (
      gen_random_uuid(), new_uid,
      'investisseur@ovc.test',
      json_build_object('sub', new_uid::text, 'email', 'investisseur@ovc.test'),
      'email', now(), now(), now()
    );

    RAISE NOTICE 'Compte créé : investisseur@ovc.test';
  ELSE
    RAISE NOTICE 'Compte déjà existant — aucune action effectuée.';
  END IF;
END $$;

-- 3. (Optionnel) Ajouter dans la table subscribers pour le suivi
INSERT INTO subscribers (
  first_name, last_name, email, amount, currency,
  parts, nav_entry, objective, horizon, risk, country
) VALUES (
  'Investisseur', 'Test',
  'investisseur@ovc.test',
  1000.00, 'EUR',
  10.0000, 100.0000,
  'Test interne', '1 an', 'Modéré', 'France'
)
ON CONFLICT DO NOTHING;
