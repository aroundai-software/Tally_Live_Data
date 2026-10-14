import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tallylive/providers/company_provider.dart';
import 'package:tallylive/utils/combined_company_selection.dart';
import 'package:tallylive/utils/company_scope.dart';
import 'package:tallylive/widgets/combined_report_widgets.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  group('CombinedCompanySelection', () {
    test('normalizeList trims, drops blanks/placeholder, dedupes, sorts', () {
      final result = CombinedCompanySelection.normalizeList([
        '  Beta Co  ',
        '',
        'No Company Linked',
        'Alpha Co',
        'Beta Co',
        null,
        '  ',
      ]);
      expect(result, ['Alpha Co', 'Beta Co']);
    });

    test('validateSelection keeps only allowed companies', () {
      final validated = CombinedCompanySelection.validateSelection(
        selected: ['Alpha Co', 'Hacker Co', 'Beta Co', ''],
        allowed: ['Beta Co', 'Alpha Co', 'Gamma Co'],
      );
      expect(validated, ['Alpha Co', 'Beta Co']);
      expect(validated.contains('Hacker Co'), isFalse);
    });

    test('isReady requires at least 2 companies', () {
      expect(CombinedCompanySelection.isReady(['A']), isFalse);
      expect(CombinedCompanySelection.isReady(['A', 'B']), isTrue);
      expect(CombinedCompanySelection.isReady(['A', 'A']), isFalse);
      expect(CombinedCompanySelection.isReady(['  A  ', 'B']), isTrue);
    });

    test('selectionKey is stable for same set', () {
      final a = CombinedCompanySelection.selectionKey(['B', 'A']);
      final b = CombinedCompanySelection.selectionKey(['A', 'B', 'A']);
      expect(a, b);
      expect(a, 'A|B');
    });
  });

  group('combinedDateMatches', () {
    test('all includes any date including null', () {
      expect(combinedDateMatches(null, 'all'), isTrue);
      expect(combinedDateMatches(DateTime(2024, 1, 1), 'all'), isTrue);
    });

    test('non-all filters exclude null dates', () {
      expect(combinedDateMatches(null, 'today'), isFalse);
      expect(combinedDateMatches(null, 'thisMonth'), isFalse);
    });

    test('today matches only current day', () {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day, 15, 0);
      final yesterday = today.subtract(const Duration(days: 1));
      expect(combinedDateMatches(today, 'today'), isTrue);
      expect(combinedDateMatches(yesterday, 'today'), isFalse);
    });
  });

  group('CompanyState user Combined Reports flag', () {
    test('defaults off and toggles independently of company features', () {
      final state = CompanyState();
      expect(state.userCombinedReportsEnabled, isFalse);

      state.setFeatures({'dashboard': true, 'sales': true});
      expect(state.userCombinedReportsEnabled, isFalse);

      state.setUserCombinedReportsEnabled(true);
      expect(state.userCombinedReportsEnabled, isTrue);

      state.selectCompany('Company A');
      expect(state.userCombinedReportsEnabled, isTrue);

      state.clearUserCapabilities();
      expect(state.userCombinedReportsEnabled, isFalse);
    });
  });

  group('CompanyState combined mode', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('enterCombinedMode requires ≥2 and clears selectedCompany', () {
      final state = CompanyState();
      expect(state.enterCombinedMode(['Only One']), isFalse);
      expect(state.isCombinedMode, isFalse);

      expect(state.enterCombinedMode(['B', 'A']), isTrue);
      expect(state.isCombinedMode, isTrue);
      expect(state.selectedCompany, isNull);
      expect(state.selectedCompanies, ['A', 'B']);
      expect(state.scopeKey, 'combined:A|B');
    });

    test('selectCompany exits combined and clears set', () {
      final state = CompanyState();
      state.enterCombinedMode(['A', 'B']);
      final rev = state.companyRevision;
      state.selectCompany('X');
      expect(state.isCombinedMode, isFalse);
      expect(state.selectedCompany, 'X');
      expect(state.selectedCompanies, isEmpty);
      expect(state.scopeKey, 'single:X');
      expect(state.companyRevision, greaterThan(rev));
    });

    test('disabling user flag exits combined mode', () {
      final state = CompanyState();
      state.setUserCombinedReportsEnabled(true);
      state.enterCombinedMode(['A', 'B']);
      state.setUserCombinedReportsEnabled(false);
      expect(state.isCombinedMode, isFalse);
      expect(state.selectedCompanies, isEmpty);
      expect(state.selectedCompany, isNull);
    });

    test('setFeaturesUnion ORs feature maps', () {
      final state = CompanyState();
      state.setFeaturesUnion([
        {'sales': true, 'stock': false},
        {'sales': false, 'purchases': true, 'stock': true},
      ]);
      expect(state.isFeatureEnabled('sales'), isTrue);
      expect(state.isFeatureEnabled('purchases'), isTrue);
      expect(state.isFeatureEnabled('stock'), isTrue);
    });

    test('clearCompany resets mode and set', () {
      final state = CompanyState();
      state.enterCombinedMode(['A', 'B']);
      state.clearCompany();
      expect(state.isCombinedMode, isFalse);
      expect(state.selectedCompanies, isEmpty);
      expect(state.scopeKey, 'none');
    });
  });

  group('CompanyScope scope keys', () {
    test('stillActiveScope rejects none and mismatches', () {
      expect(CompanyScope.stillActiveScope('single:A', 'single:A'), isTrue);
      expect(CompanyScope.stillActiveScope('single:A', 'single:B'), isFalse);
      expect(CompanyScope.stillActiveScope('none', 'none'), isFalse);
      expect(CompanyScope.stillActiveScope(null, 'single:A'), isFalse);
    });

    test('scopeKeyForCombined matches selectionKey', () {
      expect(
        CompanyScope.scopeKeyForCombined(['B', 'A']),
        'combined:A|B',
      );
      expect(CompanyScope.scopeKeyForCombined(['A']), 'none');
    });
  });
}
