import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import '../models/stock_item.dart';
import '../models/ledger.dart';
import '../models/receivable_payable.dart';
import '../models/sales_invoice.dart';
import '../models/purchase_invoice.dart';
import '../models/daybook_entry.dart';
import '../models/ledger_bill_settlement.dart';

class SupabaseService {
  final SupabaseClient _client = Supabase.instance.client;

  // ─── Auth & User Profiles ─────────────────────────────────────
  User? get currentUser => _client.auth.currentUser;
  Session? get currentSession => _client.auth.currentSession;

  Future<AuthResponse> signInWithPhone({required String phone, required String password}) async {
    final allDigits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    final tenDigits = allDigits.length >= 10 ? allDigits.substring(allDigits.length - 10) : allDigits;
    
    final emailAlias1 = '$tenDigits@gmail.com';
    final emailAlias2 = '$tenDigits@tallylive.com';
    final emailAlias3 = '$tenDigits@tallylive.app';

    Object? firstError;

    // 1. Try 10-digit gmail.com email alias
    try {
      return await _client.auth.signInWithPassword(
        email: emailAlias1,
        password: password,
      );
    } catch (e) {
      firstError = e;
    }

    // 2. Try 10-digit tallylive.com email alias
    try {
      return await _client.auth.signInWithPassword(
        email: emailAlias2,
        password: password,
      );
    } catch (_) {}

    // 3. Try 10-digit tallylive.app email alias
    try {
      return await _client.auth.signInWithPassword(
        email: emailAlias3,
        password: password,
      );
    } catch (_) {}

    // 3. Try raw input as email
    try {
      return await _client.auth.signInWithPassword(
        email: phone.trim(),
        password: password,
      );
    } catch (_) {}

    if (firstError != null) {
      throw firstError;
    }
    throw 'Invalid phone number or password. Please check your credentials and try again.';
  }

  Future<AuthResponse> registerUser({
    required String fullName,
    required String phone,
    required String password,
    String? companyName,
  }) async {
    final allDigits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    final tenDigits = allDigits.length >= 10 ? allDigits.substring(allDigits.length - 10) : allDigits;
    if (tenDigits.length < 10) throw 'Please enter a valid 10-digit mobile number.';
    if (password.length < 6) throw 'Password must be at least 6 characters.';

    final emailAlias = '$tenDigits@tallylive.app';

    AuthResponse res;
    try {
      res = await _client.auth.signUp(
        email: emailAlias,
        password: password,
        data: {
          'full_name': fullName.trim(),
          'phone_number': tenDigits,
        },
      );
    } catch (e) {
      final errStr = e.toString().toLowerCase();
      if (errStr.contains('user_already_exists')) {
        throw 'An account with this mobile number already exists. Please try logging in instead.';
      } else if (errStr.contains('email_provider_disabled') || errStr.contains('email signups are disabled')) {
        throw 'Account registration is temporarily unavailable. Please try again later or contact support.';
      } else if (errStr.contains('rate limit') || errStr.contains('429') || errStr.contains('over_email_send_rate_limit')) {
        try {
          res = await signInWithPhone(phone: tenDigits, password: password);
        } catch (_) {
          throw 'Registration limit exceeded. Please wait a few minutes and try again.';
        }
      } else {
        rethrow;
      }
    }

    final user = res.user;
    if (user != null) {
      try {
        await _client.from('users').upsert({
          'id': user.id,
          'full_name': fullName.trim(),
          'phone_number': tenDigits,
          'company_name': companyName?.trim() ?? '',
          'role': 'owner',
        });
      } catch (err) {
        print('Profile upsert warning: $err');
      }

      if (companyName != null && companyName.trim().isNotEmpty) {
        try {
          await linkCompanyToUser(
            userId: user.id,
            companyName: companyName.trim(),
            mobileNumber: tenDigits,
          );
        } catch (_) {}
      }
    }

    return res;
  }

  Future<AuthResponse> adminRegisterUser({
    required String fullName,
    required String phone,
    required String password,
  }) async {
    final allDigits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    final tenDigits = allDigits.length >= 10 ? allDigits.substring(allDigits.length - 10) : allDigits;
    if (tenDigits.length < 10) throw 'Please enter a valid 10-digit mobile number.';
    if (password.length < 6) throw 'Password must be at least 6 characters.';

    final emailAlias = '$tenDigits@tallylive.app';

    final tempClient = SupabaseClient(
      SupabaseConfig.supabaseUrl,
      SupabaseConfig.supabaseAnonKey,
      authOptions: const AuthClientOptions(
        authFlowType: AuthFlowType.implicit,
      ),
    );

    AuthResponse res;
    try {
      res = await tempClient.auth.signUp(
        email: emailAlias,
        password: password,
        data: {
          'full_name': fullName.trim(),
          'phone_number': tenDigits,
        },
      );
    } catch (e) {
      final errStr = e.toString().toLowerCase();
      if (errStr.contains('user_already_exists')) {
        throw 'An account with this mobile number already exists.';
      } else if (errStr.contains('email_provider_disabled') || errStr.contains('email signups are disabled')) {
        throw 'Account registration is temporarily unavailable.';
      } else if (errStr.contains('rate limit') || errStr.contains('429') || errStr.contains('over_email_send_rate_limit')) {
        throw 'Registration limit exceeded. Please wait a few minutes and try again.';
      } else {
        rethrow;
      }
    } finally {
      // Clean up temporary client auth session to avoid leaks
      try {
        await tempClient.auth.signOut();
      } catch (_) {}
    }

    final user = res.user;
    if (user != null) {
      try {
        await _client.from('users').upsert({
          'id': user.id,
          'full_name': fullName.trim(),
          'phone_number': tenDigits,
          'company_name': '',
          'role': 'owner',
        });
      } catch (err) {
        print('Profile upsert warning: $err');
      }
    }

    return res;
  }

  Future<Map<String, dynamic>?> getUserProfile(String userId) async {
    try {
      final response = await _client
          .from('users')
          .select()
          .eq('id', userId)
          .maybeSingle();
      return response;
    } catch (e) {
      return null;
    }
  }

  Future<void> updatePassword(String newPassword) async {
    await _client.auth.updateUser(
      UserAttributes(password: newPassword),
    );
  }

  Future<void> updateUserPhone(String userId, String newPhone) async {
    final cleanDigits = newPhone.replaceAll(RegExp(r'[^0-9]'), '');
    final tenDigits = cleanDigits.length >= 10 ? cleanDigits.substring(cleanDigits.length - 10) : cleanDigits;

    // 1. Try RPC call to update both Auth & Profile
    try {
      await _client.rpc('update_owner_phone', params: {'p_new_phone': tenDigits});
      return;
    } catch (_) {}

    // 2. Fallback to direct table update
    final existing = await getUserProfile(userId);
    if (existing != null) {
      await _client.from('users').update({
        'phone_number': tenDigits,
      }).eq('id', userId);
    } else {
      await _client.from('users').upsert({
        'id': userId,
        'phone_number': tenDigits,
        'company_name': 'Demo Company',
        'role': 'owner',
      });
    }
  }

  Future<void> updateUserFullName(String userId, String newName) async {
    // 1. Update Auth metadata so Supabase Auth Dashboard updates Display name
    try {
      await _client.auth.updateUser(
        UserAttributes(data: {'full_name': newName.trim()}),
      );
    } catch (_) {}

    // 2. Update public.users profile table
    final existing = await getUserProfile(userId);
    if (existing != null) {
      await _client.from('users').update({
        'full_name': newName.trim(),
      }).eq('id', userId);
    } else {
      await _client.from('users').upsert({
        'id': userId,
        'full_name': newName.trim(),
        'company_name': 'Demo Company',
        'role': 'owner',
      });
    }
  }

  Future<List<String>> getUserCompanies(String userId) async {
    try {
      // 1. Query user_companies mapping table
      final response = await _client
          .from('user_companies')
          .select('company_name')
          .eq('user_id', userId);

      if (response is List && response.isNotEmpty) {
        final list = response
            .map((row) => row['company_name']?.toString() ?? '')
            .where((name) => name.isNotEmpty)
            .toList();
        if (list.isNotEmpty) return list;
      }
    } catch (_) {}

    // 2. Query primary company in public.users profile
    try {
      final profile = await getUserProfile(userId);
      if (profile != null) {
        final primaryCompany = profile['company_name']?.toString();
        final userPhone = profile['phone_number']?.toString().replaceAll(RegExp(r'[^0-9]'), '') ?? '';
        final tenDigits = userPhone.length >= 10 ? userPhone.substring(userPhone.length - 10) : userPhone;

        if (primaryCompany != null && primaryCompany.trim().isNotEmpty) {
          return [primaryCompany.trim()];
        }

        // 3. Auto-match active companies in tally_companies by registered mobile number
        if (tenDigits.isNotEmpty) {
          final matched = await _client
              .from('tally_companies')
              .select('company_name, mobile_number, phone_number')
              .eq('is_active', true);

          if (matched is List && matched.isNotEmpty) {
            final autoAssigned = <String>[];
            for (final row in matched) {
              final dbMobile = (row['mobile_number'] ?? row['phone_number'] ?? '').toString().replaceAll(RegExp(r'[^0-9]'), '');
              if (dbMobile.isNotEmpty && (dbMobile.contains(tenDigits) || tenDigits.contains(dbMobile))) {
                final cName = row['company_name']?.toString();
                if (cName != null && cName.isNotEmpty && !autoAssigned.contains(cName)) {
                  autoAssigned.add(cName);
                }
              }
            }
            if (autoAssigned.isNotEmpty) return autoAssigned;
          }
        }
      }
    } catch (_) {}

    return [];
  }

  Future<String> linkCompanyToUser({
    required String userId,
    required String companyName,
    required String mobileNumber,
  }) async {
    final cleanName = companyName.trim();
    final cleanMobile = mobileNumber.replaceAll(RegExp(r'[^0-9]'), '');
    final tenDigits = cleanMobile.length >= 10 ? cleanMobile.substring(cleanMobile.length - 10) : cleanMobile;

    if (cleanName.isEmpty) throw 'Please enter the exact company name.';
    if (tenDigits.isEmpty) throw 'Please enter a valid mobile number.';

    // 1. Fetch matching company from tally_companies where company_name ILIKE cleanName
    final response = await _client
        .from('tally_companies')
        .select('company_name, mobile_number, phone_number')
        .ilike('company_name', cleanName)
        .eq('is_active', true);

    if (response is! List || response.isEmpty) {
      throw 'No active company found with name "$cleanName".';
    }

    // 2. Verify mobile number match
    Map<String, dynamic>? matchedRow;
    for (final item in response) {
      final row = item as Map<String, dynamic>;
      final dbMobile = (row['mobile_number'] ?? row['phone_number'] ?? '').toString().replaceAll(RegExp(r'[^0-9]'), '');
      if (dbMobile.contains(tenDigits) || tenDigits.contains(dbMobile) && dbMobile.isNotEmpty) {
        matchedRow = row;
        break;
      }
    }

    if (matchedRow == null) {
      throw 'The mobile number provided does not match the registered phone number for "$cleanName".';
    }

    final matchedCompanyName = matchedRow['company_name'].toString();

    // 3. Upsert into user_companies mapping table or RPC
    try {
      await _client.rpc('link_company_to_user', params: {
        'p_user_id': userId,
        'p_company_name': matchedCompanyName,
      });
    } catch (_) {
      try {
        await _client.from('user_companies').upsert({
          'user_id': userId,
          'company_name': matchedCompanyName,
        });
      } catch (_) {
        // Fallback: update company_name in public.users profile
        await _client.from('users').update({
          'company_name': matchedCompanyName,
        }).eq('id', userId);
      }
    }

    return matchedCompanyName;
  }

  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  // ─── Companies ───────────────────────────────────────────────
  Future<List<String>> getCompanies() async {
    try {
      final names = <String>{};

      // Fetch all company names from tally_companies table
      int offset = 0;
      const int limit = 1000;
      bool hasMore = true;
      while (hasMore) {
        final response = await _client
            .from('tally_companies')
            .select('company_name')
            .eq('is_active', true)
            .range(offset, offset + limit - 1);
        final data = response as List;
        for (var item in data) {
          final name = item['company_name'];
          if (name != null && name.toString().isNotEmpty) {
            names.add(name.toString());
          }
        }
        hasMore = data.length == limit;
        offset += limit;
      }

      final sorted = names.toList()..sort();
      return sorted;
    } catch (e) {
      throw Exception('Failed to fetch companies: $e');
    }
  }

  // ─── Company Features & Subscription Gating ───────────────────
  Future<Map<String, bool>> getCompanyFeatures(String companyName) async {
    try {
      final response = await _client
          .from('company_features')
          .select()
          .ilike('company_name', companyName)
          .maybeSingle();

      if (response == null) {
        // Fallback: If not found, look up company ID and insert on-the-fly
        final comp = await _client
            .from('tally_companies')
            .select('id')
            .ilike('company_name', companyName)
            .maybeSingle();
        if (comp != null) {
          final compId = comp['id'];
          final inserted = await _client
              .from('company_features')
              .insert({
                'company_id': compId,
                'company_name': companyName,
              })
              .select()
              .maybeSingle();
          if (inserted != null) {
            return _parseFeatureMap(inserted);
          }
        }
        return _defaultFeatureMap();
      }
      return _parseFeatureMap(response);
    } catch (e, st) {
      print('getCompanyFeatures error for $companyName: $e\n$st');
      return _defaultFeatureMap();
    }
  }

  Stream<Map<String, bool>> streamCompanyFeatures(String companyName) {
    return _client
        .from('company_features')
        .stream(primaryKey: ['id'])
        .eq('company_name', companyName)
        .map((events) {
      if (events.isEmpty) return _defaultFeatureMap();
      return _parseFeatureMap(events.first);
    });
  }

  Future<void> updateCompanyFeatures(String companyName, Map<String, bool> features) async {
    try {
      // First ensure the record exists (in case it is missing)
      await getCompanyFeatures(companyName);
      
      await _client.from('company_features').update({
        'is_dashboard_enabled': features['dashboard'] ?? true,
        'is_stock_enabled': features['stock'] ?? true,
        'is_ledgers_enabled': features['ledgers'] ?? true,
        'is_outstanding_enabled': features['outstanding'] ?? true,
        'is_sales_enabled': features['sales'] ?? true,
        'is_purchases_enabled': features['purchases'] ?? true,
        'is_analytics_enabled': features['analytics'] ?? true,
        // Dashboard JSONB — storing all sub-features and configurations
        'dashboard_config': {
          'db_net_position': features['db_net_position'] ?? true,
          'db_summary_cards': features['db_summary_cards'] ?? true,
          'db_daybook': features['db_daybook'] ?? true,
          'db_quick_actions': features['db_quick_actions'] ?? true,
          'out_receivables': features['out_receivables'] ?? true,
          'out_payables': features['out_payables'] ?? true,
          'rep_sales': features['rep_sales'] ?? true,
          'rep_purchases': features['rep_purchases'] ?? true,
          'rep_ledgers': features['rep_ledgers'] ?? true,
          'stock_cost': features['stock_cost'] ?? true,
          'cards': {
            'cash_bank':           features['db_card_cash_bank']           ?? true,
            'stock_value':         features['db_card_stock_value']         ?? true,
            'today_sales':         features['db_card_today_sales']         ?? true,
            'today_purchases':     features['db_card_today_purchases']     ?? true,
            'overdue_receivables': features['db_card_overdue_receivables'] ?? true,
            'overdue_payables':    features['db_card_overdue_payables']    ?? true,
          },
          'quick_actions': {
            'stock':   features['db_qa_stock']   ?? true,
            'ledgers': features['db_qa_ledgers'] ?? true,
            'sales':   features['db_qa_sales']   ?? true,
            'reports': features['db_qa_reports'] ?? true,
          },
          'net_position': {
            'stock':       features['db_np_stock']       ?? true,
            'receivables': features['db_np_receivables'] ?? true,
            'payables':    features['db_np_payables']    ?? true,
            'cash':        features['db_np_cash']        ?? true,
            'bank':        features['db_np_bank']        ?? true,
          },
        },
      }).ilike('company_name', companyName);
    } catch (e) {
      throw Exception('Failed to update company features: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getAllCompaniesFeatures() async {
    try {
      // 1. Fetch all active companies
      final companiesRes = await _client
          .from('tally_companies')
          .select('id, company_name')
          .eq('is_active', true);
      
      final companies = (companiesRes as List).cast<Map<String, dynamic>>();
      
      // 2. Fetch all configuration rows in company_features
      final featuresRes = await _client.from('company_features').select();
      final featuresList = (featuresRes as List).cast<Map<String, dynamic>>();

      final results = <Map<String, dynamic>>[];

      for (var comp in companies) {
        final compName = comp['company_name']?.toString() ?? '';
        if (compName.isEmpty) continue;

        var feat = featuresList.firstWhere(
          (f) => f['company_id'] == comp['id'] || f['company_name'] == compName,
          orElse: () => {},
        );

        if (feat.isEmpty) {
          // Self-heal: insert missing entry
          try {
            final newFeat = await _client
                .from('company_features')
                .insert({
                  'company_id': comp['id'],
                  'company_name': compName,
                })
                .select()
                .maybeSingle();
            if (newFeat != null) {
              feat = newFeat;
            }
          } catch (_) {}
        }

        results.add({
          'company_name': compName,
          'features': feat.isNotEmpty ? _parseFeatureMap(feat) : _defaultFeatureMap(),
        });
      }

      results.sort((a, b) => a['company_name'].toString().compareTo(b['company_name'].toString()));
      return results;
    } catch (e) {
      throw Exception('Failed to fetch all companies features: $e');
    }
  }

  Map<String, bool> _parseFeatureMap(Map<dynamic, dynamic> row) {
    // Parse dashboard JSONB config — flatten nested JSON into prefixed keys
    final dashCfg = (row['dashboard_config'] as Map<String, dynamic>?) ?? {};
    final cards   = (dashCfg['cards']         as Map<String, dynamic>?) ?? {};
    final qa      = (dashCfg['quick_actions'] as Map<String, dynamic>?) ?? {};
    final netPos  = (dashCfg['net_position']  as Map<String, dynamic>?) ?? {};

    return {
      'dashboard': row['is_dashboard_enabled'] ?? true,
      'stock': row['is_stock_enabled'] ?? true,
      'ledgers': row['is_ledgers_enabled'] ?? true,
      'outstanding': row['is_outstanding_enabled'] ?? true,
      'sales': row['is_sales_enabled'] ?? true,
      'purchases': row['is_purchases_enabled'] ?? true,
      'analytics': row['is_analytics_enabled'] ?? true,
      // Dashboard sub-features (read from JSONB instead of separate columns)
      'db_net_position': dashCfg['db_net_position'] as bool? ?? true,
      'db_summary_cards': dashCfg['db_summary_cards'] as bool? ?? true,
      'db_daybook': dashCfg['db_daybook'] as bool? ?? true,
      'db_quick_actions': dashCfg['db_quick_actions'] as bool? ?? true,
      // Outstanding sub-features (read from JSONB instead of separate columns)
      'out_receivables': dashCfg['out_receivables'] as bool? ?? true,
      'out_payables': dashCfg['out_payables'] as bool? ?? true,
      // Reports sub-features (read from JSONB instead of separate columns)
      'rep_sales': dashCfg['rep_sales'] as bool? ?? true,
      'rep_purchases': dashCfg['rep_purchases'] as bool? ?? true,
      'rep_ledgers': dashCfg['rep_ledgers'] as bool? ?? true,
      // Stock sub-features (read from JSONB instead of separate columns)
      'stock_cost': dashCfg['stock_cost'] as bool? ?? true,
      // Dashboard JSONB — individual cards (default true when key absent)
      'db_card_cash_bank':           cards['cash_bank']           as bool? ?? true,
      'db_card_stock_value':         cards['stock_value']         as bool? ?? true,
      'db_card_today_sales':         cards['today_sales']         as bool? ?? true,
      'db_card_today_purchases':     cards['today_purchases']     as bool? ?? true,
      'db_card_overdue_receivables': cards['overdue_receivables'] as bool? ?? true,
      'db_card_overdue_payables':    cards['overdue_payables']    as bool? ?? true,
      // Dashboard JSONB — quick action buttons
      'db_qa_stock':   qa['stock']   as bool? ?? true,
      'db_qa_ledgers': qa['ledgers'] as bool? ?? true,
      'db_qa_sales':   qa['sales']   as bool? ?? true,
      'db_qa_reports': qa['reports'] as bool? ?? true,
      // Dashboard JSONB — Net Position detail rows
      'db_np_stock':       netPos['stock']       as bool? ?? true,
      'db_np_receivables': netPos['receivables'] as bool? ?? true,
      'db_np_payables':    netPos['payables']    as bool? ?? true,
      'db_np_cash':        netPos['cash']        as bool? ?? true,
      'db_np_bank':        netPos['bank']        as bool? ?? true,
    };
  }

  Map<String, bool> _defaultFeatureMap() {
    return {
      'dashboard': true,
      'stock': true,
      'ledgers': true,
      'outstanding': true,
      'sales': true,
      'purchases': true,
      'analytics': true,
      // Dashboard sub-features
      'db_net_position': true,
      'db_summary_cards': true,
      'db_daybook': true,
      'db_quick_actions': true,
      // Outstanding sub-features
      'out_receivables': true,
      'out_payables': true,
      // Reports sub-features
      'rep_sales': true,
      'rep_purchases': true,
      'rep_ledgers': true,
      // Stock sub-features
      'stock_cost': true,
      // Dashboard JSONB — individual cards
      'db_card_cash_bank': true,
      'db_card_stock_value': true,
      'db_card_today_sales': true,
      'db_card_today_purchases': true,
      'db_card_overdue_receivables': true,
      'db_card_overdue_payables': true,
      // Dashboard JSONB — quick action buttons
      'db_qa_stock': true,
      'db_qa_ledgers': true,
      'db_qa_sales': true,
      'db_qa_reports': true,
      // Dashboard JSONB — Net Position detail rows
      'db_np_stock': true,
      'db_np_receivables': true,
      'db_np_payables': true,
      'db_np_cash': true,
      'db_np_bank': true,
    };
  }

  // ─── Products (Stock) ──────────────────────────────────────────
  Future<List<StockItem>> getProducts({String? searchQuery, String? companyName}) async {
    try {
      final data = await _fetchAll(
        'stock_items',
        companyName: companyName,
        searchQuery: searchQuery,
        searchColumn: 'ItemName',
        orderColumn: 'ItemName',
      );
      return data.map((e) => StockItem.fromJson(e)).toList();
    } catch (e) {
      throw Exception('Failed to fetch products: $e');
    }
  }

  Future<double> getTotalStockValue({String? companyName}) async {
    try {
      final data = await _fetchAll(
        'stock_items',
        select: 'ItemQuantity, ItemRate',
        companyName: companyName,
      );
      double total = 0;
      for (var item in data) {
        final qty = _toDouble(item['ItemQuantity']);
        final rate = _toDouble(item['ItemRate']);
        total += qty * rate;
      }
      return total;
    } catch (e) {
      return 0;
    }
  }

  Future<int> getProductCount({String? companyName}) async {
    return _fetchCount('stock_items', companyName: companyName);
  }

  // ─── Customers (Ledgers) ───────────────────────────────────────
  Future<List<Ledger>> getCustomers({String? searchQuery, String? companyName}) async {
    try {
      final data = await _fetchAll(
        'customers',
        companyName: companyName,
        searchQuery: searchQuery,
        searchColumn: 'customer_name',
        orderColumn: 'customer_name',
      );
      return data.map((e) => Ledger.fromJson(e)).toList();
    } catch (e) {
      throw Exception('Failed to fetch customers: $e');
    }
  }

  Future<double> getTotalCash({String? companyName}) async {
    if (companyName == null || companyName.isEmpty || companyName == 'No Company Linked') return 0;
    try {
      final response = await _client
          .from('customers')
          .select('closing_balance')
          .ilike('company_name', companyName)
          .or('ledger_type.ilike.%cash%') as List;
      double total = 0;
      for (var item in response) {
        total += _toDouble(item['closing_balance']);
      }
      return total;
    } catch (e) {
      return 0;
    }
  }

  Future<double> getTotalBank({String? companyName}) async {
    if (companyName == null || companyName.isEmpty || companyName == 'No Company Linked') return 0;
    try {
      final response = await _client
          .from('customers')
          .select('closing_balance')
          .ilike('company_name', companyName)
          .or('ledger_type.ilike.%bank%') as List;
      double total = 0;
      for (var item in response) {
        total += _toDouble(item['closing_balance']);
      }
      return total;
    } catch (e) {
      return 0;
    }
  }

  Future<List<Ledger>> getCashBankLedgers({String? companyName}) async {
    if (companyName == null || companyName.isEmpty || companyName == 'No Company Linked') return [];
    try {
      final response = await _client
          .from('customers')
          .select()
          .ilike('company_name', companyName)
          .or('ledger_type.ilike.%bank%,ledger_type.ilike.%cash%') as List;
      return response.map((e) => Ledger.fromJson(e)).toList();
    } catch (e) {
      return [];
    }
  }

  Future<DateTime?> getLastSyncTime({String? companyName}) async {
    if (companyName == null || companyName.isEmpty || companyName == 'No Company Linked') return null;
    try {
      final response = await _client
          .from('sync_logs')
          .select('finished_at, updated_at')
          .ilike('company_name', companyName)
          .or('status.ilike.%success%,status.ilike.%completed%')
          .order('finished_at', ascending: false)
          .limit(1) as List;
          
      if (response.isNotEmpty) {
        final finishedAt = response[0]['finished_at'];
        if (finishedAt != null) {
          return DateTime.tryParse(finishedAt.toString());
        }
        final updatedAt = response[0]['updated_at'];
        if (updatedAt != null) {
          return DateTime.tryParse(updatedAt.toString());
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<int> getCustomerCount({String? companyName}) async {
    return _fetchCount('customers', companyName: companyName);
  }

  // ─── Outstanding (Receivables & Payables) ──────────────────────
  Future<List<OutstandingRecord>> getOutstandingReceivables({String? searchQuery, String? companyName}) async {
    try {
      final data = await _fetchAll(
        'outstanding_receivables',
        companyName: companyName,
        searchQuery: searchQuery,
        searchColumn: 'customer_name',
        orderColumn: 'customer_name',
      );
      return data.map((e) => OutstandingRecord.fromJson(e)).toList();
    } catch (e) {
      throw Exception('Failed to fetch outstanding receivables: $e');
    }
  }

  Future<List<OutstandingRecord>> getOutstandingPayables({String? searchQuery, String? companyName}) async {
    try {
      final data = await _fetchAll(
        'outstanding_payables',
        companyName: companyName,
        searchQuery: searchQuery,
        searchColumn: 'customer_name',
        orderColumn: 'customer_name',
      );
      return data.map((e) => OutstandingRecord.fromJson(e)).toList();
    } catch (e) {
      throw Exception('Failed to fetch outstanding payables: $e');
    }
  }

  Future<double> getTotalOverdueReceivables({String? companyName}) async {
    try {
      final data = await _fetchAll(
        'outstanding_receivables',
        select: 'amount, closing_balance, overdue_days, duedate',
        companyName: companyName,
      );
      double total = 0;
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      for (var item in data) {
        final amount = _toDouble(item['amount']);
        final closing = _toDouble(item['closing_balance']);
        final val = closing != 0 ? closing.abs() : amount.abs();

        final overdueDays = item['overdue_days'] != null
            ? (item['overdue_days'] is num
                ? (item['overdue_days'] as num).toInt()
                : int.tryParse(item['overdue_days'].toString()))
            : null;

        final dueDate = item['duedate'] != null
            ? DateTime.tryParse(item['duedate'].toString())
            : null;

        bool isOverdue = (overdueDays != null && overdueDays > 0) ||
            (dueDate != null && dueDate.isBefore(today));

        if (isOverdue) {
          total += val;
        }
      }
      return total;
    } catch (e) {
      return 0;
    }
  }


  Future<double> getTotalOverduePayables({String? companyName}) async {
    try {
      final data = await _fetchAll(
        'outstanding_payables',
        select: 'amount, closing_balance, overdue_days, duedate',
        companyName: companyName,
      );
      double total = 0;
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      for (var item in data) {
        final amount = _toDouble(item['amount']);
        final closing = _toDouble(item['closing_balance']);
        final val = closing != 0 ? closing.abs() : amount.abs();

        final overdueDays = item['overdue_days'] != null
            ? (item['overdue_days'] is num
                ? (item['overdue_days'] as num).toInt()
                : int.tryParse(item['overdue_days'].toString()))
            : null;

        final dueDate = item['duedate'] != null
            ? DateTime.tryParse(item['duedate'].toString())
            : null;

        bool isOverdue = (overdueDays != null && overdueDays > 0) ||
            (dueDate != null && dueDate.isBefore(today));

        if (isOverdue) {
          total += val;
        }
      }
      return total;
    } catch (e) {
      return 0;
    }
  }
  Future<double> getTotalReceivables({String? companyName}) async {
    try {
      final data = await _fetchAll(
        'outstanding_receivables',
        select: 'amount, closing_balance',
        companyName: companyName,
      );
      double total = 0;
      for (var item in data) {
        final amount = _toDouble(item['amount']);
        final closing = _toDouble(item['closing_balance']);
        total += closing != 0 ? closing.abs() : amount.abs();
      }
      return total;
    } catch (e) {
      return 0;
    }
  }

  Future<double> getTotalPayables({String? companyName}) async {
    try {
      final data = await _fetchAll(
        'outstanding_payables',
        select: 'amount, closing_balance',
        companyName: companyName,
      );
      double total = 0;
      for (var item in data) {
        final amount = _toDouble(item['amount']);
        final closing = _toDouble(item['closing_balance']);
        total += closing != 0 ? closing.abs() : amount.abs();
      }
      return total;
    } catch (e) {
      return 0;
    }
  }

  // ─── Sales Invoices ────────────────────────────────────────────
  Future<List<SalesInvoice>> getSalesInvoices({String? searchQuery, String? companyName}) async {
    try {
      if (companyName == null || companyName.isEmpty || companyName == 'No Company Linked') return [];
      var query = _client.from('sales_invoices').select().ilike('company_name', companyName);
      if (searchQuery != null && searchQuery.isNotEmpty) {
        query = query.or('customer_name.ilike.%$searchQuery%,invoice_number.ilike.%$searchQuery%');
      }
      final response = await query.order('invoice_date', ascending: false).limit(5000);
      final data = response as List;
      return data.map((e) => SalesInvoice.fromJson(e)).toList();
    } catch (e) {
      throw Exception('Failed to fetch sales invoices: $e');
    }
  }


  Future<int> getTodaysSalesCount({String? companyName}) async {
    if (companyName == null || companyName.isEmpty || companyName == 'No Company Linked') return 0;
    try {
      final today = DateTime.now();
      final dateStr = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      final data = await _client
          .from('sales_invoices')
          .select('id')
          .ilike('company_name', companyName)
          .gte('invoice_date', dateStr)
          .lte('invoice_date', dateStr)
          .limit(5000) as List;
      return data.length;
    } catch (e) {
      return 0;
    }
  }

  Future<int> getTodaysPurchasesCount({String? companyName}) async {
    if (companyName == null || companyName.isEmpty || companyName == 'No Company Linked') return 0;
    try {
      final today = DateTime.now();
      final dateStr = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      final data = await _client
          .from('purchase_invoices')
          .select('id')
          .ilike('company_name', companyName)
          .gte('invoice_date', dateStr)
          .lte('invoice_date', dateStr)
          .limit(5000) as List;
      return data.length;
    } catch (e) {
      return 0;
    }
  }

  Future<double> getTodaysSales({String? companyName}) async {
    if (companyName == null || companyName.isEmpty || companyName == 'No Company Linked') return 0;
    try {
      final today = DateTime.now();
      final dateStr = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      final data = await _client
          .from('sales_invoices')
          .select('net_amount')
          .ilike('company_name', companyName)
          .gte('invoice_date', dateStr)
          .lte('invoice_date', dateStr)
          .limit(5000) as List;
      double total = 0;
      for (var item in data) {
        total += _toDouble(item['net_amount']);
      }
      return total;
    } catch (e) {
      return 0;
    }
  }

  Future<double> getTodaysPurchases({String? companyName}) async {
    if (companyName == null || companyName.isEmpty || companyName == 'No Company Linked') return 0;
    try {
      final today = DateTime.now();
      final dateStr = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      final data = await _client
          .from('purchase_invoices')
          .select('net_amount')
          .ilike('company_name', companyName)
          .gte('invoice_date', dateStr)
          .lte('invoice_date', dateStr)
          .limit(5000) as List;
      double total = 0;
      for (var item in data) {
        total += _toDouble(item['net_amount']);
      }
      return total;
    } catch (e) {
      return 0;
    }
  }
  Future<double> getTotalSales({String? companyName}) async {
    try {
      final data = await _fetchAll(
        'sales_invoices',
        select: 'net_amount',
        companyName: companyName,
      );
      double total = 0;
      for (var item in data) {
        total += _toDouble(item['net_amount']);
      }
      return total;
    } catch (e) {
      return 0;
    }
  }

  Future<int> getSalesInvoiceCount({String? companyName}) async {
    return _fetchCount('sales_invoices', companyName: companyName);
  }

  Future<List<InvoiceItem>> getInvoiceItems(String invoiceId) async {
    try {
      final response = await _client
          .from('invoice_items')
          .select()
          .eq('invoice_id', invoiceId);
      return (response as List).map((e) => InvoiceItem.fromJson(e)).toList();
    } catch (e) {
      return [];
    }
  }

  Future<Map<String, double>> getProductSalesTotals({required String companyName}) async {
    if (companyName.isEmpty || companyName == 'No Company Linked') return {};
    try {
      final response = await _client
          .from('invoice_items')
          .select('product_name, total_amount')
          .ilike('company_name', companyName);
          
      final Map<String, double> salesTotals = {};
      for (var item in response as List) {
        final String name = item['product_name'] ?? '';
        if (name.isNotEmpty) {
          final double amount = _toDouble(item['total_amount']);
          salesTotals[name] = (salesTotals[name] ?? 0.0) + amount;
        }
      }
      return salesTotals;
    } catch (e) {
      return {};
    }
  }

  // ─── Purchase Invoices ─────────────────────────────────────────
  Future<List<PurchaseInvoice>> getPurchaseInvoices({String? searchQuery, String? companyName}) async {
    try {
      if (companyName == null || companyName.isEmpty || companyName == 'No Company Linked') return [];
      var query = _client.from('purchase_invoices').select().ilike('company_name', companyName);
      if (searchQuery != null && searchQuery.isNotEmpty) {
        query = query.or('supplier_name.ilike.%$searchQuery%,invoice_number.ilike.%$searchQuery%');
      }
      final response = await query.order('invoice_date', ascending: false).limit(5000);
      final data = response as List;
      return data.map((e) => PurchaseInvoice.fromJson(e)).toList();
    } catch (e) {
      throw Exception('Failed to fetch purchase invoices: $e');
    }
  }

  Future<double> getTotalPurchases({String? companyName}) async {
    try {
      final data = await _fetchAll(
        'purchase_invoices',
        select: 'net_amount',
        companyName: companyName,
      );
      double total = 0;
      for (var item in data) {
        total += _toDouble(item['net_amount']);
      }
      return total;
    } catch (e) {
      return 0;
    }
  }

  Future<int> getPurchaseInvoiceCount({String? companyName}) async {
    return _fetchCount('purchase_invoices', companyName: companyName);
  }

  Future<List<PurchaseInvoiceItem>> getPurchaseInvoiceItems(String invoiceId) async {
    try {
      final response = await _client
          .from('invoice_items_purchase')
          .select()
          .eq('purchase_invoice_id', invoiceId);
      return (response as List).map((e) => PurchaseInvoiceItem.fromJson(e)).toList();
    } catch (e) {
      return [];
    }
  }

  // ─── Daybook ───────────────────────────────────────────────────
  Future<List<DaybookEntry>> getDaybookEntries({DateTime? date, String? companyName, String? searchQuery}) async {
    if (companyName == null || companyName.isEmpty || companyName == 'No Company Linked') return [];
    try {
      dynamic query = _client.from('tally_daybook').select().ilike('company_name', companyName);
      
      if (date != null) {
        // Filter by specific date (ignore time)
        final startOfDay = DateTime(date.year, date.month, date.day).toUtc().toIso8601String();
        final endOfDay = DateTime(date.year, date.month, date.day, 23, 59, 59, 999).toUtc().toIso8601String();
        query = query.gte('date', startOfDay).lte('date', endOfDay);
      }
      
      if (searchQuery != null && searchQuery.isNotEmpty) {
         query = query.or('voucher_number.ilike.%$searchQuery%,ledger_name.ilike.%$searchQuery%,voucher_type.ilike.%$searchQuery%');
      }

      final response = await query.order('date', ascending: false).limit(1000);
      return (response as List).map((e) => DaybookEntry.fromJson(e)).toList();
    } catch (e) {
      return [];
    }
  }

  Future<List<DaybookEntry>> getLedgerVouchers({
    required String companyName,
    required String ledgerName,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      dynamic query = _client
          .from('tally_daybook')
          .select()
          .ilike('company_name', companyName)
          .ilike('ledger_name', ledgerName);

      if (startDate != null) {
        final start = DateTime(startDate.year, startDate.month, startDate.day).toUtc().toIso8601String();
        query = query.gte('date', start);
      }
      if (endDate != null) {
        final end = DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59, 999).toUtc().toIso8601String();
        query = query.lte('date', end);
      }

      // Order ascending to calculate running balances
      final response = await query.order('date', ascending: true).limit(1000);
      return (response as List).map((e) => DaybookEntry.fromJson(e)).toList();
    } catch (e) {
      return [];
    }
  }

  Future<Map<String, double>> getDaybookSummary({DateTime? date, String? companyName}) async {
    try {
      final entries = await getDaybookEntries(date: date, companyName: companyName);
      double inflow = 0;
      double outflow = 0;
      for (var entry in entries) {
        if (entry.isDebit) {
          inflow += entry.amount.abs();
        } else {
          outflow += entry.amount.abs();
        }
      }
      return {'inflow': inflow, 'outflow': outflow};
    } catch (e) {
      return {'inflow': 0, 'outflow': 0};
    }
  }

  // ─── Reports & Analytics ───────────────────────────────────────
  
  Future<List<Map<String, dynamic>>> getFastMovingItems({String? companyName, int days = 30}) async {
    try {
      final response = await _client.rpc('get_fast_moving_items', params: {
        'p_company_name': companyName,
        'p_days': days,
      });
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error in getFastMovingItems: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getSlowMovingItems({String? companyName, int days = 30}) async {
    try {
      final response = await _client.rpc('get_slow_moving_items', params: {
        'p_company_name': companyName,
        'p_days': days,
      });
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getHighValueItems({String? companyName}) async {
    try {
      final response = await _client.rpc('get_high_value_items', params: {
        'p_company_name': companyName,
      });
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getUnusedLedgers({String? companyName, int days = 180}) async {
    try {
      final response = await _client.rpc('get_unused_ledgers', params: {
        'p_company_name': companyName,
        'p_days': days,
      });
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getUnusedItems({String? companyName, int days = 180}) async {
    try {
      final response = await _client.rpc('get_unused_items', params: {
        'p_company_name': companyName,
        'p_days': days,
      });
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      return [];
    }
  }

  Future<int> getUnusedLedgersCount({String? companyName, int days = 180}) async {
    try {
      final response = await _client.rpc('get_unused_ledgers', params: {
        'p_company_name': companyName,
        'p_days': days,
      }).count(CountOption.exact);
      return response.count;
    } catch (e) {
      return 0;
    }
  }

  Future<int> getUnusedItemsCount({String? companyName, int days = 180}) async {
    try {
      final response = await _client.rpc('get_unused_items', params: {
        'p_company_name': companyName,
        'p_days': days,
      }).count(CountOption.exact);
      return response.count;
    } catch (e) {
      return 0;
    }
  }

  Future<List<Map<String, dynamic>>> getDailyProfit({String? companyName, int days = 7}) async {
    try {
      final response = await _client.rpc('get_daily_profit', params: {
        'p_company_name': companyName,
        'p_days': days,
      });
      return List<Map<String, dynamic>>.from(response);
    } catch (e, st) {
      print('Error in getDailyProfit: $e\n$st');
      return [];
    }
  }

  // ─── Helpers ───────────────────────────────────────────────────

  Future<List<dynamic>> _fetchAll(String table, {
    String select = '*',
    String? companyName,
    String? searchQuery,
    String? searchColumn,
    String? orderColumn,
    bool ascending = true,
  }) async {
    if (companyName == null || companyName.isEmpty || companyName == 'No Company Linked') return [];
    List<dynamic> allData = [];
    int offset = 0;
    const int limit = 1000;
    bool hasMore = true;

    while (hasMore) {
      dynamic query = _client.from(table).select(select).ilike('company_name', companyName);
      
      if (searchQuery != null && searchQuery.isNotEmpty) {
        if (table == 'sales_invoices') {
          query = query.or('customer_name.ilike.%$searchQuery%,invoice_number.ilike.%$searchQuery%');
        } else if (table == 'purchase_invoices') {
          query = query.or('supplier_name.ilike.%$searchQuery%,invoice_number.ilike.%$searchQuery%');
        } else if (table == 'stock_items') {
          // Multi-column search for products: Name, PartNumber, Rate, Quantity
          // Since Rate and Quantity are numeric, we can't use ilike directly on them in Supabase .or() 
          // easily without casting, but we can search in text columns and handle numeric filtering if needed.
          // For now, let's support Name and PartNumber in the query.
          query = query.or('ItemName.ilike.%$searchQuery%,PartNumber.ilike.%$searchQuery%');
        } else if (searchColumn != null) {
          query = query.ilike(searchColumn, '%$searchQuery%');
        }
      }

      if (orderColumn != null) {
        query = query.order(orderColumn, ascending: ascending);
      }

      if (select != '*') {
        final response = await query.limit(5000);
        return response as List;
      }

      final response = await query.range(offset, offset + limit - 1);
      final data = response as List;
      allData.addAll(data);
      hasMore = data.length == limit;
      offset += limit;
    }
    return allData;
  }

  Future<int> _fetchCount(String table, {String? companyName}) async {
    if (companyName == null || companyName.isEmpty || companyName == 'No Company Linked') return 0;
    try {
      final response = await _client
          .from(table)
          .select('id')
          .ilike('company_name', companyName)
          .count(CountOption.exact);
      return response.count;
    } catch (e) {
      return 0;
    }
  }

  // ── Money Flow / Settlements ────────────────────────────────────────────────
  
  Future<List<LedgerBillSettlement>> getBillSettlements(String companyName) async {
    // Fetch all pages of settlement data
    List<dynamic> allData = [];
    int offset = 0;
    const int pageSize = 1000;
    bool hasMore = true;

    while (hasMore) {
      final response = await _client
          .from('ledger_bill_settlements')
          .select()
          .ilike('company_name', companyName)
          .order('cleared_date', ascending: false)
          .range(offset, offset + pageSize - 1);
      final page = response as List;
      allData.addAll(page);
      hasMore = page.length == pageSize;
      offset += pageSize;
    }
    return allData.map((json) => LedgerBillSettlement.fromJson(json)).toList();
  }

  Future<List<Ledger>> getLedgersByName({required String companyName, required String ledgerName}) async {
    try {
      final response = await _client
          .from('customers')
          .select()
          .ilike('company_name', companyName)
          .ilike('customer_name', ledgerName)
          .limit(5);
      return (response as List).map((e) => Ledger.fromJson(e)).toList();
    } catch (e) {
      return [];
    }
  }

  Future<List<LedgerBillSettlement>> getBillSettlementsForLedger(String companyName, String ledgerName) async {
    final data = await _fetchAll(
      'ledger_bill_settlements',
      companyName: companyName,
      orderColumn: 'cleared_date',
      ascending: false,
    );
    
    return data
        .map((json) => LedgerBillSettlement.fromJson(json))
        .where((s) => s.ledgerName.toLowerCase() == ledgerName.toLowerCase())
        .toList();
  }

  static double _toDouble(dynamic val) {
    if (val == null) return 0;
    if (val is double) return val;
    if (val is int) return val.toDouble();
    return double.tryParse(val.toString()) ?? 0;
  }
}

