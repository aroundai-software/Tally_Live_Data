import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../config/app_theme.dart';

/// Tally-style Cash Flow Summary (Inflow | Outflow) for one month.
class CashFlowSummaryScreen extends StatelessWidget {
  final String periodLabel;
  final Map<String, dynamic> summary;

  const CashFlowSummaryScreen({
    super.key,
    required this.periodLabel,
    required this.summary,
  });

  static final _amtFmt = NumberFormat('#,##0.00');
  static final _dateFmt = DateFormat('d MMM yyyy');

  double _num(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    final s = value.toString();
    if (s.length < 10) return null;
    return DateTime.tryParse(s.substring(0, 10));
  }

  List<Map<String, dynamic>> _lines(String key) {
    final raw = summary[key];
    if (raw is! List) return const [];
    final lines = raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    lines.sort((a, b) {
      final an = (a['particulars']?.toString() ?? '').toLowerCase();
      final bn = (b['particulars']?.toString() ?? '').toLowerCase();
      return an.compareTo(bn);
    });
    return lines;
  }

  @override
  Widget build(BuildContext context) {
    final inflowLines = _lines('inflow_lines');
    final outflowLines = _lines('outflow_lines');
    final totalIn = _num(summary['total_inflow']);
    final totalOut = _num(summary['total_outflow']);
    final nett = _num(summary['nett']);
    final from = _parseDate(summary['from_date']);
    final to = _parseDate(summary['to_date']);
    final periodText = (from != null && to != null)
        ? '${_dateFmt.format(from)} to ${_dateFmt.format(to)}'
        : periodLabel;

    return Scaffold(
      backgroundColor: AppTheme.surfaceColor,
      appBar: AppBar(
        title: Text(
          'Cash Flow Summary',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: AppTheme.textPrimary,
          ),
        ),
        backgroundColor: AppTheme.cardColor,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: AppTheme.textPrimary),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Text(
            periodText,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 640;
              if (wide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _sideColumn('Inflow', inflowLines, totalIn, const Color(0xFFE11D48))),
                    const SizedBox(width: 12),
                    Expanded(child: _sideColumn('Outflow', outflowLines, totalOut, const Color(0xFF2563EB))),
                  ],
                );
              }
              return Column(
                children: [
                  _sideColumn('Inflow', inflowLines, totalIn, const Color(0xFFE11D48)),
                  const SizedBox(height: 12),
                  _sideColumn('Outflow', outflowLines, totalOut, const Color(0xFF2563EB)),
                ],
              );
            },
          ),
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
            decoration: BoxDecoration(
              color: AppTheme.cardColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.dividerColor),
            ),
            child: Column(
              children: [
                Text(
                  nett >= 0 ? 'Nett Inflow' : 'Nett Outflow',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _amtFmt.format(nett.abs()),
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: nett >= 0 ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sideColumn(
    String title,
    List<Map<String, dynamic>> lines,
    double total,
    Color accent,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 14,
                color: accent,
              ),
            ),
          ),
          if (lines.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'No $title lines for this month.',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
              ),
            )
          else
            ...lines.map((line) {
              final name = line['particulars']?.toString() ?? '';
              final amt = _num(line['amount']);
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ),
                    Text(
                      _amtFmt.format(amt),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ],
                ),
              );
            }),
          Divider(height: 1, color: AppTheme.dividerColor),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Total $title',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
                Text(
                  _amtFmt.format(total),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
