import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

void main() {
  test('Test invoice date filtering', () {
    final now = DateTime(2026, 9, 3, 16, 43, 28);
    final today = DateTime(now.year, now.month, now.day);
    
    // Simulating the invoice date from Supabase
    final rawString = '2026-09-03T00:00:00+00:00'; 
    final parsed = DateTime.tryParse(rawString)?.toLocal();
    print('Parsed: $parsed');
    
    DateTime? filterStart = DateTime(now.year, now.month, now.day);
    DateTime? filterEnd = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
    
    print('Filter Start: $filterStart');
    print('Filter End: $filterEnd');
    
    bool isAfter = parsed!.isAfter(filterStart.subtract(const Duration(milliseconds: 1)));
    bool isBefore = parsed.isBefore(filterEnd.add(const Duration(milliseconds: 1)));
    
    print('Is After: $isAfter');
    print('Is Before: $isBefore');
  });
}
