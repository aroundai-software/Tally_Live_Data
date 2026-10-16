-- Lightweight dormant KPIs for Analytics Overview (counts + dead stock sum).
-- Avoids paging full unused lists just to fill three Overview cards.

BEGIN;

SET LOCAL search_path = public, pg_catalog;

CREATE OR REPLACE FUNCTION public.get_dormant_overview_kpis(
  p_company_name text,
  p_ledger_days integer DEFAULT 180,
  p_item_days integer DEFAULT 180
)
RETURNS TABLE (
  unused_ledgers_count bigint,
  unused_items_count bigint,
  dead_stock_value numeric
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  today_ist date := (now() AT TIME ZONE 'Asia/Kolkata')::date;
  ledger_days int := GREATEST(COALESCE(p_ledger_days, 180), 1);
  item_days int := GREATEST(COALESCE(p_item_days, 180), 1);
  ledger_start date := today_ist - (ledger_days - 1);
  item_start date := today_ist - (item_days - 1);
  v_ledgers bigint := 0;
  v_items bigint := 0;
  v_dead numeric := 0;
BEGIN
  IF NOT public._caller_can_access_company(p_company_name) THEN
    RETURN QUERY SELECT 0::bigint, 0::bigint, 0::numeric;
    RETURN;
  END IF;

  SELECT COUNT(*)::bigint INTO v_ledgers
  FROM public.customers c
  WHERE c.is_active = true
    AND c.company_name = btrim(p_company_name)
    AND NOT EXISTS (
      SELECT 1
      FROM public.sales_invoices si
      WHERE si.company_name = c.company_name
        AND si.customer_name = c.customer_name
        AND DATE(si.invoice_date AT TIME ZONE 'Asia/Kolkata') >= ledger_start
        AND DATE(si.invoice_date AT TIME ZONE 'Asia/Kolkata') <= today_ist
    );

  SELECT
    COUNT(*)::bigint,
    COALESCE(SUM(s."ItemQuantity" * s."ItemRate"), 0)::numeric
  INTO v_items, v_dead
  FROM public.stock_items s
  WHERE s.company_name = btrim(p_company_name)
    AND s."ItemQuantity" > 0
    AND NOT EXISTS (
      SELECT 1
      FROM public.invoice_items i
      JOIN public.sales_invoices si ON i.invoice_id = si.id
      WHERE si.company_name = s.company_name
        AND i.product_name = s."ItemName"
        AND DATE(si.invoice_date AT TIME ZONE 'Asia/Kolkata') >= item_start
        AND DATE(si.invoice_date AT TIME ZONE 'Asia/Kolkata') <= today_ist
    );

  RETURN QUERY SELECT v_ledgers, v_items, v_dead;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_combined_dormant_overview_kpis(
  p_company_names text[],
  p_ledger_days integer DEFAULT 180,
  p_item_days integer DEFAULT 180
)
RETURNS TABLE (
  unused_ledgers_count bigint,
  unused_items_count bigint,
  dead_stock_value numeric
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_allowed text[];
  today_ist date := (now() AT TIME ZONE 'Asia/Kolkata')::date;
  ledger_days int := GREATEST(COALESCE(p_ledger_days, 180), 1);
  item_days int := GREATEST(COALESCE(p_item_days, 180), 1);
  ledger_start date := today_ist - (ledger_days - 1);
  item_start date := today_ist - (item_days - 1);
  v_ledgers bigint := 0;
  v_items bigint := 0;
  v_dead numeric := 0;
BEGIN
  IF p_company_names IS NULL OR cardinality(p_company_names) < 2 THEN
    RETURN QUERY SELECT 0::bigint, 0::bigint, 0::numeric;
    RETURN;
  END IF;

  v_allowed := public._combined_allowed_companies(p_company_names);
  IF v_allowed IS NULL OR cardinality(v_allowed) < 2 THEN
    RETURN QUERY SELECT 0::bigint, 0::bigint, 0::numeric;
    RETURN;
  END IF;

  SELECT COUNT(*)::bigint INTO v_ledgers
  FROM public.customers c
  WHERE c.is_active = true
    AND c.company_name = ANY(v_allowed)
    AND NOT EXISTS (
      SELECT 1
      FROM public.sales_invoices si
      WHERE si.company_name = c.company_name
        AND si.customer_name = c.customer_name
        AND DATE(si.invoice_date AT TIME ZONE 'Asia/Kolkata') >= ledger_start
        AND DATE(si.invoice_date AT TIME ZONE 'Asia/Kolkata') <= today_ist
    );

  SELECT
    COUNT(*)::bigint,
    COALESCE(SUM(s."ItemQuantity" * s."ItemRate"), 0)::numeric
  INTO v_items, v_dead
  FROM public.stock_items s
  WHERE s.company_name = ANY(v_allowed)
    AND s."ItemQuantity" > 0
    AND NOT EXISTS (
      SELECT 1
      FROM public.invoice_items i
      JOIN public.sales_invoices si ON i.invoice_id = si.id
      WHERE si.company_name = s.company_name
        AND i.product_name = s."ItemName"
        AND DATE(si.invoice_date AT TIME ZONE 'Asia/Kolkata') >= item_start
        AND DATE(si.invoice_date AT TIME ZONE 'Asia/Kolkata') <= today_ist
    );

  RETURN QUERY SELECT v_ledgers, v_items, v_dead;
END;
$$;

REVOKE ALL ON FUNCTION public.get_dormant_overview_kpis(text, integer, integer) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_combined_dormant_overview_kpis(text[], integer, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_dormant_overview_kpis(text, integer, integer)
  TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_combined_dormant_overview_kpis(text[], integer, integer)
  TO authenticated, service_role;

COMMIT;
