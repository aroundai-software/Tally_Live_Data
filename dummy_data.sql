-- ============================================
-- FIX: Update company_name to match Tally company
-- Run this FIRST if you already inserted the dummy data
-- ============================================
UPDATE customers SET company_name = 'RISE REFRIGERATION COMPANY (New)' WHERE company_name = 'HospiMed Pharma';
UPDATE sales_invoices SET company_name = 'RISE REFRIGERATION COMPANY (New)' WHERE company_name = 'HospiMed Pharma';

-- ============================================
-- DUMMY DATA: customers (ledgers)
-- ============================================
INSERT INTO customers (customer_name, customer_category_name, address, city, state, pincode, country, contact_person, mobile_number, email, gst_number, pan_number, mailing_name, alias, credit_period, credit_limit, opening_balance, customer_discount_percentage, company_name, is_active)
VALUES
  ('City Hospital', 'Hospital', '45 MG Road', 'Bangalore', 'Karnataka', '560001', 'India', 'Dr. Rajesh Kumar', '9876543210', 'purchase@cityhospital.in', '29AABCC1234F1ZP', 'AABCC1234F', 'City Hospital Pvt Ltd', 'CH', '30 days', 500000, 125000.00, 5.0, 'HospiMed Pharma', true),
  ('Apollo Clinic', 'Hospital', '78 Jubilee Hills', 'Hyderabad', 'Telangana', '500033', 'India', 'Dr. Priya Sharma', '9876543211', 'pharma@apolloclinic.com', '36AADCA5678G1ZQ', 'AADCA5678G', 'Apollo Clinic Hyderabad', 'ACH', '45 days', 1000000, 340000.00, 5.0, 'HospiMed Pharma', true),
  ('Fortis Healthcare', 'Hospital', '14 Bannerghatta Road', 'Bangalore', 'Karnataka', '560076', 'India', 'Mr. Anil Mehta', '9876543212', 'supply@fortis.in', '29AABCF9012H1ZR', 'AABCF9012H', 'Fortis Healthcare Ltd', 'FH', '30 days', 2000000, 560000.00, 5.0, 'HospiMed Pharma', true),
  ('Manipal Hospital', 'Hospital', '98 HAL Airport Road', 'Bangalore', 'Karnataka', '560017', 'India', 'Ms. Kavita Rao', '9876543213', 'procurement@manipal.edu', '29AAECM3456I1ZS', 'AAECM3456I', 'Manipal Hospital Bangalore', 'MH', '60 days', 1500000, 450000.00, 10.0, 'HospiMed Pharma', true),
  ('Sunshine Children Hospital', 'Hospital', '33 Banjara Hills', 'Hyderabad', 'Telangana', '500034', 'India', 'Dr. Suman Reddy', '9876543214', 'pharma@sunshinehospital.in', '36AADCS7890J1ZT', 'AADCS7890J', 'Sunshine Children Hospital', 'SCH', '30 days', 750000, 228000.00, 0.0, 'HospiMed Pharma', true),
  ('Green Cross Pharmacy', 'Retail Pharmacy', '12 Anna Nagar', 'Chennai', 'Tamil Nadu', '600040', 'India', 'Mr. Venkat Suresh', '9876543215', 'greencross@gmail.com', '33AABCG2345K1ZU', 'AABCG2345K', 'Green Cross Pharmacy', 'GCP', '15 days', 200000, 84000.00, 0.0, 'HospiMed Pharma', true),
  ('MedPlus Store Koramangala', 'Retail Pharmacy', '99 Koramangala 4th Block', 'Bangalore', 'Karnataka', '560034', 'India', 'Mr. Ravi Prasad', '9876543216', 'koramangala@medplus.in', '29AAECM6789L1ZV', 'AAECM6789L', 'MedPlus Store Koramangala', 'MPK', '15 days', 150000, 56000.00, 5.0, 'HospiMed Pharma', true),
  ('Sagar Medical Store', 'Retail Pharmacy', '22 Lalbagh Road', 'Bangalore', 'Karnataka', '560027', 'India', 'Mr. Sagar Patel', '9876543217', 'sagarmedical@gmail.com', '29AABCS4567M1ZW', NULL, 'Sagar Medical Store', 'SMS', '7 days', 100000, 32000.00, 5.0, 'HospiMed Pharma', true),
  ('Wellness Pharmacy JP Nagar', 'Retail Pharmacy', '56 JP Nagar Phase 2', 'Bangalore', 'Karnataka', '560078', 'India', 'Ms. Deepa Nair', '9876543218', 'wellness.jpn@gmail.com', '29AABCW8901N1ZX', 'AABCW8901N', 'Wellness Pharmacy JP Nagar', 'WPJ', '15 days', 120000, 78000.00, 5.0, 'HospiMed Pharma', true),
  ('Ramaiah Memorial Hospital', 'Hospital', '18 New BEL Road', 'Bangalore', 'Karnataka', '560054', 'India', 'Dr. Harish Gowda', '9876543219', 'pharmacy@msramaiah.in', '29AAECR1234O1ZY', 'AAECR1234O', 'M S Ramaiah Memorial Hospital', 'RMH', '45 days', 800000, 195000.00, 7.5, 'HospiMed Pharma', true),
  ('LifeCare Distributors', 'Distributor', '5 Industrial Area, Peenya', 'Bangalore', 'Karnataka', '560058', 'India', 'Mr. Dinesh Shah', '9876543220', 'lifecare@distributors.in', '29AABCL5678P1ZZ', 'AABCL5678P', 'LifeCare Distributors Pvt Ltd', 'LCD', '30 days', 3000000, 0.00, 12.0, 'HospiMed Pharma', true),
  ('Narayana Health', 'Hospital', '258/A Bommasandra', 'Bangalore', 'Karnataka', '560099', 'India', 'Mr. Sunil Verma', '9876543221', 'purchase@narayanahealth.org', '29AAECN9012Q1ZA', 'AAECN9012Q', 'Narayana Health City', 'NH', '60 days', 2500000, 780000.00, 8.0, 'HospiMed Pharma', true),
  ('Jan Aushadhi Kendra HSR', 'Retail Pharmacy', '27th Main, HSR Layout', 'Bangalore', 'Karnataka', '560102', 'India', 'Mr. Mohan Das', '9876543222', 'janhsr@gmail.com', NULL, NULL, 'Jan Aushadhi Kendra HSR', 'JAK', NULL, 50000, 15000.00, 0.0, 'HospiMed Pharma', true),
  ('Columbia Asia Hospital', 'Hospital', '26/4 Brigade Gateway', 'Bangalore', 'Karnataka', '560055', 'India', 'Ms. Anita Desai', '9876543223', 'supply@columbiaasia.com', '29AADCC3456R1ZB', 'AADCC3456R', 'Columbia Asia Hospital', 'CAH', '30 days', 600000, 145000.00, 5.0, 'HospiMed Pharma', true),
  ('Netmeds Warehouse', 'Distributor', '44 Whitefield Main Road', 'Bangalore', 'Karnataka', '560066', 'India', 'Mr. Kiran Joshi', '9876543224', 'warehouse.blr@netmeds.com', '29AAECN7890S1ZC', 'AAECN7890S', 'Netmeds Marketplace Ltd', 'NM', '45 days', 5000000, 0.00, 15.0, 'HospiMed Pharma', true),
  ('Sakra World Hospital', 'Hospital', '52/2 Devarabeesanahalli', 'Bangalore', 'Karnataka', '560103', 'India', 'Dr. Ashwin Patel', '9876543225', 'purchase@sakraworldhospital.com', '29AADCS1234T1ZD', 'AADCS1234T', 'Sakra World Hospital', 'SWH', '30 days', 700000, 98000.00, 5.0, 'HospiMed Pharma', false),
  ('Old Town Chemist', 'Retail Pharmacy', '8 Gandhi Bazaar', 'Bangalore', 'Karnataka', '560004', 'India', 'Mr. Prakash Iyengar', '9876543226', NULL, NULL, NULL, 'Old Town Chemist', 'OTC', NULL, 30000, 8500.00, 0.0, 'HospiMed Pharma', false);

-- ============================================
-- DUMMY DATA: sales_invoices
-- ============================================
INSERT INTO sales_invoices (invoice_number, invoice_date, customer_name, customer_id, total_amount, gst_amount, net_amount, discount_amount, discount_percentage, subtotal_before_discount, status, "Type", notes, remarks, shipping_address, company_name, customer_category_name, round_off, synced_to_tally)
VALUES
  ('INV-2026-001', '2026-04-01', 'City Hospital', NULL, 12500.00, 2250.00, 14750.00, 625.00, 5.0, 13125.00, 'paid', 'Credit', NULL, 'Delivered on time', '45 MG Road, Bangalore 560001', 'HospiMed Pharma', 'Hospital', -0.50, true),
  ('INV-2026-002', '2026-04-02', 'Green Cross Pharmacy', NULL, 8400.00, 1512.00, 9912.00, 0.00, 0.0, 8400.00, 'paid', 'Cash', NULL, NULL, '12 Anna Nagar, Chennai 600040', 'HospiMed Pharma', 'Retail Pharmacy', 0.00, true),
  ('INV-2026-003', '2026-04-03', 'Apollo Clinic', NULL, 34200.00, 6156.00, 40356.00, 1710.00, 5.0, 35910.00, 'pending', 'Credit', 'Urgent order', 'Priority delivery', '78 Jubilee Hills, Hyderabad 500033', 'HospiMed Pharma', 'Hospital', 0.40, false),
  ('INV-2026-004', '2026-04-04', 'MedPlus Store Koramangala', NULL, 5600.00, 1008.00, 6608.00, 280.00, 5.0, 5880.00, 'paid', 'Credit', NULL, NULL, '99 Koramangala, Bangalore 560034', 'HospiMed Pharma', 'Retail Pharmacy', 0.00, true),
  ('INV-2026-005', '2026-04-05', 'Sunshine Children Hospital', NULL, 22800.00, 4104.00, 26904.00, 0.00, 0.0, 22800.00, 'pending', 'Credit', NULL, 'Partial delivery accepted', '33 Banjara Hills, Hyderabad 500034', 'HospiMed Pharma', 'Hospital', -0.20, false),
  ('INV-2026-006', '2026-04-05', 'Walk-in Customer', NULL, 1250.00, 225.00, 1475.00, 0.00, 0.0, 1250.00, 'paid', 'Cash', NULL, NULL, NULL, 'HospiMed Pharma', NULL, 0.00, true),
  ('INV-2026-007', '2026-04-06', 'Fortis Healthcare', NULL, 56000.00, 10080.00, 66080.00, 2800.00, 5.0, 58800.00, 'pending', 'Credit', 'Monthly supply order', 'Net 30 days', '14 Bannerghatta Road, Bangalore 560076', 'HospiMed Pharma', 'Hospital', 0.00, false),
  ('INV-2026-008', '2026-04-07', 'Sagar Medical Store', NULL, 3200.00, 576.00, 3776.00, 160.00, 5.0, 3360.00, 'paid', 'Cash', NULL, NULL, '22 Lalbagh Road, Bangalore 560027', 'HospiMed Pharma', 'Retail Pharmacy', 0.00, true),
  ('INV-2026-009', '2026-04-07', 'Manipal Hospital', NULL, 45000.00, 8100.00, 53100.00, 4500.00, 10.0, 49500.00, 'paid', 'Credit', 'Quarterly contract', NULL, '98 HAL Airport Rd, Bangalore 560017', 'HospiMed Pharma', 'Hospital', 0.00, true),
  ('INV-2026-010', '2026-04-08', 'Wellness Pharmacy JP Nagar', NULL, 7800.00, 1404.00, 9204.00, 390.00, 5.0, 8190.00, 'pending', 'Credit', NULL, NULL, '56 JP Nagar Phase 2, Bangalore 560078', 'HospiMed Pharma', 'Retail Pharmacy', -0.40, false);

-- ============================================
-- DUMMY DATA: invoice_items
-- Use subqueries to link to the invoices above
-- ============================================

-- Items for INV-2026-001 (City Hospital)
INSERT INTO invoice_items (invoice_id, product_name, product_code, quantity, free_quantity, unit_price, gst_rate, gst_amount, total_amount, discount_percentage, discount_amount, category_discount_percentage, company_name)
VALUES
  ((SELECT id FROM sales_invoices WHERE invoice_number = 'INV-2026-001' LIMIT 1), 'Amoxicillin 500mg', 'AMX500', 100, 5, 45.00, 18, 810.00, 5310.00, 0, 0, 0, 'Cipla'),
  ((SELECT id FROM sales_invoices WHERE invoice_number = 'INV-2026-001' LIMIT 1), 'Paracetamol 650mg', 'PCM650', 200, 10, 12.50, 18, 450.00, 2950.00, 0, 0, 0, 'GSK'),
  ((SELECT id FROM sales_invoices WHERE invoice_number = 'INV-2026-001' LIMIT 1), 'Surgical Gloves (Box)', 'SGL100', 50, 0, 85.00, 18, 765.00, 5015.00, 5, 212.50, 0, 'Medline');

-- Items for INV-2026-002 (Green Cross Pharmacy)
INSERT INTO invoice_items (invoice_id, product_name, product_code, quantity, free_quantity, unit_price, gst_rate, gst_amount, total_amount, discount_percentage, discount_amount, category_discount_percentage, company_name)
VALUES
  ((SELECT id FROM sales_invoices WHERE invoice_number = 'INV-2026-002' LIMIT 1), 'Cetirizine 10mg', 'CTZ10', 500, 25, 3.20, 12, 192.00, 1792.00, 0, 0, 0, 'Dr Reddys'),
  ((SELECT id FROM sales_invoices WHERE invoice_number = 'INV-2026-002' LIMIT 1), 'Omeprazole 20mg', 'OMP20', 300, 15, 8.50, 12, 306.00, 2856.00, 0, 0, 0, 'Sun Pharma'),
  ((SELECT id FROM sales_invoices WHERE invoice_number = 'INV-2026-002' LIMIT 1), 'Azithromycin 500mg', 'AZT500', 100, 0, 35.00, 18, 630.00, 4130.00, 5, 175.00, 0, 'Zydus');

-- Items for INV-2026-003 (Apollo Clinic)
INSERT INTO invoice_items (invoice_id, product_name, product_code, quantity, free_quantity, unit_price, gst_rate, gst_amount, total_amount, discount_percentage, discount_amount, category_discount_percentage, company_name)
VALUES
  ((SELECT id FROM sales_invoices WHERE invoice_number = 'INV-2026-003' LIMIT 1), 'Insulin Glargine 100IU', 'INSG100', 50, 0, 320.00, 12, 1920.00, 17920.00, 0, 0, 0, 'Sanofi'),
  ((SELECT id FROM sales_invoices WHERE invoice_number = 'INV-2026-003' LIMIT 1), 'Metformin 500mg', 'MTF500', 1000, 50, 4.80, 12, 576.00, 5376.00, 0, 0, 0, 'USV'),
  ((SELECT id FROM sales_invoices WHERE invoice_number = 'INV-2026-003' LIMIT 1), 'Blood Glucose Strips (50s)', 'BGS50', 200, 10, 55.00, 18, 1980.00, 12980.00, 5, 550.00, 0, 'Accu-Chek');

-- Items for INV-2026-004 (MedPlus Koramangala)
INSERT INTO invoice_items (invoice_id, product_name, product_code, quantity, free_quantity, unit_price, gst_rate, gst_amount, total_amount, discount_percentage, discount_amount, category_discount_percentage, company_name)
VALUES
  ((SELECT id FROM sales_invoices WHERE invoice_number = 'INV-2026-004' LIMIT 1), 'Vitamin D3 60K', 'VTD60K', 100, 5, 28.00, 18, 504.00, 3304.00, 0, 0, 0, 'Cadila'),
  ((SELECT id FROM sales_invoices WHERE invoice_number = 'INV-2026-004' LIMIT 1), 'Calcium + D3 Tablets', 'CAD3', 200, 10, 12.00, 12, 288.00, 2688.00, 5, 120.00, 0, 'Abbott');

-- Items for INV-2026-005 (Sunshine Children Hospital)
INSERT INTO invoice_items (invoice_id, product_name, product_code, quantity, free_quantity, unit_price, gst_rate, gst_amount, total_amount, discount_percentage, discount_amount, category_discount_percentage, company_name)
VALUES
  ((SELECT id FROM sales_invoices WHERE invoice_number = 'INV-2026-005' LIMIT 1), 'Augmentin Syrup 30ml', 'AUGS30', 200, 10, 65.00, 12, 1560.00, 14560.00, 0, 0, 0, 'GSK'),
  ((SELECT id FROM sales_invoices WHERE invoice_number = 'INV-2026-005' LIMIT 1), 'ORS Powder', 'ORS01', 500, 25, 8.00, 5, 200.00, 4200.00, 0, 0, 0, 'FDC'),
  ((SELECT id FROM sales_invoices WHERE invoice_number = 'INV-2026-005' LIMIT 1), 'Zinc Dispersible 20mg', 'ZNC20', 300, 15, 5.50, 12, 198.00, 1848.00, 0, 0, 0, 'Mankind');

-- Items for INV-2026-006 (Walk-in Customer)
INSERT INTO invoice_items (invoice_id, product_name, product_code, quantity, free_quantity, unit_price, gst_rate, gst_amount, total_amount, discount_percentage, discount_amount, category_discount_percentage, company_name)
VALUES
  ((SELECT id FROM sales_invoices WHERE invoice_number = 'INV-2026-006' LIMIT 1), 'Crocin Advance 500mg', 'CRC500', 2, 0, 35.00, 18, 12.60, 82.60, 0, 0, 0, 'GSK'),
  ((SELECT id FROM sales_invoices WHERE invoice_number = 'INV-2026-006' LIMIT 1), 'Betadine 100ml', 'BTD100', 1, 0, 120.00, 18, 21.60, 141.60, 0, 0, 0, 'Win-Medicare');

-- Items for INV-2026-007 (Fortis Healthcare)
INSERT INTO invoice_items (invoice_id, product_name, product_code, quantity, free_quantity, unit_price, gst_rate, gst_amount, total_amount, discount_percentage, discount_amount, category_discount_percentage, company_name)
VALUES
  ((SELECT id FROM sales_invoices WHERE invoice_number = 'INV-2026-007' LIMIT 1), 'IV Saline 500ml', 'IVS500', 500, 0, 42.00, 12, 2520.00, 23520.00, 0, 0, 0, 'Baxter'),
  ((SELECT id FROM sales_invoices WHERE invoice_number = 'INV-2026-007' LIMIT 1), 'Ceftriaxone 1g Inj', 'CFX1G', 200, 10, 85.00, 18, 3060.00, 20060.00, 0, 0, 0, 'Alkem'),
  ((SELECT id FROM sales_invoices WHERE invoice_number = 'INV-2026-007' LIMIT 1), 'Disposable Syringes 5ml', 'DSP5ML', 1000, 50, 4.50, 18, 810.00, 5310.00, 5, 225.00, 0, 'HMD');

-- Items for INV-2026-008 (Sagar Medical Store)
INSERT INTO invoice_items (invoice_id, product_name, product_code, quantity, free_quantity, unit_price, gst_rate, gst_amount, total_amount, discount_percentage, discount_amount, category_discount_percentage, company_name)
VALUES
  ((SELECT id FROM sales_invoices WHERE invoice_number = 'INV-2026-008' LIMIT 1), 'Dolo 650mg', 'DLO650', 100, 5, 15.00, 12, 180.00, 1680.00, 0, 0, 0, 'Micro Labs'),
  ((SELECT id FROM sales_invoices WHERE invoice_number = 'INV-2026-008' LIMIT 1), 'Pan-D Capsules', 'PAND', 50, 0, 32.00, 12, 192.00, 1792.00, 5, 80.00, 0, 'Alkem');

-- Items for INV-2026-009 (Manipal Hospital)
INSERT INTO invoice_items (invoice_id, product_name, product_code, quantity, free_quantity, unit_price, gst_rate, gst_amount, total_amount, discount_percentage, discount_amount, category_discount_percentage, company_name)
VALUES
  ((SELECT id FROM sales_invoices WHERE invoice_number = 'INV-2026-009' LIMIT 1), 'Pantoprazole 40mg Inj', 'PNT40I', 300, 15, 55.00, 12, 1980.00, 18480.00, 10, 1650.00, 0, 'Sun Pharma'),
  ((SELECT id FROM sales_invoices WHERE invoice_number = 'INV-2026-009' LIMIT 1), 'Ondansetron 4mg Inj', 'OND4I', 200, 10, 22.00, 12, 528.00, 4928.00, 0, 0, 0, 'Cipla'),
  ((SELECT id FROM sales_invoices WHERE invoice_number = 'INV-2026-009' LIMIT 1), 'Tramadol 50mg Inj', 'TRM50I', 100, 0, 38.00, 12, 456.00, 4256.00, 10, 380.00, 0, 'Neon Labs'),
  ((SELECT id FROM sales_invoices WHERE invoice_number = 'INV-2026-009' LIMIT 1), 'Sterile Gauze Pads (100s)', 'SGP100', 50, 5, 180.00, 18, 1620.00, 10620.00, 10, 900.00, 0, 'Johnson & Johnson');

-- Items for INV-2026-010 (Wellness Pharmacy)
INSERT INTO invoice_items (invoice_id, product_name, product_code, quantity, free_quantity, unit_price, gst_rate, gst_amount, total_amount, discount_percentage, discount_amount, category_discount_percentage, company_name)
VALUES
  ((SELECT id FROM sales_invoices WHERE invoice_number = 'INV-2026-010' LIMIT 1), 'Shelcal 500mg', 'SHL500', 200, 10, 18.00, 12, 432.00, 4032.00, 5, 180.00, 0, 'Torrent'),
  ((SELECT id FROM sales_invoices WHERE invoice_number = 'INV-2026-010' LIMIT 1), 'Becosules Capsules', 'BCS01', 150, 5, 22.00, 18, 594.00, 3894.00, 0, 0, 0, 'Pfizer'),
  ((SELECT id FROM sales_invoices WHERE invoice_number = 'INV-2026-010' LIMIT 1), 'Evion 400mg', 'EVN400', 100, 5, 12.00, 5, 60.00, 1260.00, 5, 60.00, 0, 'Merck');
