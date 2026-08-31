-- 1. Tally Companies Table
CREATE TABLE public.tally_companies (
  id uuid not null default gen_random_uuid (),
  company_name text not null,
  company_number text null,
  guid text not null,
  master_id text null,
  address_line1 text null,
  address_line2 text null,
  city text null,
  emirate text null,
  country text null default 'UAE'::text,
  pin_code text null,
  mobile_number text null,
  phone_number text null,
  email text null,
  website text null,
  trn_number text null,
  trade_license_number text null,
  trade_license_expiry date null,
  base_currency text null default 'AED'::text,
  books_from date null,
  financial_year_from date null,
  is_active boolean null default true,
  sync_enabled boolean null default true,
  created_at timestamp with time zone null default now(),
  updated_at timestamp with time zone null default now(),
  constraint tally_companies_pkey primary key (id),
  constraint tally_companies_company_number_key unique (company_number),
  constraint tally_companies_guid_key unique (guid),
  constraint tally_companies_trn_number_key unique (trn_number)
) TABLESPACE pg_default;

-- 2. Customers Table
CREATE TABLE customers (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  customer_name TEXT NOT NULL,
  customer_category_name TEXT,
  address TEXT,
  city TEXT,
  state TEXT,
  pincode TEXT,
  country TEXT,
  contact_person TEXT,
  mobile_number TEXT,
  email TEXT,
  gst_number TEXT,
  pan_number TEXT,
  mailing_name TEXT,
  alias TEXT,
  credit_period TEXT,
  credit_limit NUMERIC,
  opening_balance NUMERIC DEFAULT 0,
  customer_discount_percentage NUMERIC DEFAULT 0,
  company_name TEXT,
  guid TEXT,
  master_id TEXT,
  is_active BOOLEAN DEFAULT TRUE,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()),
  UNIQUE (guid)
);

-- 3. Stock Items Table
CREATE TABLE stock_items (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  "ItemName" TEXT NOT NULL,
  "PartNumber" TEXT,
  "ItemUnit" TEXT,
  "ItemAltUnit" TEXT,
  "ItemParent" TEXT,
  "Category" TEXT,
  "Alias" TEXT,
  "hsn" TEXT,
  "Description" TEXT,
  "ItemQuantity" INTEGER DEFAULT 0,
  "ItemRate" NUMERIC DEFAULT 0,
  "GstRate" NUMERIC DEFAULT 0,
  "MRP" NUMERIC DEFAULT 0,
  "StandardCost" NUMERIC,
  "StandardPrice" NUMERIC,
  "OpeningValue" NUMERIC,
  "floor_rate" NUMERIC,
  "offer_discount_percentage" NUMERIC DEFAULT 0,
  is_active BOOLEAN DEFAULT TRUE,
  image_url TEXT,
  company_name TEXT,
  guid TEXT,
  master_id TEXT,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()),
  UNIQUE (guid)
);

-- 4. Sales Invoices Table
CREATE TABLE sales_invoices (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  invoice_number TEXT NOT NULL,
  invoice_date TIMESTAMP WITH TIME ZONE,
  customer_name TEXT,
  customer_id UUID REFERENCES customers(id),
  total_amount NUMERIC DEFAULT 0,
  gst_amount NUMERIC DEFAULT 0,
  net_amount NUMERIC DEFAULT 0,
  discount_amount NUMERIC DEFAULT 0,
  discount_percentage NUMERIC DEFAULT 0,
  subtotal_before_discount NUMERIC DEFAULT 0,
  status TEXT,
  "Type" TEXT,
  notes TEXT,
  remarks TEXT,
  shipping_address TEXT,
  company_name TEXT,
  customer_category_name TEXT,
  round_off NUMERIC,
  synced_to_tally BOOLEAN DEFAULT FALSE,
  guid TEXT,
  master_id TEXT,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()),
  UNIQUE (guid)
);

-- 5. Invoice Items Table
CREATE TABLE invoice_items (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  invoice_id UUID REFERENCES sales_invoices(id) ON DELETE CASCADE,
  product_name TEXT NOT NULL,
  product_code TEXT,
  quantity INTEGER DEFAULT 0,
  free_quantity INTEGER DEFAULT 0,
  unit_price NUMERIC DEFAULT 0,
  gst_rate NUMERIC DEFAULT 0,
  gst_amount NUMERIC DEFAULT 0,
  total_amount NUMERIC DEFAULT 0,
  discount_percentage NUMERIC DEFAULT 0,
  discount_amount NUMERIC DEFAULT 0,
  category_discount_percentage NUMERIC DEFAULT 0,
  company_name TEXT,
  guid TEXT,
  master_id TEXT,
  UNIQUE (guid)
);

-- 6. Outstanding Receivables Table
CREATE TABLE outstanding_receivables (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  customer_name TEXT NOT NULL,
  date TIMESTAMP WITH TIME ZONE,
  invoicenumber TEXT,
  opening_balance NUMERIC DEFAULT 0,
  closing_balance NUMERIC DEFAULT 0,
  amount NUMERIC DEFAULT 0,
  duedate TIMESTAMP WITH TIME ZONE,
  overdue_days INTEGER,
  bill_type TEXT,
  company_name TEXT,
  guid TEXT,
  master_id TEXT,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()),
  UNIQUE (guid)
);

-- 7. Outstanding Payables Table
CREATE TABLE outstanding_payables (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  customer_name TEXT NOT NULL,
  date TIMESTAMP WITH TIME ZONE,
  invoicenumber TEXT,
  opening_balance NUMERIC DEFAULT 0,
  closing_balance NUMERIC DEFAULT 0,
  amount NUMERIC DEFAULT 0,
  duedate TIMESTAMP WITH TIME ZONE,
  overdue_days INTEGER,
  bill_type TEXT,
  company_name TEXT,
  guid TEXT,
  master_id TEXT,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()),
  UNIQUE (guid)
);

-- 8. Company Name Backfill Trigger Function
CREATE OR REPLACE FUNCTION set_company_name_from_guid()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.guid IS NOT NULL THEN
    SELECT company_name INTO NEW.company_name
    FROM tally_companies
    WHERE guid = NEW.guid;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 9. Trigger for outstanding_payables
DROP TRIGGER IF EXISTS trigger_set_company_name_payables ON outstanding_payables;
CREATE TRIGGER trigger_set_company_name_payables
BEFORE INSERT OR UPDATE ON outstanding_payables
FOR EACH ROW
EXECUTE FUNCTION set_company_name_from_guid();

-- 10. Trigger for outstanding_receivables
DROP TRIGGER IF EXISTS trigger_set_company_name_receivables ON outstanding_receivables;
CREATE TRIGGER trigger_set_company_name_receivables
BEFORE INSERT OR UPDATE ON outstanding_receivables
FOR EACH ROW
EXECUTE FUNCTION set_company_name_from_guid();

-- 11. Run these to backfill existing missing data in Supabase!
-- UPDATE outstanding_payables 
-- SET company_name = (SELECT company_name FROM tally_companies WHERE guid = outstanding_payables.guid) 
-- WHERE company_name IS NULL AND guid IS NOT NULL;

-- UPDATE outstanding_receivables 
-- SET company_name = (SELECT company_name FROM tally_companies WHERE guid = outstanding_receivables.guid) 
-- WHERE company_name IS NULL AND guid IS NOT NULL;

-- 12. Tally Daybook Table
CREATE TABLE tally_daybook (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  date TIMESTAMP WITH TIME ZONE,
  voucher_number TEXT,
  voucher_type TEXT,
  ledger_name TEXT,
  amount NUMERIC DEFAULT 0,
  is_debit BOOLEAN,
  narration TEXT,
  company_name TEXT,
  guid TEXT UNIQUE,
  master_id TEXT,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now())
);

-- 13. Reports RPC Functions

-- Fast Moving Items
CREATE OR REPLACE FUNCTION get_fast_moving_items(p_company_name TEXT, p_days INT DEFAULT 30)
RETURNS TABLE (product_name TEXT, total_sold NUMERIC) AS $$
BEGIN
  RETURN QUERY
  SELECT i.product_name, SUM(i.quantity)::NUMERIC as total_sold
  FROM invoice_items i
  JOIN sales_invoices si ON i.invoice_id = si.id
  WHERE si.invoice_date >= (CURRENT_DATE - (p_days || ' days')::interval)
  AND (p_company_name IS NULL OR si.company_name = p_company_name)
  GROUP BY i.product_name
  ORDER BY total_sold DESC;
END;
$$ LANGUAGE plpgsql;

-- Slow Moving Items
CREATE OR REPLACE FUNCTION get_slow_moving_items(p_company_name TEXT, p_days INT DEFAULT 30)
RETURNS TABLE (product_name TEXT, total_sold NUMERIC) AS $$
BEGIN
  RETURN QUERY
  SELECT s."ItemName" as product_name, COALESCE(SUM(i.quantity), 0)::NUMERIC as total_sold
  FROM stock_items s
  LEFT JOIN invoice_items i ON s."ItemName" = i.product_name
  LEFT JOIN sales_invoices si ON i.invoice_id = si.id AND si.invoice_date >= (CURRENT_DATE - (p_days || ' days')::interval)
  WHERE (p_company_name IS NULL OR s.company_name = p_company_name)
  GROUP BY s."ItemName"
  HAVING COALESCE(SUM(i.quantity), 0) < 5
  ORDER BY total_sold ASC;
END;
$$ LANGUAGE plpgsql;

-- High Value Items
CREATE OR REPLACE FUNCTION get_high_value_items(p_company_name TEXT)
RETURNS TABLE (product_name TEXT, quantity INTEGER, stock_value NUMERIC) AS $$
BEGIN
  RETURN QUERY
  SELECT s."ItemName" as product_name, s."ItemQuantity" as quantity, (s."ItemQuantity" * s."ItemRate") as stock_value
  FROM stock_items s
  WHERE s."ItemQuantity" > 0
  AND (p_company_name IS NULL OR s.company_name = p_company_name)
  ORDER BY stock_value DESC;
END;
$$ LANGUAGE plpgsql;

-- Unused Ledgers
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
  )
  AND c.is_active = true
  AND (p_company_name IS NULL OR c.company_name = p_company_name);
END;
$$ LANGUAGE plpgsql;

-- Unused Items
CREATE OR REPLACE FUNCTION get_unused_items(p_company_name TEXT, p_days INT DEFAULT 180)
RETURNS TABLE (product_name TEXT, quantity INTEGER, stock_value NUMERIC) AS $$
BEGIN
  RETURN QUERY
  SELECT s."ItemName" as product_name, s."ItemQuantity" as quantity, (s."ItemQuantity" * s."ItemRate") as stock_value
  FROM stock_items s
  WHERE s."ItemQuantity" > 0
  AND s."ItemName" NOT IN (
      SELECT DISTINCT i.product_name 
      FROM invoice_items i
      JOIN sales_invoices si ON i.invoice_id = si.id
      WHERE si.invoice_date >= (CURRENT_DATE - (p_days || ' days')::interval)
  )
  AND (p_company_name IS NULL OR s.company_name = p_company_name)
  ORDER BY stock_value DESC;
END;
$$ LANGUAGE plpgsql;

-- Daily Profit
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
  LEFT JOIN stock_items s ON i.product_name = s."ItemName"
  WHERE si.invoice_date >= (CURRENT_DATE - (p_days || ' days')::interval)
  AND (p_company_name IS NULL OR si.company_name = p_company_name)
  GROUP BY DATE(si.invoice_date)
  ORDER BY sale_date DESC;
END;
$$ LANGUAGE plpgsql;

-- 14. Company Features and Gating Table
CREATE TABLE IF NOT EXISTS public.company_features (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL UNIQUE,
  company_name text NOT NULL,
  is_dashboard_enabled boolean NOT NULL DEFAULT true,
  is_stock_enabled boolean NOT NULL DEFAULT true,
  is_ledgers_enabled boolean NOT NULL DEFAULT true,
  is_outstanding_enabled boolean NOT NULL DEFAULT true,
  is_sales_enabled boolean NOT NULL DEFAULT true,
  is_purchases_enabled boolean NOT NULL DEFAULT true,
  is_analytics_enabled boolean NOT NULL DEFAULT true,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  CONSTRAINT company_features_pkey PRIMARY KEY (id),
  CONSTRAINT company_features_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.tally_companies(id) ON DELETE CASCADE
);

-- Trigger to automatically populate company_features when a new company is created
CREATE OR REPLACE FUNCTION public.handle_new_company_features()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.company_features (company_id, company_name)
  VALUES (NEW.id, NEW.company_name)
  ON CONFLICT (company_id) DO NOTHING;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Hook trigger to tally_companies table
DROP TRIGGER IF EXISTS on_company_created ON public.tally_companies;
CREATE TRIGGER on_company_created
  AFTER INSERT ON public.tally_companies
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_company_features();


-- 15. Migration: Add Sub-Features Columns to company_features Table
ALTER TABLE public.company_features 
  -- Dashboard sub-features
  ADD COLUMN IF NOT EXISTS is_db_net_position_enabled boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS is_db_summary_cards_enabled boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS is_db_daybook_enabled boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS is_db_quick_actions_enabled boolean NOT NULL DEFAULT true,

  -- Outstanding sub-features
  ADD COLUMN IF NOT EXISTS is_out_receivables_enabled boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS is_out_payables_enabled boolean NOT NULL DEFAULT true,

  -- Reports sub-features
  ADD COLUMN IF NOT EXISTS is_rep_sales_enabled boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS is_rep_purchases_enabled boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS is_rep_ledgers_enabled boolean NOT NULL DEFAULT true,

  -- Stock sub-features
  ADD COLUMN IF NOT EXISTS is_stock_cost_enabled boolean NOT NULL DEFAULT true;

-- 16. Migration: Add dashboard_config JSONB column for individual card/button gating
-- Stores fine-grained visibility settings (individual cards, quick action buttons)
-- without requiring new boolean columns for each new UI element added in future.
ALTER TABLE public.company_features
  ADD COLUMN IF NOT EXISTS dashboard_config JSONB NOT NULL DEFAULT '{}'::jsonb;

-- Comment on the new column
COMMENT ON COLUMN public.company_features.dashboard_config IS
  'JSONB config for individual dashboard item visibility.
   Structure: { "cards": { "cash_bank": bool, "stock_value": bool, "today_sales": bool,
   "today_purchases": bool, "overdue_receivables": bool, "overdue_payables": bool },
   "quick_actions": { "stock": bool, "ledgers": bool, "sales": bool, "reports": bool } }
   Missing keys default to true (visible) in application code.';
