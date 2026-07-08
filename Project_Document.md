# Hospimed Project Documentation

## 1. Project Overview
Hospimed is a Flutter-based mobile and web application designed to manage medical/hospital equipment inventory, sales, and analytics. It seamlessly integrates with a Supabase (PostgreSQL) backend, serving as a comprehensive dashboard that handles data potentially synchronized from accounting software (like Tally).

## 2. Technology Stack
- **Frontend**: Flutter (Dart)
- **Backend & Database**: Supabase (PostgreSQL)
- **Data Visualization**: `fl_chart` package in Flutter
- **State Management**: Provider (e.g., CompanyProvider)

## 3. Core Modules

### 3.1 Company Management
Allows switching between different companies or branches. Data is filtered on the frontend and backend using `company_name` or `guid`.

### 3.2 Sales & Invoices
Manages the core sales workflow. 
- **Sales Invoices**: Tracks invoice numbers, dates, customers, total amounts, discounts, and GST.
- **Invoice Items**: Detailed line items for each invoice tracking product names, quantities, unit prices, and GST rates.

### 3.3 Inventory Management
Tracks medical stock items, including standard cost, selling price, current quantities, categories, and HSN codes. 

### 3.4 Customers & Outstanding Balances
Tracks customer details and their financial standing, including outstanding receivables and payables. Helps in determining overdue amounts and credit limits.

## 4. Analytics & Reports Engine

Because mobile devices have limited processing power, all heavy calculations for analytics are performed on the Supabase PostgreSQL server using optimized SQL Remote Procedure Calls (RPCs).

### 4.1 Fast Moving Items
Identifies the most popular items based on total quantity sold over a configurable period (default 30 days).
- **Backend**: `get_fast_moving_items` RPC.

### 4.2 Slow Moving Items
Identifies stock items that are sitting on shelves with little to no sales.
- **Backend**: `get_slow_moving_items` RPC.

### 4.3 Unused Ledgers (Dormant Customers)
Identifies customers who have not made a purchase within the last 6 months (default 180 days).
- **Backend**: `get_unused_ledgers` RPC.

### 4.4 Unused Items (Dead Stock)
Identifies inventory items that have zero sales over the last 6 months but are still in stock.
- **Backend**: `get_unused_items` RPC.

### 4.5 Daily Sales & Estimated Profit
Calculates daily revenue and estimated gross profit. 
- **Revenue**: Sum of invoice totals for the day.
- **Profit**: `(Selling Price - Standard Cost) * Quantity`. Uses a fallback logic where it checks `StandardCost`, then `ItemRate`, or defaults to `0` if neither is available.
- **Backend**: `get_daily_profit` RPC.

## 5. Database Schema Summary
Key tables involved in the operations include:
- `tally_companies`: Base company details.
- `customers`: Customer directory and balances.
- `stock_items`: Inventory and pricing.
- `sales_invoices` & `invoice_items`: Transaction records.
- `outstanding_receivables` / `outstanding_payables`: Accounts tracking.
- `tally_daybook`: Daily voucher tracking.

## 6. Architecture & Security
- **Row Level Security (RLS)**: Can be applied on Supabase to ensure users only access their authorized company data.
- **Data Sync**: The database structure includes `guid`, `master_id`, and `synced_to_tally` fields to facilitate two-way or one-way syncing with external ERP systems like Tally.
