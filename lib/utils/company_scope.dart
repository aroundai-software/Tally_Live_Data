import 'package:flutter/foundation.dart';
import '../providers/company_provider.dart';
import 'combined_company_selection.dart';

/// Helpers for strict per-company / per-scope data isolation in the Flutter app.
class CompanyScope {
  CompanyScope._();

  static bool isValid(String? company) =>
      company != null &&
      company.trim().isNotEmpty &&
      company != 'No Company Linked';

  /// Returns true when [current] still matches the company captured at load start.
  static bool stillActive(String? captured, String? current) =>
      captured != null && captured == current && isValid(current);

  static Key screenKey(String prefix, String? company) =>
      ValueKey('$prefix:${company ?? ''}');

  /// Isolation key from [CompanyState] (`single:<name>` or `combined:<key>`).
  static String scopeKeyOf(CompanyState state) => state.scopeKey;

  static String scopeKeyForSingle(String? company) {
    if (!isValid(company)) return 'none';
    return 'single:${company!.trim()}';
  }

  static String scopeKeyForCombined(Iterable<String?> companies) {
    final list = CombinedCompanySelection.normalizeList(companies);
    if (!CombinedCompanySelection.isReady(list)) return 'none';
    return 'combined:${CombinedCompanySelection.selectionKey(list)}';
  }

  static bool stillActiveScope(String? capturedKey, String? currentKey) =>
      capturedKey != null &&
      currentKey != null &&
      capturedKey == currentKey &&
      capturedKey != 'none' &&
      currentKey != 'none';

  static Key screenKeyForScope(String prefix, String scopeKey) =>
      ValueKey('$prefix:$scopeKey');

  /// True when the app has an active single company or a ready combined set.
  static bool hasActiveScope(CompanyState state) {
    if (state.isCombinedMode) {
      return CombinedCompanySelection.isReady(state.selectedCompanies);
    }
    return isValid(state.selectedCompany);
  }

  /// Company for a row opened from a list (ledger, stock item, etc.).
  /// Prefer the record's own company — required in Combined where
  /// [CompanyState.selectedCompany] is null.
  static String? companyForRecord(
    CompanyState state,
    String? recordCompany,
  ) {
    final fromRecord = recordCompany?.trim();
    if (isValid(fromRecord)) return fromRecord;
    if (!state.isCombinedMode) {
      final selected = state.selectedCompany?.trim();
      if (isValid(selected)) return selected;
    }
    return null;
  }
}
