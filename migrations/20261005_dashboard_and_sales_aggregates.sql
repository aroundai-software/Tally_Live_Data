-- Fast dashboard + stock sales aggregates (company-scoped).
-- Apply in Supabase SQL editor / migration runner before relying on RPCs in the app.
-- App falls back to client aggregation if these functions are missing.
BEGIN;

SET LOCAL search_path = public, pg_catalog;

CREATE OR REPLACE FUNCTION get_dashboard_aggregates(
  p_company_name TEXT,
  p_today_start TIMESTAMPTZ,
  p_today_end TIMESTAMPTZ
)
RETURNS JSON
LANGUAGE plpgsql
STABLE
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

CREATE OR REPLACE FUNCTION get_product_sales_totals(p_company_name TEXT)
RETURNS TABLE (product_name TEXT, total_amount NUMERIC)
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
  RETURN QUERY
  SELECT i.product_name::text, SUM(COALESCE(i.total_amount, 0))::numeric
  FROM invoice_items i
  JOIN sales_invoices si ON i.invoice_id = si.id
  WHERE si.company_name = p_company_name
    AND i.product_name IS NOT NULL
    AND btrim(i.product_name) <> ''
  GROUP BY i.product_name
  ORDER BY i.product_name;
END;
$$;

GRANT EXECUTE ON FUNCTION get_dashboard_aggregates(TEXT, TIMESTAMPTZ, TIMESTAMPTZ) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION get_product_sales_totals(TEXT) TO anon, authenticated, service_role;

COMMIT;
