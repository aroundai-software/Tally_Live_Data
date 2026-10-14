-- Prevent privilege escalation via PostgREST: non–super-admins must not change
-- role / is_active / is_combined_reports_enabled on public.users (including self).
-- Profile fields (full_name, phone_number, company_name) stay updatable per existing RLS.

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

REVOKE ALL ON FUNCTION public._jwt_is_service_role() FROM PUBLIC;
REVOKE ALL ON FUNCTION public._caller_is_super_admin() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public._jwt_is_service_role() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public._caller_is_super_admin() TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.users_protect_privilege_columns()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Sync agents / service role may manage rows freely.
  IF public._jwt_is_service_role() THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'INSERT' THEN
    IF NOT public._caller_is_super_admin() THEN
      -- New self-service / owner profiles: force safe defaults.
      NEW.role := 'owner';
      NEW.is_combined_reports_enabled := false;
      NEW.is_active := coalesce(NEW.is_active, true);
      IF NEW.is_active IS DISTINCT FROM true THEN
        NEW.is_active := true;
      END IF;
    END IF;
    RETURN NEW;
  END IF;

  -- UPDATE: block privilege column changes unless caller is super_admin.
  IF NEW.role IS DISTINCT FROM OLD.role
     OR NEW.is_active IS DISTINCT FROM OLD.is_active
     OR NEW.is_combined_reports_enabled IS DISTINCT FROM OLD.is_combined_reports_enabled THEN
    IF NOT public._caller_is_super_admin() THEN
      RAISE EXCEPTION 'Only a super admin can change role, access, or Combined Reports flags'
        USING ERRCODE = '42501';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_users_protect_privilege_columns ON public.users;
CREATE TRIGGER trg_users_protect_privilege_columns
  BEFORE INSERT OR UPDATE ON public.users
  FOR EACH ROW
  EXECUTE FUNCTION public.users_protect_privilege_columns();

COMMENT ON FUNCTION public.users_protect_privilege_columns() IS
  'Blocks non–super-admin (and non–service_role) changes to users.role, is_active, is_combined_reports_enabled.';
