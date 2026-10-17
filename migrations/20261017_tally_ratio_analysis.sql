-- Tally Ratio Analysis snapshot (FY start → as-of date).
-- One row per company; full refresh each sync. Recv. Turnover in days is the
-- primary KPI for Payment Speed; full name/value map kept in ratios jsonb.

CREATE TABLE IF NOT EXISTS public.tally_ratio_analysis (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  company_name text NOT NULL,
  company_guid text NOT NULL,
  from_date date NOT NULL,
  to_date date NOT NULL,
  recv_turnover_days numeric NULL,
  ratios jsonb NOT NULL DEFAULT '{}'::jsonb,
  synced_at timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now()),
  created_at timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now()),
  updated_at timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now()),
  CONSTRAINT tally_ratio_analysis_pkey PRIMARY KEY (id),
  CONSTRAINT tally_ratio_analysis_company_guid_key UNIQUE (company_guid)
);

CREATE INDEX IF NOT EXISTS tally_ratio_analysis_company_name_idx
  ON public.tally_ratio_analysis (company_name);

ALTER TABLE public.tally_ratio_analysis ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS tally_ratio_analysis_select_linked ON public.tally_ratio_analysis;
CREATE POLICY tally_ratio_analysis_select_linked
  ON public.tally_ratio_analysis
  FOR SELECT
  TO authenticated
  USING (
    company_name IN (
      SELECT uc.company_name
      FROM public.user_companies uc
      WHERE uc.user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS tally_ratio_analysis_sync_all ON public.tally_ratio_analysis;
CREATE POLICY tally_ratio_analysis_sync_all
  ON public.tally_ratio_analysis
  FOR ALL
  TO anon, authenticated
  USING (true)
  WITH CHECK (true);

COMMENT ON TABLE public.tally_ratio_analysis IS
  'Latest Tally Ratio Analysis snapshot per company (from_date=FY start, to_date=sync day).';
