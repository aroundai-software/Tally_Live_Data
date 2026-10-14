-- Combined Reports is user-scoped (not company_features).
-- Admin enables this per user; the app lists that user's linked companies.

ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS is_combined_reports_enabled boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.users.is_combined_reports_enabled IS
  'When true, this user can enter Combined app mode from company selection and view multi-company data.';
