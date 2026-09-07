import 'package:supabase/supabase.dart';
import 'dart:io';

// This script checks what RLS policies exist on relevant tables
Future<void> main() async {
  // Using anon key - service role key needed to see policy details
  final client = SupabaseClient('https://gwerbqebixlmniqzlhuk.supabase.co', 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imd3ZXJicWViaXhsbW5pcXpsaHVrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODU5MTAwOTUsImV4cCI6MjEwMTQ4NjA5NX0.qq7Ddl-SxH6glpUypFDrD8Jf5sQ8uPd85QhfTGtqvOE');
  
  // Test customers table (which works fine in app)
  try {
    final r = await client.from('customers').select('company_name').limit(1);
    print('customers (anon): ${(r as List).length} records');
  } catch (e) { print('customers (anon) ERROR: $e'); }
  
  // Test ledger_bill_settlements (which is broken in app)  
  try {
    final r = await client.from('ledger_bill_settlements').select('company_name').limit(1);
    print('ledger_bill_settlements (anon): ${(r as List).length} records');
  } catch (e) { print('ledger_bill_settlements (anon) ERROR: $e'); }

  exit(0);
}
