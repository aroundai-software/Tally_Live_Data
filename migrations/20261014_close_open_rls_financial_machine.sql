-- Remove wide-open RLS that nullified linked-company isolation on
-- Balance Sheet / P&L tables and machine_companies.
--
-- App users: SELECT only for companies in user_companies (or super_admin for machines).
-- Python/Tally sync: must use the service_role key (bypasses RLS). Do not use anon for writes.

-- ── Balance Sheet / Profit & Loss ───────────────────────────────────────────

DROP POLICY IF EXISTS balance_sheet_reports_sync_all ON public.balance_sheet_reports;
DROP POLICY IF EXISTS balance_sheet_lines_sync_all ON public.balance_sheet_lines;
DROP POLICY IF EXISTS profit_loss_reports_sync_all ON public.profit_loss_reports;
DROP POLICY IF EXISTS profit_loss_lines_sync_all ON public.profit_loss_lines;

-- Recreate linked SELECT policies (idempotent) so app reads still work.
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

-- ── machine_companies ───────────────────────────────────────────────────────

DROP POLICY IF EXISTS machine_companies_sync_all ON public.machine_companies;

DROP POLICY IF EXISTS machine_companies_select_linked ON public.machine_companies;
CREATE POLICY machine_companies_select_linked
  ON public.machine_companies
  FOR SELECT
  TO authenticated
  USING (
    company_name IN (
      SELECT uc.company_name
      FROM public.user_companies uc
      WHERE uc.user_id = auth.uid()
    )
    OR public._caller_is_super_admin()
  );

COMMENT ON POLICY balance_sheet_reports_select_linked ON public.balance_sheet_reports IS
  'Authenticated users may read BS reports only for linked companies.';
COMMENT ON POLICY machine_companies_select_linked ON public.machine_companies IS
  'Authenticated users may read machine↔company links for their companies; super_admin may read all. Writes via service_role only.';
