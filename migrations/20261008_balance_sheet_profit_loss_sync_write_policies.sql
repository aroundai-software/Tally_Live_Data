-- Allow Python sync (anon key, same as customers/daybook) to write financial report snapshots.
-- App users still only SELECT their linked companies via the existing authenticated policies.

DROP POLICY IF EXISTS balance_sheet_reports_sync_all ON public.balance_sheet_reports;
CREATE POLICY balance_sheet_reports_sync_all
  ON public.balance_sheet_reports
  FOR ALL
  TO anon, authenticated
  USING (true)
  WITH CHECK (true);

DROP POLICY IF EXISTS balance_sheet_lines_sync_all ON public.balance_sheet_lines;
CREATE POLICY balance_sheet_lines_sync_all
  ON public.balance_sheet_lines
  FOR ALL
  TO anon, authenticated
  USING (true)
  WITH CHECK (true);

DROP POLICY IF EXISTS profit_loss_reports_sync_all ON public.profit_loss_reports;
CREATE POLICY profit_loss_reports_sync_all
  ON public.profit_loss_reports
  FOR ALL
  TO anon, authenticated
  USING (true)
  WITH CHECK (true);

DROP POLICY IF EXISTS profit_loss_lines_sync_all ON public.profit_loss_lines;
CREATE POLICY profit_loss_lines_sync_all
  ON public.profit_loss_lines
  FOR ALL
  TO anon, authenticated
  USING (true)
  WITH CHECK (true);
