-- Review against a schema-only export and test in staging before production.
-- Transactional: any unsupported dependency/policy aborts the whole migration.
-- No Tally connector changes. No RLS/grant assumptions for app data access.
BEGIN;
CREATE TEMP TABLE tallylive_saved_functions ON COMMIT DROP AS
SELECT p.oid, p.proname, pg_get_function_identity_arguments(p.oid) AS args,
       pg_get_userbyid(p.proowner) AS owner_name,
       COALESCE(p.proacl, acldefault('f', p.proowner)) AS acl
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname IN
('get_slow_moving_items','get_high_value_items','get_unused_ledgers','get_unused_items','get_daily_profit');
DO $$
BEGIN
  IF (SELECT count(*) FROM tallylive_saved_functions) <> 5 THEN
    RAISE EXCEPTION 'Expected exactly five existing report functions; review deployed schema first';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_proc p JOIN tallylive_saved_functions s ON s.oid=p.oid
             WHERE p.prosecdef OR p.proconfig IS NOT NULL) THEN
    RAISE EXCEPTION 'Custom function security/configuration found; review it before applying';
  END IF;
END $$;
ALTER TABLE public.stock_items ALTER COLUMN "ItemQuantity" TYPE numeric USING "ItemQuantity"::numeric;
ALTER TABLE public.invoice_items ALTER COLUMN quantity TYPE numeric USING quantity::numeric;
ALTER TABLE public.invoice_items ALTER COLUMN free_quantity TYPE numeric USING free_quantity::numeric;
DO $$
BEGIN
  IF to_regclass('public.invoice_items_purchase') IS NOT NULL THEN
    ALTER TABLE public.invoice_items_purchase ALTER COLUMN quantity TYPE numeric USING quantity::numeric;
    ALTER TABLE public.invoice_items_purchase ALTER COLUMN free_quantity TYPE numeric USING free_quantity::numeric;
  END IF;
END $$;
-- RESTRICT is deliberate: never drop dependent views or policies automatically.
DROP FUNCTION public.get_high_value_items(text) RESTRICT;
DROP FUNCTION public.get_unused_items(text, integer) RESTRICT;
SET LOCAL search_path = public, pg_catalog;
CREATE OR REPLACE FUNCTION get_slow_moving_items(p_company_name TEXT, p_days INT DEFAULT 30)
RETURNS TABLE (product_name TEXT, total_sold NUMERIC) AS $$
BEGIN
  RETURN QUERY
  SELECT s."ItemName" as product_name, COALESCE(SUM(i.quantity), 0)::NUMERIC as total_sold
  FROM stock_items s
  LEFT JOIN (
    SELECT ii.product_name, si.company_name, ii.quantity
    FROM invoice_items ii
    JOIN sales_invoices si ON ii.invoice_id = si.id
    WHERE si.invoice_date >= (CURRENT_DATE - (p_days || ' days')::interval)
  ) i ON s."ItemName" = i.product_name AND s.company_name = i.company_name
  WHERE (p_company_name IS NULL OR s.company_name = p_company_name)
  GROUP BY s."ItemName"
  HAVING COALESCE(SUM(i.quantity), 0) < 5
  ORDER BY total_sold ASC;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION get_high_value_items(p_company_name TEXT)
RETURNS TABLE (product_name TEXT, quantity NUMERIC, stock_value NUMERIC) AS $$
BEGIN
  RETURN QUERY
  SELECT s."ItemName" as product_name, s."ItemQuantity" as quantity, (s."ItemQuantity" * s."ItemRate") as stock_value
  FROM stock_items s
  WHERE s."ItemQuantity" > 0
  AND (p_company_name IS NULL OR s.company_name = p_company_name)
  ORDER BY stock_value DESC;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION get_unused_ledgers(p_company_name TEXT, p_days INT DEFAULT 180)
RETURNS TABLE (customer_name TEXT, mobile_number TEXT, city TEXT) AS $$
BEGIN
  RETURN QUERY
  SELECT c.customer_name, c.mobile_number, c.city
  FROM customers c
  WHERE c.customer_name NOT IN (
      SELECT DISTINCT si.customer_name 
      FROM sales_invoices si
      WHERE si.invoice_date >= (CURRENT_DATE - (p_days || ' days')::interval)
      AND si.customer_name IS NOT NULL
      AND si.company_name = c.company_name
  )
  AND c.is_active = true
  AND (p_company_name IS NULL OR c.company_name = p_company_name);
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION get_unused_items(p_company_name TEXT, p_days INT DEFAULT 180)
RETURNS TABLE (product_name TEXT, quantity NUMERIC, stock_value NUMERIC) AS $$
BEGIN
  RETURN QUERY
  SELECT s."ItemName" as product_name, s."ItemQuantity" as quantity, (s."ItemQuantity" * s."ItemRate") as stock_value
  FROM stock_items s
  WHERE s."ItemQuantity" > 0
  AND s."ItemName" NOT IN (
      SELECT DISTINCT i.product_name 
      FROM invoice_items i
      JOIN sales_invoices si ON i.invoice_id = si.id
      WHERE si.company_name = s.company_name AND si.invoice_date >= (CURRENT_DATE - (p_days || ' days')::interval)
  )
  AND (p_company_name IS NULL OR s.company_name = p_company_name)
  ORDER BY stock_value DESC;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION get_daily_profit(p_company_name TEXT, p_days INT DEFAULT 7)
RETURNS TABLE (sale_date DATE, total_revenue NUMERIC, estimated_profit NUMERIC) AS $$
BEGIN
  RETURN QUERY
  SELECT 
      DATE(si.invoice_date) as sale_date,
      SUM(i.total_amount) as total_revenue,
      SUM( (i.unit_price - COALESCE(s."StandardCost", s."ItemRate", 0)) * i.quantity ) as estimated_profit
  FROM sales_invoices si
  JOIN invoice_items i ON si.id = i.invoice_id
  LEFT JOIN stock_items s ON i.product_name = s."ItemName" AND s.company_name = si.company_name
  WHERE si.invoice_date >= (CURRENT_DATE - (p_days || ' days')::interval)
  AND (p_company_name IS NULL OR si.company_name = p_company_name)
  GROUP BY DATE(si.invoice_date)
  ORDER BY sale_date DESC;
END;
$$ LANGUAGE plpgsql;
-- Restore prior ownership and execution grants after return-type changes.
-- Clear creation-time default ACLs before replaying the captured grants.
DO $$
DECLARE f record; a record; grantee_name text; current_oid oid;
BEGIN
  FOR f IN SELECT * FROM tallylive_saved_functions LOOP
    current_oid := to_regprocedure(format('public.%I(%s)', f.proname, f.args));
    EXECUTE format('ALTER FUNCTION public.%I(%s) OWNER TO %I', f.proname, f.args, f.owner_name);
    FOR a IN SELECT DISTINCT grantee FROM pg_proc p,
      LATERAL aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) acl
      WHERE p.oid=current_oid LOOP
      grantee_name := CASE WHEN a.grantee=0 THEN 'PUBLIC' ELSE quote_ident(pg_get_userbyid(a.grantee)) END;
      EXECUTE format('REVOKE ALL ON FUNCTION public.%I(%s) FROM %s', f.proname, f.args, grantee_name);
    END LOOP;
    FOR a IN SELECT * FROM aclexplode(f.acl) LOOP
      grantee_name := CASE WHEN a.grantee=0 THEN 'PUBLIC' ELSE quote_ident(pg_get_userbyid(a.grantee)) END;
      EXECUTE format('GRANT %s ON FUNCTION public.%I(%s) TO %s%s', a.privilege_type,
        f.proname, f.args, grantee_name, CASE WHEN a.is_grantable THEN ' WITH GRANT OPTION' ELSE '' END);
    END LOOP;
  END LOOP;
END $$;
COMMIT;
