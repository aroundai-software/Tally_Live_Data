import sqlite3,re,json
from pathlib import Path
root=Path(__file__).resolve().parents[1]
source=(root/'supabase_schema.sql').read_text()
db=sqlite3.connect(':memory:')
db.executescript('''
create table stock_items ("ItemName" text,"ItemQuantity" real,"ItemRate" real,"StandardCost" real,company_name text);
create table invoice_items (invoice_id text,product_name text,quantity real,total_amount real,unit_price real);
create table sales_invoices (id text,invoice_date text,company_name text,customer_name text);
create table customers (customer_name text,mobile_number text,city text,is_active int,company_name text);
''')
def query(name,company='A',days=30):
    # Execute original SELECT with only PostgreSQL date/cast/parameter syntax adapted for SQLite.
    block=source.split('FUNCTION '+name+'(',1)[1].split('$$ LANGUAGE',1)[0]
    sql=block.split('RETURN QUERY',1)[1].split(';',1)[0]
    sql=sql.replace("::NUMERIC","").replace("::numeric","")
    sql=sql.replace("(CURRENT_DATE - (p_days || ' days')::interval)",f"date('2026-09-29','-{days} days')")
    sql=sql.replace('p_company_name',':company')
    return db.execute(sql,{'company':company}).fetchall()
results=[]
db.execute('insert into stock_items values (?,?,?,?,?)',('Widget',10,50,50,'A'))
db.execute('insert into sales_invoices values (?,?,?,?)',('old','2025-01-01','A','Old Customer'))
db.execute('insert into invoice_items values (?,?,?,?,?)',('old','Widget',20,2000,100))
actual=query('get_slow_moving_items')
results.append({'case':'No sales in 30 days still must appear as slow','expected':[['Widget',0]],'actual':actual,'pass':actual==[('Widget',0)]})
db.execute('delete from invoice_items');db.execute('delete from sales_invoices')
db.execute('insert into stock_items values (?,?,?,?,?)',('Widget',5,70,70,'B'))
db.execute('insert into sales_invoices values (?,?,?,?)',('new','2026-09-29','A','Buyer'))
db.execute('insert into invoice_items values (?,?,?,?,?)',('new','Widget',1,100,100))
actual=query('get_daily_profit')
results.append({'case':'Same product name in two authorized companies must not duplicate company A revenue','expected':[['2026-09-29',100,50]],'actual':actual,'pass':actual==[('2026-09-29',100,50)]})
db.execute('insert into customers values (?,?,?,?,?)',('Shared Buyer','000','','1','A'))
db.execute('insert into sales_invoices values (?,?,?,?)',('b','2026-09-29','B','Shared Buyer'))
actual=query('get_unused_ledgers')
results.append({'case':'Activity in company B must not hide a dormant company A customer','expected':[['Shared Buyer','000','']],'actual':actual,'pass':actual==[('Shared Buyer','000','')]})
print(json.dumps({'engine':'SQLite with date/cast/parameter adaptation; no deployed PostgreSQL or live database test','results':results},indent=2))

assert all(r['pass'] for r in results), 'SQL regression failure'
