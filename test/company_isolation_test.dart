import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tallylive/providers/company_provider.dart';
import 'package:tallylive/utils/company_scope.dart';

void main() {
  group('CompanyScope', () {
    test('isValid rejects null, blank, and placeholder', () {
      expect(CompanyScope.isValid(null), isFalse);
      expect(CompanyScope.isValid(''), isFalse);
      expect(CompanyScope.isValid('   '), isFalse);
      expect(CompanyScope.isValid('No Company Linked'), isFalse);
      expect(CompanyScope.isValid('AL ZAHRA DEMO EQIPMENT'), isTrue);
    });

    test('stillActive only when captured matches current and is valid', () {
      const a = 'AL ZAHRA DEMO EQIPMENT';
      const b = 'OTHER CO';
      expect(CompanyScope.stillActive(a, a), isTrue);
      expect(CompanyScope.stillActive(a, b), isFalse);
      expect(CompanyScope.stillActive(a, null), isFalse);
      expect(CompanyScope.stillActive(null, a), isFalse);
      expect(CompanyScope.stillActive('', ''), isFalse);
    });

    test('screenKey embeds company name', () {
      final key = CompanyScope.screenKey('dash', 'AL ZAHRA DEMO EQIPMENT');
      expect(key, isA<ValueKey<String>>());
      expect((key as ValueKey<String>).value, 'dash:AL ZAHRA DEMO EQIPMENT');
      expect(CompanyScope.screenKey('stock', null), const ValueKey('stock:'));
    });
  });

  group('CompanyState revision', () {
    test('selectCompany increments revision and trims name', () {
      final state = CompanyState();
      expect(state.companyRevision, 0);

      state.selectCompany('  AL ZAHRA DEMO EQIPMENT  ');
      expect(state.selectedCompany, 'AL ZAHRA DEMO EQIPMENT');
      expect(state.companyRevision, 1);
      expect(state.featuresLoaded, isFalse);

      // Same company again: no revision bump
      state.selectCompany('AL ZAHRA DEMO EQIPMENT');
      expect(state.companyRevision, 1);

      state.selectCompany('OTHER CO');
      expect(state.companyRevision, 2);
      expect(state.selectedCompany, 'OTHER CO');
    });

    test('selectCompany ignores empty names', () {
      final state = CompanyState();
      state.selectCompany('AL ZAHRA DEMO EQIPMENT');
      final rev = state.companyRevision;
      state.selectCompany('   ');
      expect(state.selectedCompany, 'AL ZAHRA DEMO EQIPMENT');
      expect(state.companyRevision, rev);
    });

    test('clearCompany bumps revision and clears selection', () {
      final state = CompanyState();
      state.selectCompany('AL ZAHRA DEMO EQIPMENT');
      state.setFeatures({'stock': true});
      state.notifySyncCompleted();
      expect(state.syncTrigger, 1);
      expect(state.featuresLoaded, isTrue);

      final revBefore = state.companyRevision;
      state.clearCompany();
      expect(state.selectedCompany, isNull);
      expect(state.companyRevision, revBefore + 1);
      expect(state.syncTrigger, 0);
      expect(state.featuresLoaded, isFalse);
    });

    test('race guard simulation: stale load discarded after switch', () {
      final state = CompanyState();
      state.selectCompany('Company A');
      final captured = state.selectedCompany;
      var generation = 1;
      final results = <String>[];

      // Simulate in-flight load for A
      void applyIfActive(int gen, String? company, String label) {
        if (gen != generation) return;
        if (!CompanyScope.stillActive(company, state.selectedCompany)) return;
        results.add(label);
      }

      // User switches before A finishes
      state.selectCompany('Company B');
      generation++;
      applyIfActive(1, captured, 'stale-A'); // should discard
      applyIfActive(generation, state.selectedCompany, 'fresh-B');

      expect(results, ['fresh-B']);
      expect(CompanyScope.stillActive(captured, state.selectedCompany), isFalse);
    });
  });
}
