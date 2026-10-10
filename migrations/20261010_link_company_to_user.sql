-- Additive company linking: INSERT only — never replaces other linked companies.
-- Also keeps a unique (user_id, company_name) so upserts are safe.

CREATE UNIQUE INDEX IF NOT EXISTS user_companies_user_id_company_name_uidx
  ON public.user_companies (user_id, company_name);

CREATE OR REPLACE FUNCTION public.link_company_to_user(
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

  -- Add link; ignore if already present. Does NOT delete other companies.
  INSERT INTO public.user_companies (user_id, company_name)
  VALUES (p_user_id, v_name)
  ON CONFLICT (user_id, company_name) DO NOTHING;

  -- If profile has no primary company yet, set it (do not overwrite an existing one).
  UPDATE public.users
  SET company_name = v_name
  WHERE id = p_user_id
    AND (company_name IS NULL OR btrim(company_name) = '');
END;
$$;

GRANT EXECUTE ON FUNCTION public.link_company_to_user(uuid, text)
  TO anon, authenticated;

COMMENT ON FUNCTION public.link_company_to_user(uuid, text) IS
  'Adds one company to a user (merge). Never removes other linked companies.';
