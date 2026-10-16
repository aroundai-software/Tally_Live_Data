import 'package:flutter/material.dart';
import '../models/financial_report.dart';
import 'summary_card.dart';
import '../config/app_theme.dart';

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
            color: AppTheme.cardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.dividerColor),
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
              Divider(height: 1, color: AppTheme.dividerColor),
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
                    Container(width: 1, color: AppTheme.dividerColor),
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
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: _sideHeader(title, accent),
          ),
          Divider(height: 1, color: AppTheme.dividerColor),
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
            color: AppTheme.textSecondary,
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
          Padding(
            padding: const EdgeInsets.all(14),
            child: Text(
              '—',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
          )
        else
          ...lines.expand((line) => _lineWithChildren(line, stacked: stacked)),
        if (totalLabel != null && total != null) ...[
          Divider(height: 1, color: AppTheme.dividerColor),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    totalLabel,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textPrimary,
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
        Padding(
          padding: const EdgeInsets.fromLTRB(36, 4, 14, 10),
          child: Text(
            'No ledgers under this group',
            style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
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
        color: AppTheme.isDark ? const Color(0xFF243044) : const Color(0xFFF5F7FB),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Text(
                line.particulars,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textSecondary,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              formatCurrency(line.amount),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: AppTheme.textPrimary,
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
    final isInteractive = canExpand || canOpenSummary;

    final nameStyle = TextStyle(
      fontSize: stacked ? 14 : (line.indent > 0 ? 12 : 12.5),
      height: 1.3,
      fontWeight: line.emphasize ? FontWeight.w700 : FontWeight.w500,
      color: isInteractive
          ? AppTheme.primaryColor
          : (line.emphasize ? AppTheme.textPrimary : AppTheme.textSecondary),
    );
    final amountStyle = TextStyle(
      fontSize: stacked ? 13.5 : 12,
      fontWeight: FontWeight.w800,
      color: AppTheme.textPrimary,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    VoidCallback? onRowTap;
    if (canExpand) {
      onRowTap = () => onToggleExpand!(group);
    } else if (canOpenSummary) {
      onRowTap = () => onOpenSummary!(line);
    }

    final pad = stacked ? 14.0 : 12.0;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onRowTap,
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
                    color: AppTheme.textSecondary,
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
                    color: AppTheme.textSecondary,
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
                    color: AppTheme.textSecondary,
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
                  color: AppTheme.textPrimary,
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

/// True when [p] is exactly [label] or starts with "[label] " / "[label](".
/// Avoids "indirect incomes".contains("direct incomes") false positives.
bool _plLabelIs(String p, String label) {
  if (p == label) return true;
  if (p.startsWith('$label ')) return true;
  if (p.startsWith('$label(')) return true;
  return false;
}

String _stripAddLessPrefix(String particulars) {
  final p = particulars.trim();
  final lower = p.toLowerCase();
  if (lower.startsWith('add:')) return p.substring(4).trim();
  if (lower.startsWith('less:')) return p.substring(5).trim();
  return p;
}

TallyReportRow _plRow(
  FinancialReportLine line, {
  String? label,
  double? amount,
  bool emphasize = true,
}) {
  final display = label ?? _stripAddLessPrefix(line.particulars);
  return TallyReportRow(
    particulars: display,
    amount: amount ?? line.amount.abs(),
    emphasize: emphasize,
    drillGroupName: resolveDrillGroupName(display),
  );
}

/// Build classic Tally P&L columns (same order as Gateway → Profit & Loss).
///
/// Trading (left): Opening Stock, Purchase Accounts, Direct Expenses, Gross Profit c/o
/// Trading (right): Sales Accounts, Direct Incomes, Closing Stock
/// Then Indirect Expenses / Nett vs Gross Profit b/f / Indirect Incomes.
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
  double openingStock = 0;
  double purchases = 0;
  double closingStock = 0;
  double directExpenses = 0;
  double indirectIncomes = 0;
  double indirectExpenses = 0;

  FinancialReportLine? openingLine;
  FinancialReportLine? purchaseLine;
  FinancialReportLine? closingLine;
  FinancialReportLine? directExpenseLine;
  FinancialReportLine? salesLine;
  FinancialReportLine? directIncomeLine;
  FinancialReportLine? indirectIncomeLine;
  FinancialReportLine? indirectExpenseLine;
  var hasCosLine = false;

  for (final line in ordered) {
    final p = line.particulars.toLowerCase().trim();
    final signed = tallySignedAmount(line);
    final abs = signed.abs();

    if (_plLabelIs(p, 'sales accounts')) {
      sales = abs;
      salesLine = line;
    } else if (_plLabelIs(p, 'direct incomes')) {
      directIncomes = abs;
      directIncomeLine = line;
    } else if (p.startsWith('cost of sales')) {
      costOfSales = abs;
      hasCosLine = true;
    } else if (p == 'opening stock' || p.startsWith('add: opening')) {
      openingStock = abs;
      openingLine = line;
    } else if (p.contains('purchase accounts') ||
        (p.startsWith('add:') && p.contains('purchase'))) {
      purchases = abs;
      purchaseLine = line;
    } else if (p == 'closing stock' ||
        p.startsWith('less: closing') ||
        p.startsWith('less:closing')) {
      closingStock = abs;
      closingLine = line;
    } else if (_plLabelIs(p, 'direct expenses')) {
      directExpenses = abs;
      directExpenseLine = line;
    } else if (_plLabelIs(p, 'indirect incomes')) {
      indirectIncomes = abs;
      indirectIncomeLine = line;
    } else if (_plLabelIs(p, 'indirect expenses')) {
      indirectExpenses = abs;
      indirectExpenseLine = line;
    }
  }

  if (!hasCosLine) {
    costOfSales =
        openingStock + purchases + directExpenses - closingStock;
  }

  // Gross = Sales + Direct Incomes − Cost of Sales (matches Tally).
  final gross = sales + directIncomes - costOfSales;
  // Nett = Gross + Indirect Incomes − Indirect Expenses.
  final nett = gross + indirectIncomes - indirectExpenses;

  final left = <TallyReportRow>[];
  final right = <TallyReportRow>[];

  // ── Trading account (classic Tally order) ──
  if (openingLine != null) {
    left.add(_plRow(openingLine, label: 'Opening Stock', amount: openingStock));
  }
  if (purchaseLine != null) {
    left.add(_plRow(purchaseLine, label: 'Purchase Accounts', amount: purchases));
  }
  if (directExpenseLine != null) {
    left.add(_plRow(directExpenseLine, amount: directExpenses));
  }

  if (salesLine != null) {
    right.add(_plRow(salesLine, amount: sales));
  }
  if (directIncomeLine != null) {
    right.add(_plRow(directIncomeLine, amount: directIncomes));
  }
  if (closingLine != null) {
    right.add(_plRow(closingLine, label: 'Closing Stock', amount: closingStock));
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

  // Tally trading total = Opening + Purchase + Direct Exp + GP
  //                    = Sales + Direct Incomes + Closing Stock
  final tradingLeft = openingStock +
      purchases +
      directExpenses +
      (gross >= 0 ? gross : 0);
  final tradingRight = sales +
      directIncomes +
      closingStock +
      (gross < 0 ? gross.abs() : 0);
  final tradingTotal =
      tradingLeft > 0 ? tradingLeft : tradingRight;

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
  if (indirectExpenseLine != null) {
    left.add(_plRow(indirectExpenseLine, amount: indirectExpenses));
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

  if (indirectIncomeLine != null) {
    right.add(_plRow(indirectIncomeLine, amount: indirectIncomes));
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
  final plLeftTotal =
      indirectExpenses + (nett >= 0 ? nett : 0) + (gross < 0 ? gross.abs() : 0);
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
