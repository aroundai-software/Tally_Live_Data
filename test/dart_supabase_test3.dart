import 'package:supabase/supabase.dart';
import 'dart:io';

Future<void> main() async {
  final client = SupabaseClient('https://gwerbqebixlmniqzlhuk.supabase.co', 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imd3ZXJicWViaXhsbW5pcXpsaHVrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODU5MTAwOTUsImV4cCI6MjEwMTQ4NjA5NX0.qq7Ddl-SxH6glpUypFDrD8Jf5sQ8uPd85QhfTGtqvOE');
  
  final companyName = 'Kuncharakkattil Granites';
  
  List<dynamic> allData = [];
  int offset = 0;
  const int limit = 1000;
  bool hasMore = true;

  try {
    while (hasMore) {
      dynamic query = client.from('sales_invoices').select('*').ilike('company_name', companyName).order('invoice_date', ascending: false);

      final response = await query.range(offset, offset + limit - 1);
      final data = response as List;
      allData.addAll(data);
      hasMore = data.length == limit;
      offset += limit;
    }
    
    // Now apply filter logic
    final now = DateTime(2026, 9, 3, 16, 43, 28);
    DateTime filterStart = DateTime(now.year, now.month, now.day);
    DateTime filterEnd = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
    
    int matchCount = 0;
    for (var item in allData) {
      if (item['invoice_date'] != null) {
        final parsed = DateTime.tryParse(item['invoice_date'])?.toLocal();
        if (parsed != null) {
          if (parsed.isAfter(filterStart.subtract(const Duration(milliseconds: 1))) &&
              parsed.isBefore(filterEnd.add(const Duration(milliseconds: 1)))) {
            matchCount++;
          }
        }
      }
    }
    
    print('Matches today: ' + matchCount.toString());
    
  } catch (e) {
    print('Error: ' + e.toString());
  }
  exit(0);
}
