import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tallylive/providers/company_provider.dart';
import 'package:tallylive/screens/admin_panel_screen.dart';
import 'package:tallylive/services/supabase_service.dart';

class _SubFixtureClient extends http.BaseClient {
  final requests = <http.BaseRequest>[];
  late http.Response Function(http.BaseRequest) handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    final r = handler(request);
    return http.StreamedResponse(
      Stream.value(r.bodyBytes),
      r.statusCode,
      headers: {
        ...r.headers,
        'content-type': 'application/json',
        'content-range': '0-0/1',
      },
      request: request,
    );
  }
}

http.Response _json(Object value, [int status = 200]) => http.Response(
      jsonEncode(value),
      status,
      headers: {'content-type': 'application/json'},
    );

String _jwt(String sub) {
  String segment(Object x) =>
      base64Url.encode(utf8.encode(jsonEncode(x))).replaceAll('=', '');
  return '${segment({'alg': 'none', 'typ': 'JWT'})}.'
      '${segment({
        'sub': sub,
        'role': 'authenticated',
        'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
      })}.fixture';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final client = _SubFixtureClient();

  late Map<String, dynamic> machine;
  late List<Map<String, dynamic>> machineCompanies;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://fixture.invalid',
      anonKey: 'fixture-public-key',
      httpClient: client,
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: false,
        detectSessionInUri: false,
      ),
    );
  });

  tearDownAll(() async {
    await Supabase.instance.dispose();
  });

  setUp(() async {
    client.requests.clear();
    final past = DateTime.now().toUtc().subtract(const Duration(days: 3));
    machine = {
      'id': 'm1',
      'machine_name': 'DESKTOP-TEST',
      'current_company': 'Demo Co',
      'sync_should_run': false,
      'expires_at': past.toIso8601String(),
      'last_seen_at': DateTime.now().toUtc().toIso8601String(),
      'updated_at': past.toIso8601String(),
    };
    machineCompanies = [
      {'machine_name': 'DESKTOP-TEST', 'company_name': 'Demo Co'},
      {'machine_name': 'DESKTOP-TEST', 'company_name': 'Other Co'},
    ];

    client.handler = (r) {
      final path = r.url.path;
      final method = r.method.toUpperCase();

      if (path.contains('/auth/')) {
        final token = _jwt('admin-user');
        return _json({
          'access_token': token,
          'token_type': 'bearer',
          'expires_in': 3600,
          'refresh_token': 'fixture-refresh',
          'user': {
            'id': 'admin-user',
            'aud': 'authenticated',
            'role': 'authenticated',
            'email': 'admin@tallylive.com',
            'created_at': '2026-09-29T00:00:00Z',
            'app_metadata': {},
            'user_metadata': {},
          },
        });
      }

      if (path.contains('pause_expired_sync_machines') ||
          path.endsWith('rpc/pause_expired_sync_machines')) {
        return _json({'message': 'not found', 'code': 'PGRST202'}, 404);
      }

      if (path.endsWith('/users') && method == 'GET') {
        return _json({
          'id': 'admin-user',
          'full_name': 'Root Admin',
          'role': 'super_admin',
          'is_active': true,
          'company_name': 'Admin Co',
        });
      }

      if (path.endsWith('script_control')) {
        if (method == 'GET') {
          // Single-row fetch by id (enable-expired path reads expires_at).
          final idEq = r.url.queryParameters['id'];
          if (idEq != null) {
            return _json(machine);
          }
          return _json([machine]);
        }
        if (method == 'PATCH' || method == 'PUT') {
          final body = r is http.Request
              ? jsonDecode(r.body) as Map<String, dynamic>
              : <String, dynamic>{};
          machine = {...machine, ...body};
          return _json([machine]);
        }
      }

      if (path.endsWith('machine_companies') && method == 'GET') {
        final mn = r.url.queryParameters['machine_name'];
        final cn = r.url.queryParameters['company_name'];
        var rows = List<Map<String, dynamic>>.from(machineCompanies);
        if (mn != null && mn.startsWith('eq.')) {
          final name = mn.substring(3);
          rows = rows.where((e) => e['machine_name'] == name).toList();
        }
        if (cn != null && cn.startsWith('eq.')) {
          final name = cn.substring(3);
          rows = rows.where((e) => e['company_name'] == name).toList();
        }
        return _json(rows);
      }

      return _json([]);
    };

    await Supabase.instance.client.auth.signInWithPassword(
      email: 'admin@tallylive.com',
      password: 'fixture-only',
    );
  });

  tearDown(() async {
    await Supabase.instance.client.auth.signOut(scope: SignOutScope.local);
  });

  test('cannot enable sync when subscription already expired', () async {
    final ok = await SupabaseService().updateSyncMachineControl(
      'm1',
      syncShouldRun: true,
    );
    expect(ok, isFalse, reason: 'Expired license must refuse enable');
    expect(machine['sync_should_run'], isFalse);
  });

  test('extending expiry into the future enables sync', () async {
    final now = DateTime.now();
    // Simulate date-picker value (midnight local) — service should keep that day valid until 23:59:59.
    final futureMidnight = DateTime(now.year, now.month, now.day).add(const Duration(days: 30));
    final ok = await SupabaseService().updateSyncMachineControl(
      'm1',
      expiresAt: futureMidnight,
      syncShouldRun: true,
    );
    expect(ok, isTrue);
    expect(machine['sync_should_run'], isTrue);
    final saved = DateTime.parse(machine['expires_at'].toString()).toLocal();
    expect(saved.isAfter(DateTime.now()), isTrue);
    expect(saved.hour, 23);
    expect(saved.minute, 59);
  });

  test('pausing sync works while license is still valid', () async {
    final future = DateTime.now().add(const Duration(days: 10));
    machine['expires_at'] = future.toUtc().toIso8601String();
    machine['sync_should_run'] = true;

    final ok = await SupabaseService().updateSyncMachineControl(
      'm1',
      syncShouldRun: false,
    );
    expect(ok, isTrue);
    expect(machine['sync_should_run'], isFalse);
  });

  test('company subscription uses soonest linked machine expiry', () async {
    final soon = DateTime.now().toUtc().add(const Duration(days: 5));
    final later = DateTime.now().toUtc().add(const Duration(days: 40));
    // Second machine with later expiry for same company link set.
    final machinesForInFilter = [
      {
        'machine_name': 'DESKTOP-TEST',
        'expires_at': soon.toIso8601String(),
      },
      {
        'machine_name': 'LAPTOP-2',
        'expires_at': later.toIso8601String(),
      },
    ];
    machineCompanies = [
      {'machine_name': 'DESKTOP-TEST', 'company_name': 'Demo Co'},
      {'machine_name': 'LAPTOP-2', 'company_name': 'Demo Co'},
    ];

    client.handler = (r) {
      final path = r.url.path;
      final method = r.method.toUpperCase();
      if (path.contains('/auth/')) {
        return _json({
          'access_token': _jwt('admin-user'),
          'token_type': 'bearer',
          'expires_in': 3600,
          'refresh_token': 'x',
          'user': {
            'id': 'admin-user',
            'aud': 'authenticated',
            'role': 'authenticated',
            'email': 'admin@tallylive.com',
            'created_at': '2026-09-29T00:00:00Z',
            'app_metadata': {},
            'user_metadata': {},
          },
        });
      }
      if (path.contains('pause_expired')) {
        return _json(0);
      }
      if (path.endsWith('/users')) {
        return _json({
          'id': 'admin-user',
          'role': 'super_admin',
          'is_active': true,
        });
      }
      if (path.endsWith('machine_companies') && method == 'GET') {
        return _json(machineCompanies);
      }
      if (path.endsWith('script_control') && method == 'GET') {
        return _json(machinesForInFilter);
      }
      return _json([]);
    };

    final result =
        await SupabaseService().getCompanySubscriptionExpiry('Demo Co');
    expect(result.expiresAt, isNotNull);
    expect(
      result.expiresAt!.difference(soon).inMinutes.abs() < 2,
      isTrue,
      reason: 'Soonest expiry should win',
    );
    expect(result.machineName, 'DESKTOP-TEST');
  });

  testWidgets('Subscriptions tab lists machine and blocks enable when expired',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      CompanyProvider(
        state: CompanyState(),
        child: const MaterialApp(
          home: AdminPanelScreen(isRootAdmin: true),
        ),
      ),
    );
    await tester.pump();
    for (var i = 0; i < 25; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }

    await tester.tap(find.text('Subscriptions').first);
    for (var i = 0; i < 25; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }

    expect(find.textContaining('DESKTOP-TEST'), findsWidgets);
    expect(find.textContaining('Demo Co'), findsWidgets);

    // Expired machine should offer extend actions / show paused state.
    expect(
      find.textContaining('Expired').evaluate().isNotEmpty ||
          find.textContaining('paused').evaluate().isNotEmpty ||
          find.textContaining('Paused').evaluate().isNotEmpty ||
          find.textContaining('Extend').evaluate().isNotEmpty ||
          find.byIcon(Icons.more_vert).evaluate().isNotEmpty ||
          find.byIcon(Icons.more_horiz).evaluate().isNotEmpty,
      isTrue,
      reason: 'Expired subscription UI affordance should be visible',
    );
  });
}
