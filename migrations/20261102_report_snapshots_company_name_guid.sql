-- Balance Sheet, P&L, and Ratio Analysis: one snapshot per year-company.
-- Same Tally GUID with a different company_name must not overwrite the other year.
-- Run in Supabase SQL editor after 20261102_tally_companies_identity.sql.

BEGIN;

ALTER TABLE public.balance_sheet_reports
  DROP CONSTRAINT IF EXISTS balance_sheet_reports_company_guid_key;

ALTER TABLE public.profit_loss_reports
  DROP CONSTRAINT IF EXISTS profit_loss_reports_company_guid_key;

ALTER TABLE public.tally_ratio_analysis
  DROP CONSTRAINT IF EXISTS tally_ratio_analysis_company_guid_key;

DROP INDEX IF EXISTS public.balance_sheet_reports_company_guid_key;
DROP INDEX IF EXISTS public.profit_loss_reports_company_guid_key;
DROP INDEX IF EXISTS public.tally_ratio_analysis_company_guid_key;

ALTER TABLE public.balance_sheet_reports
  DROP CONSTRAINT IF EXISTS balance_sheet_reports_company_name_guid_key;

ALTER TABLE public.profit_loss_reports
  DROP CONSTRAINT IF EXISTS profit_loss_reports_company_name_guid_key;

ALTER TABLE public.tally_ratio_analysis
  DROP CONSTRAINT IF EXISTS tally_ratio_analysis_company_name_guid_key;

ALTER TABLE public.balance_sheet_reports
  ADD CONSTRAINT balance_sheet_reports_company_name_guid_key
  UNIQUE (company_name, company_guid);

ALTER TABLE public.profit_loss_reports
  ADD CONSTRAINT profit_loss_reports_company_name_guid_key
  UNIQUE (company_name, company_guid);

ALTER TABLE public.tally_ratio_analysis
  ADD CONSTRAINT tally_ratio_analysis_company_name_guid_key
  UNIQUE (company_name, company_guid);

COMMIT;
