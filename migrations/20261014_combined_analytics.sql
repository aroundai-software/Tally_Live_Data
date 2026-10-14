-- Combined mode: multi-company Analytics RPCs (profit / velocity / dormant).
-- Reuses public._combined_allowed_companies from 20261014_combined_aggregates.sql
-- (allow-list ∩ user_companies + is_combined_reports_enabled).
-- App falls back to per-company fan-out if these functions are missing.
BEGIN;

SET LOCAL search_path = public, pg_catalog;

-- Requires helper from 20261014_combined_aggregates.sql
DO $$
BEGIN
  IF to_regprocedure('public._combined_allowed_companies(text[])') IS NULL THEN
    RAISE EXCEPTION
      'Missing public._combined_allowed_companies(text[]). Run 20261014_combined_aggregates.sql first.';
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.get_combined_daily_profit(
  p_company_names text[],
  p_days int DEFAULT 7
)
RETURNS TABLE (sale_date date, total_revenue numeric, estimated_profit numeric)
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  v_allowed text[];
BEGIN
  IF p_company_names IS NULL OR cardinality(p_company_names) < 2 THEN
    RETURN;
  END IF;

  v_allowed := public._combined_allowed_companies(p_company_names);
  IF v_allowed IS NULL OR cardinality(v_allowed) < 2 THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT
    DATE(si.invoice_date) AS sale_date,
    SUM(i.total_amount)::numeric AS total_revenue,
    SUM(
      (i.unit_price - COALESCE(s."StandardCost", s."ItemRate", 0)) * i.quantity
    )::numeric AS estimated_profit
  FROM sales_invoices si
  JOIN invoice_items i ON si.id = i.invoice_id
  LEFT JOIN stock_items s
    ON i.product_name = s."ItemName"
   AND s.company_name = si.company_name
  WHERE si.company_name = ANY(v_allowed)
    AND si.invoice_date >= (CURRENT_DATE - (p_days || ' days')::interval)
  GROUP BY DATE(si.invoice_date)
  ORDER BY sale_date DESC;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_combined_fast_moving_items(
  p_company_names text[],
  p_days int DEFAULT 30
)
RETURNS TABLE (product_name text, total_sold numeric)
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  v_allowed text[];
BEGIN
  IF p_company_names IS NULL OR cardinality(p_company_names) < 2 THEN
    RETURN;
  END IF;

  v_allowed := public._combined_allowed_companies(p_company_names);
  IF v_allowed IS NULL OR cardinality(v_allowed) < 2 THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT
    i.product_name::text,
    SUM(i.quantity)::numeric AS total_sold
  FROM invoice_items i
  JOIN sales_invoices si ON i.invoice_id = si.id
  WHERE si.company_name = ANY(v_allowed)
    AND si.invoice_date >= (CURRENT_DATE - (p_days || ' days')::interval)
    AND i.product_name IS NOT NULL
    AND btrim(i.product_name) <> ''
  GROUP BY i.product_name
  ORDER BY total_sold DESC, i.product_name ASC;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_combined_slow_moving_items(
  p_company_names text[],
  p_days int DEFAULT 30
)
RETURNS TABLE (product_name text, total_sold numeric)
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  v_allowed text[];
BEGIN
  IF p_company_names IS NULL OR cardinality(p_company_names) < 2 THEN
    RETURN;
  END IF;

  v_allowed := public._combined_allowed_companies(p_company_names);
  IF v_allowed IS NULL OR cardinality(v_allowed) < 2 THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT
    s."ItemName"::text AS product_name,
    COALESCE(SUM(i.quantity), 0)::numeric AS total_sold
  FROM stock_items s
  LEFT JOIN (
    SELECT ii.product_name, si.company_name, ii.quantity
    FROM invoice_items ii
    JOIN sales_invoices si ON ii.invoice_id = si.id
    WHERE si.company_name = ANY(v_allowed)
      AND si.invoice_date >= (CURRENT_DATE - (p_days || ' days')::interval)
  ) i
    ON s."ItemName" = i.product_name
   AND s.company_name = i.company_name
  WHERE s.company_name = ANY(v_allowed)
  GROUP BY s."ItemName"
  HAVING COALESCE(SUM(i.quantity), 0) < 5
  ORDER BY total_sold ASC, s."ItemName" ASC;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_combined_high_value_items(
  p_company_names text[]
)
RETURNS TABLE (
  company_name text,
  product_name text,
  quantity numeric,
  stock_value numeric
)
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  v_allowed text[];
BEGIN
  IF p_company_names IS NULL OR cardinality(p_company_names) < 2 THEN
    RETURN;
  END IF;

  v_allowed := public._combined_allowed_companies(p_company_names);
  IF v_allowed IS NULL OR cardinality(v_allowed) < 2 THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT
    s.company_name::text,
    s."ItemName"::text AS product_name,
    s."ItemQuantity"::numeric AS quantity,
    (s."ItemQuantity" * s."ItemRate")::numeric AS stock_value
  FROM stock_items s
  WHERE s.company_name = ANY(v_allowed)
    AND s."ItemQuantity" > 0
  ORDER BY stock_value DESC, s."ItemName" ASC;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_combined_unused_ledgers(
  p_company_names text[],
  p_days int DEFAULT 180
)
RETURNS TABLE (
  company_name text,
  customer_name text,
  mobile_number text,
  city text
)
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  v_allowed text[];
BEGIN
  IF p_company_names IS NULL OR cardinality(p_company_names) < 2 THEN
    RETURN;
  END IF;

  v_allowed := public._combined_allowed_companies(p_company_names);
  IF v_allowed IS NULL OR cardinality(v_allowed) < 2 THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT
    c.company_name::text,
    c.customer_name::text,
    c.mobile_number::text,
    c.city::text
  FROM customers c
  WHERE c.company_name = ANY(v_allowed)
    AND c.is_active = true
    AND c.customer_name NOT IN (
      SELECT DISTINCT si.customer_name
      FROM sales_invoices si
      WHERE si.company_name = c.company_name
        AND si.customer_name IS NOT NULL
        AND si.invoice_date >= (CURRENT_DATE - (p_days || ' days')::interval)
    )
  ORDER BY c.customer_name ASC, c.company_name ASC;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_combined_unused_items(
  p_company_names text[],
  p_days int DEFAULT 180
)
RETURNS TABLE (
  company_name text,
  product_name text,
  quantity numeric,
  stock_value numeric
)
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  v_allowed text[];
BEGIN
  IF p_company_names IS NULL OR cardinality(p_company_names) < 2 THEN
    RETURN;
  END IF;

  v_allowed := public._combined_allowed_companies(p_company_names);
  IF v_allowed IS NULL OR cardinality(v_allowed) < 2 THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT
    s.company_name::text,
    s."ItemName"::text AS product_name,
    s."ItemQuantity"::numeric AS quantity,
    (s."ItemQuantity" * s."ItemRate")::numeric AS stock_value
  FROM stock_items s
  WHERE s.company_name = ANY(v_allowed)
    AND s."ItemQuantity" > 0
    AND s."ItemName" NOT IN (
      SELECT DISTINCT i.product_name
      FROM invoice_items i
      JOIN sales_invoices si ON i.invoice_id = si.id
      WHERE si.company_name = s.company_name
        AND si.invoice_date >= (CURRENT_DATE - (p_days || ' days')::interval)
    )
  ORDER BY stock_value DESC, s."ItemName" ASC;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_combined_daily_profit(text[], int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_combined_fast_moving_items(text[], int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_combined_slow_moving_items(text[], int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_combined_high_value_items(text[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_combined_unused_ledgers(text[], int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_combined_unused_items(text[], int) TO authenticated;

COMMIT;
