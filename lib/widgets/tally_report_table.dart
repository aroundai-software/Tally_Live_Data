import 'package:flutter/material.dart';
import '../models/financial_report.dart';
import 'summary_card.dart';

/// One display row in a Tally-style two-column report.
class TallyReportRow {
  final String particulars;
  final double amount;
  final bool emphasize;
  final int indent;
  final bool isSubtotal;
  /// Group name to open on tap (null = not drillable).
  final String? drillGroupName;

  const TallyReportRow({
    required this.particulars,
    required this.amount,
    this.emphasize = false,
    this.indent = 0,
    this.isSubtotal = false,
    this.drillGroupName,
  });

  factory TallyReportRow.fromLine(
    FinancialReportLine line, {
    bool? emphasize,
    int indent = 0,
    double? amount,
    String? drillGroupName,
  }) {
    final name = line.particulars.replaceAll(RegExp(r'\s*:$'), '');
    return TallyReportRow(
      particulars: name,
      amount: amount ?? line.amount.abs(),
      emphasize: emphasize ?? (line.isCalculated || line.isTotal),
      indent: indent,
      drillGroupName: drillGroupName ?? resolveDrillGroupName(name),
    );
  }
}

/// Strip Add:/Less: prefixes; return null for non-drillable calculated rows.
String? resolveDrillGroupName(String particulars) {
  var p = particulars.trim();
  final lower = p.toLowerCase();
  if (lower.isEmpty || lower == 'total') return null;
  if (lower.contains('gross profit') || lower.contains('gross loss')) return null;
  if (lower.contains('nett profit') || lower.contains('nett loss')) return null;
  if (lower.contains('net profit') || lower.contains('net loss')) return null;
  if (lower.contains('difference in opening')) return null;
  if (lower.startsWith('cost of sales')) return null;
  if (lower.startsWith('add:')) {
    p = p.substring(4).trim();
  } else if (lower.startsWith('less:')) {
    p = p.substring(5).trim();
  }
  if (p.isEmpty) return null;
  return p;
}

/// Tally-style amount: negative shown as (-)₹x,xx,xxx.xx
String formatTallySignedAmount(double amount) {
  if (amount < 0) {
    return '(-)${formatCurrency(amount.abs())}';
  }
  return formatCurrency(amount);
}

/// Child line under an expanded group (Tally Balance Sheet inline detail).
class TallyChildRow {
  final String name;
  final double signedAmount;
  final bool isGroup;

  const TallyChildRow({
    required this.name,
    required this.signedAmount,
    this.isGroup = false,
  });
}

/// Condensed Tally-style report.
/// Wide screens: side-by-side columns. Narrow (mobile): stacked full-width sections.
class TallyReportTable extends StatelessWidget {
  static const double _wideBreakpoint = 720;

  final String leftTitle;
  final String rightTitle;
  final List<TallyReportRow> leftLines;
  final List<TallyReportRow> rightLines;
  final String? leftTotalLabel;
  final String? rightTotalLabel;
  final double? leftTotal;
  final double? rightTotal;
  final Color leftAccent;
  final Color rightAccent;
  /// Open Group Summary (Tally Enter on a group).
  final void Function(TallyReportRow row)? onOpenSummary;
  /// Expand / collapse group on the report (Tally BS inline).
  final void Function(String groupName)? onToggleExpand;
  final Set<String> expandedGroups;
  final Set<String> loadingGroups;
  final Map<String, List<TallyChildRow>> groupChildren;
  final void Function(TallyChildRow child)? onChildTap;

  const TallyReportTable({
    super.key,
    required this.leftTitle,
    required this.rightTitle,
    required this.leftLines,
    required this.rightLines,
    this.leftTotalLabel,
    this.rightTotalLabel,
    this.leftTotal,
    this.rightTotal,
    this.leftAccent = const Color(0xFFB45309),
    this.rightAccent = const Color(0xFF0F766E),
    this.onOpenSummary,
    this.onToggleExpand,
    this.expandedGroups = const {},
    this.loadingGroups = const {},
    this.groupChildren = const {},
    this.onChildTap,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < _wideBreakpoint;
        if (stacked) {
          return Column(
            children: [
              _sectionCard(
                title: leftTitle,
                accent: leftAccent,
                lines: leftLines,
                totalLabel: leftTotalLabel,
                total: leftTotal,
                stacked: true,
              ),
              const SizedBox(height: 12),
              _sectionCard(
                title: rightTitle,
                accent: rightAccent,
                lines: rightLines,
                totalLabel: rightTotalLabel,
                total: rightTotal,
                stacked: true,
              ),
            ],
          );
        }

        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE4E9F1)),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                child: Row(
                  children: [
                    Expanded(child: _sideHeader(leftTitle, leftAccent)),
                    const SizedBox(width: 12),
                    Expanded(child: _sideHeader(rightTitle, rightAccent)),
                  ],
                ),
              ),
              const Divider(height: 1, color: Color(0xFFE4E9F1)),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _columnBody(
                        lines: leftLines,
                        accent: leftAccent,
                        totalLabel: leftTotalLabel,
                        total: leftTotal,
                        stacked: false,
                      ),
                    ),
                    Container(width: 1, color: const Color(0xFFE4E9F1)),
                    Expanded(
                      child: _columnBody(
                        lines: rightLines,
                        accent: rightAccent,
                        totalLabel: rightTotalLabel,
                        total: rightTotal,
                        stacked: false,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _sectionCard({
    required String title,
    required Color accent,
    required List<TallyReportRow> lines,
    String? totalLabel,
    double? total,
    required bool stacked,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE4E9F1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: _sideHeader(title, accent),
          ),
          const Divider(height: 1, color: Color(0xFFE4E9F1)),
          _columnBody(
            lines: lines,
            accent: accent,
            totalLabel: totalLabel,
            total: total,
            stacked: stacked,
          ),
        ],
      ),
    );
  }

  Widget _sideHeader(String title, Color accent) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 14,
          decoration: BoxDecoration(
            color: accent,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
              color: accent,
            ),
          ),
        ),
        Text(
          'Amount',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: Colors.grey.shade500,
          ),
        ),
      ],
    );
  }

  Widget _columnBody({
    required List<TallyReportRow> lines,
    required Color accent,
    String? totalLabel,
    double? total,
    required bool stacked,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (lines.isEmpty)
          const Padding(
            padding: EdgeInsets.all(14),
            child: Text(
              '—',
              style: TextStyle(color: Color(0xFF6B7A94), fontSize: 13),
            ),
          )
        else
          ...lines.expand((line) => _lineWithChildren(line, stacked: stacked)),
        if (totalLabel != null && total != null) ...[
          const Divider(height: 1, color: Color(0xFFE4E9F1)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    totalLabel,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F1A2B),
                    ),
                  ),
                ),
                Text(
                  formatCurrency(total),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: accent,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  List<Widget> _lineWithChildren(TallyReportRow line, {required bool stacked}) {
    final widgets = <Widget>[_lineRow(line, stacked: stacked)];
    final group = line.drillGroupName;
    if (group == null || !expandedGroups.contains(group)) return widgets;

    if (loadingGroups.contains(group)) {
      widgets.add(
        const Padding(
          padding: EdgeInsets.fromLTRB(36, 8, 14, 12),
          child: LinearProgressIndicator(minHeight: 2),
        ),
      );
      return widgets;
    }

    final kids = groupChildren[group] ?? const <TallyChildRow>[];
    if (kids.isEmpty) {
      widgets.add(
        const Padding(
          padding: EdgeInsets.fromLTRB(36, 4, 14, 10),
          child: Text(
            'No ledgers under this group',
            style: TextStyle(fontSize: 12, color: Color(0xFF6B7A94)),
          ),
        ),
      );
      return widgets;
    }

    for (final child in kids) {
      widgets.add(_childRow(child, stacked: stacked));
    }
    return widgets;
  }

  Widget _lineRow(TallyReportRow line, {required bool stacked}) {
    if (line.isSubtotal) {
      return Container(
        color: const Color(0xFFF5F7FB),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Text(
                line.particulars,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF6B7A94),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              formatCurrency(line.amount),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0F1A2B),
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      );
    }

    final group = line.drillGroupName;
    final canExpand = group != null && onToggleExpand != null;
    final canOpenSummary = group != null && onOpenSummary != null;
    final isExpanded = group != null && expandedGroups.contains(group);

    final nameStyle = TextStyle(
      fontSize: stacked ? 14 : (line.indent > 0 ? 12 : 12.5),
      height: 1.3,
      fontWeight: line.emphasize ? FontWeight.w700 : FontWeight.w500,
      color: canExpand || canOpenSummary
          ? const Color(0xFF2453FF)
          : (line.emphasize ? const Color(0xFF0F1A2B) : const Color(0xFF3A4A63)),
    );
    final amountStyle = TextStyle(
      fontSize: stacked ? 13.5 : 12,
      fontWeight: FontWeight.w800,
      color: const Color(0xFF0F1A2B),
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    final pad = stacked ? 14.0 : 12.0;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: canExpand ? () => onToggleExpand!(group) : null,
        child: Padding(
          padding: EdgeInsets.fromLTRB(pad + line.indent * pad, stacked ? 12 : 8, 8, stacked ? 12 : 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (canExpand)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Icon(
                    isExpanded
                        ? Icons.expand_more_rounded
                        : Icons.chevron_right_rounded,
                    size: 20,
                    color: const Color(0xFF6B7A94),
                  ),
                ),
              Expanded(
                child: Text(
                  line.particulars,
                  softWrap: true,
                  style: nameStyle,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                formatCurrency(line.amount),
                textAlign: TextAlign.right,
                style: amountStyle,
              ),
              if (canOpenSummary)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  tooltip: 'Group Summary',
                  icon: Icon(
                    Icons.open_in_new_rounded,
                    size: 16,
                    color: Colors.grey.shade500,
                  ),
                  onPressed: () => onOpenSummary!(line),
                )
              else
                const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _childRow(TallyChildRow child, {required bool stacked}) {
    final pad = stacked ? 14.0 : 12.0;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onChildTap == null ? null : () => onChildTap!(child),
        child: Padding(
          padding: EdgeInsets.fromLTRB(pad + (stacked ? 28 : 22), 8, 40, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  child.name,
                  softWrap: true,
                  style: TextStyle(
                    fontSize: stacked ? 13 : 12,
                    height: 1.3,
                    fontWeight: child.isGroup ? FontWeight.w600 : FontWeight.w400,
                    fontStyle: FontStyle.italic,
                    color: const Color(0xFF3A4A63),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                formatTallySignedAmount(child.signedAmount),
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: stacked ? 12.5 : 11.5,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF0F1A2B),
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Balance Sheet helpers (Tally Dr/Cr side placement) ─────────

const _kBsPrimaryGroups = <String>{
  'capital account',
  'loans (liability)',
  'current liabilities',
  'fixed assets',
  'current assets',
  'investments',
  'suspense a/c',
  'branch / divisions',
  'profit & loss a/c',
  'profit and loss a/c',
  'misc. expenses (asset)',
  'miscellaneous expenses (asset)',
  'difference in opening balances',
};

bool _isStockLabel(String particulars) {
  final p = particulars.toLowerCase().trim();
  return p == 'closing stock' ||
      p == 'opening stock' ||
      p.startsWith('less: closing') ||
      p.startsWith('add: opening');
}

/// Signed amount as exported by Tally (Cr positive, Dr negative).
double tallySignedAmount(FinancialReportLine line) {
  if (line.credit > 0 && line.debit <= 0) return line.credit;
  if (line.debit > 0 && line.credit <= 0) return -line.debit;
  final tag = (line.drCr ?? '').toLowerCase();
  if (tag == 'cr') return line.amount.abs();
  if (tag == 'dr') return -line.amount.abs();
  final s = (line.section ?? '').toLowerCase();
  if (s == 'assets' || s == 'expenses') return -line.amount.abs();
  return line.amount.abs();
}

/// Condensed BS groups only — stock labels are never top-level on BS.
List<FinancialReportLine> condensedBalanceSheetLines(
  List<FinancialReportLine> lines,
) {
  return lines.where((l) {
    final p = l.particulars.toLowerCase().trim();
    if (_isStockLabel(p)) return false;
    if (p.startsWith('add:') || p.startsWith('less:')) return false;
    if (_kBsPrimaryGroups.contains(p)) return true;
    if (p.contains('difference in opening')) return true;
    return false;
  }).toList()
    ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
}

/// Tally places Cr balances on Liabilities (left), Dr on Assets (right).
bool isBalanceSheetLiability(FinancialReportLine line) {
  return tallySignedAmount(line) >= 0;
}

/// Build left/right rows + balancing "Difference in opening balances" like Tally.
({
  List<TallyReportRow> left,
  List<TallyReportRow> right,
  double leftTotal,
  double rightTotal,
}) buildBalanceSheetColumns(List<FinancialReportLine> lines) {
  final condensed = condensedBalanceSheetLines(lines);
  final left = <TallyReportRow>[];
  final right = <TallyReportRow>[];

  for (final line in condensed) {
    final row = TallyReportRow.fromLine(line, emphasize: true);
    if (isBalanceSheetLiability(line)) {
      left.add(row);
    } else {
      right.add(row);
    }
  }
  var leftTotal = left.fold<double>(0, (s, r) => s + r.amount);
  var rightTotal = right.fold<double>(0, (s, r) => s + r.amount);
  final gap = leftTotal - rightTotal;

  final alreadyHasDiff = condensed.any(
    (l) => l.particulars.toLowerCase().contains('difference in opening'),
  );

  if (!alreadyHasDiff && gap.abs() > 0.009) {
    final diffRow = TallyReportRow(
      particulars: 'Difference in opening balances',
      amount: gap.abs(),
      emphasize: true,
    );
    if (gap > 0) {
      right.add(diffRow);
      rightTotal += gap.abs();
    } else {
      left.add(diffRow);
      leftTotal += gap.abs();
    }
  }

  return (
    left: left,
    right: right,
    leftTotal: leftTotal,
    rightTotal: rightTotal,
  );
}

// ─── Profit & Loss helpers ─────────────────────────────────────

bool _isCosChild(String particulars) {
  final p = particulars.toLowerCase().trim();
  return p == 'opening stock' ||
      p.startsWith('add:') ||
      p.startsWith('less:') ||
      p == 'direct expenses';
}

/// Build Tally condensed P&L columns (Cost of Sales + Gross/Nett).
({
  List<TallyReportRow> left,
  List<TallyReportRow> right,
  double leftTotal,
  double rightTotal,
  double grossProfit,
  double nettProfit,
}) buildProfitLossColumns(List<FinancialReportLine> lines) {
  final ordered = List<FinancialReportLine>.from(lines)
    ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  double sales = 0;
  double directIncomes = 0;
  double costOfSales = 0;
  double indirectIncomes = 0;
  double indirectExpenses = 0;

  FinancialReportLine? cosLine;
  final cosChildren = <FinancialReportLine>[];
  final salesLines = <FinancialReportLine>[];
  final indirectIncomeLines = <FinancialReportLine>[];
  final indirectExpenseLines = <FinancialReportLine>[];

  for (final line in ordered) {
    final p = line.particulars.toLowerCase().trim();
    final signed = tallySignedAmount(line);

    if (p.contains('sales accounts')) {
      sales = signed.abs();
      salesLines.add(line);
    } else if (p.contains('direct incomes')) {
      directIncomes = signed.abs();
      salesLines.add(line);
    } else if (p.startsWith('cost of sales')) {
      costOfSales = signed.abs();
      cosLine = line;
    } else if (_isCosChild(p)) {
      cosChildren.add(line);
    } else if (p.contains('indirect incomes')) {
      indirectIncomes = signed.abs();
      indirectIncomeLines.add(line);
    } else if (p.contains('indirect expenses')) {
      indirectExpenses = signed.abs();
      indirectExpenseLines.add(line);
    }
  }

  // Gross = Sales + Direct Incomes − Cost of Sales (matches Tally).
  final gross = sales + directIncomes - costOfSales;
  // Nett = Gross + Indirect Incomes − Indirect Expenses.
  final nett = gross + indirectIncomes - indirectExpenses;

  final left = <TallyReportRow>[];
  final right = <TallyReportRow>[];

  // ── Trading account ──
  if (cosLine != null) {
    left.add(TallyReportRow.fromLine(cosLine, emphasize: true, amount: costOfSales));
    for (final child in cosChildren) {
      left.add(TallyReportRow.fromLine(child, indent: 1));
    }
  } else {
    for (final child in cosChildren) {
      left.add(TallyReportRow.fromLine(child));
    }
  }

  for (final line in salesLines) {
    right.add(TallyReportRow.fromLine(line, emphasize: true));
  }

  if (gross >= 0) {
    left.add(TallyReportRow(
      particulars: 'Gross Profit c/o',
      amount: gross,
      emphasize: true,
    ));
  } else {
    right.add(TallyReportRow(
      particulars: 'Gross Loss c/o',
      amount: gross.abs(),
      emphasize: true,
    ));
  }

  final tradingTotal = sales + directIncomes;
  left.add(TallyReportRow(
    particulars: 'Total',
    amount: tradingTotal,
    isSubtotal: true,
  ));
  right.add(TallyReportRow(
    particulars: 'Total',
    amount: tradingTotal,
    isSubtotal: true,
  ));

  // ── Profit & Loss account ──
  for (final line in indirectExpenseLines) {
    left.add(TallyReportRow.fromLine(line, emphasize: true));
  }

  if (gross >= 0) {
    right.add(TallyReportRow(
      particulars: 'Gross Profit b/f',
      amount: gross,
      emphasize: true,
    ));
  } else {
    left.add(TallyReportRow(
      particulars: 'Gross Loss b/f',
      amount: gross.abs(),
      emphasize: true,
    ));
  }

  for (final line in indirectIncomeLines) {
    right.add(TallyReportRow.fromLine(line, emphasize: true));
  }

  if (nett >= 0) {
    left.add(TallyReportRow(
      particulars: 'Nett Profit',
      amount: nett,
      emphasize: true,
    ));
  } else {
    right.add(TallyReportRow(
      particulars: 'Nett Loss',
      amount: nett.abs(),
      emphasize: true,
    ));
  }

  // Bottom totals = P&L section (matches Tally: Indirect Exp vs GP+Inc+Nett Loss).
  final plLeftTotal = indirectExpenses + (nett >= 0 ? nett : 0) + (gross < 0 ? gross.abs() : 0);
  final plRightTotal =
      (gross >= 0 ? gross : 0) + indirectIncomes + (nett < 0 ? nett.abs() : 0);

  return (
    left: left,
    right: right,
    leftTotal: plLeftTotal,
    rightTotal: plRightTotal,
    grossProfit: gross,
    nettProfit: nett,
  );
}
