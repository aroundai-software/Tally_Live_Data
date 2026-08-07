# Hospimed: Comprehensive Project Analysis

## 1. Introduction & Overview
Hospimed (also referred to in documentation as Rahul Traders) is a robust, cross-platform mobile and web application built using the Flutter framework. It is backed by a Supabase (PostgreSQL) database. The primary goal of the application is to manage medical and hospital equipment inventory, track sales, monitor financial standing, and provide deep analytics.

**Technology Stack:**
- **Frontend:** Flutter (Dart) for rendering seamlessly on iOS, Android, and Web.
- **Backend & Database:** Supabase (PostgreSQL) for secure, scalable, real-time data management.
- **Data Visualization:** `fl_chart` for dynamic rendering of charts.
- **State Management:** Provider pattern (e.g., CompanyProvider).

## 2. What Does the App Do?
The application serves as a comprehensive operational and financial dashboard. Its core functionalities are split into several modules:

### 2.1 Inventory & Stock Management
- **Catalog Management:** Displays complete product catalogs with Item Name, Quantity, Rate, Standard Cost, and MRP.
- **Valuation:** Calculates the total value of stock currently on hand dynamically (`Sum(ItemQuantity * ItemRate)`).

### 2.2 Sales & Invoices
- **Invoice Tracking:** Manages the entire sales workflow, capturing invoice numbers, dates, customer details, and net amounts.
- **Line Items & Taxation:** Handles itemized billing, calculating subtotals, applying discount percentages, and calculating GST rates dynamically to produce a net amount.

### 2.3 Customer & Ledger Management
- **Directory:** Manages a directory of customers, their contact details, credit limits, and opening balances.
- **Outstanding Balances:** Tracks Receivables (money owed to the business) and Payables (money the business owes to suppliers). It monitors aging bills and overdue days to highlight accounts needing collection efforts.

### 2.4 Daybook (Audit Trail)
- **Daily Transactions:** Provides a clear audit trail of daily accounting vouchers (Receipts, Payments, Sales, etc.).
- **Debit/Credit Tracking:** Segregates transactions accurately based on their accounting nature.

### 2.5 Analytics & Reports Engine
To optimize performance on mobile devices, Hospimed offloads heavy analytical calculations to the Supabase backend using optimized SQL Remote Procedure Calls (RPCs). 
- **Fast/Slow Moving Items:** Identifies top-selling products and underperforming products.
- **Dead Stock:** Highlights inventory items with zero sales over the last 180 days, allowing the business to identify tied-up capital.
- **Dormant Customers:** Identifies customers who haven't made a purchase recently (e.g., 6 months), aiding in targeted re-engagement campaigns.
- **Daily Sales & Estimated Profit:** Uses 14-day trends to map daily revenue and calculates gross profit by dynamically checking standard costs and item rates against selling prices.

## 3. What is it Used For?
Hospimed is used as a central hub for business operations. It is specifically tailored for medical equipment suppliers or hospital administration to:
1. Provide a mobile-friendly layer over existing traditional accounting software (like Tally). Data is synchronized using unique identifiers (`guid`, `master_id`).
2. Give business owners instant access to their financial health and inventory status without needing to log into complex ERP systems on desktop computers.
3. Streamline the process of viewing stock availability and generating sales invoices on the go.

## 4. How it Helps Businesses
The implementation of Hospimed brings significant operational and financial benefits to a business:

- **Enhanced Cash Flow Management:** By explicitly tracking overdue days on receivables, businesses can optimize their collection efforts, reducing bad debts and improving cash flow.
- **Capital Optimization:** Identifying 'Dead Stock' (unused items) allows businesses to clear out inventory that is tying up capital and taking up warehouse space.
- **Targeted Marketing & Sales:** By identifying 'Dormant Customers', the sales team can proactively reach out to old clients with promotions or follow-ups to re-engage them.
- **Strategic Decision Making:** The Daily Sales & Estimated Profit charts provide owners with an immediate pulse on the business's profitability, allowing them to make rapid adjustments to pricing or procurement strategies.
- **Operational Efficiency:** Sales teams in the field can check stock levels and pricing in real-time on their mobile devices, improving customer response times and closing deals faster.

## 5. Security & Architecture
- **Data Privacy:** Uses PostgreSQL Row Level Security (RLS) to ensure that users can only access data belonging to their specific company/branch.
- **Scalability:** The decision to use SQL RPCs for analytics ensures that as the database grows (thousands of invoices), the mobile app remains snappy and responsive.
