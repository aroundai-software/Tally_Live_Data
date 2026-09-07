class LedgerBillSettlement {
  final String id;
  final String companyName;
  final String ledgerName;
  final String billReference;
  final DateTime? billDate;
  final double billAmount;
  final DateTime? dueDate;
  final DateTime? clearedDate;
  final int? daysToClear;
  final int? daysFromDueDate;
  final String? guid;

  LedgerBillSettlement({
    required this.id,
    required this.companyName,
    required this.ledgerName,
    required this.billReference,
    this.billDate,
    required this.billAmount,
    this.dueDate,
    this.clearedDate,
    this.daysToClear,
    this.daysFromDueDate,
    this.guid,
  });

  factory LedgerBillSettlement.fromJson(Map<String, dynamic> json) {
    return LedgerBillSettlement(
      id: json['id'] as String,
      companyName: json['company_name'] as String? ?? '',
      ledgerName: json['ledger_name'] as String? ?? '',
      billReference: json['bill_reference'] as String? ?? '',
      billDate: json['bill_date'] != null ? DateTime.parse(json['bill_date'] as String) : null,
      billAmount: (json['bill_amount'] as num?)?.toDouble() ?? 0.0,
      dueDate: json['due_date'] != null ? DateTime.parse(json['due_date'] as String) : null,
      clearedDate: json['cleared_date'] != null ? DateTime.parse(json['cleared_date'] as String) : null,
      daysToClear: json['days_to_clear'] as int?,
      daysFromDueDate: json['days_from_due_date'] as int?,
      guid: json['guid'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'company_name': companyName,
      'ledger_name': ledgerName,
      'bill_reference': billReference,
      'bill_date': billDate?.toIso8601String(),
      'bill_amount': billAmount,
      'due_date': dueDate?.toIso8601String(),
      'cleared_date': clearedDate?.toIso8601String(),
      'days_to_clear': daysToClear,
      'days_from_due_date': daysFromDueDate,
      'guid': guid,
    };
  }
}
