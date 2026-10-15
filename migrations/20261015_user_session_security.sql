-- Harden single-device sessions:
-- 1) Store GoTrue session id + client session id
-- 2) Atomic claim_device_session RPC (conflict / force + revoke other auth sessions)
-- 3) require_active_device_session() enforced via _caller_can_access_company
-- 4) Block direct client updates of session columns (must use RPC)
-- 5) clear_device_session on logout

BEGIN;

ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS active_auth_session_id uuid;

COMMENT ON COLUMN public.users.active_auth_session_id IS
  'GoTrue auth.sessions.id currently allowed for this user (from JWT session_id claim).';

-- ─── Assert current JWT belongs to the claimed device session ───────────────
CREATE OR REPLACE FUNCTION public.require_active_device_session()
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  claimed_auth uuid;
  claimed_client text;
  jwt_sid text;
BEGIN
  IF public._jwt_is_service_role() THEN
    RETURN;
  END IF;

  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated'
      USING ERRCODE = '42501';
  END IF;

  SELECT u.active_auth_session_id, u.active_session_id
    INTO claimed_auth, claimed_client
  FROM public.users u
  WHERE u.id = auth.uid();

  -- Not claimed yet (legacy / mid-login): allow.
  IF (claimed_auth IS NULL) AND (claimed_client IS NULL OR claimed_client = '') THEN
    RETURN;
  END IF;

  jwt_sid := nullif(auth.jwt() ->> 'session_id', '');

  IF claimed_auth IS NOT NULL THEN
    IF jwt_sid IS NULL OR jwt_sid IS DISTINCT FROM claimed_auth::text THEN
      RAISE EXCEPTION 'DEVICE_SESSION_REPLACED'
        USING ERRCODE = 'P0001',
              HINT = 'Signed in on another device';
    END IF;
    RETURN;
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.require_active_device_session() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.require_active_device_session()
  TO authenticated, service_role;

-- Gate all company RPCs that already call this helper.
CREATE OR REPLACE FUNCTION public._caller_can_access_company(p_company_name text)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF public._jwt_is_service_role() THEN
    RETURN true;
  END IF;

  IF auth.uid() IS NULL THEN
    RETURN false;
  END IF;

  -- Reject JWTs from a replaced/kicked device before company checks.
  PERFORM public.require_active_device_session();

  IF p_company_name IS NULL OR btrim(p_company_name) = '' THEN
    RETURN false;
  END IF;

  IF public._caller_is_super_admin() THEN
    RETURN true;
  END IF;

  RETURN EXISTS (
    SELECT 1
    FROM public.user_companies uc
    WHERE uc.user_id = auth.uid()
      AND uc.company_name = btrim(p_company_name)
  )
  OR EXISTS (
    SELECT 1
    FROM public.users u
    WHERE u.id = auth.uid()
      AND coalesce(u.company_name, '') = btrim(p_company_name)
  );
END;
$$;

-- ─── Prevent direct UPDATE of session columns (RPC only) ────────────────────
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
       OR NEW.active_device_platform IS DISTINCT FROM OLD.active_device_platform THEN
      RAISE EXCEPTION 'Session fields can only be changed via claim_device_session / clear_device_session'
        USING ERRCODE = '42501';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_users_protect_session_columns ON public.users;
CREATE TRIGGER trg_users_protect_session_columns
  BEFORE UPDATE ON public.users
  FOR EACH ROW
  EXECUTE FUNCTION public.users_protect_session_columns();

-- ─── Atomic claim + revoke other GoTrue sessions ────────────────────────────
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

  SELECT u.active_session_id INTO existing_client
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
    active_session_id = btrim(p_client_session_id),
    active_auth_session_id = jwt_sid,
    session_claimed_at = now(),
    active_device_label = p_device_label,
    active_device_platform = p_device_platform
  WHERE id = uid;

  -- Drop every other auth session for this user (invalidates other devices' refresh).
  IF jwt_sid IS NOT NULL THEN
    DELETE FROM auth.sessions
    WHERE user_id = uid
      AND id IS DISTINCT FROM jwt_sid;
  ELSE
    DELETE FROM auth.sessions
    WHERE user_id = uid;
  END IF;

  -- Mark orphaned refresh tokens revoked when possible.
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

REVOKE ALL ON FUNCTION public.claim_device_session(text, boolean, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.claim_device_session(text, boolean, text, text)
  TO authenticated, service_role;

-- ─── Clear claim on logout ──────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.clear_device_session()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
BEGIN
  IF uid IS NULL THEN
    RETURN;
  END IF;

  PERFORM set_config('app.claiming_session', '1', true);

  UPDATE public.users
  SET
    active_session_id = NULL,
    active_auth_session_id = NULL,
    session_claimed_at = NULL,
    active_device_label = NULL,
    active_device_platform = NULL
  WHERE id = uid;
END;
$$;

REVOKE ALL ON FUNCTION public.clear_device_session() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.clear_device_session()
  TO authenticated, service_role;

COMMIT;
