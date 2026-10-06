import 'package:flutter/foundation.dart';

/// Helpers for strict per-company data isolation in the Flutter app.
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
}
