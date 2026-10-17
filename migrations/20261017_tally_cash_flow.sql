-- Tally Cash Flow monthly snapshot (FY start → as-of date).
-- One row per company; full refresh each sync. months jsonb holds
-- [{period, inflow, outflow, nett}, ...] in Tally report order.

CREATE TABLE IF NOT EXISTS public.tally_cash_flow (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  company_name text NOT NULL,
  company_guid text NOT NULL,
  from_date date NOT NULL,
  to_date date NOT NULL,
  months jsonb NOT NULL DEFAULT '[]'::jsonb,
  total_inflow numeric NULL,
  total_outflow numeric NULL,
  total_nett numeric NULL,
  synced_at timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now()),
  created_at timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now()),
  updated_at timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now()),
  CONSTRAINT tally_cash_flow_pkey PRIMARY KEY (id),
  CONSTRAINT tally_cash_flow_company_name_key UNIQUE (company_name)
);

CREATE INDEX IF NOT EXISTS tally_cash_flow_company_guid_idx
  ON public.tally_cash_flow (company_guid);

ALTER TABLE public.tally_cash_flow ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS tally_cash_flow_select_linked ON public.tally_cash_flow;
CREATE POLICY tally_cash_flow_select_linked
  ON public.tally_cash_flow
  FOR SELECT
  TO authenticated
  USING (
    company_name IN (
      SELECT uc.company_name
      FROM public.user_companies uc
      WHERE uc.user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS tally_cash_flow_sync_all ON public.tally_cash_flow;
CREATE POLICY tally_cash_flow_sync_all
  ON public.tally_cash_flow
  FOR ALL
  TO anon, authenticated
  USING (true)
  WITH CHECK (true);

COMMENT ON TABLE public.tally_cash_flow IS
  'Latest Tally Cash Flow monthly snapshot per company (from_date=FY start, to_date=sync day).';
