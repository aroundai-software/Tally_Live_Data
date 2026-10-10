class FinancialReportLine {
  final String id;
  final String reportId;
  final String rowType;
  final String? section;
  final String particulars;
  final String? tallyGroupName;
  final String? lineKey;
  final String? parentLineKey;
  final double amount;
  final double debit;
  final double credit;
  final String? drCr;
  final bool isTotal;
  final bool isCalculated;
  final String? ledgerGuid;
  final int sortOrder;

  const FinancialReportLine({
    required this.id,
    required this.reportId,
    required this.rowType,
    this.section,
    required this.particulars,
    this.tallyGroupName,
    this.lineKey,
    this.parentLineKey,
    this.amount = 0,
    this.debit = 0,
    this.credit = 0,
    this.drCr,
    this.isTotal = false,
    this.isCalculated = false,
    this.ledgerGuid,
    this.sortOrder = 0,
  });

  factory FinancialReportLine.fromJson(Map<String, dynamic> json) {
    return FinancialReportLine(
      id: json['id']?.toString() ?? '',
      reportId: json['report_id']?.toString() ?? '',
      rowType: json['row_type']?.toString() ?? 'group',
      section: json['section']?.toString(),
      particulars: (json['particulars'] ?? '').toString(),
      tallyGroupName: json['tally_group_name']?.toString(),
      lineKey: json['line_key']?.toString(),
      parentLineKey: json['parent_line_key']?.toString(),
      amount: _toDouble(json['amount']),
      debit: _toDouble(json['debit']),
      credit: _toDouble(json['credit']),
      drCr: json['dr_cr']?.toString(),
      isTotal: json['is_total'] == true,
      isCalculated: json['is_calculated'] == true,
      ledgerGuid: json['ledger_guid']?.toString(),
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
    );
  }
}

class BalanceSheetReport {
  final String id;
  final String companyName;
  final String companyGuid;
  final DateTime asOnDate;
  final String format;
  final double totalLiabilities;
  final double totalAssets;
  final DateTime? syncedAt;
  final List<FinancialReportLine> lines;

  const BalanceSheetReport({
    required this.id,
    required this.companyName,
    required this.companyGuid,
    required this.asOnDate,
    this.format = 'condensed',
    this.totalLiabilities = 0,
    this.totalAssets = 0,
    this.syncedAt,
    this.lines = const [],
  });

  factory BalanceSheetReport.fromJson(
    Map<String, dynamic> json, {
    List<FinancialReportLine> lines = const [],
  }) {
    return BalanceSheetReport(
      id: json['id']?.toString() ?? '',
      companyName: (json['company_name'] ?? '').toString(),
      companyGuid: (json['company_guid'] ?? '').toString(),
      asOnDate: DateTime.tryParse(json['as_on_date']?.toString() ?? '') ??
          DateTime.now(),
      format: (json['format'] ?? 'condensed').toString(),
      totalLiabilities: _toDouble(json['total_liabilities']),
      totalAssets: _toDouble(json['total_assets']),
      syncedAt: DateTime.tryParse(json['synced_at']?.toString() ?? ''),
      lines: lines,
    );
  }

  List<FinancialReportLine> linesForSection(String section) => lines
      .where((l) => (l.section ?? '').toLowerCase() == section.toLowerCase())
      .toList()
    ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
}

class ProfitLossReport {
  final String id;
  final String companyName;
  final String companyGuid;
  final DateTime fromDate;
  final DateTime toDate;
  final String format;
  final bool showGrossProfit;
  final double grossProfit;
  final double grossLoss;
  final double nettProfit;
  final double nettLoss;
  final DateTime? syncedAt;
  final List<FinancialReportLine> lines;

  const ProfitLossReport({
    required this.id,
    required this.companyName,
    required this.companyGuid,
    required this.fromDate,
    required this.toDate,
    this.format = 'condensed',
    this.showGrossProfit = true,
    this.grossProfit = 0,
    this.grossLoss = 0,
    this.nettProfit = 0,
    this.nettLoss = 0,
    this.syncedAt,
    this.lines = const [],
  });

  factory ProfitLossReport.fromJson(
    Map<String, dynamic> json, {
    List<FinancialReportLine> lines = const [],
  }) {
    return ProfitLossReport(
      id: json['id']?.toString() ?? '',
      companyName: (json['company_name'] ?? '').toString(),
      companyGuid: (json['company_guid'] ?? '').toString(),
      fromDate: DateTime.tryParse(json['from_date']?.toString() ?? '') ??
          DateTime.now(),
      toDate: DateTime.tryParse(json['to_date']?.toString() ?? '') ??
          DateTime.now(),
      format: (json['format'] ?? 'condensed').toString(),
      showGrossProfit: json['show_gross_profit'] ?? true,
      grossProfit: _toDouble(json['gross_profit']),
      grossLoss: _toDouble(json['gross_loss']),
      nettProfit: _toDouble(json['nett_profit']),
      nettLoss: _toDouble(json['nett_loss']),
      syncedAt: DateTime.tryParse(json['synced_at']?.toString() ?? ''),
      lines: lines,
    );
  }

  List<FinancialReportLine> linesForSection(String section) => lines
      .where((l) => (l.section ?? '').toLowerCase() == section.toLowerCase())
      .toList()
    ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
}

double _toDouble(dynamic value) {
  if (value == null) return 0;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString()) ?? 0;
}
