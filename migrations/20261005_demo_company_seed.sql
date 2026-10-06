-- =============================================================================
-- TallyLive Demo Company — seed data for customer demos
-- Run in Supabase SQL Editor (service role / postgres).
--
-- Creates:
--   • 1 demo company + full feature flags
--   • 50 customers (40 debtors, 5 creditors, 2 cash, 3 bank)
--   • 50 stock items
--   • 25 sales invoices + 50 sale line items
--   • 15 purchase invoices + 30 purchase line items
--   • 25 receivables + 15 payables
--   • 40 daybook rows (incl. today)
--   • 20 bill-settlement rows (money-flow screen)
--   • 3 godowns, 3 cost centres
--   • 1 recent sync_log row
--
-- After running, link a demo user:
--   INSERT INTO user_companies (user_id, company_name)
--   VALUES ('<auth-user-uuid>', 'TallyLive Demo Company');
-- =============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- 0) Remove previous demo seed (safe re-run)
-- ---------------------------------------------------------------------------
DELETE FROM public.invoice_items
WHERE company_name = 'TallyLive Demo Company';

DELETE FROM public.invoice_items_purchase
WHERE company_name = 'TallyLive Demo Company';

DELETE FROM public.sales_invoices
WHERE company_name = 'TallyLive Demo Company';

DELETE FROM public.purchase_invoices
WHERE company_name = 'TallyLive Demo Company';

DELETE FROM public.outstanding_receivables
WHERE company_name = 'TallyLive Demo Company';

DELETE FROM public.outstanding_payables
WHERE company_name = 'TallyLive Demo Company';

DELETE FROM public.tally_daybook
WHERE company_name = 'TallyLive Demo Company';

DELETE FROM public.ledger_bill_settlements
WHERE company_name = 'TallyLive Demo Company';

DELETE FROM public.stock_items
WHERE company_name = 'TallyLive Demo Company';

DELETE FROM public.customers
WHERE company_name = 'TallyLive Demo Company';

DELETE FROM public.tally_godowns
WHERE company_name = 'TallyLive Demo Company';

DELETE FROM public.tally_cost_centers
WHERE company_name = 'TallyLive Demo Company';

DELETE FROM public.sync_logs
WHERE company_name = 'TallyLive Demo Company';

DELETE FROM public.company_features
WHERE company_name = 'TallyLive Demo Company';

DELETE FROM public.tally_companies
WHERE company_name = 'TallyLive Demo Company';

-- ---------------------------------------------------------------------------
-- 1) Company master
-- ---------------------------------------------------------------------------
INSERT INTO public.tally_companies (
  id,
  company_name,
  company_number,
  guid,
  master_id,
  address_line1,
  city,
  country,
  pin_code,
  mobile_number,
  email,
  base_currency,
  books_from,
  financial_year_from,
  is_active,
  sync_enabled,
  gst_number
) VALUES (
  'aaaaaaaa-bbbb-cccc-dddd-111111111111'::uuid,
  'TallyLive Demo Company',
  'DEMO-001',
  'demo-tallylive-company-0001',
  '1',
  '12 Demo Industrial Estate',
  'Mumbai',
  'India',
  '400001',
  '9876543210',
  'demo@tallylive.app',
  'INR',
  '2025-04-01'::date,
  '2025-04-01'::date,
  true,
  true,
  '27AABCT1234D1Z5'
);

-- ---------------------------------------------------------------------------
-- 2) Feature flags — all modules ON for demo
--    Note: inserting tally_companies already creates a company_features row
--    via trigger on_company_created, so UPDATE (do not INSERT again).
-- ---------------------------------------------------------------------------
UPDATE public.company_features
SET
  company_name = 'TallyLive Demo Company',
  is_dashboard_enabled = true,
  is_stock_enabled = true,
  is_ledgers_enabled = true,
  is_outstanding_enabled = true,
  is_sales_enabled = true,
  is_purchases_enabled = true,
  is_analytics_enabled = true,
  dashboard_config = '{
    "db_net_position": true,
    "db_summary_cards": true,
    "db_daybook": true,
    "db_quick_actions": true,
    "out_receivables": true,
    "out_payables": true,
    "rep_sales": true,
    "rep_purchases": true,
    "rep_ledgers": true,
    "cash_flow": true,
    "cf_summary": true,
    "cf_overview": true,
    "cf_pie_chart": true,
    "cf_trend": true,
    "cf_fastest": true,
    "cf_slowest": true,
    "ls_transactions": true,
    "ls_performance": true,
    "stock_cost": true,
    "stock_item_parents": true,
    "cards": {
      "cash_bank": true,
      "stock_value": true,
      "today_sales": true,
      "today_purchases": true,
      "overdue_receivables": true,
      "overdue_payables": true,
      "total_receivables": true,
      "total_payables": true
    },
    "quick_actions": {
      "stock": true,
      "ledgers": true,
      "sales": true,
      "reports": true
    },
    "net_position": {
      "stock": true,
      "receivables": true,
      "payables": true,
      "cash": true,
      "bank": true
    }
  }'::jsonb,
  updated_at = now()
WHERE company_id = 'aaaaaaaa-bbbb-cccc-dddd-111111111111'::uuid;

-- ---------------------------------------------------------------------------
-- 3) Customers / ledgers (50)
--    1-40 debtors, 41-45 creditors, 46-47 cash, 48-50 bank
-- ---------------------------------------------------------------------------
INSERT INTO public.customers (
  id,
  customer_name,
  ledger_type,
  address,
  city,
  state,
  pincode,
  country,
  contact_person,
  mobile_number,
  email,
  gst_number,
  credit_period,
  credit_limit,
  opening_balance,
  closing_balance,
  customer_discount_percentage,
  company_name,
  guid,
  master_id,
  is_active,
  alter_id
)
SELECT
  gen_random_uuid(),
  CASE
    WHEN i <= 40 THEN 'Demo Customer ' || lpad(i::text, 2, '0')
    WHEN i <= 45 THEN 'Demo Supplier ' || lpad((i - 40)::text, 2, '0')
    WHEN i = 46 THEN 'Cash'
    WHEN i = 47 THEN 'Petty Cash'
    ELSE 'Demo Bank ' || lpad((i - 47)::text, 2, '0')
  END,
  CASE
    WHEN i <= 40 THEN 'Sundry Debtors'
    WHEN i <= 45 THEN 'Sundry Creditors'
    WHEN i <= 47 THEN 'Cash-in-Hand'
    ELSE 'Bank Accounts'
  END,
  'Demo Street ' || i,
  CASE (i % 5)
    WHEN 0 THEN 'Mumbai'
    WHEN 1 THEN 'Pune'
    WHEN 2 THEN 'Delhi'
    WHEN 3 THEN 'Bangalore'
    ELSE 'Chennai'
  END,
  'Maharashtra',
  lpad((400000 + i)::text, 6, '0'),
  'India',
  'Contact Person ' || i,
  '98' || lpad((10000000 + i)::text, 8, '0'),
  'customer' || i || '@demo.tallylive.app',
  CASE WHEN i <= 45 THEN '27AABCD' || lpad(i::text, 4, '0') || 'Z1' ELSE NULL END,
  CASE WHEN i <= 40 THEN '30 Days' ELSE NULL END,
  CASE WHEN i <= 40 THEN 250000 ELSE NULL END,
  CASE
    WHEN i <= 40 THEN round((5000 + i * 137.25)::numeric, 2)
    WHEN i <= 45 THEN round(-(3000 + i * 89.50)::numeric, 2)
    WHEN i <= 47 THEN round((15000 + i * 500)::numeric, 2)
    ELSE round((85000 + i * 12000)::numeric, 2)
  END,
  CASE
    WHEN i <= 40 THEN round((8000 + i * 215.75)::numeric, 2)
    WHEN i <= 45 THEN round(-(4500 + i * 112.30)::numeric, 2)
    WHEN i <= 47 THEN round((25000 + i * 750)::numeric, 2)
    ELSE round((125000 + i * 18500)::numeric, 2)
  END,
  CASE WHEN i <= 40 THEN (i % 5) ELSE 0 END,
  'TallyLive Demo Company',
  'demo-cust-' || lpad(i::text, 4, '0'),
  (1000 + i)::text,
  true,
  i
FROM generate_series(1, 50) AS i;

-- ---------------------------------------------------------------------------
-- 4) Stock items (50)
-- ---------------------------------------------------------------------------
INSERT INTO public.stock_items (
  "ItemName",
  "PartNumber",
  "ItemUnit",
  "ItemParent",
  "Category",
  "Description",
  "ItemQuantity",
  "ItemRate",
  "GstRate",
  "MRP",
  "StandardCost",
  "StandardPrice",
  "is_active",
  company_name,
  guid,
  master_id,
  alter_id
)
SELECT
  'Demo Product ' || lpad(i::text, 2, '0'),
  'SKU-DEMO-' || lpad(i::text, 4, '0'),
  CASE (i % 3) WHEN 0 THEN 'Nos' WHEN 1 THEN 'Kg' ELSE 'Box' END,
  CASE (i % 4)
    WHEN 0 THEN 'Electronics'
    WHEN 1 THEN 'Hardware'
    WHEN 2 THEN 'Consumables'
    ELSE 'Spare Parts'
  END,
  CASE (i % 4)
    WHEN 0 THEN 'Electronics'
    WHEN 1 THEN 'Hardware'
    WHEN 2 THEN 'Consumables'
    ELSE 'Spare Parts'
  END,
  'Demo stock item for TallyLive showcase #' || i,
  (10 + (i * 3) % 120)::integer,
  round((99.00 + i * 47.50)::numeric, 2),
  CASE (i % 4) WHEN 0 THEN 18 WHEN 1 THEN 12 WHEN 2 THEN 5 ELSE 28 END,
  round((149.00 + i * 55.00)::numeric, 2),
  round((75.00 + i * 35.00)::numeric, 2),
  round((120.00 + i * 45.00)::numeric, 2),
  true,
  'TallyLive Demo Company',
  'demo-stock-' || lpad(i::text, 4, '0'),
  (2000 + i)::text,
  i
FROM generate_series(1, 50) AS i;

-- ---------------------------------------------------------------------------
-- 5) Sales invoices (25) + line items (50)
-- ---------------------------------------------------------------------------
WITH debtors AS (
  SELECT id, customer_name, row_number() OVER (ORDER BY customer_name) AS rn
  FROM public.customers
  WHERE company_name = 'TallyLive Demo Company'
    AND ledger_type = 'Sundry Debtors'
),
sales AS (
  INSERT INTO public.sales_invoices (
    id,
    invoice_number,
    invoice_date,
    customer_name,
    customer_id,
    total_amount,
    gst_amount,
    net_amount,
    discount_amount,
    status,
    "Type",
    notes,
    company_name,
    ledger_type,
    synced_to_tally,
    guid,
    master_id,
    alter_id
  )
  SELECT
    gen_random_uuid(),
    'SINV-DEMO-' || lpad(s::text, 4, '0'),
    timezone('Asia/Kolkata', (CURRENT_DATE - ((s - 1) % 30))::timestamp + time '11:30:00'),
    d.customer_name,
    d.id,
    round((5000 + s * 825.50)::numeric, 2),
    round((900 + s * 148.50)::numeric, 2),
    round((4100 + s * 677.00)::numeric, 2),
    CASE WHEN s % 5 = 0 THEN 250 ELSE 0 END,
    CASE WHEN s % 4 = 0 THEN 'Paid' ELSE 'Pending' END,
    CASE (s % 3) WHEN 0 THEN 'Sales' WHEN 1 THEN 'Tax Invoice' ELSE 'Credit Note' END,
    'Demo sales invoice #' || s,
    'TallyLive Demo Company',
    'Sundry Debtors',
    true,
    'demo-sale-' || lpad(s::text, 4, '0'),
    (3000 + s)::text,
    s
  FROM generate_series(1, 25) AS s
  JOIN debtors d ON d.rn = ((s - 1) % 40) + 1
  RETURNING id, guid, invoice_number, total_amount, gst_amount, alter_id
)
INSERT INTO public.invoice_items (
  invoice_id,
  product_name,
  product_code,
  quantity,
  unit_price,
  gst_rate,
  gst_amount,
  total_amount,
  company_name,
  guid,
  master_id,
  alter_id
)
SELECT
  s.id,
  'Demo Product ' || lpad((((n - 1) % 50) + 1)::text, 2, '0'),
  'SKU-DEMO-' || lpad((((n - 1) % 50) + 1)::text, 4, '0'),
  2 + (n % 5),
  round((450 + n * 35.25)::numeric, 2),
  18,
  round((81 + n * 6.35)::numeric, 2),
  round((981 + n * 41.60)::numeric, 2),
  'TallyLive Demo Company',
  s.guid || '-line-' || n,
  (4000 + n)::text,
  s.alter_id
FROM sales s
CROSS JOIN generate_series(1, 2) AS n;

-- ---------------------------------------------------------------------------
-- 6) Purchase invoices (15) + line items (30)
-- ---------------------------------------------------------------------------
WITH suppliers AS (
  SELECT id, customer_name, row_number() OVER (ORDER BY customer_name) AS rn
  FROM public.customers
  WHERE company_name = 'TallyLive Demo Company'
    AND ledger_type = 'Sundry Creditors'
),
purchases AS (
  INSERT INTO public.purchase_invoices (
    id,
    invoice_number,
    invoice_date,
    supplier_name,
    supplier_id,
    total_amount,
    gst_amount,
    net_amount,
    status,
    type,
    notes,
    company_name,
    synced_to_tally,
    guid,
    master_id,
    alter_id
  )
  SELECT
    gen_random_uuid(),
    'PINV-DEMO-' || lpad(p::text, 4, '0'),
    (CURRENT_DATE - ((p - 1) % 25))::date,
    s.customer_name,
    s.id,
    round((3200 + p * 612.75)::numeric, 2),
    round((576 + p * 110.30)::numeric, 2),
    round((2624 + p * 502.45)::numeric, 2),
    CASE WHEN p % 3 = 0 THEN 'Paid' ELSE 'Pending' END,
    'Purchase',
    'Demo purchase bill #' || p,
    'TallyLive Demo Company',
    true,
    'demo-purch-' || lpad(p::text, 4, '0'),
    (5000 + p)::text,
    p
  FROM generate_series(1, 15) AS p
  JOIN suppliers s ON s.rn = ((p - 1) % 5) + 1
  RETURNING id, guid, alter_id
)
INSERT INTO public.invoice_items_purchase (
  purchase_invoice_id,
  product_name,
  product_code,
  quantity,
  unit_price,
  gst_rate,
  gst_amount,
  total_amount,
  company_name,
  guid,
  alter_id
)
SELECT
  p.id,
  'Demo Product ' || lpad((((n - 1) % 50) + 1)::text, 2, '0'),
  'SKU-DEMO-' || lpad((((n - 1) % 50) + 1)::text, 4, '0'),
  3 + (n % 4),
  round((280 + n * 22.40)::numeric, 2),
  12,
  round((33.60 + n * 2.69)::numeric, 2),
  round((313.60 + n * 25.09)::numeric, 2),
  'TallyLive Demo Company',
  p.guid || '-line-' || n,
  p.alter_id
FROM purchases p
CROSS JOIN generate_series(1, 2) AS n;

-- ---------------------------------------------------------------------------
-- 7) Outstanding receivables (25) + payables (15)
-- ---------------------------------------------------------------------------
INSERT INTO public.outstanding_receivables (
  customer_name,
  date,
  invoicenumber,
  opening_balance,
  closing_balance,
  amount,
  duedate,
  overdue_days,
  bill_type,
  guid,
  master_id,
  company_name,
  credit_days,
  group_name,
  mobile
)
SELECT
  c.customer_name,
  timezone('Asia/Kolkata', (CURRENT_DATE - (i % 45))::timestamp),
  'OB-REC-' || lpad(i::text, 4, '0'),
  round((2000 + i * 120)::numeric, 2),
  round((2500 + i * 145)::numeric, 2),
  round((2500 + i * 145)::numeric, 2),
  timezone('Asia/Kolkata', (CURRENT_DATE - (i % 45) + 30)::timestamp),
  CASE WHEN i % 4 = 0 THEN (i % 20) + 1 ELSE 0 END,
  'Receivable',
  'demo-rec-' || lpad(i::text, 4, '0'),
  (6000 + i)::text,
  'TallyLive Demo Company',
  30,
  'Sundry Debtors',
  c.mobile_number
FROM generate_series(1, 25) AS i
JOIN LATERAL (
  SELECT customer_name, mobile_number
  FROM public.customers
  WHERE company_name = 'TallyLive Demo Company'
    AND ledger_type = 'Sundry Debtors'
  ORDER BY customer_name
  OFFSET ((i - 1) % 40)
  LIMIT 1
) c ON true;

INSERT INTO public.outstanding_payables (
  customer_name,
  date,
  invoicenumber,
  opening_balance,
  closing_balance,
  amount,
  duedate,
  overdue_days,
  bill_type,
  guid,
  master_id,
  company_name,
  credit_days,
  group_name,
  mobile
)
SELECT
  c.customer_name,
  timezone('Asia/Kolkata', (CURRENT_DATE - (i % 30))::timestamp),
  'OB-PAY-' || lpad(i::text, 4, '0'),
  round(-(1800 + i * 95)::numeric, 2),
  round(-(2100 + i * 110)::numeric, 2),
  round((2100 + i * 110)::numeric, 2),
  timezone('Asia/Kolkata', (CURRENT_DATE - (i % 30) + 15)::timestamp),
  CASE WHEN i % 3 = 0 THEN (i % 15) + 2 ELSE 0 END,
  'Payable',
  'demo-pay-' || lpad(i::text, 4, '0'),
  (7000 + i)::text,
  'TallyLive Demo Company',
  15,
  'Sundry Creditors',
  c.mobile_number
FROM generate_series(1, 15) AS i
JOIN LATERAL (
  SELECT customer_name, mobile_number
  FROM public.customers
  WHERE company_name = 'TallyLive Demo Company'
    AND ledger_type = 'Sundry Creditors'
  ORDER BY customer_name
  OFFSET ((i - 1) % 5)
  LIMIT 1
) c ON true;

-- ---------------------------------------------------------------------------
-- 8) Daybook (40 rows — includes today's activity)
-- ---------------------------------------------------------------------------
INSERT INTO public.tally_daybook (
  date,
  voucher_number,
  voucher_type,
  ledger_name,
  amount,
  is_debit,
  narration,
  company_name,
  guid,
  master_id,
  particulars,
  alter_id
)
SELECT
  timezone('Asia/Kolkata', (CURRENT_DATE - (i % 10))::timestamp + ((i % 24) || ' hours')::interval),
  'DB-' || lpad(i::text, 4, '0'),
  CASE (i % 5)
    WHEN 0 THEN 'Receipt'
    WHEN 1 THEN 'Payment'
    WHEN 2 THEN 'Sales'
    WHEN 3 THEN 'Purchase'
    ELSE 'Journal'
  END,
  CASE (i % 5)
    WHEN 0 THEN 'Demo Customer ' || lpad(((i % 40) + 1)::text, 2, '0')
    WHEN 1 THEN 'Demo Supplier ' || lpad(((i % 5) + 1)::text, 2, '0')
    WHEN 2 THEN 'Demo Customer ' || lpad(((i % 40) + 1)::text, 2, '0')
    WHEN 3 THEN 'Demo Supplier ' || lpad(((i % 5) + 1)::text, 2, '0')
    ELSE 'Demo Bank 01'
  END,
  round((1500 + i * 275.50)::numeric, 2),
  (i % 2 = 0),
  'Demo daybook entry #' || i,
  'TallyLive Demo Company',
  'demo-daybook-' || lpad(i::text, 4, '0'),
  (8000 + i)::text,
  CASE (i % 5)
    WHEN 0 THEN 'By Cash'
    WHEN 1 THEN 'To Bank'
    WHEN 2 THEN 'Sales Invoice'
    WHEN 3 THEN 'Purchase Bill'
    ELSE 'Contra Entry'
  END,
  i
FROM generate_series(1, 40) AS i;

-- ---------------------------------------------------------------------------
-- 9) Bill settlements (money-flow / analytics)
-- ---------------------------------------------------------------------------
INSERT INTO public.ledger_bill_settlements (
  company_name,
  ledger_name,
  bill_reference,
  bill_date,
  bill_amount,
  due_date,
  cleared_date,
  days_to_clear,
  days_from_due_date,
  guid,
  alter_id
)
SELECT
  'TallyLive Demo Company',
  'Demo Customer ' || lpad((((i - 1) % 40) + 1)::text, 2, '0'),
  'BILL-REF-' || lpad(i::text, 4, '0'),
  (CURRENT_DATE - (30 + i))::date,
  round((3500 + i * 210)::numeric, 2),
  (CURRENT_DATE - (10 + i))::date,
  (CURRENT_DATE - (5 + (i % 8)))::date,
  10 + (i % 25),
  CASE WHEN i % 4 = 0 THEN -3 ELSE (i % 12) END,
  'demo-settle-' || lpad(i::text, 4, '0'),
  i
FROM generate_series(1, 20) AS i;

-- ---------------------------------------------------------------------------
-- 10) Godowns + cost centres
-- ---------------------------------------------------------------------------
INSERT INTO public.tally_godowns (name, parent, address, company_name, guid, master_id, is_active, alter_id)
VALUES
  ('Main Warehouse', 'Primary Location', 'Demo Warehouse Road', 'TallyLive Demo Company', 'demo-godown-0001', '9001', true, 1),
  ('Branch Store', 'Main Warehouse', 'Branch Lane 2', 'TallyLive Demo Company', 'demo-godown-0002', '9002', true, 2),
  ('Transit Godown', 'Primary Location', 'Highway Side', 'TallyLive Demo Company', 'demo-godown-0003', '9003', true, 3);

INSERT INTO public.tally_cost_centers (name, parent, category, company_name, guid, master_id, is_active)
VALUES
  ('Sales Division', 'Primary', 'Revenue', 'TallyLive Demo Company', 'demo-cc-0001', '9101', true),
  ('Admin Overheads', 'Primary', 'Expense', 'TallyLive Demo Company', 'demo-cc-0002', '9102', true),
  ('Project Alpha', 'Sales Division', 'Project', 'TallyLive Demo Company', 'demo-cc-0003', '9103', true);

-- ---------------------------------------------------------------------------
-- 11) Recent sync log (dashboard "last synced")
-- ---------------------------------------------------------------------------
INSERT INTO public.sync_logs (
  started_at,
  finished_at,
  status,
  total_steps,
  steps_passed,
  steps_failed,
  duration_seconds,
  machine_name,
  company_name
) VALUES (
  (now() AT TIME ZONE 'Asia/Kolkata') - interval '12 minutes',
  (now() AT TIME ZONE 'Asia/Kolkata') - interval '8 minutes',
  'success',
  13,
  13,
  0,
  240,
  'demo-machine',
  'TallyLive Demo Company'
);

COMMIT;

-- ---------------------------------------------------------------------------
-- Link demo user (run separately with your auth user id):
--
-- INSERT INTO public.user_companies (user_id, company_name)
-- VALUES ('YOUR-AUTH-USER-UUID', 'TallyLive Demo Company')
-- ON CONFLICT DO NOTHING;
--
-- UPDATE public.users
-- SET company_name = 'TallyLive Demo Company'
-- WHERE id = 'YOUR-AUTH-USER-UUID';
-- ---------------------------------------------------------------------------
