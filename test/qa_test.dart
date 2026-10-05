import 'dart:async';
import 'package:tallylive/screens/reports_screen.dart';
import 'package:tallylive/models/purchase_invoice.dart';
import 'package:tallylive/screens/admin_panel_screen.dart';
import 'package:tallylive/screens/profile_screen.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:tallylive/screens/receivables_payables_screen.dart';
import 'package:tallylive/screens/ledger_statement_screen.dart';
import 'package:tallylive/models/ledger.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tallylive/services/supabase_service.dart';
import 'package:tallylive/models/stock_item.dart';
import 'package:tallylive/models/sales_invoice.dart';
import 'package:tallylive/providers/company_provider.dart';
import 'package:tallylive/screens/stock_screen.dart';

class FixtureClient extends http.BaseClient {
  final requests = <http.BaseRequest>[];
  bool handlerPaginates = false;
  Future<void> Function(http.BaseRequest)? beforeResponse;
  late http.Response Function(http.BaseRequest) handler;
  @override Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    await beforeResponse?.call(request);
    var r = handler(request);
    if (!handlerPaginates && r.statusCode == 200 && request.url.queryParameters.containsKey('offset')) {
      final body = jsonDecode(r.body);
      if (body is List) {
        final offset = int.parse(request.url.queryParameters['offset']!);
        final limit = int.parse(request.url.queryParameters['limit'] ?? '1000');
        r = jsonResponse(body.skip(offset).take(limit).toList());
      }
    }
    return http.StreamedResponse(Stream.value(r.bodyBytes), r.statusCode, headers:{...r.headers, if ((request.headers['Prefer'] ?? request.headers['prefer'] ?? '').contains('count=exact')) 'content-range':'*/0'},request:request);
  }
}
http.Response jsonResponse(Object value) => http.Response(jsonEncode(value),200,headers:{'content-type':'application/json'});
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final client=FixtureClient();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(url:'https://fixture.invalid',anonKey:'fixture-public-key',
      httpClient:client,authOptions:const FlutterAuthClientOptions(autoRefreshToken:false,detectSessionInUri:false));
  });
  tearDownAll(() async { await Supabase.instance.dispose(); });
  setUp(() { client.requests.clear(); client.handlerPaginates=false; client.beforeResponse=null; client.handler=(_)=>jsonResponse([]); });
  test('stock model preserves fractional quantity and value', () {
    final item=StockItem.fromJson({'ItemName':'Cable','ItemQuantity':2.75,'ItemRate':100});
    expect(item.quantity,2.75,reason:'2.75 metres must remain 2.75');
    expect(item.stockValue,275);
  });
  test('invoice model preserves fractional quantity', () {
    final item=InvoiceItem.fromJson({'product_name':'Cable','quantity':2.75});
    expect(item.quantity,2.75);
  });
  test('stock model handles integer quantities correctly', () {
    final item=StockItem.fromJson({'ItemName':'Box','ItemQuantity':3,'ItemRate':100});
    expect(item.quantity,3); expect(item.stockValue,300);
  });
  test('totals include more than 5000 rows', () async {
    client.handlerPaginates = true;
    client.handler=(r) {
      final limit=int.parse(r.url.queryParameters['limit']??'1000');
      final offset=int.parse(r.url.queryParameters['offset']??'0');
      final left=6001-offset;
      return jsonResponse(List.generate(left<limit?left:limit,(_)=>{'total_amount':1}));
    };
    expect(await SupabaseService().getTotalSales(companyName:'Fixture'),6001);
  });
  test('invoice with matching business guid remains pending', () async {
    client.handler=(r)=>r.url.path.endsWith('outstanding_receivables')
      ?jsonResponse([{'guid':'voucher-001'}])
      :jsonResponse([{'id':'row-uuid-001','guid':'voucher-001','invoice_number':'INV-1','status':'Pending'}]);
    final rows=await SupabaseService().getSalesInvoices(companyName:'Fixture');
    expect(rows.single.status,'Pending');
  });
  test('today filter covers entire day not only midnight', () async {
    await SupabaseService().getTodaysSales(companyName:'Fixture');
    final values=client.requests.single.url.queryParametersAll['invoice_date']!;
    final lower=values.firstWhere((s)=>s.startsWith('gte.')).substring(4);
    final upper=values.firstWhere((s)=>s.startsWith('lte.')||s.startsWith('lt.'));
    final parsedUpper=upper.substring(upper.indexOf('.')+1);
    expect(parsedUpper,isNot(lower),reason:'start and end must span a day');
  });
  test('network failure must not report a real zero balance', () async {
    client.handler=(_)=>http.Response('{"message":"fixture forbidden","code":"42501"}',403,headers:{'content-type':'application/json'});
    await expectLater(SupabaseService().getTotalSales(companyName:'Fixture'),throwsA(anything));
  });
  test('credit invoice is not counted as received cash', () async {
    client.handler=(_)=>jsonResponse([{'date':'2026-09-29','voucher_type':'Sales','amount':1000,'is_debit':true}]);
    final summary=await SupabaseService().getDaybookSummary(companyName:'Fixture');
    expect(summary['inflow'],0,reason:'Credit sale is not a cash receipt');
  });
  test('ledger statement reads beyond first 1000 entries', () async {
    client.handler=(r) {
      return jsonResponse(List.generate(1200,(i)=>{'voucher_number':'V$i','amount':1,'is_debit':true}));
    };
    expect((await SupabaseService().getLedgerVouchers(companyName:'Fixture',ledgerName:'Customer')).length,1200);
  });
  testWidgets('cost-disabled stock screen must not show stock value', (tester) async {
    tester.view.physicalSize=const Size(390,844); tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    client.handler=(r)=>r.url.path.endsWith('stock_items')
      ?jsonResponse([{'id':'stock-1','ItemName':'Confidential widget','ItemQuantity':2,'ItemRate':321,'is_active':true}])
      :jsonResponse([]);
    final state=CompanyState()..selectCompany('Fixture')..setFeatures({'stock_cost':false});
    await tester.pumpWidget(CompanyProvider(state:state,child:const MaterialApp(home:StockScreen())));
    await tester.pumpAndSettle();
    expect(find.text('Confidential widget'),findsOneWidget);
    final leaked=find.byWidgetPredicate((w)=>w is Text && (w.data??'').contains('642'));
    expect(leaked,findsNothing,reason:'Hidden rate remains derivable from displayed stock value and quantity');
  });

  testWidgets('payables-only screen must use payables summary', (tester) async {
    tester.view.physicalSize=const Size(390,844);tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    client.handler=(r)=>jsonResponse(r.url.path.endsWith('outstanding_receivables')
      ?[{'id':'r','customer_name':'Restricted customer','closing_balance':999,'amount':999,'overdue_days':0}]
      :r.url.path.endsWith('outstanding_payables')
      ?[{'id':'p','customer_name':'Allowed supplier','closing_balance':123,'amount':123,'overdue_days':0}]:[]);
    final state=CompanyState()..selectCompany('Fixture')..setFeatures({'out_receivables':false,'out_payables':true});
    await tester.pumpWidget(CompanyProvider(state:state,child:const MaterialApp(home:ReceivablesPayablesScreen())));
    await tester.pumpAndSettle();
    expect(find.text('Receivables'),findsNothing,reason:'Disabled receivable summary must not appear under Payables');
  });
  testWidgets('disabled transaction tab must also disable transaction exports', (tester) async {
    SharedPreferences.setMockInitialValues({});
    client.handler=(r)=>jsonResponse(r.url.path.endsWith('tally_daybook')
      ?[{'date':'2026-09-29','voucher_number':'SECRET-1','ledger_name':'Fixture Customer','voucher_type':'Sales','amount':900,'is_debit':true}]:[]);
    final state=CompanyState()..selectCompany('Fixture')..setFeatures({'ls_transactions':false,'ls_performance':true});
    await tester.pumpWidget(CompanyProvider(state:state,child:MaterialApp(home:LedgerStatementScreen(ledger:Ledger.fromJson({'customer_name':'Fixture Customer'})))));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('More Options'));await tester.pumpAndSettle();
    expect(find.text('Share via...'),findsNothing,reason:'Transaction data must not be exported from performance-only view');
  });


  testWidgets('profile handles a legitimate name with repeated spaces', (tester) async {
    PackageInfo.setMockInitialValues(appName:'TallyLive',packageName:'fixture',version:'1.0',buildNumber:'1',buildSignature:'');
    String segment(Object x)=>base64Url.encode(utf8.encode(jsonEncode(x))).replaceAll('=','');
    final token="${segment({'alg':'none','typ':'JWT'})}.${segment({'sub':'fixture-user','role':'authenticated','exp':DateTime.now().millisecondsSinceEpoch~/1000+3600})}.fixture";
    client.handler=(r) {
      if(r.url.path.contains('/auth/')) return jsonResponse({'access_token':token,'token_type':'bearer','expires_in':3600,'refresh_token':'fixture-refresh','user':{'id':'fixture-user','aud':'authenticated','role':'authenticated','email':'fixture@example.invalid','created_at':'2026-09-29T00:00:00Z','app_metadata':{},'user_metadata':{}}});
      if(r.url.path.endsWith('/users')) return jsonResponse({'id':'fixture-user','full_name':'John  Doe','phone_number':'0000000000','role':'owner','company_name':'Fixture'});
      return jsonResponse([]);
    };
    await Supabase.instance.client.auth.signInWithPassword(email:'fixture@example.invalid',password:'fixture-only');
    final state=CompanyState()..selectCompany('Fixture');
    await tester.pumpWidget(CompanyProvider(state:state,child:const MaterialApp(home:ProfileScreen())));
    await tester.pumpAndSettle();
    expect(tester.takeException(),isNull,reason:'Repeated spaces are accepted by the name form');
    await tester.runAsync(() => Supabase.instance.client.auth.signOut(scope:SignOutScope.local));
  });


  test('small sales total sums correctly', () async {
    client.handler=(_)=>jsonResponse([{'total_amount':10},{'total_amount':20}]);
    expect(await SupabaseService().getTotalSales(companyName:'Fixture'),30);
  });
  test('matching row id and outstanding guid keeps pending status', () async {
    client.handler=(r)=>r.url.path.endsWith('outstanding_receivables')
      ?jsonResponse([{'guid':'shared-id'}])
      :jsonResponse([{'id':'shared-id','guid':'shared-id','invoice_number':'INV-1'}]);
    expect((await SupabaseService().getSalesInvoices(companyName:'Fixture')).single.status,'Pending');
  });
  test('small ledger reads all returned entries', () async {
    client.handler=(_)=>jsonResponse([{'voucher_number':'V1','amount':1,'is_debit':true},{'voucher_number':'V2','amount':2,'is_debit':true}]);
    expect((await SupabaseService().getLedgerVouchers(companyName:'Fixture',ledgerName:'Customer')).length,2);
  });


  test('purchase quantity strings and free quantities preserve decimals', () {
    final item = PurchaseInvoiceItem.fromJson({'quantity': '2.75', 'free_quantity': '0.25'});
    expect(item.quantity, 2.75);
    expect(item.freeQuantity, 0.25);
  });
  test('pagination respects smaller server page caps and exact company names', () async {
    client.handlerPaginates = true;
    client.handler = (r) {
      expect(r.url.queryParameters['company_name'], 'eq.A_100%');
      expect(r.url.queryParameters['order'], startsWith('id.asc'));
      final offset = int.parse(r.url.queryParameters['offset'] ?? '0');
      final remaining = 601 - offset;
      return jsonResponse(List.generate(remaining > 250 ? 250 : remaining, (_) => {'total_amount': 1}));
    };
    expect(await SupabaseService().getTotalSales(companyName: 'A_100%'), 601);
  });
  test('later page failure never produces partial totals', () async {
    client.handlerPaginates = true;
    client.handler = (r) => r.url.queryParameters['offset'] == '0'
      ? jsonResponse([{'total_amount': 10}])
      : http.Response('{"message":"offline","code":"08006"}', 503, headers: {'content-type':'application/json'});
    await expectLater(SupabaseService().getTotalSales(companyName: 'Fixture'), throwsA(anything));
  });
  test('missing outstanding record preserves paid and cancelled source statuses', () async {
    client.handler = (r) => jsonResponse(r.url.path.endsWith('outstanding_receivables') ? [] : [
      {'id':'1','guid':'v1','status':'Paid'}, {'id':'2','guid':'v2','status':'Cancelled'}]);
    final rows = await SupabaseService().getSalesInvoices(companyName:'Fixture');
    expect(rows.map((r) => r.status), ['Paid', 'Cancelled']);
  });
  test('purchase business guid remains pending', () async {
    client.handler = (r) => jsonResponse(r.url.path.endsWith('outstanding_payables')
      ? [{'guid':'p1'}] : [{'id':'row1','guid':'p1','status':'Paid'}]);
    expect((await SupabaseService().getPurchaseInvoices(companyName:'Fixture')).single.status, 'Pending');
  });
  test('today purchase count uses a half-open next-day boundary', () async {
    await SupabaseService().getTodaysPurchasesCount(companyName:'Fixture');
    final values = client.requests.single.url.queryParametersAll['invoice_date']!;
    final start = DateTime.parse(values.firstWhere((v) => v.startsWith('gte.')).substring(4));
    final end = DateTime.parse(values.firstWhere((v) => v.startsWith('lt.')).substring(3));
    expect(end.difference(start), const Duration(days: 1));
  });
  test('receipt and payment summary retains legitimate cash direction', () async {
    client.handler = (_) => jsonResponse([
      {'voucher_type':'Receipt','amount':150}, {'voucher_type':'Payment','amount':50},
      {'voucher_type':'Purchase','amount':300}, {'voucher_type':'Journal','amount':900}]);
    expect(await SupabaseService().getDaybookSummary(companyName:'Fixture'), {'inflow':150.0,'outflow':50.0});
  });
  test('disabled master and hidden cost block dependent dashboard features', () {
    final state = CompanyState()..setFeatures({'stock_cost':false, 'outstanding':false, 'ledgers':false});
    for (final feature in ['db_np_stock','db_card_stock_value','out_receivables','out_payables','ls_transactions','ls_performance']) {
      expect(state.isFeatureEnabled(feature), false, reason:feature);
    }
    expect(state.isFeatureEnabled('sales'), true);
  });
  testWidgets('receivable/payable permission swap clears data and fetches only permitted type', (tester) async {
    client.handler = (r) => jsonResponse(r.url.path.endsWith('outstanding_payables')
      ? [{'id':'p','customer_name':'Supplier','closing_balance':123}] : []);
    final state = CompanyState()..selectCompany('Fixture')..setFeatures({'out_receivables':false,'out_payables':true});
    await tester.pumpWidget(CompanyProvider(state:state, child:const MaterialApp(home:ReceivablesPayablesScreen())));
    await tester.pumpAndSettle();
    expect(client.requests.where((r) => r.url.path.endsWith('outstanding_receivables')), isEmpty);
    client.requests.clear();
    state.setFeatures({'out_receivables':true,'out_payables':false});
    await tester.pumpAndSettle();
    expect(client.requests.where((r) => r.url.path.endsWith('outstanding_payables')), isEmpty);
    expect(find.text('Payables'), findsNothing);
    expect(find.text('Supplier'), findsNothing);
  });
  testWidgets('disabled ledger transactions never fetch daybook and revocation clears rows', (tester) async {
    client.handler = (r) => jsonResponse(r.url.path.endsWith('tally_daybook') ? [
      {'id':'d1','voucher_number':'SECRET-1','date':'2026-09-29','voucher_type':'Sales','amount':900,'is_debit':true}] : []);
    final state = CompanyState()..selectCompany('Fixture')..setFeatures({'ls_transactions':false,'ls_performance':false});
    final ledger = Ledger.fromJson({'customer_name':'Fixture Customer'});
    await tester.pumpWidget(CompanyProvider(state:state, child:MaterialApp(home:LedgerStatementScreen(ledger:ledger))));
    await tester.pumpAndSettle();
    expect(client.requests.where((r) => r.url.path.endsWith('tally_daybook')), isEmpty);
    state.setFeatures({'ls_transactions':true,'ls_performance':false});
    await tester.pumpAndSettle();
    expect(client.requests.where((r) => r.url.path.endsWith('tally_daybook')), isNotEmpty);
    state.setFeatures({'ls_transactions':false,'ls_performance':false});
    await tester.pumpAndSettle();
    expect(find.text('SECRET-1'), findsNothing);
  });
  testWidgets('anonymous admin route does not fetch privileged tables', (tester) async {
    tester.view.physicalSize = const Size(390, 844); tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
    final state = CompanyState();
    await tester.pumpWidget(CompanyProvider(state:state, child:const MaterialApp(home:AdminPanelScreen(isRootAdmin:true))));
    await tester.pumpAndSettle();
    expect(find.text('Companies'), findsNothing);
    expect(client.requests.where((r) => r.url.path.contains('/rest/')), isEmpty);
  });


  testWidgets('cost-disabled Analytics hides cost reports and dormant item values', (tester) async {
    client.handler = (r) {
      if (r.url.path.endsWith('get_unused_items')) return jsonResponse([{'product_name':'Hidden cost item','quantity':2,'stock_value':642}]);
      if (r.url.path.endsWith('_count')) return jsonResponse(0);
      return jsonResponse([]);
    };
    final state = CompanyState()..selectCompany('Fixture')..setFeatures({'stock_cost':false});
    await tester.pumpWidget(CompanyProvider(state:state, child:const MaterialApp(home:ReportsScreen())));
    await tester.pumpAndSettle();
    expect(client.requests.where((r) => r.url.path.endsWith('get_daily_profit') || r.url.path.endsWith('get_high_value_items')), isEmpty);
    expect(find.text('High Value'), findsNothing);
    await tester.tap(find.text('Dormant')); await tester.pumpAndSettle();
    await tester.tap(find.text('Unused Items')); await tester.pumpAndSettle();
    expect(find.text('Hidden cost item'), findsOneWidget);
    expect(find.byWidgetPredicate((w) => w is Text && (w.data ?? '').contains('642')), findsNothing);
  });
  testWidgets('permission change during outstanding request finishes current loading', (tester) async {
    final pending = Completer<void>();
    client.beforeResponse = (r) async {
      if (r.url.path.endsWith('outstanding_receivables')) await pending.future;
    };
    client.handler = (r) => jsonResponse(r.url.path.endsWith('outstanding_payables')
      ? [{'id':'p','customer_name':'Current supplier','closing_balance':123}] : []);
    final state = CompanyState()..selectCompany('Fixture')..setFeatures({'out_receivables':true,'out_payables':false});
    await tester.pumpWidget(CompanyProvider(state:state, child:const MaterialApp(home:ReceivablesPayablesScreen())));
    await tester.pump(); await tester.pump(const Duration(milliseconds:100));
    expect(client.requests.where((r) => r.url.path.endsWith('outstanding_receivables')), isNotEmpty);
    state.setFeatures({'out_receivables':false,'out_payables':true});
    await tester.pumpAndSettle();
    expect(find.text('Current supplier'), findsWidgets);
    pending.complete(); await tester.pumpAndSettle();
    expect(find.text('Current supplier'), findsWidgets);
    expect(find.text('Receivables'), findsNothing);
  });


  testWidgets('failed stock master save restores every dependent setting', (tester) async {
    client.handler = (_) => http.Response('{"message":"denied","code":"42501"}',403,headers:{'content-type':'application/json'});
    final original = {'stock':true,'stock_cost':false,'db_card_stock_value':true,'db_np_stock':true,'db_qa_stock':true};
    Map<String,bool>? result;
    await tester.pumpWidget(MaterialApp(home:Builder(builder:(context) => Scaffold(body:TextButton(
      child:const Text('Open settings'), onPressed:() async {
        result = await Navigator.of(context).push<Map<String,bool>>(MaterialPageRoute(builder:(_) => StockFeaturesScreen(companyName:'Fixture',initialFeatures:original)));
      })) )));
    await tester.tap(find.text('Open settings')); await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch).first); await tester.pumpAndSettle();
    expect(find.textContaining('Failed to update setting'), findsOneWidget);
    expect(tester.widget<Switch>(find.byType(Switch).first).value, true);
    await tester.tap(find.byIcon(Icons.arrow_back_rounded)); await tester.pumpAndSettle();
    expect(result, original);
  });


  testWidgets('inactive restored administrator cannot load admin data', (tester) async {
    tester.view.physicalSize = const Size(390,844); tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
    String segment(Object value) => base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=','');
    final token = "${segment({'alg':'none','typ':'JWT'})}.${segment({'sub':'inactive-admin','role':'authenticated','exp':DateTime.now().millisecondsSinceEpoch~/1000+3600})}.fixture";
    client.handler = (r) {
      if (r.url.path.contains('/auth/')) return jsonResponse({'access_token':token,'token_type':'bearer','expires_in':3600,'refresh_token':'fixture-refresh','user':{'id':'inactive-admin','aud':'authenticated','role':'authenticated','email':'admin@tallylive.com','created_at':'2026-09-29T00:00:00Z','app_metadata':{},'user_metadata':{}}});
      if (r.url.path.endsWith('/users')) return jsonResponse({'id':'inactive-admin','role':'super_admin','is_active':false});
      return jsonResponse([]);
    };
    await tester.runAsync(() => Supabase.instance.client.auth.signInWithPassword(email:'admin@tallylive.com',password:'fixture-only'));
    final state = CompanyState();
    await tester.pumpWidget(CompanyProvider(state:state, child:const MaterialApp(home:AdminPanelScreen(isRootAdmin:true))));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds:50)));
    await tester.pumpAndSettle();
    expect(Supabase.instance.client.auth.currentUser,isNull);
    expect(client.requests.where((r) => r.url.path.endsWith('company_features') || r.url.path.endsWith('tally_companies')),isEmpty);
    expect(find.text('Companies'),findsNothing);
  });


  test('company switches cannot reuse old access settings', () {
    final state = CompanyState()..selectCompany('A');
    expect(state.isFeatureEnabled('stock_cost'),false);
    state.setFeatures({'stock_cost':true});
    expect(state.isFeatureEnabled('stock_cost'),true);
    state.selectCompany('B');
    expect(state.featuresLoaded,false);
    expect(state.isFeatureEnabled('stock_cost'),false);
  });
  test('failed permission lookup never grants all features', () async {
    client.handler = (_) => http.Response('{"message":"denied","code":"42501"}',403,headers:{'content-type':'application/json'});
    final features = await SupabaseService().getCompanyFeatures('Fixture');
    expect(features,isNotEmpty);
    expect(features.values.any((v) => v),false);
  });

}
