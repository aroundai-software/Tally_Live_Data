import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tallylive/providers/company_provider.dart';
import 'package:tallylive/screens/admin_panel_screen.dart';

class _AdminFixtureClient extends http.BaseClient {
  final requests = <http.BaseRequest>[];
  late http.Response Function(http.BaseRequest) handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    final r = handler(request);
    return http.StreamedResponse(
      Stream.value(r.bodyBytes),
      r.statusCode,
      headers: {...r.headers, 'content-type': 'application/json'},
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
  final client = _AdminFixtureClient();

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

  setUp(() {
    client.requests.clear();
    client.handler = (_) => _json([]);
  });

  Future<void> signInAsActiveSuperAdmin() async {
    final token = _jwt('admin-user');
    client.handler = (r) {
      final path = r.url.path;
      if (path.contains('/auth/')) {
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
      if (path.endsWith('/users') && r.method == 'GET') {
        // Profile lookup (maybeSingle) and user list both hit users.
        if (r.url.queryParameters['id']?.startsWith('eq.') == true ||
            r.url.queryParameters.containsKey('id')) {
          return _json({
            'id': 'admin-user',
            'full_name': 'Root Admin',
            'phone_number': '9999999999',
            'role': 'super_admin',
            'is_active': true,
            'company_name': 'Admin Co',
          });
        }
        return _json([
          {
            'id': 'admin-user',
            'full_name': 'Root Admin',
            'phone_number': '9999999999',
            'role': 'super_admin',
            'is_active': true,
            'company_name': 'Admin Co',
          },
          {
            'id': 'u2',
            'full_name': 'Shop User',
            'phone_number': '8888888888',
            'role': 'owner',
            'is_active': true,
            'company_name': 'Demo Co',
          },
        ]);
      }
      if (path.endsWith('company_features') || path.endsWith('tally_companies')) {
        return _json([
          {
            'company_name': 'Demo Co',
            'guid': 'g1',
            'is_active': true,
            'features': {'stock': true, 'outstanding': true},
          },
          {
            'company_name': 'Idle Co',
            'guid': 'g2',
            'is_active': false,
            'features': {'stock': false},
          },
        ]);
      }
      if (path.contains('script_control') ||
          path.contains('machine') ||
          path.endsWith('sync_machines')) {
        return _json([
          {
            'id': 'm1',
            'machine_name': 'DESKTOP-TEST',
            'is_active': true,
            'can_run': true,
          },
        ]);
      }
      if (path.contains('user_companies')) {
        return _json([
          {'user_id': 'u2', 'company_name': 'Demo Co'},
        ]);
      }
      return _json([]);
    };

    await Supabase.instance.client.auth.signInWithPassword(
      email: 'admin@tallylive.com',
      password: 'fixture-only',
    );
  }

  testWidgets('active super admin can open admin shell and switch tabs',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await signInAsActiveSuperAdmin();
    final state = CompanyState();
    await tester.pumpWidget(
      CompanyProvider(
        state: state,
        child: const MaterialApp(
          home: AdminPanelScreen(isRootAdmin: true),
        ),
      ),
    );
    // Post-frame access check + async loads (avoid pumpAndSettle — shimmer/tickers).
    await tester.pump();
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.text('Companies'), findsWidgets);
    expect(find.textContaining('Demo Co'), findsWidgets);

    await tester.tap(find.text('Users').first);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.textContaining('Shop User'), findsWidgets);

    await tester.tap(find.text('Subscriptions').first);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    await tester.tap(find.text('Settings').first);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    await tester.runAsync(
      () => Supabase.instance.client.auth.signOut(scope: SignOutScope.local),
    );
  });

  testWidgets('guest cannot see admin companies content', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.runAsync(
      () => Supabase.instance.client.auth.signOut(scope: SignOutScope.local),
    );
    client.handler = (_) => _json([]);

    await tester.pumpWidget(
      CompanyProvider(
        state: CompanyState(),
        child: const MaterialApp(home: AdminPanelScreen(isRootAdmin: true)),
      ),
    );
    await tester.pump();
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(
      client.requests.where((r) => r.url.path.contains('/rest/')),
      isEmpty,
    );
    expect(find.textContaining('Demo Co'), findsNothing);
  });
}
