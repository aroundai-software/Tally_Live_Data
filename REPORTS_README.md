# Analytics & Reports Documentation

This document outlines the logic, database queries, and frontend implementation for the Analytics & Reports page in the Hospimed dashboard. 

## Overview
The Reports page provides the following key analytics:
1. Fast Moving Items
2. Slow Moving Items
3. Unused Ledgers (Dormant Customers)
4. Unused Items (Dead Stock)
5. Sales Profit Daily

Because mobile devices have limited processing power, **all calculations are performed on the Supabase (PostgreSQL) server** using SQL Remote Procedure Calls (RPCs). The Flutter application simply fetches the aggregated results.

---

## 1. Fast Moving & Slow Moving Items

### Logic & Calculation
We define item velocity based on the **total quantity sold** over the last `X` days (default is 30 days). 
- **Fast Moving**: Items sorted in descending order of total quantity sold. The highest numbers represent the fastest moving items.
- **Slow Moving**: Items sorted in ascending order. We filter out items that have zero stock (to only show items sitting on shelves) and rank them by lowest sales volume (including 0 sales if they don't appear in invoice items).

### SQL Implementation
```sql
-- Fast Moving Items (RPC: get_fast_moving_items)
SELECT 
    product_name, 
    SUM(quantity) as total_sold
FROM invoice_items
JOIN sales_invoices ON invoice_items.invoice_id = sales_invoices.id
WHERE sales_invoices.invoice_date >= (CURRENT_DATE - INTERVAL '30 days')
GROUP BY product_name
ORDER BY total_sold DESC
LIMIT 20;

-- Slow Moving Items (RPC: get_slow_moving_items)
SELECT 
    s.ItemName as product_name,
    COALESCE(SUM(i.quantity), 0) as total_sold
FROM stock_items s
LEFT JOIN invoice_items i ON s.ItemName = i.product_name
LEFT JOIN sales_invoices si ON i.invoice_id = si.id AND si.invoice_date >= (CURRENT_DATE - INTERVAL '30 days')
WHERE s.ItemQuantity > 0 -- Must have stock
GROUP BY s.ItemName
ORDER BY total_sold ASC
LIMIT 20;
```

---

## 2. Unused Ledgers (Dormant Customers)

### Logic & Calculation
Identifies customers that exist in the `customers` table but have **not** made a purchase (no records in `sales_invoices`) in the last `X` days (default is 180 days / 6 months).

### SQL Implementation
```sql
-- Unused Ledgers (RPC: get_unused_ledgers)
SELECT c.customer_name, c.mobile_number, c.city
FROM customers c
WHERE c.customer_name NOT IN (
    SELECT DISTINCT customer_name 
    FROM sales_invoices 
    WHERE invoice_date >= (CURRENT_DATE - INTERVAL '180 days')
    AND customer_name IS NOT NULL
)
AND c.is_active = true
LIMIT 50;
```

---

## 3. Unused Items (Dead Stock)

### Logic & Calculation
Identifies items that are physically in stock (`ItemQuantity > 0`) but have **zero sales** in the last 180 days.

### SQL Implementation
```sql
-- Unused Items (RPC: get_unused_items)
SELECT ItemName, ItemQuantity, (ItemQuantity * ItemRate) as stock_value
FROM stock_items
WHERE ItemQuantity > 0
AND ItemName NOT IN (
    SELECT DISTINCT product_name 
    FROM invoice_items i
    JOIN sales_invoices si ON i.invoice_id = si.id
    WHERE si.invoice_date >= (CURRENT_DATE - INTERVAL '180 days')
)
ORDER BY stock_value DESC
LIMIT 50;
```

---

## 4. Sales Profit Daily

### Logic & Calculation
Calculates the estimated daily Gross Profit.
**Formula**: `Gross Profit = (Sale Price per unit - Standard Cost per unit) * Quantity Sold`

**Limitation**: True historical profit requires knowing the exact cost of the item *on the day it was sold*. Since Tally typically syncs the *current* `StandardCost`, this calculation provides an **Estimated Gross Profit** based on the item's current cost in the database.

### SQL Implementation
```sql
-- Sales Profit Daily (RPC: get_daily_profit)
SELECT 
    DATE(si.invoice_date) as sale_date,
    SUM(i.total_amount) as total_revenue,
    SUM( (i.unit_price - COALESCE(s.StandardCost, s.ItemRate, 0)) * i.quantity ) as estimated_profit
FROM sales_invoices si
JOIN invoice_items i ON si.id = i.invoice_id
LEFT JOIN stock_items s ON i.product_name = s.ItemName
WHERE si.invoice_date >= (CURRENT_DATE - INTERVAL '7 days')
GROUP BY DATE(si.invoice_date)
ORDER BY sale_date DESC;
```

---

## Flutter Integration

1. **Backend Integration**: 
   - The Flutter `SupabaseService` uses `supabase.rpc('function_name')` to execute the above queries and return JSON data.
2. **UI Implementation**:
   - `ReportsScreen` will use a TabBar or a Grid of Cards to separate the analytics.
   - The Daily Profit will be visualized using a Bar Chart or Line Chart via the `fl_chart` package.
   - The Fast/Slow/Unused items will be displayed in DataTables or ListViews sorted dynamically.
