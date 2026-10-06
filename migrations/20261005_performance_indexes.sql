-- Speed up company-scoped list screens (Ledgers, Stock, Sales, etc.).
-- Fixes statement timeouts from full-table scans / expensive sorts.
-- Safe to re-run (IF NOT EXISTS).

BEGIN;

CREATE INDEX IF NOT EXISTS customers_company_name_name_idx
  ON public.customers (company_name, customer_name);

CREATE INDEX IF NOT EXISTS customers_company_name_ledger_type_idx
  ON public.customers (company_name, ledger_type);

CREATE INDEX IF NOT EXISTS stock_items_company_name_itemname_idx
  ON public.stock_items (company_name, "ItemName");

CREATE INDEX IF NOT EXISTS sales_invoices_company_date_idx
  ON public.sales_invoices (company_name, invoice_date DESC);

CREATE INDEX IF NOT EXISTS purchase_invoices_company_date_idx
  ON public.purchase_invoices (company_name, invoice_date DESC);

CREATE INDEX IF NOT EXISTS outstanding_receivables_company_name_idx
  ON public.outstanding_receivables (company_name, customer_name);

CREATE INDEX IF NOT EXISTS outstanding_payables_company_name_idx
  ON public.outstanding_payables (company_name, customer_name);

CREATE INDEX IF NOT EXISTS invoice_items_company_name_idx
  ON public.invoice_items (company_name);

CREATE INDEX IF NOT EXISTS tally_daybook_company_date_idx
  ON public.tally_daybook (company_name, date DESC);

CREATE INDEX IF NOT EXISTS ledger_bill_settlements_company_date_idx
  ON public.ledger_bill_settlements (company_name, cleared_date DESC);

COMMIT;
