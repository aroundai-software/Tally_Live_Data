-- Gate single-company aggregate/analytics RPCs: caller must be linked to the
-- company (or super_admin / service_role). Revoke anon EXECUTE.

BEGIN;

CREATE OR REPLACE FUNCTION public._caller_can_access_company(p_company_name text)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF public._jwt_is_service_role() THEN
    RETURN true;
  END IF;

  IF auth.uid() IS NULL THEN
    RETURN false;
  END IF;

  IF p_company_name IS NULL OR btrim(p_company_name) = '' THEN
    RETURN false;
  END IF;

  IF public._caller_is_super_admin() THEN
    RETURN true;
  END IF;

  RETURN EXISTS (
    SELECT 1
    FROM public.user_companies uc
    WHERE uc.user_id = auth.uid()
      AND uc.company_name = btrim(p_company_name)
  )
  OR EXISTS (
    SELECT 1
    FROM public.users u
    WHERE u.id = auth.uid()
      AND coalesce(u.company_name, '') = btrim(p_company_name)
  );
END;
$$;

REVOKE ALL ON FUNCTION public._caller_can_access_company(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public._caller_can_access_company(text)
  TO authenticated, service_role;

-- ─── Dashboard aggregates ───────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_dashboard_aggregates(
  p_company_name TEXT,
  p_today_start TIMESTAMPTZ,
  p_today_end TIMESTAMPTZ
)
RETURNS JSON
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  result JSON;
BEGIN
  IF p_company_name IS NULL OR btrim(p_company_name) = '' THEN
    RETURN json_build_object(
      'stock_value', 0, 'stock_count', 0,
      'receivables', 0, 'overdue_receivables', 0,
      'payables', 0, 'overdue_payables', 0,
      'sales', 0, 'sales_count', 0,
      'purchases', 0, 'purchase_count', 0,
      'todays_sales', 0, 'todays_sales_count', 0,
      'todays_purchases', 0, 'todays_purchases_count', 0,
      'daybook_inflow', 0, 'daybook_outflow', 0,
      'cash', 0, 'bank', 0
    );
  END IF;

  IF NOT public._caller_can_access_company(p_company_name) THEN
    RAISE EXCEPTION 'Not allowed to access this company'
      USING ERRCODE = '42501';
  END IF;

  SELECT json_build_object(
    'stock_value', COALESCE((
      SELECT SUM(COALESCE("ItemQuantity", 0)::numeric * COALESCE("ItemRate", 0)::numeric)
      FROM stock_items WHERE company_name = p_company_name
    ), 0),
    'stock_count', COALESCE((
      SELECT COUNT(*)::int FROM stock_items WHERE company_name = p_company_name
    ), 0),
    'receivables', COALESCE((
      SELECT SUM(ABS(CASE WHEN COALESCE(closing_balance, 0) <> 0 THEN closing_balance ELSE amount END))
      FROM outstanding_receivables WHERE company_name = p_company_name
    ), 0),
    'overdue_receivables', COALESCE((
      SELECT SUM(ABS(CASE WHEN COALESCE(closing_balance, 0) <> 0 THEN closing_balance ELSE amount END))
      FROM outstanding_receivables
      WHERE company_name = p_company_name AND COALESCE(overdue_days, 0) > 0
    ), 0),
    'payables', COALESCE((
      SELECT SUM(ABS(CASE WHEN COALESCE(closing_balance, 0) <> 0 THEN closing_balance ELSE amount END))
      FROM outstanding_payables WHERE company_name = p_company_name
    ), 0),
    'overdue_payables', COALESCE((
      SELECT SUM(ABS(CASE WHEN COALESCE(closing_balance, 0) <> 0 THEN closing_balance ELSE amount END))
      FROM outstanding_payables
      WHERE company_name = p_company_name AND COALESCE(overdue_days, 0) > 0
    ), 0),
    'sales', COALESCE((
      SELECT SUM(COALESCE(total_amount, 0)) FROM sales_invoices WHERE company_name = p_company_name
    ), 0),
    'sales_count', COALESCE((
      SELECT COUNT(*)::int FROM sales_invoices WHERE company_name = p_company_name
    ), 0),
    'purchases', COALESCE((
      SELECT SUM(COALESCE(total_amount, 0)) FROM purchase_invoices WHERE company_name = p_company_name
    ), 0),
    'purchase_count', COALESCE((
      SELECT COUNT(*)::int FROM purchase_invoices WHERE company_name = p_company_name
    ), 0),
    'todays_sales', COALESCE((
      SELECT SUM(COALESCE(total_amount, 0)) FROM sales_invoices
      WHERE company_name = p_company_name
        AND invoice_date >= p_today_start AND invoice_date < p_today_end
    ), 0),
    'todays_sales_count', COALESCE((
      SELECT COUNT(*)::int FROM sales_invoices
      WHERE company_name = p_company_name
        AND invoice_date >= p_today_start AND invoice_date < p_today_end
    ), 0),
    'todays_purchases', COALESCE((
      SELECT SUM(COALESCE(total_amount, 0)) FROM purchase_invoices
      WHERE company_name = p_company_name
        AND invoice_date >= p_today_start AND invoice_date < p_today_end
    ), 0),
    'todays_purchases_count', COALESCE((
      SELECT COUNT(*)::int FROM purchase_invoices
      WHERE company_name = p_company_name
        AND invoice_date >= p_today_start AND invoice_date < p_today_end
    ), 0),
    'daybook_inflow', COALESCE((
      SELECT SUM(ABS(amount)) FROM tally_daybook
      WHERE company_name = p_company_name
        AND guid NOT ILIKE '%#sub#%'
        AND lower(voucher_type) = 'receipt'
        AND date >= p_today_start AND date < p_today_end
    ), 0),
    'daybook_outflow', COALESCE((
      SELECT SUM(ABS(amount)) FROM tally_daybook
      WHERE company_name = p_company_name
        AND guid NOT ILIKE '%#sub#%'
        AND lower(voucher_type) = 'payment'
        AND date >= p_today_start AND date < p_today_end
    ), 0),
    'cash', COALESCE((
      SELECT SUM(COALESCE(closing_balance, 0)) FROM customers
      WHERE company_name = p_company_name
        AND (
          ledger_type ILIKE '%Cash%'
          OR lower(customer_name) LIKE 'cash%'
          OR lower(customer_name) LIKE 'petty cash%'
        )
        AND NOT (ledger_type ILIKE '%charge%' OR ledger_type ILIKE '%expense%')
        AND NOT (customer_name ILIKE '%charges%' OR customer_name ILIKE '%vetting%')
        AND lower(btrim(customer_name)) NOT IN ('opening balance', 'closing balance')
        AND (
          ledger_type ILIKE 'Cash-in-Hand'
          OR ledger_type ILIKE 'Cash'
          OR ledger_type ILIKE '%Cash%'
        )
    ), 0),
    'bank', COALESCE((
      SELECT SUM(COALESCE(closing_balance, 0)) FROM customers
      WHERE company_name = p_company_name
        AND ledger_type ILIKE '%Bank%'
        AND NOT (ledger_type ILIKE '%charge%' OR ledger_type ILIKE '%expense%')
        AND NOT (customer_name ILIKE '%charges%' OR customer_name ILIKE '%vetting%')
        AND lower(btrim(customer_name)) NOT IN ('opening balance', 'closing balance')
        AND (
          ledger_type ILIKE 'Bank Accounts'
          OR ledger_type ILIKE 'Bank OD A/c'
          OR ledger_type ILIKE 'Bank OCC A/c'
          OR ledger_type ILIKE '%Bank%'
        )
    ), 0)
  ) INTO result;

  RETURN result;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_product_sales_totals(p_company_name TEXT)
RETURNS TABLE (product_name TEXT, total_amount NUMERIC)
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
BEGIN
  IF NOT public._caller_can_access_company(p_company_name) THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT i.product_name::text, SUM(COALESCE(i.total_amount, 0))::numeric
  FROM invoice_items i
  JOIN sales_invoices si ON i.invoice_id = si.id
  WHERE si.company_name = btrim(p_company_name)
    AND i.product_name IS NOT NULL
    AND btrim(i.product_name) <> ''
  GROUP BY i.product_name
  ORDER BY i.product_name;
END;
$$;

-- ─── Analytics (were SECURITY DEFINER with optional company = all) ──
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
  today_ist DATE := (now() AT TIME ZONE 'Asia/Kolkata')::date;
BEGIN
  IF NOT public._caller_can_access_company(p_company_name) THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT
      DATE(si.invoice_date AT TIME ZONE 'Asia/Kolkata') as sale_date,
      SUM(i.total_amount) as total_revenue,
      SUM( (i.unit_price - COALESCE(s."StandardCost", s."ItemRate", 0)) * i.quantity ) as estimated_profit
  FROM public.sales_invoices si
  JOIN public.invoice_items i ON si.id = i.invoice_id
  LEFT JOIN public.stock_items s
    ON i.product_name = s."ItemName"
   AND s.company_name = si.company_name
  WHERE si.invoice_date >= (today_ist - (p_days || ' days')::interval)
    AND si.company_name = btrim(p_company_name)
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
  today_ist DATE := (now() AT TIME ZONE 'Asia/Kolkata')::date;
BEGIN
  IF NOT public._caller_can_access_company(p_company_name) THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT i.product_name, SUM(i.quantity)::NUMERIC as total_sold
  FROM public.invoice_items i
  JOIN public.sales_invoices si ON i.invoice_id = si.id
  WHERE si.invoice_date >= (today_ist - (p_days || ' days')::interval)
    AND si.company_name = btrim(p_company_name)
  GROUP BY i.product_name
  ORDER BY total_sold DESC;
END;
$$;

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
  today_ist DATE := (now() AT TIME ZONE 'Asia/Kolkata')::date;
BEGIN
  IF NOT public._caller_can_access_company(p_company_name) THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT s."ItemName" as product_name, COALESCE(SUM(i.quantity), 0)::NUMERIC as total_sold
  FROM public.stock_items s
  LEFT JOIN public.invoice_items i ON s."ItemName" = i.product_name
  LEFT JOIN public.sales_invoices si
    ON i.invoice_id = si.id
   AND si.company_name = s.company_name
   AND si.invoice_date >= (today_ist - (p_days || ' days')::interval)
  WHERE s.company_name = btrim(p_company_name)
  GROUP BY s."ItemName"
  HAVING COALESCE(SUM(i.quantity), 0) < 5
  ORDER BY total_sold ASC;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_high_value_items(p_company_name text)
RETURNS TABLE(product_name text, quantity integer, stock_value numeric)
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
BEGIN
  IF NOT public._caller_can_access_company(p_company_name) THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT s."ItemName" as product_name, s."ItemQuantity" as quantity,
         (s."ItemQuantity" * s."ItemRate") as stock_value
  FROM stock_items s
  WHERE s."ItemQuantity" > 0
    AND s.company_name = btrim(p_company_name)
  ORDER BY stock_value DESC;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_unused_items(
  p_company_name text,
  p_days integer DEFAULT 180
)
RETURNS TABLE(product_name text, quantity integer, stock_value numeric)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  today_ist DATE := (now() AT TIME ZONE 'Asia/Kolkata')::date;
BEGIN
  IF NOT public._caller_can_access_company(p_company_name) THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT s."ItemName" as product_name, s."ItemQuantity" as quantity,
         (s."ItemQuantity" * s."ItemRate") as stock_value
  FROM public.stock_items s
  WHERE s."ItemQuantity" > 0
    AND s.company_name = btrim(p_company_name)
    AND s."ItemName" NOT IN (
      SELECT DISTINCT i.product_name
      FROM public.invoice_items i
      JOIN public.sales_invoices si ON i.invoice_id = si.id
      WHERE si.invoice_date >= (today_ist - (p_days || ' days')::interval)
        AND si.company_name = btrim(p_company_name)
        AND i.product_name IS NOT NULL
    )
  ORDER BY stock_value DESC;
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
  today_ist DATE := (now() AT TIME ZONE 'Asia/Kolkata')::date;
BEGIN
  IF NOT public._caller_can_access_company(p_company_name) THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT c.customer_name, c.mobile_number, c.city
  FROM public.customers c
  WHERE c.is_active = true
    AND c.company_name = btrim(p_company_name)
    AND c.customer_name NOT IN (
      SELECT DISTINCT si.customer_name
      FROM public.sales_invoices si
      WHERE si.invoice_date >= (today_ist - (p_days || ' days')::interval)
        AND si.company_name = btrim(p_company_name)
        AND si.customer_name IS NOT NULL
    );
END;
$$;

-- Lock down grants: no anon
REVOKE ALL ON FUNCTION public.get_dashboard_aggregates(text, timestamptz, timestamptz) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_product_sales_totals(text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_daily_profit(text, integer) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_fast_moving_items(text, integer) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_slow_moving_items(text, integer) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_high_value_items(text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_unused_items(text, integer) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_unused_ledgers(text, integer) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.get_dashboard_aggregates(text, timestamptz, timestamptz)
  TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_product_sales_totals(text)
  TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_daily_profit(text, integer)
  TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_fast_moving_items(text, integer)
  TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_slow_moving_items(text, integer)
  TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_high_value_items(text)
  TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_unused_items(text, integer)
  TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_unused_ledgers(text, integer)
  TO authenticated, service_role;

COMMIT;
