-- Track previous device when a new device claims the session (for profile UI).

BEGIN;

ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS last_device_label text,
  ADD COLUMN IF NOT EXISTS last_device_platform text,
  ADD COLUMN IF NOT EXISTS last_session_claimed_at timestamptz;

COMMENT ON COLUMN public.users.last_device_label IS
  'Device label from the previous active session (before force-login / re-login).';
COMMENT ON COLUMN public.users.last_device_platform IS
  'Platform of the previous active session.';
COMMENT ON COLUMN public.users.last_session_claimed_at IS
  'When the previous device last claimed the session.';

CREATE OR REPLACE FUNCTION public.users_protect_session_columns()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF public._jwt_is_service_role() THEN
    RETURN NEW;
  END IF;

  IF coalesce(current_setting('app.claiming_session', true), '') = '1' THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'UPDATE' THEN
    IF NEW.active_session_id IS DISTINCT FROM OLD.active_session_id
       OR NEW.active_auth_session_id IS DISTINCT FROM OLD.active_auth_session_id
       OR NEW.session_claimed_at IS DISTINCT FROM OLD.session_claimed_at
       OR NEW.active_device_label IS DISTINCT FROM OLD.active_device_label
       OR NEW.active_device_platform IS DISTINCT FROM OLD.active_device_platform
       OR NEW.last_device_label IS DISTINCT FROM OLD.last_device_label
       OR NEW.last_device_platform IS DISTINCT FROM OLD.last_device_platform
       OR NEW.last_session_claimed_at IS DISTINCT FROM OLD.last_session_claimed_at THEN
      RAISE EXCEPTION 'Session fields can only be changed via claim_device_session / clear_device_session'
        USING ERRCODE = '42501';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.claim_device_session(
  p_client_session_id text,
  p_force boolean DEFAULT false,
  p_device_label text DEFAULT NULL,
  p_device_platform text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  uid uuid := auth.uid();
  jwt_sid uuid;
  existing_client text;
  existing_label text;
  existing_platform text;
  existing_claimed_at timestamptz;
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
  END IF;

  IF p_client_session_id IS NULL OR btrim(p_client_session_id) = '' THEN
    RAISE EXCEPTION 'client session id required' USING ERRCODE = '22023';
  END IF;

  BEGIN
    jwt_sid := nullif(auth.jwt() ->> 'session_id', '')::uuid;
  EXCEPTION WHEN others THEN
    jwt_sid := NULL;
  END;

  SELECT
    u.active_session_id,
    u.active_device_label,
    u.active_device_platform,
    u.session_claimed_at
  INTO
    existing_client,
    existing_label,
    existing_platform,
    existing_claimed_at
  FROM public.users u
  WHERE u.id = uid
  FOR UPDATE;

  IF existing_client IS NOT NULL
     AND existing_client <> ''
     AND existing_client IS DISTINCT FROM btrim(p_client_session_id)
     AND NOT coalesce(p_force, false) THEN
    RETURN jsonb_build_object(
      'ok', false,
      'conflict', true
    );
  END IF;

  PERFORM set_config('app.claiming_session', '1', true);

  UPDATE public.users
  SET
    -- Archive previous device when a different client session takes over.
    last_device_label = CASE
      WHEN existing_client IS NOT NULL
           AND existing_client <> ''
           AND existing_client IS DISTINCT FROM btrim(p_client_session_id)
           AND coalesce(existing_label, '') <> ''
        THEN existing_label
      ELSE last_device_label
    END,
    last_device_platform = CASE
      WHEN existing_client IS NOT NULL
           AND existing_client <> ''
           AND existing_client IS DISTINCT FROM btrim(p_client_session_id)
        THEN existing_platform
      ELSE last_device_platform
    END,
    last_session_claimed_at = CASE
      WHEN existing_client IS NOT NULL
           AND existing_client <> ''
           AND existing_client IS DISTINCT FROM btrim(p_client_session_id)
        THEN existing_claimed_at
      ELSE last_session_claimed_at
    END,
    active_session_id = btrim(p_client_session_id),
    active_auth_session_id = jwt_sid,
    session_claimed_at = now(),
    active_device_label = p_device_label,
    active_device_platform = p_device_platform
  WHERE id = uid;

  IF jwt_sid IS NOT NULL THEN
    DELETE FROM auth.sessions
    WHERE user_id = uid
      AND id IS DISTINCT FROM jwt_sid;
  ELSE
    DELETE FROM auth.sessions
    WHERE user_id = uid;
  END IF;

  UPDATE auth.refresh_tokens
  SET revoked = true, updated_at = now()
  WHERE user_id = uid::text
    AND coalesce(revoked, false) = false
    AND (
      jwt_sid IS NULL
      OR session_id IS DISTINCT FROM jwt_sid
    );

  RETURN jsonb_build_object(
    'ok', true,
    'conflict', false,
    'auth_session_id', jwt_sid
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.clear_device_session()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
  existing_label text;
  existing_platform text;
  existing_claimed_at timestamptz;
BEGIN
  IF uid IS NULL THEN
    RETURN;
  END IF;

  SELECT
    u.active_device_label,
    u.active_device_platform,
    u.session_claimed_at
  INTO
    existing_label,
    existing_platform,
    existing_claimed_at
  FROM public.users u
  WHERE u.id = uid;

  PERFORM set_config('app.claiming_session', '1', true);

  UPDATE public.users
  SET
    last_device_label = CASE
      WHEN coalesce(existing_label, '') <> '' THEN existing_label
      ELSE last_device_label
    END,
    last_device_platform = CASE
      WHEN coalesce(existing_label, '') <> '' THEN existing_platform
      ELSE last_device_platform
    END,
    last_session_claimed_at = CASE
      WHEN coalesce(existing_label, '') <> '' THEN existing_claimed_at
      ELSE last_session_claimed_at
    END,
    active_session_id = NULL,
    active_auth_session_id = NULL,
    session_claimed_at = NULL,
    active_device_label = NULL,
    active_device_platform = NULL
  WHERE id = uid;
END;
$$;

COMMIT;
