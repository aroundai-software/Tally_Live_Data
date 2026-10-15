import 'package:flutter_test/flutter_test.dart';
import 'package:tallylive/models/financial_report.dart';
import 'package:tallylive/widgets/tally_report_table.dart';

FinancialReportLine _line({
  required String particulars,
  required double amount,
  required String section,
  required int sortOrder,
}) {
  return FinancialReportLine(
    id: '$sortOrder',
    reportId: 'r1',
    rowType: 'group',
    section: section,
    particulars: particulars,
    amount: amount,
    sortOrder: sortOrder,
  );
}

void main() {
  final sampleLines = [
    _line(
      particulars: 'Cost of Sales',
      amount: 405280.79,
      section: 'expenses',
      sortOrder: 1,
    ),
    _line(
      particulars: 'Opening Stock',
      amount: 4231255.18,
      section: 'expenses',
      sortOrder: 2,
    ),
    _line(
      particulars: 'Add: Purchase Accounts',
      amount: 435427.96,
      section: 'expenses',
      sortOrder: 3,
    ),
    _line(
      particulars: 'Less: Closing Stock',
      amount: 4261902.35,
      section: 'expenses',
      sortOrder: 4,
    ),
    _line(
      particulars: 'Direct Expenses',
      amount: 500,
      section: 'expenses',
      sortOrder: 5,
    ),
    _line(
      particulars: 'Sales Accounts',
      amount: 1090882.25,
      section: 'incomes',
      sortOrder: 6,
    ),
    _line(
      particulars: 'Direct Incomes',
      amount: 1000,
      section: 'incomes',
      sortOrder: 7,
    ),
    _line(
      particulars: 'Indirect Expenses',
      amount: 434650.99,
      section: 'expenses',
      sortOrder: 8,
    ),
    _line(
      particulars: 'Indirect Incomes',
      amount: 183.72,
      section: 'incomes',
      sortOrder: 9,
    ),
  ];

  test('P&L gross/nett do not treat Indirect Incomes as Direct Incomes', () {
    final cols = buildProfitLossColumns(sampleLines);
    expect(cols.grossProfit, closeTo(686601.46, 0.01));
    expect(cols.nettProfit, closeTo(252134.19, 0.01));
  });

  test('P&L rows follow classic Tally order for cross-check', () {
    final cols = buildProfitLossColumns(sampleLines);

    expect(
      cols.left.map((r) => r.particulars).toList(),
      [
        'Opening Stock',
        'Purchase Accounts',
        'Direct Expenses',
        'Gross Profit c/o',
        'Total',
        'Indirect Expenses',
        'Nett Profit',
      ],
    );
    expect(
      cols.right.map((r) => r.particulars).toList(),
      [
        'Sales Accounts',
        'Direct Incomes',
        'Closing Stock',
        'Total',
        'Gross Profit b/f',
        'Indirect Incomes',
      ],
    );

    // Trading total matches Tally (Closing Stock on income side).
    final tradingTotal = cols.left.firstWhere((r) => r.isSubtotal).amount;
    expect(tradingTotal, closeTo(5353784.60, 0.01));
    expect(cols.leftTotal, closeTo(686785.18, 0.01));
    expect(cols.rightTotal, closeTo(686785.18, 0.01));
  });
}
