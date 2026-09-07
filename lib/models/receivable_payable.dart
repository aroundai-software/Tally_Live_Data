class OutstandingRecord {
  final String? id;
  final String customerName;
  final DateTime? date;
  final String invoiceNumber;
  final double openingBalance;
  final double closingBalance;
  final double amount;
  final DateTime? dueDate;
  final int? overdueDays;
  final String? billType;
  final String? companyName;
  final String? guid;
  final DateTime? updatedAt;

  OutstandingRecord({
    this.id,
    required this.customerName,
    this.date,
    this.invoiceNumber = '',
    this.openingBalance = 0,
    this.closingBalance = 0,
    this.amount = 0,
    this.dueDate,
    this.overdueDays,
    this.billType,
    this.companyName,
    this.guid,
    this.updatedAt,
  });

  factory OutstandingRecord.fromJson(Map<String, dynamic> json) {
    return OutstandingRecord(
      id: json['id']?.toString(),
      customerName: json['customer_name']?.toString() ?? '',
      date: json['date'] != null ? DateTime.tryParse(json['date'].toString())?.toLocal() : null,
      invoiceNumber: json['invoicenumber']?.toString() ?? '',
      openingBalance: _toDouble(json['opening_balance']),
      closingBalance: _toDouble(json['closing_balance']),
      amount: _toDouble(json['amount']),
      dueDate: json['duedate'] != null ? DateTime.tryParse(json['duedate'].toString())?.toLocal() : null,
      overdueDays: json['overdue_days'] != null
          ? (json['overdue_days'] is num
              ? (json['overdue_days'] as num).toInt()
              : int.tryParse(json['overdue_days'].toString()))
          : null,
      billType: json['bill_type']?.toString(),
      companyName: json['company_name']?.toString(),
      guid: json['guid']?.toString() ?? json['Guid']?.toString(),
      updatedAt: json['updated_at'] != null ? DateTime.tryParse(json['updated_at'].toString())?.toLocal() : null,
    );
  }

  bool get isOverdue => overdueDays != null && overdueDays! > 0;

  static double _toDouble(dynamic val) {
    if (val == null) return 0;
    if (val is double) return val;
    if (val is int) return val.toDouble();
    return double.tryParse(val.toString()) ?? 0;
  }
}
