-- Harden link/unlink company RPCs:
-- - Revoke anon execute
-- - Require auth.uid() = p_user_id (self) OR super_admin OR service_role
-- - Self-link must prove phone ownership against tally_companies

CREATE UNIQUE INDEX IF NOT EXISTS user_companies_user_id_company_name_uidx
  ON public.user_companies (user_id, company_name);

-- Helpers (idempotent with 20261014_users_protect_privilege_columns.sql)
CREATE OR REPLACE FUNCTION public._jwt_is_service_role()
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
  SELECT coalesce(auth.jwt() ->> 'role', '') = 'service_role';
$$;

CREATE OR REPLACE FUNCTION public._caller_is_super_admin()
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  r text;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN false;
  END IF;
  SELECT u.role INTO r
  FROM public.users u
  WHERE u.id = auth.uid();
  RETURN coalesce(r, '') = 'super_admin';
END;
$$;

CREATE OR REPLACE FUNCTION public._digits_last10(p text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    WHEN length(regexp_replace(coalesce(p, ''), '[^0-9]', '', 'g')) >= 10
      THEN right(regexp_replace(coalesce(p, ''), '[^0-9]', '', 'g'), 10)
    ELSE regexp_replace(coalesce(p, ''), '[^0-9]', '', 'g')
  END;
$$;

-- Drop old 2-arg signature so grants/anon cannot linger on it.
DROP FUNCTION IF EXISTS public.link_company_to_user(uuid, text);

CREATE OR REPLACE FUNCTION public.link_company_to_user(
  p_user_id uuid,
  p_company_name text,
  p_mobile text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_name text := btrim(p_company_name);
  v_is_admin boolean := public._caller_is_super_admin();
  v_is_service boolean := public._jwt_is_service_role();
  v_company_name text;
  v_company_mobile text;
  v_proof text;
  v_profile_phone text;
BEGIN
  IF p_user_id IS NULL OR v_name IS NULL OR v_name = '' THEN
    RAISE EXCEPTION 'user_id and company_name are required';
  END IF;

  IF NOT v_is_service AND NOT v_is_admin THEN
    IF auth.uid() IS NULL OR auth.uid() IS DISTINCT FROM p_user_id THEN
      RAISE EXCEPTION 'Not allowed to link companies for another user'
        USING ERRCODE = '42501';
    END IF;
  END IF;

  SELECT tc.company_name,
         coalesce(nullif(btrim(tc.mobile_number), ''), nullif(btrim(tc.phone_number), ''))
    INTO v_company_name, v_company_mobile
  FROM public.tally_companies tc
  WHERE lower(btrim(tc.company_name)) = lower(v_name)
    AND coalesce(tc.is_active, true) = true
  ORDER BY CASE WHEN btrim(tc.company_name) = v_name THEN 0 ELSE 1 END
  LIMIT 1;

  IF v_company_name IS NULL THEN
    RAISE EXCEPTION 'No active company found with that name';
  END IF;

  -- Self-link: require phone proof against the company record.
  IF NOT v_is_service AND NOT v_is_admin THEN
    SELECT u.phone_number INTO v_profile_phone
    FROM public.users u
    WHERE u.id = p_user_id;

    v_proof := public._digits_last10(coalesce(nullif(btrim(p_mobile), ''), v_profile_phone));
    IF v_proof IS NULL OR length(v_proof) < 10 THEN
      RAISE EXCEPTION 'A valid 10-digit mobile number is required to link this company';
    END IF;

    IF public._digits_last10(v_company_mobile) IS DISTINCT FROM v_proof THEN
      RAISE EXCEPTION 'Mobile number does not match the registered phone for this company';
    END IF;
  END IF;

  INSERT INTO public.user_companies (user_id, company_name)
  VALUES (p_user_id, v_company_name)
  ON CONFLICT (user_id, company_name) DO NOTHING;

  UPDATE public.users
  SET company_name = v_company_name
  WHERE id = p_user_id
    AND (company_name IS NULL OR btrim(company_name) = '');
END;
$$;

CREATE OR REPLACE FUNCTION public.unlink_company_from_user(
  p_user_id uuid,
  p_company_name text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_name text := btrim(p_company_name);
  v_is_admin boolean := public._caller_is_super_admin();
  v_is_service boolean := public._jwt_is_service_role();
BEGIN
  IF p_user_id IS NULL OR v_name IS NULL OR v_name = '' THEN
    RAISE EXCEPTION 'user_id and company_name are required';
  END IF;

  IF NOT v_is_service AND NOT v_is_admin THEN
    IF auth.uid() IS NULL OR auth.uid() IS DISTINCT FROM p_user_id THEN
      RAISE EXCEPTION 'Not allowed to unlink companies for another user'
        USING ERRCODE = '42501';
    END IF;
  END IF;

  DELETE FROM public.user_companies
  WHERE user_id = p_user_id
    AND lower(btrim(company_name)) = lower(v_name);

  UPDATE public.users u
  SET company_name = COALESCE(
    (
      SELECT uc.company_name
      FROM public.user_companies uc
      WHERE uc.user_id = p_user_id
      ORDER BY uc.company_name
      LIMIT 1
    ),
    ''
  )
  WHERE u.id = p_user_id
    AND lower(btrim(COALESCE(u.company_name, ''))) = lower(v_name);
END;
$$;

REVOKE ALL ON FUNCTION public.link_company_to_user(uuid, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.unlink_company_from_user(uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.link_company_to_user(uuid, text, text) FROM anon;
REVOKE ALL ON FUNCTION public.unlink_company_from_user(uuid, text) FROM anon;

GRANT EXECUTE ON FUNCTION public.link_company_to_user(uuid, text, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.unlink_company_from_user(uuid, text) TO authenticated, service_role;

COMMENT ON FUNCTION public.link_company_to_user(uuid, text, text) IS
  'Adds one company link. Self: auth.uid must match + phone proof. Admin/service: no phone required.';
COMMENT ON FUNCTION public.unlink_company_from_user(uuid, text) IS
  'Removes one company link. Self or super_admin/service only.';
