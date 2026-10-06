-- Multi-company isolation: unique key becomes (company_name, guid)
-- Keep tally_companies.guid UNIQUE alone (one company master per Tally GUID).
-- Run in Supabase SQL editor. Aborts if blank company_name / guid rows exist.

BEGIN;

DO $migration$
DECLARE
  t text;
  bad_count bigint;
  conname text;
  idxname text;
  tables text[] := ARRAY[
    'customers',
    'stock_items',
    'sales_invoices',
    'invoice_items',
    'purchase_invoices',
    'invoice_items_purchase',
    'outstanding_receivables',
    'outstanding_payables',
    'tally_daybook',
    'tally_godowns',
    'tally_cost_centers',
    'ledger_bill_settlements'
  ];
BEGIN
  FOREACH t IN ARRAY tables LOOP
    EXECUTE format(
      $sql$
        SELECT COUNT(*)
        FROM public.%I
        WHERE company_name IS NULL
           OR btrim(company_name) = ''
           OR guid IS NULL
           OR btrim(guid::text) = ''
      $sql$,
      t
    ) INTO bad_count;

    IF bad_count > 0 THEN
      RAISE EXCEPTION
        'Table % has % row(s) with blank company_name or guid - clean data before migration',
        t,
        bad_count;
    END IF;

    -- Drop UNIQUE constraints that are only on (guid)
    FOR conname IN
      SELECT c.conname
      FROM pg_constraint c
      JOIN pg_class rel ON rel.oid = c.conrelid
      JOIN pg_namespace nsp ON nsp.oid = rel.relnamespace
      WHERE nsp.nspname = 'public'
        AND rel.relname = t
        AND c.contype = 'u'
        AND pg_get_constraintdef(c.oid) ~* $re$\(guid\)\s*$re$
    LOOP
      EXECUTE format('ALTER TABLE public.%I DROP CONSTRAINT %I', t, conname);
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
        AND trel.relname = t
        AND x.indisunique
        AND NOT x.indisprimary
        AND x.indnkeyatts = 1
        AND a.attname = 'guid'
    LOOP
      EXECUTE format('DROP INDEX IF EXISTS public.%I', idxname);
    END LOOP;

    EXECUTE format('ALTER TABLE public.%I ALTER COLUMN company_name SET NOT NULL', t);
    EXECUTE format('ALTER TABLE public.%I ALTER COLUMN guid SET NOT NULL', t);
    EXECUTE format(
      'CREATE UNIQUE INDEX IF NOT EXISTS %I ON public.%I (company_name, guid)',
      t || '_company_name_guid_uidx',
      t
    );
  END LOOP;
END
$migration$;

COMMIT;
