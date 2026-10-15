-- Keep up to 5 previous device logins per user (for profile history UI).

BEGIN;

CREATE TABLE IF NOT EXISTS public.user_device_login_history (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  device_label text,
  device_platform text,
  claimed_at timestamptz,
  ended_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_user_device_login_history_user_ended
  ON public.user_device_login_history (user_id, ended_at DESC);

COMMENT ON TABLE public.user_device_login_history IS
  'Previous device sessions (max 5 kept per user) for profile display.';

ALTER TABLE public.user_device_login_history ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS user_device_login_history_select_own
  ON public.user_device_login_history;
CREATE POLICY user_device_login_history_select_own
  ON public.user_device_login_history
  FOR SELECT
  TO authenticated
  USING (user_id = auth.uid() OR public._caller_is_super_admin());

-- Clients must not insert/update/delete; only SECURITY DEFINER RPCs.
REVOKE ALL ON TABLE public.user_device_login_history FROM PUBLIC;
GRANT SELECT ON TABLE public.user_device_login_history TO authenticated;
GRANT ALL ON TABLE public.user_device_login_history TO service_role;

CREATE OR REPLACE FUNCTION public._append_device_login_history(
  p_user_id uuid,
  p_device_label text,
  p_device_platform text,
  p_claimed_at timestamptz
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_user_id IS NULL THEN
    RETURN;
  END IF;
  IF coalesce(btrim(p_device_label), '') = ''
     AND coalesce(btrim(p_device_platform), '') = '' THEN
    RETURN;
  END IF;

  INSERT INTO public.user_device_login_history (
    user_id,
    device_label,
    device_platform,
    claimed_at,
    ended_at
  ) VALUES (
    p_user_id,
    nullif(btrim(p_device_label), ''),
    nullif(btrim(p_device_platform), ''),
    p_claimed_at,
    now()
  );

  DELETE FROM public.user_device_login_history h
  WHERE h.user_id = p_user_id
    AND h.id NOT IN (
      SELECT id
      FROM public.user_device_login_history
      WHERE user_id = p_user_id
      ORDER BY ended_at DESC, created_at DESC
      LIMIT 5
    );
END;
$$;

REVOKE ALL ON FUNCTION public._append_device_login_history(uuid, text, text, timestamptz)
  FROM PUBLIC;

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

  -- Archive outgoing device into history (last 5).
  IF existing_client IS NOT NULL
     AND existing_client <> ''
     AND existing_client IS DISTINCT FROM btrim(p_client_session_id) THEN
    PERFORM public._append_device_login_history(
      uid,
      existing_label,
      existing_platform,
      existing_claimed_at
    );
  END IF;

  UPDATE public.users
  SET
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

  IF coalesce(existing_label, '') <> ''
     OR coalesce(existing_platform, '') <> '' THEN
    PERFORM public._append_device_login_history(
      uid,
      existing_label,
      existing_platform,
      existing_claimed_at
    );
  END IF;

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
