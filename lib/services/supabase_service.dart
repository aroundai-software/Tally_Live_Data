import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/stock_item.dart';
import '../models/ledger.dart';
import '../models/receivable_payable.dart';
import '../models/sales_invoice.dart';
import '../models/purchase_invoice.dart';
import '../models/daybook_entry.dart';

class SupabaseService {
  final SupabaseClient _client = Supabase.instance.client;

  // ─── Companies ───────────────────────────────────────────────
  Future<List<String>> getCompanies() async {
    try {
      final names = <String>{};

      // Fetch all company names from tally_companies table
      int offset = 0;
      const int limit = 1000;
      bool hasMore = true;
      while (hasMore) {
        final response = await _client
            .from('tally_companies')
            .select('company_name')
            .eq('is_active', true)
            .range(offset, offset + limit - 1);
        final data = response as List;
        for (var item in data) {
          final name = item['company_name'];
          if (name != null && name.toString().isNotEmpty) {
            names.add(name.toString());
          }
        }
        hasMore = data.length == limit;
        offset += limit;
      }

      final sorted = names.toList()..sort();
      return sorted;
    } catch (e) {
      throw Exception('Failed to fetch companies: $e');
    }
  }

  // ─── Products (Stock) ──────────────────────────────────────────
  Future<List<StockItem>> getProducts({String? searchQuery, String? companyName}) async {
    try {
      final data = await _fetchAll(
        'stock_items',
        companyName: companyName,
        searchQuery: searchQuery,
        searchColumn: 'ItemName',
        orderColumn: 'ItemName',
      );
      return data.map((e) => StockItem.fromJson(e)).toList();
    } catch (e) {
      throw Exception('Failed to fetch products: $e');
    }
  }

  Future<double> getTotalStockValue({String? companyName}) async {
    try {
      final data = await _fetchAll(
        'stock_items',
        select: 'ItemQuantity, ItemRate',
        companyName: companyName,
      );
      double total = 0;
      for (var item in data) {
        final qty = _toDouble(item['ItemQuantity']);
        final rate = _toDouble(item['ItemRate']);
        total += qty * rate;
      }
      return total;
    } catch (e) {
      return 0;
    }
  }

  Future<int> getProductCount({String? companyName}) async {
    return _fetchCount('stock_items', companyName: companyName);
  }

  // ─── Customers (Ledgers) ───────────────────────────────────────
  Future<List<Ledger>> getCustomers({String? searchQuery, String? companyName}) async {
    try {
      final data = await _fetchAll(
        'customers',
        companyName: companyName,
        searchQuery: searchQuery,
        searchColumn: 'customer_name',
        orderColumn: 'customer_name',
      );
      return data.map((e) => Ledger.fromJson(e)).toList();
    } catch (e) {
      throw Exception('Failed to fetch customers: $e');
    }
  }

  Future<int> getCustomerCount({String? companyName}) async {
    return _fetchCount('customers', companyName: companyName);
  }

  // ─── Outstanding (Receivables & Payables) ──────────────────────
  Future<List<OutstandingRecord>> getOutstandingReceivables({String? searchQuery, String? companyName}) async {
    try {
      final data = await _fetchAll(
        'outstanding_receivables',
        companyName: companyName,
        searchQuery: searchQuery,
        searchColumn: 'customer_name',
        orderColumn: 'customer_name',
      );
      return data.map((e) => OutstandingRecord.fromJson(e)).toList();
    } catch (e) {
      throw Exception('Failed to fetch outstanding receivables: $e');
    }
  }

  Future<List<OutstandingRecord>> getOutstandingPayables({String? searchQuery, String? companyName}) async {
    try {
      final data = await _fetchAll(
        'outstanding_payables',
        companyName: companyName,
        searchQuery: searchQuery,
        searchColumn: 'customer_name',
        orderColumn: 'customer_name',
      );
      return data.map((e) => OutstandingRecord.fromJson(e)).toList();
    } catch (e) {
      throw Exception('Failed to fetch outstanding payables: $e');
    }
  }

  Future<double> getTotalReceivables({String? companyName}) async {
    try {
      final data = await _fetchAll(
        'outstanding_receivables',
        select: 'amount, closing_balance',
        companyName: companyName,
      );
      double total = 0;
      for (var item in data) {
        final amount = _toDouble(item['amount']);
        final closing = _toDouble(item['closing_balance']);
        total += closing != 0 ? closing.abs() : amount.abs();
      }
      return total;
    } catch (e) {
      return 0;
    }
  }

  Future<double> getTotalPayables({String? companyName}) async {
    try {
      final data = await _fetchAll(
        'outstanding_payables',
        select: 'amount, closing_balance',
        companyName: companyName,
      );
      double total = 0;
      for (var item in data) {
        final amount = _toDouble(item['amount']);
        final closing = _toDouble(item['closing_balance']);
        total += closing != 0 ? closing.abs() : amount.abs();
      }
      return total;
    } catch (e) {
      return 0;
    }
  }

  // ─── Sales Invoices ────────────────────────────────────────────
  Future<List<SalesInvoice>> getSalesInvoices({String? searchQuery, String? companyName}) async {
    try {
      final data = await _fetchAll(
        'sales_invoices',
        companyName: companyName,
        searchQuery: searchQuery,
        orderColumn: 'invoice_date',
        ascending: false,
      );
      return data.map((e) => SalesInvoice.fromJson(e)).toList();
    } catch (e) {
      throw Exception('Failed to fetch sales invoices: $e');
    }
  }

  Future<double> getTotalSales({String? companyName}) async {
    try {
      final data = await _fetchAll(
        'sales_invoices',
        select: 'net_amount',
        companyName: companyName,
      );
      double total = 0;
      for (var item in data) {
        total += _toDouble(item['net_amount']);
      }
      return total;
    } catch (e) {
      return 0;
    }
  }

  Future<int> getSalesInvoiceCount({String? companyName}) async {
    return _fetchCount('sales_invoices', companyName: companyName);
  }

  Future<List<InvoiceItem>> getInvoiceItems(String invoiceId) async {
    try {
      final response = await _client
          .from('invoice_items')
          .select()
          .eq('invoice_id', invoiceId);
      return (response as List).map((e) => InvoiceItem.fromJson(e)).toList();
    } catch (e) {
      return [];
    }
  }

  // ─── Purchase Invoices ─────────────────────────────────────────
  Future<List<PurchaseInvoice>> getPurchaseInvoices({String? searchQuery, String? companyName}) async {
    try {
      final data = await _fetchAll(
        'purchase_invoices',
        companyName: companyName,
        searchQuery: searchQuery,
        orderColumn: 'invoice_date',
        ascending: false,
      );
      return data.map((e) => PurchaseInvoice.fromJson(e)).toList();
    } catch (e) {
      throw Exception('Failed to fetch purchase invoices: $e');
    }
  }

  Future<double> getTotalPurchases({String? companyName}) async {
    try {
      final data = await _fetchAll(
        'purchase_invoices',
        select: 'net_amount',
        companyName: companyName,
      );
      double total = 0;
      for (var item in data) {
        total += _toDouble(item['net_amount']);
      }
      return total;
    } catch (e) {
      return 0;
    }
  }

  Future<int> getPurchaseInvoiceCount({String? companyName}) async {
    return _fetchCount('purchase_invoices', companyName: companyName);
  }

  Future<List<PurchaseInvoiceItem>> getPurchaseInvoiceItems(String invoiceId) async {
    try {
      final response = await _client
          .from('invoice_items_purchase')
          .select()
          .eq('purchase_invoice_id', invoiceId);
      return (response as List).map((e) => PurchaseInvoiceItem.fromJson(e)).toList();
    } catch (e) {
      return [];
    }
  }

  // ─── Daybook ───────────────────────────────────────────────────
  Future<List<DaybookEntry>> getDaybookEntries({DateTime? date, String? companyName, String? searchQuery}) async {
    try {
      dynamic query = _client.from('tally_daybook').select();
      
      if (companyName != null && companyName.isNotEmpty) {
        query = query.ilike('company_name', companyName);
      }
      
      if (date != null) {
        // Filter by specific date (ignore time)
        final startOfDay = DateTime(date.year, date.month, date.day).toUtc().toIso8601String();
        final endOfDay = DateTime(date.year, date.month, date.day, 23, 59, 59, 999).toUtc().toIso8601String();
        query = query.gte('date', startOfDay).lte('date', endOfDay);
      }
      
      if (searchQuery != null && searchQuery.isNotEmpty) {
         query = query.or('voucher_number.ilike.%$searchQuery%,ledger_name.ilike.%$searchQuery%,voucher_type.ilike.%$searchQuery%');
      }

      final response = await query.order('date', ascending: false).limit(1000);
      return (response as List).map((e) => DaybookEntry.fromJson(e)).toList();
    } catch (e) {
      return [];
    }
  }

  Future<Map<String, double>> getDaybookSummary({DateTime? date, String? companyName}) async {
    try {
      final entries = await getDaybookEntries(date: date, companyName: companyName);
      double inflow = 0;
      double outflow = 0;
      for (var entry in entries) {
        if (entry.isDebit) {
          inflow += entry.amount.abs();
        } else {
          outflow += entry.amount.abs();
        }
      }
      return {'inflow': inflow, 'outflow': outflow};
    } catch (e) {
      return {'inflow': 0, 'outflow': 0};
    }
  }

  // ─── Reports & Analytics ───────────────────────────────────────
  
  Future<List<Map<String, dynamic>>> getFastMovingItems({String? companyName, int days = 30}) async {
    try {
      final response = await _client.rpc('get_fast_moving_items', params: {
        'p_company_name': companyName,
        'p_days': days,
      });
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error in getFastMovingItems: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getSlowMovingItems({String? companyName, int days = 30}) async {
    try {
      final response = await _client.rpc('get_slow_moving_items', params: {
        'p_company_name': companyName,
        'p_days': days,
      });
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getUnusedLedgers({String? companyName, int days = 180}) async {
    try {
      final response = await _client.rpc('get_unused_ledgers', params: {
        'p_company_name': companyName,
        'p_days': days,
      });
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getUnusedItems({String? companyName, int days = 180}) async {
    try {
      final response = await _client.rpc('get_unused_items', params: {
        'p_company_name': companyName,
        'p_days': days,
      });
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getDailyProfit({String? companyName, int days = 7}) async {
    try {
      final response = await _client.rpc('get_daily_profit', params: {
        'p_company_name': companyName,
        'p_days': days,
      });
      return List<Map<String, dynamic>>.from(response);
    } catch (e, st) {
      print('Error in getDailyProfit: $e\n$st');
      return [];
    }
  }

  // ─── Helpers ───────────────────────────────────────────────────

  Future<List<dynamic>> _fetchAll(String table, {
    String select = '*',
    String? companyName,
    String? searchQuery,
    String? searchColumn,
    String? orderColumn,
    bool ascending = true,
  }) async {
    List<dynamic> allData = [];
    int offset = 0;
    const int limit = 1000;
    bool hasMore = true;

    while (hasMore) {
      dynamic query = _client.from(table).select(select);
      
      if (companyName != null && companyName.isNotEmpty) {
        query = query.ilike('company_name', companyName);
      }
      
      if (searchQuery != null && searchQuery.isNotEmpty) {
        if (table == 'sales_invoices') {
          query = query.or('customer_name.ilike.%$searchQuery%,invoice_number.ilike.%$searchQuery%');
        } else if (table == 'purchase_invoices') {
          query = query.or('supplier_name.ilike.%$searchQuery%,invoice_number.ilike.%$searchQuery%');
        } else if (table == 'stock_items') {
          // Multi-column search for products: Name, PartNumber, Rate, Quantity
          // Since Rate and Quantity are numeric, we can't use ilike directly on them in Supabase .or() 
          // easily without casting, but we can search in text columns and handle numeric filtering if needed.
          // For now, let's support Name and PartNumber in the query.
          query = query.or('ItemName.ilike.%$searchQuery%,PartNumber.ilike.%$searchQuery%');
        } else if (searchColumn != null) {
          query = query.ilike(searchColumn, '%$searchQuery%');
        }
      }

      if (orderColumn != null) {
        query = query.order(orderColumn, ascending: ascending);
      }

      final response = await query.range(offset, offset + limit - 1);
      final data = response as List;
      allData.addAll(data);
      hasMore = data.length == limit;
      offset += limit;
    }
    return allData;
  }

  Future<int> _fetchCount(String table, {String? companyName}) async {
    try {
      int total = 0;
      int offset = 0;
      const int limit = 1000;
      bool hasMore = true;

      while (hasMore) {
        dynamic query = _client.from(table).select('id');
        if (companyName != null && companyName.isNotEmpty) {
          query = query.ilike('company_name', companyName);
        }
        final response = await query.range(offset, offset + limit - 1);
        final data = response as List;
        total += data.length;
        hasMore = data.length == limit;
        offset += limit;
      }
      return total;
    } catch (e) {
      return 0;
    }
  }

  static double _toDouble(dynamic val) {
    if (val == null) return 0;
    if (val is double) return val;
    if (val is int) return val.toDouble();
    return double.tryParse(val.toString()) ?? 0;
  }
}

