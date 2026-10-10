-- Balance Sheet & Profit & Loss snapshot tables (Option B — 4 tables)
-- Exact Tally report sync target. Full snapshot refresh (no Alter ID).
-- RLS: authenticated users can SELECT only companies linked in user_companies.
-- Sync writes should use the service role (bypasses RLS), same as other sync tables.

-- ---------------------------------------------------------------------------
-- 1) balance_sheet_reports
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.balance_sheet_reports (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  company_name text NOT NULL,
  company_guid text NOT NULL,
  as_on_date date NOT NULL,
  format text NOT NULL DEFAULT 'condensed',
  total_liabilities numeric NOT NULL DEFAULT 0,
  total_assets numeric NOT NULL DEFAULT 0,
  synced_at timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now()),
  created_at timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now()),
  updated_at timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now()),
  CONSTRAINT balance_sheet_reports_pkey PRIMARY KEY (id),
  CONSTRAINT balance_sheet_reports_company_guid_key UNIQUE (company_guid)
);

CREATE INDEX IF NOT EXISTS balance_sheet_reports_company_name_idx
  ON public.balance_sheet_reports (company_name);

-- ---------------------------------------------------------------------------
-- 2) balance_sheet_lines  (row_type: group | ledger)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.balance_sheet_lines (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  report_id uuid NOT NULL REFERENCES public.balance_sheet_reports(id) ON DELETE CASCADE,
  company_name text NOT NULL,
  company_guid text NOT NULL,
  row_type text NOT NULL CHECK (row_type IN ('group', 'ledger')),
  section text NULL,
  particulars text NOT NULL,
  tally_group_name text NULL,
  line_key text NULL,
  parent_line_key text NULL,
  amount numeric NOT NULL DEFAULT 0,
  debit numeric NOT NULL DEFAULT 0,
  credit numeric NOT NULL DEFAULT 0,
  dr_cr text NULL,
  is_total boolean NOT NULL DEFAULT false,
  is_calculated boolean NOT NULL DEFAULT false,
  ledger_guid text NULL,
  sort_order integer NOT NULL DEFAULT 0,
  created_at timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now()),
  CONSTRAINT balance_sheet_lines_pkey PRIMARY KEY (id)
);

CREATE INDEX IF NOT EXISTS balance_sheet_lines_report_id_idx
  ON public.balance_sheet_lines (report_id);
CREATE INDEX IF NOT EXISTS balance_sheet_lines_company_guid_idx
  ON public.balance_sheet_lines (company_guid);
CREATE INDEX IF NOT EXISTS balance_sheet_lines_company_row_type_idx
  ON public.balance_sheet_lines (company_name, row_type);
CREATE INDEX IF NOT EXISTS balance_sheet_lines_group_idx
  ON public.balance_sheet_lines (company_guid, tally_group_name);
CREATE INDEX IF NOT EXISTS balance_sheet_lines_ledger_guid_idx
  ON public.balance_sheet_lines (ledger_guid);

-- ---------------------------------------------------------------------------
-- 3) profit_loss_reports
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.profit_loss_reports (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  company_name text NOT NULL,
  company_guid text NOT NULL,
  from_date date NOT NULL,
  to_date date NOT NULL,
  format text NOT NULL DEFAULT 'condensed',
  show_gross_profit boolean NOT NULL DEFAULT true,
  gross_profit numeric NOT NULL DEFAULT 0,
  gross_loss numeric NOT NULL DEFAULT 0,
  nett_profit numeric NOT NULL DEFAULT 0,
  nett_loss numeric NOT NULL DEFAULT 0,
  synced_at timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now()),
  created_at timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now()),
  updated_at timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now()),
  CONSTRAINT profit_loss_reports_pkey PRIMARY KEY (id),
  CONSTRAINT profit_loss_reports_company_guid_key UNIQUE (company_guid)
);

CREATE INDEX IF NOT EXISTS profit_loss_reports_company_name_idx
  ON public.profit_loss_reports (company_name);

-- ---------------------------------------------------------------------------
-- 4) profit_loss_lines  (row_type: group | ledger)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.profit_loss_lines (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  report_id uuid NOT NULL REFERENCES public.profit_loss_reports(id) ON DELETE CASCADE,
  company_name text NOT NULL,
  company_guid text NOT NULL,
  row_type text NOT NULL CHECK (row_type IN ('group', 'ledger')),
  section text NULL,
  particulars text NOT NULL,
  tally_group_name text NULL,
  line_key text NULL,
  parent_line_key text NULL,
  amount numeric NOT NULL DEFAULT 0,
  debit numeric NOT NULL DEFAULT 0,
  credit numeric NOT NULL DEFAULT 0,
  dr_cr text NULL,
  is_total boolean NOT NULL DEFAULT false,
  is_calculated boolean NOT NULL DEFAULT false,
  ledger_guid text NULL,
  sort_order integer NOT NULL DEFAULT 0,
  created_at timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now()),
  CONSTRAINT profit_loss_lines_pkey PRIMARY KEY (id)
);

CREATE INDEX IF NOT EXISTS profit_loss_lines_report_id_idx
  ON public.profit_loss_lines (report_id);
CREATE INDEX IF NOT EXISTS profit_loss_lines_company_guid_idx
  ON public.profit_loss_lines (company_guid);
CREATE INDEX IF NOT EXISTS profit_loss_lines_company_row_type_idx
  ON public.profit_loss_lines (company_name, row_type);
CREATE INDEX IF NOT EXISTS profit_loss_lines_group_idx
  ON public.profit_loss_lines (company_guid, tally_group_name);
CREATE INDEX IF NOT EXISTS profit_loss_lines_ledger_guid_idx
  ON public.profit_loss_lines (ledger_guid);

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------
ALTER TABLE public.balance_sheet_reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.balance_sheet_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profit_loss_reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profit_loss_lines ENABLE ROW LEVEL SECURITY;

-- Helper: company names linked to the current auth user
-- (inline in policies so we don't depend on a custom function existing)

DROP POLICY IF EXISTS balance_sheet_reports_select_linked ON public.balance_sheet_reports;
CREATE POLICY balance_sheet_reports_select_linked
  ON public.balance_sheet_reports
  FOR SELECT
  TO authenticated
  USING (
    company_name IN (
      SELECT uc.company_name
      FROM public.user_companies uc
      WHERE uc.user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS balance_sheet_lines_select_linked ON public.balance_sheet_lines;
CREATE POLICY balance_sheet_lines_select_linked
  ON public.balance_sheet_lines
  FOR SELECT
  TO authenticated
  USING (
    company_name IN (
      SELECT uc.company_name
      FROM public.user_companies uc
      WHERE uc.user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS profit_loss_reports_select_linked ON public.profit_loss_reports;
CREATE POLICY profit_loss_reports_select_linked
  ON public.profit_loss_reports
  FOR SELECT
  TO authenticated
  USING (
    company_name IN (
      SELECT uc.company_name
      FROM public.user_companies uc
      WHERE uc.user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS profit_loss_lines_select_linked ON public.profit_loss_lines;
CREATE POLICY profit_loss_lines_select_linked
  ON public.profit_loss_lines
  FOR SELECT
  TO authenticated
  USING (
    company_name IN (
      SELECT uc.company_name
      FROM public.user_companies uc
      WHERE uc.user_id = auth.uid()
    )
  );

-- No INSERT/UPDATE/DELETE policies for authenticated users.
-- Python sync should use the service role key (bypasses RLS), same as other tables.

COMMENT ON TABLE public.balance_sheet_reports IS
  'Latest Tally Balance Sheet snapshot per company (full refresh, no Alter ID).';
COMMENT ON TABLE public.balance_sheet_lines IS
  'Balance Sheet condensed groups and drill-down ledgers (row_type = group|ledger).';
COMMENT ON TABLE public.profit_loss_reports IS
  'Latest Tally Profit & Loss snapshot per company (full refresh, no Alter ID).';
COMMENT ON TABLE public.profit_loss_lines IS
  'Profit & Loss condensed groups and drill-down ledgers (row_type = group|ledger).';
