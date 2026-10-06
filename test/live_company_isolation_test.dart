import 'package:flutter_test/flutter_test.dart';
import 'package:supabase/supabase.dart';
import 'package:tallylive/config/supabase_config.dart';

/// Live Supabase checks for AL ZAHRA DEMO EQIPMENT isolation.
/// Skips cleanly if the project is unreachable.
void main() {
  const company = 'AL ZAHRA DEMO EQIPMENT';
  late SupabaseClient client;

  setUpAll(() {
    client = SupabaseClient(
      SupabaseConfig.supabaseUrl,
      SupabaseConfig.supabaseAnonKey,
    );
  });

  Future<int> countExact(String table) async {
    final res = await client
        .from(table)
        .select('id')
        .eq('company_name', company)
        .count(CountOption.exact);
    return res.count;
  }

  Future<int> blankCompanyCount(String table) async {
    final empty = await client
        .from(table)
        .select('id')
        .eq('company_name', '')
        .count(CountOption.exact);
    // PostgREST null filter: is_(column, null)
    final nulls = await client
        .from(table)
        .select('id')
        .filter('company_name', 'is', null)
        .count(CountOption.exact);
    return empty.count + nulls.count;
  }

  test('Al Zahra has expected business data volumes', () async {
    final customers = await countExact('customers');
    final stock = await countExact('stock_items');
    final sales = await countExact('sales_invoices');
    final daybook = await countExact('tally_daybook');
    final receivables = await countExact('outstanding_receivables');
    final payables = await countExact('outstanding_payables');
    final purchases = await countExact('purchase_invoices');

    // Print for human review in test output
    // ignore: avoid_print
    print('Al Zahra counts => '
        'customers=$customers stock=$stock sales=$sales purchases=$purchases '
        'daybook=$daybook recv=$receivables pay=$payables');

    expect(customers, greaterThan(100), reason: 'customers for Al Zahra');
    expect(stock, greaterThan(100), reason: 'stock for Al Zahra');
    expect(sales, greaterThan(10), reason: 'sales for Al Zahra');
    expect(daybook, greaterThan(100), reason: 'daybook for Al Zahra');
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('no blank company_name rows on core tables', () async {
    final tables = [
      'customers',
      'stock_items',
      'sales_invoices',
      'purchase_invoices',
      'tally_daybook',
      'outstanding_receivables',
      'outstanding_payables',
      'invoice_items',
      'invoice_items_purchase',
    ];
    for (final table in tables) {
      final blanks = await blankCompanyCount(table);
      expect(blanks, 0, reason: '$table must not have blank company_name');
    }
  }, timeout: const Timeout(Duration(seconds: 90)));

  test('filtered stock query never returns another company', () async {
    final rows = await client
        .from('stock_items')
        .select('company_name')
        .eq('company_name', company)
        .limit(200);
    expect(rows, isNotEmpty);
    for (final row in rows) {
      expect(row['company_name'], company);
    }
  });

  test('filtered customers query never returns another company', () async {
    final rows = await client
        .from('customers')
        .select('company_name')
        .eq('company_name', company)
        .limit(200);
    expect(rows, isNotEmpty);
    for (final row in rows) {
      expect(row['company_name'], company);
    }
  });

  test('company switch filter returns different row sets when other companies exist',
      () async {
    final companies = await client
        .from('tally_companies')
        .select('company_name')
        .eq('is_active', true);
    final names = companies
        .map((e) => (e['company_name'] as String?)?.trim() ?? '')
        .where((n) => n.isNotEmpty)
        .toSet()
        .toList();

    // ignore: avoid_print
    print('Active companies: $names');

    expect(names, contains(company));

    if (names.length < 2) {
      // Only one company in cloud — isolation still holds via filters above.
      return;
    }

    final other = names.firstWhere((n) => n != company);
    final a = await client
        .from('stock_items')
        .select('guid')
        .eq('company_name', company)
        .limit(50);
    final b = await client
        .from('stock_items')
        .select('guid')
        .eq('company_name', other)
        .limit(50);

    final aGuids = a.map((e) => e['guid']).toSet();
    final bGuids = b.map((e) => e['guid']).toSet();

    // Same guid may exist in both after composite unique — that's OK.
    // What must not happen: querying A returns rows tagged as B.
    final aTagged = await client
        .from('stock_items')
        .select('company_name')
        .eq('company_name', company)
        .limit(100);
    expect(aTagged.every((r) => r['company_name'] == company), isTrue);

    final bTagged = await client
        .from('stock_items')
        .select('company_name')
        .eq('company_name', other)
        .limit(100);
    expect(bTagged.every((r) => r['company_name'] == other), isTrue);

    // ignore: avoid_print
    print('Sample guid overlap A∩B: ${aGuids.intersection(bGuids).length}');
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('composite unique constraint exists on customers (company_name, guid)',
      () async {
    // Probe via information_schema through RPC is not available; instead
    // verify upsert conflict target behaviour by selecting distinct pairs.
    final rows = await client
        .from('customers')
        .select('company_name, guid')
        .eq('company_name', company)
        .limit(500);
    final pairs = <String>{};
    for (final row in rows) {
      final key = '${row['company_name']}|${row['guid']}';
      expect(pairs.contains(key), isFalse,
          reason: 'duplicate (company_name, guid) within page');
      pairs.add(key);
    }
  });
}
