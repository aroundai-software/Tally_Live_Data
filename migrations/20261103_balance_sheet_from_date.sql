-- Persist Balance Sheet period start so the app can clamp FY labels
-- the same way as P&L / cash flow (books_from → FY end / as_on).

ALTER TABLE public.balance_sheet_reports
  ADD COLUMN IF NOT EXISTS from_date date;

-- Backfill: use as_on_date's Indian FY start when from_date is missing.
UPDATE public.balance_sheet_reports
SET from_date = CASE
  WHEN EXTRACT(MONTH FROM as_on_date) >= 4
    THEN make_date(EXTRACT(YEAR FROM as_on_date)::int, 4, 1)
  ELSE make_date(EXTRACT(YEAR FROM as_on_date)::int - 1, 4, 1)
END
WHERE from_date IS NULL AND as_on_date IS NOT NULL;

COMMENT ON COLUMN public.balance_sheet_reports.from_date IS
  'Report period start (company books_from / FY start). as_on_date is period end.';
