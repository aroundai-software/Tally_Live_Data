import 'package:supabase/supabase.dart';
import 'dart:io';

Future<void> main() async {
  final client = SupabaseClient(
    'https://gwerbqebixlmniqzlhuk.supabase.co',
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imd3ZXJicWViaXhsbW5pcXpsaHVrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODU5MTAwOTUsImV4cCI6MjEwMTQ4NjA5NX0.qq7Ddl-SxH6glpUypFDrD8Jf5sQ8uPd85QhfTGtqvOE'
  );

  print('=== USERS ===');
  try {
    final users = await client.from('users').select();
    for (var u in users) {
      print('User details: $u');
    }
  } catch (e) {
    print('Error querying users: $e');
  }

  print('\n=== USER_COMPANIES ===');
  try {
    final userCompanies = await client.from('user_companies').select();
    print('user_companies rows: $userCompanies');
  } catch (e) {
    print('user_companies query error: $e');
  }

  print('\n=== TALLY_COMPANIES ===');
  try {
    final tallyCompanies = await client.from('tally_companies').select();
    for (var c in tallyCompanies) {
      print('TallyCompany details: $c');
    }
  } catch (e) {
    print('tally_companies query error: $e');
  }

  exit(0);
}
