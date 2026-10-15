-- Ensure ledger_bill_settlements supports sync upserts on (company_name, guid).
-- Sync uses on_conflict=company_name,guid; without this unique index uploads fail with:
--   "there is no unique or exclusion constraint matching the ON CONFLICT specification"
-- Idempotent. Aborts if blank company_name/guid rows exist (clean those first).

BEGIN;

DO $migration$
DECLARE
  bad_count bigint;
  conname text;
  idxname text;
BEGIN
  IF to_regclass('public.ledger_bill_settlements') IS NULL THEN
    RAISE NOTICE 'ledger_bill_settlements does not exist — skip';
    RETURN;
  END IF;

  SELECT COUNT(*) INTO bad_count
  FROM public.ledger_bill_settlements
  WHERE company_name IS NULL
     OR btrim(company_name) = ''
     OR guid IS NULL
     OR btrim(guid::text) = '';

  IF bad_count > 0 THEN
    RAISE EXCEPTION
      'ledger_bill_settlements has % row(s) with blank company_name or guid — clean before migration',
      bad_count;
  END IF;

  -- Drop UNIQUE constraints that are only on (guid)
  FOR conname IN
    SELECT c.conname
    FROM pg_constraint c
    JOIN pg_class rel ON rel.oid = c.conrelid
    JOIN pg_namespace nsp ON nsp.oid = rel.relnamespace
    WHERE nsp.nspname = 'public'
      AND rel.relname = 'ledger_bill_settlements'
      AND c.contype = 'u'
      AND pg_get_constraintdef(c.oid) ~* $re$\(guid\)\s*$re$
  LOOP
    EXECUTE format(
      'ALTER TABLE public.ledger_bill_settlements DROP CONSTRAINT %I',
      conname
    );
  END LOOP;

  -- Drop unique indexes on guid alone
  FOR idxname IN
    SELECT i.relname
    FROM pg_index x
    JOIN pg_class trel ON trel.oid = x.indrelid
    JOIN pg_class i ON i.oid = x.indexrelid
    JOIN pg_namespace nsp ON nsp.oid = trel.relnamespace
    JOIN pg_attribute a ON a.attrelid = trel.oid AND a.attnum = ANY (x.indkey::smallint[])
    WHERE nsp.nspname = 'public'
      AND trel.relname = 'ledger_bill_settlements'
      AND x.indisunique
      AND NOT x.indisprimary
      AND x.indnkeyatts = 1
      AND a.attname = 'guid'
  LOOP
    EXECUTE format('DROP INDEX IF EXISTS public.%I', idxname);
  END LOOP;

  ALTER TABLE public.ledger_bill_settlements
    ALTER COLUMN company_name SET NOT NULL;
  ALTER TABLE public.ledger_bill_settlements
    ALTER COLUMN guid SET NOT NULL;

  CREATE UNIQUE INDEX IF NOT EXISTS ledger_bill_settlements_company_name_guid_uidx
    ON public.ledger_bill_settlements (company_name, guid);
END
$migration$;

COMMIT;
