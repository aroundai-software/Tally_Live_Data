-- Link sync machines to every company they sync (Option 2).
-- expires_at stays on script_control (one subscription per machine).
-- App users look up company → machine_companies → script_control.expires_at.

CREATE TABLE IF NOT EXISTS public.machine_companies (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  machine_name text NOT NULL,
  company_name text NOT NULL,
  last_seen_at timestamp with time zone DEFAULT now(),
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  CONSTRAINT machine_companies_pkey PRIMARY KEY (id),
  CONSTRAINT machine_companies_machine_company_unique UNIQUE (machine_name, company_name)
);

CREATE INDEX IF NOT EXISTS idx_machine_companies_company_name
  ON public.machine_companies (company_name);

CREATE INDEX IF NOT EXISTS idx_machine_companies_machine_name
  ON public.machine_companies (machine_name);

ALTER TABLE public.machine_companies ENABLE ROW LEVEL SECURITY;

-- Sync agent (anon key) and authenticated clients can upsert/read.
DROP POLICY IF EXISTS machine_companies_sync_all ON public.machine_companies;
CREATE POLICY machine_companies_sync_all
  ON public.machine_companies
  FOR ALL
  TO anon, authenticated
  USING (true)
  WITH CHECK (true);

COMMENT ON TABLE public.machine_companies IS
  'Maps each sync PC (machine_name) to companies loaded in Tally. Subscription expiry remains on script_control.';
