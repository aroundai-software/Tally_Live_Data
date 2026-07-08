import uuid
import random
from datetime import datetime, timedelta

def get_uuid():
    return str(uuid.uuid4())

def rand_date(days_back=180):
    start = datetime.now() - timedelta(days=days_back)
    end = datetime.now()
    random_days = random.randrange((end - start).days + 1)
    return (start + timedelta(days=random_days)).strftime('%Y-%m-%d %H:%M:%S')

companies = [
    {"name": "Demo Company", "currency": "AED"},
    {"name": "Global Med Supplies FZCO", "currency": "AED"}
]

customer_names = [f"Customer {i}" for i in range(1, 51)]
supplier_names = [f"Supplier {i}" for i in range(1, 51)]
product_names = [f"Product {i}" for i in range(1, 51)]

customers = []
for i in range(50):
    comp = companies[i % 2]
    customers.append({
        "id": get_uuid(),
        "name": f"Customer {i+1} Clinic",
        "company": comp["name"],
        "mobile_number": f"+97150{random.randint(1000000, 9999999)}",
        "email": f"contact{i+1}@customer.com"
    })

stock_items = []
for i in range(50):
    comp = companies[i % 2]
    rate = round(random.uniform(50, 500), 2)
    cost = round(rate * random.uniform(0.4, 0.8), 2)
    
    if i < 10:
        qty = 0
    elif i < 25:
        qty = random.randint(1, 10)
    else:
        qty = random.randint(11, 1000)

    stock_items.append({
        "id": get_uuid(),
        "name": f"Medical Supply {i+1}",
        "rate": rate,
        "cost": cost,
        "company": comp["name"],
        "quantity": qty
    })

sales_invoices = []
for i in range(50):
    cust = random.choice(customers)
    sales_invoices.append({
        "id": get_uuid(),
        "invoice_number": f"INV-{1000+i}",
        "date": rand_date(20),
        "customer_id": cust["id"],
        "customer_name": cust["name"],
        "company": cust["company"]
    })

invoice_items = []
for i in range(50):
    inv = sales_invoices[i]
    item = random.choice([s for s in stock_items if s["company"] == inv["company"]])
    qty = random.randint(1, 100)
    price = item["rate"]
    invoice_items.append({
        "invoice_id": inv["id"],
        "product_name": item["name"],
        "quantity": qty,
        "unit_price": price,
        "total_amount": round(qty * price, 2),
        "company": inv["company"]
    })

# Update sales invoices total_amount based on items (simplified, each has 1 item)
for i in range(50):
    sales_invoices[i]["total_amount"] = invoice_items[i]["total_amount"]

out_rec = []
for i in range(50):
    cust = random.choice(customers)
    out_rec.append({
        "customer_name": cust["name"],
        "date": rand_date(90),
        "invoicenumber": f"OLD-INV-{i}",
        "amount": round(random.uniform(1000, 50000), 2),
        "duedate": rand_date(30),
        "overdue_days": random.randint(0, 90),
        "company": cust["company"]
    })

out_pay = []
for i in range(50):
    comp = companies[i % 2]
    out_pay.append({
        "customer_name": f"Supplier {i+1}",
        "date": rand_date(90),
        "invoicenumber": f"PUR-OLD-{i}",
        "amount": round(random.uniform(1000, 50000), 2),
        "duedate": rand_date(30),
        "overdue_days": random.randint(0, 90),
        "company": comp["name"]
    })

purchase_invoices = []
for i in range(50):
    comp = companies[i % 2]
    purchase_invoices.append({
        "id": get_uuid(),
        "invoice_number": f"PUR-{1000+i}",
        "date": rand_date(60),
        "supplier_name": f"Supplier {random.randint(1,20)}",
        "company": comp["name"]
    })

inv_items_pur = []
for i in range(50):
    pinv = purchase_invoices[i]
    item = random.choice([s for s in stock_items if s["company"] == pinv["company"]])
    qty = random.randint(10, 500)
    price = item["cost"]
    inv_items_pur.append({
        "purchase_invoice_id": pinv["id"],
        "product_name": item["name"],
        "quantity": qty,
        "unit_price": price,
        "total_amount": round(qty * price, 2),
        "company": pinv["company"]
    })

for i in range(50):
    purchase_invoices[i]["total_amount"] = inv_items_pur[i]["total_amount"]

daybook = []
for i in range(50):
    comp = companies[i % 2]
    is_debit = random.choice([True, False])
    vtype = "Receipt" if not is_debit else "Payment"
    # Ensure first 10 entries are strictly for today
    if i < 10:
        entry_date = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    else:
        entry_date = rand_date(30)

    daybook.append({
        "date": entry_date,
        "voucher_number": f"VCH-{1000+i}",
        "voucher_type": vtype,
        "ledger_name": f"Ledger {random.randint(1,20)}",
        "amount": round(random.uniform(100, 10000), 2),
        "is_debit": str(is_debit).lower(),
        "narration": "Auto generated entry",
        "company": comp["name"]
    })


with open('seed_data.sql', 'w', encoding='utf-8') as f:
    f.write("-- 0. Clear existing data to avoid conflicts\n")
    f.write("TRUNCATE TABLE public.tally_companies CASCADE;\n")
    f.write("TRUNCATE TABLE public.customers CASCADE;\n")
    f.write("TRUNCATE TABLE public.stock_items CASCADE;\n")
    f.write("TRUNCATE TABLE public.sales_invoices CASCADE;\n")
    f.write("TRUNCATE TABLE public.invoice_items CASCADE;\n")
    f.write("TRUNCATE TABLE public.outstanding_receivables CASCADE;\n")
    f.write("TRUNCATE TABLE public.outstanding_payables CASCADE;\n")
    f.write("TRUNCATE TABLE public.purchase_invoices CASCADE;\n")
    f.write("TRUNCATE TABLE public.invoice_items_purchase CASCADE;\n")
    f.write("TRUNCATE TABLE public.tally_daybook CASCADE;\n\n")

    f.write("-- 1. Insert 2 Companies\n")
    f.write("INSERT INTO public.tally_companies (company_name, company_number, guid, master_id, address_line1, city, base_currency, books_from, financial_year_from, trn_number) VALUES\n")
    f.write("('Demo Company', 'COMP-001', 'guid-comp-001', 'master-comp-001', 'Healthcare City', 'Dubai', 'AED', '2025-01-01', '2025-01-01', 'TRN123456789012345'),\n")
    f.write("('Global Med Supplies FZCO', 'COMP-002', 'guid-comp-002', 'master-comp-002', 'JAFZA', 'Dubai', 'AED', '2025-01-01', '2025-01-01', 'TRN987654321098765');\n\n")

    f.write("-- 2. Insert 50 Customers\n")
    f.write("INSERT INTO public.customers (id, customer_name, ledger_type, city, credit_limit, company_name, guid, master_id, mobile_number, email) VALUES\n")
    vals = [f"('{c['id']}', '{c['name']}', 'Sundry Debtors', 'Dubai', 50000, '{c['company']}', 'guid-cust-{i}', 'master-cust-{i}', '{c['mobile_number']}', '{c['email']}')" for i, c in enumerate(customers)]
    f.write(",\n".join(vals) + ";\n\n")

    f.write("-- 3. Insert 50 Stock Items\n")
    f.write("INSERT INTO public.stock_items (id, \"ItemName\", \"ItemUnit\", \"Category\", \"ItemRate\", \"StandardCost\", \"ItemQuantity\", company_name, guid, master_id) VALUES\n")
    vals = [f"('{s['id']}', '{s['name']}', 'Nos', 'Consumables', {s['rate']}, {s['cost']}, {s['quantity']}, '{s['company']}', 'guid-item-{i}', 'master-item-{i}')" for i, s in enumerate(stock_items)]
    f.write(",\n".join(vals) + ";\n\n")

    f.write("-- 4. Insert 50 Sales Invoices\n")
    f.write("INSERT INTO public.sales_invoices (id, invoice_number, invoice_date, customer_name, customer_id, total_amount, company_name, guid, master_id) VALUES\n")
    vals = [f"('{inv['id']}', '{inv['invoice_number']}', '{inv['date']}', '{inv['customer_name']}', '{inv['customer_id']}', {inv['total_amount']}, '{inv['company']}', 'guid-inv-{i}', 'master-inv-{i}')" for i, inv in enumerate(sales_invoices)]
    f.write(",\n".join(vals) + ";\n\n")

    f.write("-- 5. Insert 50 Invoice Items\n")
    f.write("INSERT INTO public.invoice_items (invoice_id, product_name, quantity, unit_price, total_amount, company_name, guid) VALUES\n")
    vals = [f"('{item['invoice_id']}', '{item['product_name']}', {item['quantity']}, {item['unit_price']}, {item['total_amount']}, '{item['company']}', 'guid-invitem-{i}')" for i, item in enumerate(invoice_items)]
    f.write(",\n".join(vals) + ";\n\n")

    f.write("-- 6. Insert 50 Outstanding Receivables\n")
    f.write("INSERT INTO public.outstanding_receivables (customer_name, date, invoicenumber, amount, duedate, overdue_days, company_name, guid, master_id) VALUES\n")
    vals = [f"('{r['customer_name']}', '{r['date']}', '{r['invoicenumber']}', {r['amount']}, '{r['duedate']}', {r['overdue_days']}, '{r['company']}', 'guid-rec-{i}', 'master-rec-{i}')" for i, r in enumerate(out_rec)]
    f.write(",\n".join(vals) + ";\n\n")

    f.write("-- 7. Insert 50 Outstanding Payables\n")
    f.write("INSERT INTO public.outstanding_payables (customer_name, date, invoicenumber, amount, duedate, overdue_days, company_name, guid, master_id) VALUES\n")
    vals = [f"('{p['customer_name']}', '{p['date']}', '{p['invoicenumber']}', {p['amount']}, '{p['duedate']}', {p['overdue_days']}, '{p['company']}', 'guid-pay-{i}', 'master-pay-{i}')" for i, p in enumerate(out_pay)]
    f.write(",\n".join(vals) + ";\n\n")

    f.write("-- 8. Insert 50 Purchase Invoices\n")
    f.write("INSERT INTO public.purchase_invoices (id, invoice_number, invoice_date, supplier_name, total_amount, company_name, guid, master_id) VALUES\n")
    vals = [f"('{pinv['id']}', '{pinv['invoice_number']}', '{pinv['date']}', '{pinv['supplier_name']}', {pinv['total_amount']}, '{pinv['company']}', 'guid-pinv-{i}', 'master-pinv-{i}')" for i, pinv in enumerate(purchase_invoices)]
    f.write(",\n".join(vals) + ";\n\n")

    f.write("-- 9. Insert 50 Purchase Invoice Items\n")
    f.write("INSERT INTO public.invoice_items_purchase (purchase_invoice_id, product_name, quantity, unit_price, total_amount, company_name, guid) VALUES\n")
    vals = [f"('{item['purchase_invoice_id']}', '{item['product_name']}', {item['quantity']}, {item['unit_price']}, {item['total_amount']}, '{item['company']}', 'guid-pinvitem-{i}')" for i, item in enumerate(inv_items_pur)]
    f.write(",\n".join(vals) + ";\n\n")

    f.write("-- 10. Insert 50 Tally Daybook Entries\n")
    f.write("INSERT INTO public.tally_daybook (date, voucher_number, voucher_type, ledger_name, amount, is_debit, narration, company_name, guid, master_id) VALUES\n")
    vals = [f"('{d['date']}', '{d['voucher_number']}', '{d['voucher_type']}', '{d['ledger_name']}', {d['amount']}, {d['is_debit']}, '{d['narration']}', '{d['company']}', 'guid-day-{i}', 'master-day-{i}')" for i, d in enumerate(daybook)]
    f.write(",\n".join(vals) + ";\n\n")

print("Generated seed_data.sql successfully!")
