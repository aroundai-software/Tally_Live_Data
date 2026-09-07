import 'package:supabase/supabase.dart';
import 'dart:io';

Future<void> main() async {
  final client = SupabaseClient('https://gwerbqebixlmniqzlhuk.supabase.co', 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imd3ZXJicWViaXhsbW5pcXpsaHVrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODU5MTAwOTUsImV4cCI6MjEwMTQ4NjA5NX0.qq7Ddl-SxH6glpUypFDrD8Jf5sQ8uPd85QhfTGtqvOE');
  final companyName = 'Kuncharakkattil Granites';
  try {
    dynamic query = client.from('ledger_bill_settlements').select('*').ilike('company_name', companyName);
    query = query.order('cleared_date', ascending: false);
    final response = await query.range(0, 999);
    final data = response as List;
    print('Found ${data.length} records.');
  } catch (e) {
    print('Error: $e');
  }
  exit(0);
}
