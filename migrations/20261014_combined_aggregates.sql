-- Combined mode: multi-company dashboard + product sales aggregates.
-- Security: intersect requested companies with user_companies for auth.uid()
-- and require users.is_combined_reports_enabled = true.
-- App falls back to client fan-out if these functions are missing.
BEGIN;

SET LOCAL search_path = public, pg_catalog;

CREATE OR REPLACE FUNCTION public._combined_allowed_companies(p_company_names text[])
RETURNS text[]
LANGUAGE sql
STABLE
AS $$
  SELECT COALESCE(array_agg(uc.company_name ORDER BY uc.company_name), ARRAY[]::text[])
  FROM public.user_companies uc
  WHERE uc.user_id = auth.uid()
    AND uc.company_name = ANY(p_company_names)
    AND EXISTS (
      SELECT 1
      FROM public.users u
      WHERE u.id = auth.uid()
        AND u.is_combined_reports_enabled = true
    );
$$;

CREATE OR REPLACE FUNCTION public.get_combined_dashboard_aggregates(
  p_company_names text[],
  p_today_start timestamptz,
  p_today_end timestamptz
)
RETURNS json
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  v_allowed text[];
  result json;
BEGIN
  IF p_company_names IS NULL OR cardinality(p_company_names) < 2 THEN
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

  v_allowed := public._combined_allowed_companies(p_company_names);
  IF v_allowed IS NULL OR cardinality(v_allowed) < 2 THEN
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

  SELECT json_build_object(
    'stock_value', COALESCE((
      SELECT SUM(COALESCE("ItemQuantity", 0)::numeric * COALESCE("ItemRate", 0)::numeric)
      FROM stock_items WHERE company_name = ANY(v_allowed)
    ), 0),
    'stock_count', COALESCE((
      SELECT COUNT(*)::int FROM stock_items WHERE company_name = ANY(v_allowed)
    ), 0),
    'receivables', COALESCE((
      SELECT SUM(ABS(CASE WHEN COALESCE(closing_balance, 0) <> 0 THEN closing_balance ELSE amount END))
      FROM outstanding_receivables WHERE company_name = ANY(v_allowed)
    ), 0),
    'overdue_receivables', COALESCE((
      SELECT SUM(ABS(CASE WHEN COALESCE(closing_balance, 0) <> 0 THEN closing_balance ELSE amount END))
      FROM outstanding_receivables
      WHERE company_name = ANY(v_allowed) AND COALESCE(overdue_days, 0) > 0
    ), 0),
    'payables', COALESCE((
      SELECT SUM(ABS(CASE WHEN COALESCE(closing_balance, 0) <> 0 THEN closing_balance ELSE amount END))
      FROM outstanding_payables WHERE company_name = ANY(v_allowed)
    ), 0),
    'overdue_payables', COALESCE((
      SELECT SUM(ABS(CASE WHEN COALESCE(closing_balance, 0) <> 0 THEN closing_balance ELSE amount END))
      FROM outstanding_payables
      WHERE company_name = ANY(v_allowed) AND COALESCE(overdue_days, 0) > 0
    ), 0),
    'sales', COALESCE((
      SELECT SUM(COALESCE(total_amount, 0)) FROM sales_invoices WHERE company_name = ANY(v_allowed)
    ), 0),
    'sales_count', COALESCE((
      SELECT COUNT(*)::int FROM sales_invoices WHERE company_name = ANY(v_allowed)
    ), 0),
    'purchases', COALESCE((
      SELECT SUM(COALESCE(total_amount, 0)) FROM purchase_invoices WHERE company_name = ANY(v_allowed)
    ), 0),
    'purchase_count', COALESCE((
      SELECT COUNT(*)::int FROM purchase_invoices WHERE company_name = ANY(v_allowed)
    ), 0),
    'todays_sales', COALESCE((
      SELECT SUM(COALESCE(total_amount, 0)) FROM sales_invoices
      WHERE company_name = ANY(v_allowed)
        AND invoice_date >= p_today_start AND invoice_date < p_today_end
    ), 0),
    'todays_sales_count', COALESCE((
      SELECT COUNT(*)::int FROM sales_invoices
      WHERE company_name = ANY(v_allowed)
        AND invoice_date >= p_today_start AND invoice_date < p_today_end
    ), 0),
    'todays_purchases', COALESCE((
      SELECT SUM(COALESCE(total_amount, 0)) FROM purchase_invoices
      WHERE company_name = ANY(v_allowed)
        AND invoice_date >= p_today_start AND invoice_date < p_today_end
    ), 0),
    'todays_purchases_count', COALESCE((
      SELECT COUNT(*)::int FROM purchase_invoices
      WHERE company_name = ANY(v_allowed)
        AND invoice_date >= p_today_start AND invoice_date < p_today_end
    ), 0),
    'daybook_inflow', COALESCE((
      SELECT SUM(ABS(amount)) FROM tally_daybook
      WHERE company_name = ANY(v_allowed)
        AND guid NOT ILIKE '%#sub#%'
        AND lower(voucher_type) = 'receipt'
        AND date >= p_today_start AND date < p_today_end
    ), 0),
    'daybook_outflow', COALESCE((
      SELECT SUM(ABS(amount)) FROM tally_daybook
      WHERE company_name = ANY(v_allowed)
        AND guid NOT ILIKE '%#sub#%'
        AND lower(voucher_type) = 'payment'
        AND date >= p_today_start AND date < p_today_end
    ), 0),
    'cash', COALESCE((
      SELECT SUM(COALESCE(closing_balance, 0)) FROM customers
      WHERE company_name = ANY(v_allowed)
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
      WHERE company_name = ANY(v_allowed)
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

CREATE OR REPLACE FUNCTION public.get_combined_product_sales_totals(p_company_names text[])
RETURNS TABLE (company_name text, product_name text, total_amount numeric)
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
    si.company_name::text,
    i.product_name::text,
    SUM(COALESCE(i.total_amount, 0))::numeric
  FROM invoice_items i
  JOIN sales_invoices si ON i.invoice_id = si.id
  WHERE si.company_name = ANY(v_allowed)
    AND i.product_name IS NOT NULL
    AND btrim(i.product_name) <> ''
  GROUP BY si.company_name, i.product_name
  ORDER BY si.company_name, i.product_name;
END;
$$;

GRANT EXECUTE ON FUNCTION public._combined_allowed_companies(text[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_combined_dashboard_aggregates(text[], timestamptz, timestamptz) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_combined_product_sales_totals(text[]) TO authenticated;

COMMIT;
