-- Fix Analytics calculation bugs:
-- 1) Single-company slow-moving SUM ignored date/company (bad LEFT JOIN)
-- 2) Inclusive N-day windows (today counts as day 1)
-- 3) IST timezone for combined RPCs (match single-company)
-- 4) Profit cost = StandardCost only (do not treat ItemRate as cost)
-- 5) high_value / unused quantity as numeric

BEGIN;

SET LOCAL search_path = public, pg_catalog;

-- ─── Helpers ───────────────────────────────────────────────────────────────
-- Inclusive lookback: "7 days" = today and the previous 6 days.
-- start_date = today_ist - (p_days - 1)

-- ─── Single-company daily profit ───────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_daily_profit(
  p_company_name text,
  p_days integer DEFAULT 7
)
RETURNS TABLE(sale_date date, total_revenue numeric, estimated_profit numeric)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  today_ist date := (now() AT TIME ZONE 'Asia/Kolkata')::date;
  start_ist date;
  days int := GREATEST(COALESCE(p_days, 7), 1);
BEGIN
  IF NOT public._caller_can_access_company(p_company_name) THEN
    RETURN;
  END IF;

  start_ist := today_ist - (days - 1);

  RETURN QUERY
  SELECT
      DATE(si.invoice_date AT TIME ZONE 'Asia/Kolkata') as sale_date,
      SUM(i.total_amount) as total_revenue,
      SUM(
        (i.unit_price - COALESCE(s."StandardCost", 0)) * i.quantity
      ) as estimated_profit
  FROM public.sales_invoices si
  JOIN public.invoice_items i ON si.id = i.invoice_id
  LEFT JOIN public.stock_items s
    ON i.product_name = s."ItemName"
   AND s.company_name = si.company_name
  WHERE si.company_name = btrim(p_company_name)
    AND DATE(si.invoice_date AT TIME ZONE 'Asia/Kolkata') >= start_ist
    AND DATE(si.invoice_date AT TIME ZONE 'Asia/Kolkata') <= today_ist
  GROUP BY DATE(si.invoice_date AT TIME ZONE 'Asia/Kolkata')
  ORDER BY sale_date DESC;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_fast_moving_items(
  p_company_name text,
  p_days integer DEFAULT 30
)
RETURNS TABLE(product_name text, total_sold numeric)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  today_ist date := (now() AT TIME ZONE 'Asia/Kolkata')::date;
  start_ist date;
  days int := GREATEST(COALESCE(p_days, 30), 1);
BEGIN
  IF NOT public._caller_can_access_company(p_company_name) THEN
    RETURN;
  END IF;

  start_ist := today_ist - (days - 1);

  RETURN QUERY
  SELECT i.product_name, SUM(i.quantity)::NUMERIC as total_sold
  FROM public.invoice_items i
  JOIN public.sales_invoices si ON i.invoice_id = si.id
  WHERE si.company_name = btrim(p_company_name)
    AND DATE(si.invoice_date AT TIME ZONE 'Asia/Kolkata') >= start_ist
    AND DATE(si.invoice_date AT TIME ZONE 'Asia/Kolkata') <= today_ist
    AND i.product_name IS NOT NULL
    AND btrim(i.product_name) <> ''
  GROUP BY i.product_name
  ORDER BY total_sold DESC, i.product_name ASC;
END;
$$;

-- Critical fix: filter sales in a subquery so SUM respects company + date.
CREATE OR REPLACE FUNCTION public.get_slow_moving_items(
  p_company_name text,
  p_days integer DEFAULT 30
)
RETURNS TABLE(product_name text, total_sold numeric)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  today_ist date := (now() AT TIME ZONE 'Asia/Kolkata')::date;
  start_ist date;
  days int := GREATEST(COALESCE(p_days, 30), 1);
BEGIN
  IF NOT public._caller_can_access_company(p_company_name) THEN
    RETURN;
  END IF;

  start_ist := today_ist - (days - 1);

  RETURN QUERY
  SELECT
    s."ItemName" as product_name,
    COALESCE(SUM(i.quantity), 0)::NUMERIC as total_sold
  FROM public.stock_items s
  LEFT JOIN (
    SELECT ii.product_name, si.company_name, ii.quantity
    FROM public.invoice_items ii
    JOIN public.sales_invoices si ON ii.invoice_id = si.id
    WHERE si.company_name = btrim(p_company_name)
      AND DATE(si.invoice_date AT TIME ZONE 'Asia/Kolkata') >= start_ist
      AND DATE(si.invoice_date AT TIME ZONE 'Asia/Kolkata') <= today_ist
  ) i
    ON s."ItemName" = i.product_name
   AND s.company_name = i.company_name
  WHERE s.company_name = btrim(p_company_name)
  GROUP BY s."ItemName"
  HAVING COALESCE(SUM(i.quantity), 0) < 5
  ORDER BY total_sold ASC, s."ItemName" ASC;
END;
$$;

-- quantity must be numeric (stock can be fractional)
DROP FUNCTION IF EXISTS public.get_high_value_items(text);
CREATE OR REPLACE FUNCTION public.get_high_value_items(p_company_name text)
RETURNS TABLE(product_name text, quantity numeric, stock_value numeric)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public._caller_can_access_company(p_company_name) THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT
    s."ItemName" as product_name,
    s."ItemQuantity"::numeric as quantity,
    (s."ItemQuantity" * s."ItemRate")::numeric as stock_value
  FROM public.stock_items s
  WHERE s."ItemQuantity" > 0
    AND s.company_name = btrim(p_company_name)
  ORDER BY stock_value DESC, s."ItemName" ASC;
END;
$$;

DROP FUNCTION IF EXISTS public.get_unused_items(text, integer);
CREATE OR REPLACE FUNCTION public.get_unused_items(
  p_company_name text,
  p_days integer DEFAULT 180
)
RETURNS TABLE(product_name text, quantity numeric, stock_value numeric)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  today_ist date := (now() AT TIME ZONE 'Asia/Kolkata')::date;
  start_ist date;
  days int := GREATEST(COALESCE(p_days, 180), 1);
BEGIN
  IF NOT public._caller_can_access_company(p_company_name) THEN
    RETURN;
  END IF;

  start_ist := today_ist - (days - 1);

  RETURN QUERY
  SELECT
    s."ItemName" as product_name,
    s."ItemQuantity"::numeric as quantity,
    (s."ItemQuantity" * s."ItemRate")::numeric as stock_value
  FROM public.stock_items s
  WHERE s."ItemQuantity" > 0
    AND s.company_name = btrim(p_company_name)
    AND s."ItemName" NOT IN (
      SELECT DISTINCT i.product_name
      FROM public.invoice_items i
      JOIN public.sales_invoices si ON i.invoice_id = si.id
      WHERE si.company_name = btrim(p_company_name)
        AND DATE(si.invoice_date AT TIME ZONE 'Asia/Kolkata') >= start_ist
        AND DATE(si.invoice_date AT TIME ZONE 'Asia/Kolkata') <= today_ist
        AND i.product_name IS NOT NULL
    )
  ORDER BY stock_value DESC, s."ItemName" ASC;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_unused_ledgers(
  p_company_name text,
  p_days integer DEFAULT 180
)
RETURNS TABLE(customer_name text, mobile_number text, city text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  today_ist date := (now() AT TIME ZONE 'Asia/Kolkata')::date;
  start_ist date;
  days int := GREATEST(COALESCE(p_days, 180), 1);
BEGIN
  IF NOT public._caller_can_access_company(p_company_name) THEN
    RETURN;
  END IF;

  start_ist := today_ist - (days - 1);

  RETURN QUERY
  SELECT c.customer_name, c.mobile_number, c.city
  FROM public.customers c
  WHERE c.is_active = true
    AND c.company_name = btrim(p_company_name)
    AND c.customer_name NOT IN (
      SELECT DISTINCT si.customer_name
      FROM public.sales_invoices si
      WHERE si.company_name = btrim(p_company_name)
        AND DATE(si.invoice_date AT TIME ZONE 'Asia/Kolkata') >= start_ist
        AND DATE(si.invoice_date AT TIME ZONE 'Asia/Kolkata') <= today_ist
        AND si.customer_name IS NOT NULL
    )
  ORDER BY c.customer_name ASC;
END;
$$;

-- ─── Combined RPCs: IST + inclusive window + StandardCost-only profit ──────
CREATE OR REPLACE FUNCTION public.get_combined_daily_profit(
  p_company_names text[],
  p_days int DEFAULT 7
)
RETURNS TABLE (sale_date date, total_revenue numeric, estimated_profit numeric)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_allowed text[];
  today_ist date := (now() AT TIME ZONE 'Asia/Kolkata')::date;
  start_ist date;
  days int := GREATEST(COALESCE(p_days, 7), 1);
BEGIN
  IF p_company_names IS NULL OR cardinality(p_company_names) < 2 THEN
    RETURN;
  END IF;

  v_allowed := public._combined_allowed_companies(p_company_names);
  IF v_allowed IS NULL OR cardinality(v_allowed) < 2 THEN
    RETURN;
  END IF;

  start_ist := today_ist - (days - 1);

  RETURN QUERY
  SELECT
    DATE(si.invoice_date AT TIME ZONE 'Asia/Kolkata') AS sale_date,
    SUM(i.total_amount)::numeric AS total_revenue,
    SUM(
      (i.unit_price - COALESCE(s."StandardCost", 0)) * i.quantity
    )::numeric AS estimated_profit
  FROM public.sales_invoices si
  JOIN public.invoice_items i ON si.id = i.invoice_id
  LEFT JOIN public.stock_items s
    ON i.product_name = s."ItemName"
   AND s.company_name = si.company_name
  WHERE si.company_name = ANY(v_allowed)
    AND DATE(si.invoice_date AT TIME ZONE 'Asia/Kolkata') >= start_ist
    AND DATE(si.invoice_date AT TIME ZONE 'Asia/Kolkata') <= today_ist
  GROUP BY DATE(si.invoice_date AT TIME ZONE 'Asia/Kolkata')
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
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_allowed text[];
  today_ist date := (now() AT TIME ZONE 'Asia/Kolkata')::date;
  start_ist date;
  days int := GREATEST(COALESCE(p_days, 30), 1);
BEGIN
  IF p_company_names IS NULL OR cardinality(p_company_names) < 2 THEN
    RETURN;
  END IF;

  v_allowed := public._combined_allowed_companies(p_company_names);
  IF v_allowed IS NULL OR cardinality(v_allowed) < 2 THEN
    RETURN;
  END IF;

  start_ist := today_ist - (days - 1);

  RETURN QUERY
  SELECT
    i.product_name::text,
    SUM(i.quantity)::numeric AS total_sold
  FROM public.invoice_items i
  JOIN public.sales_invoices si ON i.invoice_id = si.id
  WHERE si.company_name = ANY(v_allowed)
    AND DATE(si.invoice_date AT TIME ZONE 'Asia/Kolkata') >= start_ist
    AND DATE(si.invoice_date AT TIME ZONE 'Asia/Kolkata') <= today_ist
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
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_allowed text[];
  today_ist date := (now() AT TIME ZONE 'Asia/Kolkata')::date;
  start_ist date;
  days int := GREATEST(COALESCE(p_days, 30), 1);
BEGIN
  IF p_company_names IS NULL OR cardinality(p_company_names) < 2 THEN
    RETURN;
  END IF;

  v_allowed := public._combined_allowed_companies(p_company_names);
  IF v_allowed IS NULL OR cardinality(v_allowed) < 2 THEN
    RETURN;
  END IF;

  start_ist := today_ist - (days - 1);

  RETURN QUERY
  SELECT
    s."ItemName"::text AS product_name,
    COALESCE(SUM(i.quantity), 0)::numeric AS total_sold
  FROM public.stock_items s
  LEFT JOIN (
    SELECT ii.product_name, si.company_name, ii.quantity
    FROM public.invoice_items ii
    JOIN public.sales_invoices si ON ii.invoice_id = si.id
    WHERE si.company_name = ANY(v_allowed)
      AND DATE(si.invoice_date AT TIME ZONE 'Asia/Kolkata') >= start_ist
      AND DATE(si.invoice_date AT TIME ZONE 'Asia/Kolkata') <= today_ist
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
SECURITY DEFINER
SET search_path = public
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
  FROM public.stock_items s
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
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_allowed text[];
  today_ist date := (now() AT TIME ZONE 'Asia/Kolkata')::date;
  start_ist date;
  days int := GREATEST(COALESCE(p_days, 180), 1);
BEGIN
  IF p_company_names IS NULL OR cardinality(p_company_names) < 2 THEN
    RETURN;
  END IF;

  v_allowed := public._combined_allowed_companies(p_company_names);
  IF v_allowed IS NULL OR cardinality(v_allowed) < 2 THEN
    RETURN;
  END IF;

  start_ist := today_ist - (days - 1);

  RETURN QUERY
  SELECT
    c.company_name::text,
    c.customer_name::text,
    c.mobile_number::text,
    c.city::text
  FROM public.customers c
  WHERE c.company_name = ANY(v_allowed)
    AND c.is_active = true
    AND NOT EXISTS (
      SELECT 1
      FROM public.sales_invoices si
      WHERE si.company_name = c.company_name
        AND si.customer_name = c.customer_name
        AND DATE(si.invoice_date AT TIME ZONE 'Asia/Kolkata') >= start_ist
        AND DATE(si.invoice_date AT TIME ZONE 'Asia/Kolkata') <= today_ist
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
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_allowed text[];
  today_ist date := (now() AT TIME ZONE 'Asia/Kolkata')::date;
  start_ist date;
  days int := GREATEST(COALESCE(p_days, 180), 1);
BEGIN
  IF p_company_names IS NULL OR cardinality(p_company_names) < 2 THEN
    RETURN;
  END IF;

  v_allowed := public._combined_allowed_companies(p_company_names);
  IF v_allowed IS NULL OR cardinality(v_allowed) < 2 THEN
    RETURN;
  END IF;

  start_ist := today_ist - (days - 1);

  RETURN QUERY
  SELECT
    s.company_name::text,
    s."ItemName"::text AS product_name,
    s."ItemQuantity"::numeric AS quantity,
    (s."ItemQuantity" * s."ItemRate")::numeric AS stock_value
  FROM public.stock_items s
  WHERE s.company_name = ANY(v_allowed)
    AND s."ItemQuantity" > 0
    AND NOT EXISTS (
      SELECT 1
      FROM public.invoice_items i
      JOIN public.sales_invoices si ON i.invoice_id = si.id
      WHERE si.company_name = s.company_name
        AND i.product_name = s."ItemName"
        AND DATE(si.invoice_date AT TIME ZONE 'Asia/Kolkata') >= start_ist
        AND DATE(si.invoice_date AT TIME ZONE 'Asia/Kolkata') <= today_ist
    )
  ORDER BY stock_value DESC, s."ItemName" ASC;
END;
$$;

REVOKE ALL ON FUNCTION public.get_daily_profit(text, integer) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_fast_moving_items(text, integer) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_slow_moving_items(text, integer) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_high_value_items(text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_unused_items(text, integer) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_unused_ledgers(text, integer) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_combined_daily_profit(text[], int) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_combined_fast_moving_items(text[], int) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_combined_slow_moving_items(text[], int) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_combined_high_value_items(text[]) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_combined_unused_ledgers(text[], int) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_combined_unused_items(text[], int) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.get_daily_profit(text, integer) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_fast_moving_items(text, integer) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_slow_moving_items(text, integer) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_high_value_items(text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_unused_items(text, integer) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_unused_ledgers(text, integer) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_combined_daily_profit(text[], int) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_combined_fast_moving_items(text[], int) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_combined_slow_moving_items(text[], int) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_combined_high_value_items(text[]) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_combined_unused_ledgers(text[], int) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_combined_unused_items(text[], int) TO authenticated, service_role;

COMMIT;
