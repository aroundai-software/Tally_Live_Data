-- Company identity is (guid, company_name, company_number).
-- Same Tally GUID with a different year name (or company number) is a new company.
-- Overwrite only when all three match. Run in Supabase SQL editor.

BEGIN;

-- Blank and NULL company_number are the same identity value.
UPDATE public.tally_companies
SET company_number = ''
WHERE company_number IS NULL;

ALTER TABLE public.tally_companies
  ALTER COLUMN company_number SET DEFAULT '',
  ALTER COLUMN company_number SET NOT NULL;

ALTER TABLE public.tally_companies
  DROP CONSTRAINT IF EXISTS tally_companies_guid_key;

ALTER TABLE public.tally_companies
  DROP CONSTRAINT IF EXISTS tally_companies_company_number_key;

-- Year files of the same legal entity reuse GST/TRN. Identity does not include TRN.
ALTER TABLE public.tally_companies
  DROP CONSTRAINT IF EXISTS tally_companies_trn_number_key;

DROP INDEX IF EXISTS public.tally_companies_guid_key;
DROP INDEX IF EXISTS public.tally_companies_company_number_key;
DROP INDEX IF EXISTS public.tally_companies_trn_number_key;

ALTER TABLE public.tally_companies
  DROP CONSTRAINT IF EXISTS tally_companies_identity_key;

ALTER TABLE public.tally_companies
  ADD CONSTRAINT tally_companies_identity_key
  UNIQUE (guid, company_name, company_number);

COMMIT;
