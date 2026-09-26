import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Centralized service for saving and restoring user preferences
/// across all screens. All keys are namespaced with `pref_` to avoid conflicts.
class UserPreferencesService {
  // ─── Preference Keys ────────────────────────────────────────────────────────
  static const _kLastCompany         = 'pref_last_company';

  static const _kSalesSort           = 'pref_sales_sort';
  static const _kSalesDateFilter     = 'pref_sales_date_filter';

  static const _kPurchaseSort        = 'pref_purchase_sort';
  static const _kPurchaseDateFilter  = 'pref_purchase_date_filter';

  static const _kStockSort           = 'pref_stock_sort';
  static const _kStockStatusFilter   = 'pref_stock_status_filter';
  static const _kCategoryTrackingData = 'pref_category_tracking_data';
  static const _kSeenProductParents  = 'pref_seen_product_parents';

  static const _kLedgerTypeFilter    = 'pref_ledger_type_filter';

  static const _kOutstandingSortAmount = 'pref_outstanding_sort_amount';
  static const _kOutstandingSortDate   = 'pref_outstanding_sort_date';

  // ─── Company ────────────────────────────────────────────────────────────────
  static Future<void> saveLastCompany(String company) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLastCompany, company);
  }

  static Future<String?> loadLastCompany() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kLastCompany);
  }

  static Future<void> clearLastCompany() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kLastCompany);
  }

  // ─── Sales Invoice ──────────────────────────────────────────────────────────
  static Future<void> saveSalesSort(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSalesSort, value);
  }

  static Future<String> loadSalesSort() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kSalesSort) ?? 'dateNewest';
  }

  static Future<void> saveSalesDateFilter(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSalesDateFilter, value);
  }

  static Future<String> loadSalesDateFilter() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kSalesDateFilter) ?? 'today';
  }

  // ─── Purchase Invoice ───────────────────────────────────────────────────────
  static Future<void> savePurchaseSort(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPurchaseSort, value);
  }

  static Future<String> loadPurchaseSort() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kPurchaseSort) ?? 'dateNewest';
  }

  static Future<void> savePurchaseDateFilter(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPurchaseDateFilter, value);
  }

  static Future<String> loadPurchaseDateFilter() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kPurchaseDateFilter) ?? 'today';
  }

  // ─── Stock / Products ───────────────────────────────────────────────────────
  static Future<void> saveStockSort(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kStockSort, value);
  }

  static Future<String> loadStockSort() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kStockSort) ?? 'alpha_asc';
  }

  static Future<void> saveStockStatusFilter(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kStockStatusFilter, value);
  }

  static Future<String> loadStockStatusFilter() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kStockStatusFilter) ?? 'All';
  }

  // Format: { "CategoryName": { "discoveredAt": 1690000000000, "isRead": true } }
  static Future<Map<String, dynamic>> loadCategoryTrackingData() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_kCategoryTrackingData);
    if (jsonString != null && jsonString.isNotEmpty) {
      try {
        return json.decode(jsonString) as Map<String, dynamic>;
      } catch (_) {}
    }
    return {};
  }

  static Future<void> saveCategoryTrackingData(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kCategoryTrackingData, json.encode(data));
  }

  static Future<void> saveSeenProductParents(List<String> parents) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kSeenProductParents, parents);
  }

  static Future<List<String>> loadSeenProductParents() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_kSeenProductParents) ?? [];
  }

  // ─── Ledger / Customers ─────────────────────────────────────────────────────
  static Future<void> saveLedgerTypeFilter(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLedgerTypeFilter, value);
  }

  static Future<String> loadLedgerTypeFilter() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kLedgerTypeFilter) ?? 'All';
  }

  // ─── Outstanding / Receivables & Payables ──────────────────────────────────
  static Future<void> saveOutstandingSort({
    required bool sortByAmount,
    required bool sortByDate,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kOutstandingSortAmount, sortByAmount);
    await prefs.setBool(_kOutstandingSortDate, sortByDate);
  }

  static Future<({bool sortByAmount, bool sortByDate})> loadOutstandingSort() async {
    final prefs = await SharedPreferences.getInstance();
    return (
      sortByAmount: prefs.getBool(_kOutstandingSortAmount) ?? true,
      sortByDate:   prefs.getBool(_kOutstandingSortDate)   ?? false,
    );
  }
}
