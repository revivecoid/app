-- Guest (anonymous) estimating — restore the pre-login estimation flow.
--
-- SEC-03/SEC-04 moved vision-estimation behind a JWT and made both the photo
-- upload path and the storage bucket user-scoped. That is correct and stays.
-- Guests get that JWT by signing in anonymously, but GoTrue could not create
-- anonymous users against this schema: an anonymous user has NULL email and no
-- full_name, while profiles.email and profiles.full_name are NOT NULL with no
-- default. Postgres raised 23502 inside the signup trigger and GoTrue surfaced
-- it as 500 "Database error creating anonymous user".
--
-- COALESCE placeholders keep the trigger working for guests. A guest row is
-- upgraded with the real values when the account is linked/converted, because
-- the trigger only runs once per auth.users row.

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  INSERT INTO public.profiles (id, full_name, email, role)
  VALUES (
    NEW.id,
    COALESCE(
      NULLIF(NEW.raw_user_meta_data->>'full_name', ''),
      NULLIF(split_part(COALESCE(NEW.email, ''), '@', 1), ''),
      'Guest'
    ),
    COALESCE(NEW.email, ''),
    'customer'
  )
  ON CONFLICT (id) DO NOTHING;

  -- memberships is the source of truth; keep it populated for every new signup
  INSERT INTO public.memberships (user_id, scope, role, status)
  VALUES (NEW.id, 'customer', 'customer', 'active')
  ON CONFLICT DO NOTHING;

  RETURN NEW;
END;
$function$;
