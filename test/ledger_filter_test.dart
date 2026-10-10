import 'package:flutter_test/flutter_test.dart';
import 'package:tallylive/models/ledger.dart';

Ledger _ledger(Map<String, dynamic> json) => Ledger.fromJson(json);

void main() {
  group('Ledger type filters', () {
    test('sundry debtor via ledger_type', () {
      final ledger = _ledger({'customer_name': 'ABC Traders', 'ledger_type': 'Sundry Debtors'});
      expect(ledger.isDebtor, isTrue);
      expect(ledger.isCreditor, isFalse);
    });

    test('sundry creditor via ledger_type', () {
      final ledger = _ledger({'customer_name': 'XYZ Supplies', 'ledger_type': 'Sundry Creditors'});
      expect(ledger.isDebtor, isFalse);
      expect(ledger.isCreditor, isTrue);
    });

    test('missing type defaults to debtor for customer ledgers', () {
      final ledger = _ledger({'customer_name': 'GMA PINNACLE AUTOMOTIVES PRIVATE LIMITED'});
      expect(ledger.isDebtor, isTrue);
      expect(ledger.isCreditor, isFalse);
    });

    test('category fallback when ledger_type is missing', () {
      final ledger = _ledger({
        'customer_name': 'Vendor Co',
        'customer_category_name': 'Sundry Creditors',
      });
      expect(ledger.isDebtor, isFalse);
      expect(ledger.isCreditor, isTrue);
    });

    test('bank and cash ledgers are excluded from debtor/creditor tabs', () {
      final bank = _ledger({'customer_name': 'HDFC Bank', 'ledger_type': 'Bank Accounts'});
      final cash = _ledger({'customer_name': 'Cash', 'ledger_type': 'Cash-in-Hand'});

      expect(bank.isDebtor, isFalse);
      expect(bank.isCreditor, isFalse);
      expect(cash.isDebtor, isFalse);
      expect(cash.isCreditor, isFalse);
    });
  });

  group('Ledger search', () {
    test('matches alias and mailing name', () {
      final ledger = _ledger({
        'customer_name': 'Full Legal Name Pvt Ltd',
        'alias': 'FLN',
        'mailing_name': 'Short Name',
      });

      expect(ledger.matchesSearchQuery('fln'), isTrue);
      expect(ledger.matchesSearchQuery('short name'), isTrue);
      expect(ledger.matchesSearchQuery('legal'), isTrue);
      expect(ledger.matchesSearchQuery('missing'), isFalse);
    });

    test('empty query matches everything', () {
      final ledger = _ledger({'customer_name': 'Any Customer'});
      expect(ledger.matchesSearchQuery(''), isTrue);
    });
  });
}
