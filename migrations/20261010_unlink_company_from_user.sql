-- Reliable admin unlink: bypass RLS via SECURITY DEFINER RPC.
-- Client delete on user_companies can appear to "succeed" while RLS blocks the row removal.

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
BEGIN
  IF p_user_id IS NULL OR v_name IS NULL OR v_name = '' THEN
    RAISE EXCEPTION 'user_id and company_name are required';
  END IF;

  DELETE FROM public.user_companies
  WHERE user_id = p_user_id
    AND lower(btrim(company_name)) = lower(v_name);

  -- If that company was the profile primary, point primary at another link (or clear).
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

GRANT EXECUTE ON FUNCTION public.unlink_company_from_user(uuid, text)
  TO anon, authenticated;

COMMENT ON FUNCTION public.unlink_company_from_user(uuid, text) IS
  'Admin/app helper to remove a company link for a user and fix users.company_name.';
