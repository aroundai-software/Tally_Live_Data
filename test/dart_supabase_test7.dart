import 'package:supabase/supabase.dart';
import 'dart:io';

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
}

Future<void> main() async {
  final client = SupabaseClient('https://gwerbqebixlmniqzlhuk.supabase.co', 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imd3ZXJicWViaXhsbW5pcXpsaHVrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODU5MTAwOTUsImV4cCI6MjEwMTQ4NjA5NX0.qq7Ddl-SxH6glpUypFDrD8Jf5sQ8uPd85QhfTGtqvOE');
  final companyName = 'Kuncharakkattil Granites';
  try {
    dynamic query = client.from('ledger_bill_settlements').select('*').ilike('company_name', companyName);
    query = query.order('cleared_date', ascending: false);
    final response = await query.range(0, 999);
    final data = response as List;
    print('Fetched ${data.length} records.');
    final parsed = data.map((e) => LedgerBillSettlement.fromJson(e)).toList();
    print('Successfully parsed ${parsed.length} records.');
  } catch (e) {
    print('Error during parsing: $e');
  }
  exit(0);
}
