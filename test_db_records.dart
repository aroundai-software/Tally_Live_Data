import 'package:supabase_flutter/supabase_flutter.dart';
import 'lib/config/supabase_config.dart';

void main() async {
  await Supabase.initialize(
    url: SupabaseConfig.supabaseUrl,
    anonKey: SupabaseConfig.supabaseAnonKey,
  );
  
  final client = Supabase.instance.client;
  
  final data = await client
      .from('outstanding_receivables')
      .select('customer_name, invoicenumber, date, duedate, overdue_days, credit_days, amount')
      .limit(10);
      
  for (var row in data) {
    print(row);
  }
}
