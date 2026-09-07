class DaybookEntry {
  final String? id;
  final DateTime? date;
  final String? voucherNumber;
  final String voucherType;
  final String ledgerName;
  final double amount;
  final bool isDebit;
  final String? narration;
  final String? particulars;
  final String? companyName;

  DaybookEntry({
    this.id,
    this.date,
    this.voucherNumber,
    required this.voucherType,
    required this.ledgerName,
    required this.amount,
    this.isDebit = true,
    this.narration,
    this.particulars,
    this.companyName,
  });

  factory DaybookEntry.fromJson(Map<String, dynamic> json) {
    return DaybookEntry(
      id: json['id']?.toString(),
      date: json['date'] != null ? DateTime.tryParse(json['date'])?.toLocal() : null,
      voucherNumber: json['voucher_number'],
      voucherType: json['voucher_type'] ?? 'Unknown',
      ledgerName: json['ledger_name'] ?? 'Unknown',
      amount: _toDouble(json['amount']),
      isDebit: json['is_debit'] ?? true,
      narration: json['narration'],
      particulars: json['particulars'],
      companyName: json['company_name'],
    );
  }

  static double _toDouble(dynamic val) {
    if (val == null) return 0;
    if (val is double) return val;
    if (val is int) return val.toDouble();
    return double.tryParse(val.toString()) ?? 0;
  }
}
