import 'package:supabase/supabase.dart';
import 'dart:io';

Future<void> main() async {
  final client = SupabaseClient('https://gwerbqebixlmniqzlhuk.supabase.co', 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imd3ZXJicWViaXhsbW5pcXpsaHVrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODU5MTAwOTUsImV4cCI6MjEwMTQ4NjA5NX0.qq7Ddl-SxH6glpUypFDrD8Jf5sQ8uPd85QhfTGtqvOE');
  
  try {
    final response = await client.from('ledger_bill_settlements').select('*').limit(10);
    final data = response as List;
    print('Found ${data.length} records in ledger_bill_settlements.');
    if (data.isNotEmpty) {
      print('First record: ${data[0]}');
    }
  } catch (e) {
    print('Error: $e');
  }
  exit(0);
}
