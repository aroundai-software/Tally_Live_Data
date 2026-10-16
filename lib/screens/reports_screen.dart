import 'dart:async';

import '../widgets/error_state_widget.dart';
import 'package:flutter/material.dart';
import '../utils/error_handler.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../providers/company_provider.dart';
import '../utils/company_scope.dart';
import '../services/supabase_service.dart';
import '../widgets/shimmer_loading.dart';
import '../widgets/summary_card.dart';
import '../config/app_theme.dart';

// ---------------------------------------------------------------------------
// Design tokens — adaptive for light / dark via AppTheme.bindBrightness
// ---------------------------------------------------------------------------
class _Palette {
  static const blue = Color(0xFF2453FF);
  static const teal = Color(0xFF0DA6A0);
  static const amber = Color(0xFFB96A00);
  static const red = Color(0xFFC2372A);

  static Color get ink900 => AppTheme.textPrimary;
  static Color get ink700 =>
      AppTheme.isDark ? const Color(0xFFCBD5E1) : const Color(0xFF3A4A63);
  static Color get ink500 => AppTheme.textSecondary;
  static Color get line => AppTheme.dividerColor;
  static Color get paper => AppTheme.surfaceColor;

  static Color get blueSoft =>
      AppTheme.isDark ? blue.withValues(alpha: 0.18) : const Color(0xFFE9EEFF);
  static Color get tealSoft =>
      AppTheme.isDark ? teal.withValues(alpha: 0.18) : const Color(0xFFE1F5F3);
  static Color get amberSoft =>
      AppTheme.isDark ? amber.withValues(alpha: 0.18) : const Color(0xFFFBEEDC);
  static Color get redSoft =>
      AppTheme.isDark ? red.withValues(alpha: 0.18) : const Color(0xFFFBEAE8);

  static Color get chartTooltipBg => AppTheme.isDark
      ? AppTheme.cardColor.withValues(alpha: 0.98)
      : const Color(0xFF1E293B).withValues(alpha: 0.95);

  static Color get chartTooltipLabel =>
      AppTheme.isDark ? AppTheme.textPrimary : Colors.white70;
}

// Cutoff options available for the "unused" filters.
const List<int> _kCutoffOptions = [30, 90, 180, 365];

class ReportsScreen extends StatefulWidget {
  final VoidCallback? onBack;
  const ReportsScreen({super.key, this.onBack});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> with TickerProviderStateMixin {
  late TabController _tabController;
  final SupabaseService _service = SupabaseService();
  bool _isLoading = true;
  String? _error;
  int _loadGeneration = 0;
  String? _permissionKey;
  List<String> _visibleTabLabels = const [];

  List<Map<String, dynamic>> _profitData = [];
  List<Map<String, dynamic>> _fastItems = [];
  List<Map<String, dynamic>> _slowItems = [];
  List<Map<String, dynamic>> _highValueItems = [];
  List<Map<String, dynamic>> _unusedLedgers = [];
  List<Map<String, dynamic>> _unusedItems = [];

  int _overviewDays = 7;
  int _totalUnusedLedgersCount = 0;
  int _totalUnusedItemsCount = 0;
  double _deadStockKpiValue = 0;
  bool _useLineChart = false;

  bool _velocityLoaded = false;
  bool _dormantLoaded = false;
  bool _overviewKpisLoaded = false;
  bool _velocityLoading = false;
  bool _dormantLoading = false;
  bool _overviewKpisLoading = false;

  // User-adjustable "no activity in X days" cutoffs — independent per section,
  // since a quiet customer and slow-moving equipment stock aren't the same
  // business question.
  int _ledgerCutoffDays = 180;
  int _itemCutoffDays = 180;
  int _velocityCutoffDays = 30;
  String _velocityFilter = 'fast';
  String _dormantFilter = 'ledgers';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_onTabChanged);
  }

  void _onTabChanged() {
    if (!mounted || _tabController.indexIsChanging) return;
    _ensureTabDataLoaded(_tabController.index);
  }

  void _ensureTabDataLoaded(int index) {
    if (index < 0 || index >= _visibleTabLabels.length) return;
    switch (_visibleTabLabels[index]) {
      case 'Overview':
        // Lightweight KPI RPC — not the full unused lists.
        _loadOverviewKpisIfNeeded();
        break;
      case 'Velocity':
        _loadVelocityIfNeeded();
        break;
      case 'Dormant':
        _loadDormantIfNeeded();
        break;
    }
  }

  void _rebuildTabController(int tabCount) {
    if (_tabController.length != tabCount) {
      _tabController.removeListener(_onTabChanged);
      _tabController.dispose();
      _tabController = TabController(length: tabCount, vsync: this);
      _tabController.addListener(_onTabChanged);
    }
  }

  bool _initialized = false;
  int? _lastSyncTrigger;
  int? _lastCompanyRevision;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = CompanyProvider.of(context);
    final permissionKey =
        '${state.scopeKey}:${state.isFeatureEnabled('stock_cost')}:${state.isFeatureEnabled('rep_sales')}:${state.isFeatureEnabled('rep_purchases')}:${state.isFeatureEnabled('rep_ledgers')}';
    final permissionsChanged = _permissionKey != permissionKey;
    _permissionKey = permissionKey;
    final syncTrigger = state.syncTrigger;
    final revision = state.companyRevision;
    if (!_initialized) {
      _initialized = true;
      _lastSyncTrigger = syncTrigger;
      _lastCompanyRevision = revision;
      _loadData();
    } else if (_lastCompanyRevision != revision || permissionsChanged || _lastSyncTrigger != syncTrigger) {
      final companyChanged = _lastCompanyRevision != revision;
      _lastCompanyRevision = revision;
      _lastSyncTrigger = syncTrigger;
      _loadData(silent: permissionsChanged || companyChanged);
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  bool _scopeStillActive(int generation, String scopeKey) {
    return mounted &&
        generation == _loadGeneration &&
        CompanyScope.stillActiveScope(
            scopeKey, CompanyProvider.of(context).scopeKey);
  }

  bool _hasValidScope(CompanyState state) {
    if (state.isCombinedMode) return CompanyScope.hasActiveScope(state);
    return CompanyScope.isValid(state.selectedCompany);
  }

  /// Entry / pull-to-refresh: Overview (+ dormant KPIs). Velocity loads on tab open.
  Future<void> _loadData({bool silent = false}) async {
    final generation = ++_loadGeneration;
    final state = CompanyProvider.of(context);
    final scopeKey = state.scopeKey;
    if (!_hasValidScope(state)) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = state.isCombinedMode
              ? 'No companies selected'
              : 'No company selected';
        });
      }
      return;
    }
    setState(() {
      _error = null;
      if (!silent) _isLoading = true;
      _velocityLoaded = false;
      _dormantLoaded = false;
      _overviewKpisLoaded = false;
      _velocityLoading = false;
      _dormantLoading = false;
      _overviewKpisLoading = false;
      _fastItems = [];
      _slowItems = [];
      _highValueItems = [];
      _unusedLedgers = [];
      _unusedItems = [];
      _totalUnusedLedgersCount = 0;
      _totalUnusedItemsCount = 0;
      _deadStockKpiValue = 0;
    });
    try {
      final costs = state.isFeatureEnabled('stock_cost');
      final sales = state.isFeatureEnabled('rep_sales') && costs;
      final isCombined = state.isCombinedMode;
      final company = state.selectedCompany;
      final companies = state.selectedCompanies;

      // Start dormant KPIs immediately (independent of profit).
      unawaited(_loadOverviewKpisIfNeeded(force: true));

      final profit = sales
          ? (isCombined
              ? await _service.getCombinedDailyProfit(
                  companyNames: companies, days: _overviewDays)
              : await _service.getDailyProfit(
                  companyName: company, days: _overviewDays))
          : <Map<String, dynamic>>[];
      if (!_scopeStillActive(generation, scopeKey)) return;

      setState(() {
        _profitData = profit;
        _useLineChart = _overviewDays > 30;
        _isLoading = false;
      });

      // Velocity / full dormant lists only if that tab is already active.
      _ensureTabDataLoaded(_tabController.index);
    } catch (e, st) {
      print('Error loading data: $e');
      print(st);
      if (_scopeStillActive(generation, scopeKey)) {
        setState(() {
          _isLoading = false;
          _overviewKpisLoading = false;
          _error = AppErrorHandler.getFriendlyError(e);
        });
      }
    }
  }

  Future<void> _loadVelocityIfNeeded({bool force = false}) async {
    if (_velocityLoading && !force) return;
    if (_velocityLoaded && !force) return;
    final state = CompanyProvider.of(context);
    // Velocity metrics are sales-based (not purchases).
    if (!state.isFeatureEnabled('rep_sales')) return;
    if (!_hasValidScope(state)) return;

    final generation = _loadGeneration;
    final scopeKey = state.scopeKey;
    final isCombined = state.isCombinedMode;
    final company = state.selectedCompany;
    final companies = state.selectedCompanies;
    final costs = state.isFeatureEnabled('stock_cost');

    setState(() => _velocityLoading = true);
    try {
      final results = await Future.wait([
        isCombined
            ? _service.getCombinedFastMovingItems(
                companyNames: companies, days: _velocityCutoffDays)
            : _service.getFastMovingItems(
                companyName: company, days: _velocityCutoffDays),
        isCombined
            ? _service.getCombinedSlowMovingItems(
                companyNames: companies, days: _velocityCutoffDays)
            : _service.getSlowMovingItems(
                companyName: company, days: _velocityCutoffDays),
        costs
            ? (isCombined
                ? _service.getCombinedHighValueItems(companyNames: companies)
                : _service.getHighValueItems(companyName: company))
            : Future.value(<Map<String, dynamic>>[]),
      ]);
      if (!_scopeStillActive(generation, scopeKey)) return;
      setState(() {
        _fastItems = results[0];
        _slowItems = results[1];
        _highValueItems = results[2];
        _velocityLoaded = true;
        _velocityLoading = false;
      });
    } catch (e) {
      if (_scopeStillActive(generation, scopeKey)) {
        setState(() {
          _velocityLoading = false;
          _error = AppErrorHandler.getFriendlyError(e);
        });
      }
    }
  }

  Future<void> _loadDormantIfNeeded({bool force = false}) async {
    if (_dormantLoading && !force) return;
    if (_dormantLoaded && !force) return;
    final state = CompanyProvider.of(context);
    if (!state.isFeatureEnabled('rep_ledgers')) {
      if (!mounted) return;
      setState(() {
        _unusedLedgers = [];
        _unusedItems = [];
        _totalUnusedLedgersCount = 0;
        _totalUnusedItemsCount = 0;
        _dormantLoaded = true;
        _dormantLoading = false;
      });
      return;
    }
    if (!_hasValidScope(state)) return;

    final generation = _loadGeneration;
    final scopeKey = state.scopeKey;
    final isCombined = state.isCombinedMode;
    final company = state.selectedCompany;
    final companies = state.selectedCompanies;
    final costs = state.isFeatureEnabled('stock_cost');

    setState(() => _dormantLoading = true);
    try {
      final results = await Future.wait([
        isCombined
            ? _service.getCombinedUnusedLedgers(
                companyNames: companies, days: _ledgerCutoffDays)
            : _service.getUnusedLedgers(
                companyName: company, days: _ledgerCutoffDays),
        isCombined
            ? _service.getCombinedUnusedItems(
                companyNames: companies, days: _itemCutoffDays)
            : _service.getUnusedItems(
                companyName: company, days: _itemCutoffDays),
      ]);
      if (!_scopeStillActive(generation, scopeKey)) return;

      final unusedLedgers = results[0];
      final unusedItems =
          results[1].map((row) => Map<String, dynamic>.from(row)).toList();
      if (!costs) {
        for (final item in unusedItems) {
          item.remove('stock_value');
        }
        unusedItems.sort(
            (a, b) => '${a['product_name']}'.compareTo('${b['product_name']}'));
      }

      final dead = unusedItems.fold<double>(
        0,
        (s, d) =>
            s + (double.tryParse(d['stock_value']?.toString() ?? '0') ?? 0),
      );
      setState(() {
        _unusedLedgers = unusedLedgers;
        _unusedItems = unusedItems;
        _totalUnusedLedgersCount = unusedLedgers.length;
        _totalUnusedItemsCount = unusedItems.length;
        _deadStockKpiValue = dead;
        _dormantLoaded = true;
        _dormantLoading = false;
        _overviewKpisLoaded = true;
        _overviewKpisLoading = false;
      });
    } catch (e) {
      if (_scopeStillActive(generation, scopeKey)) {
        setState(() {
          _dormantLoading = false;
          _error = AppErrorHandler.getFriendlyError(e);
        });
      }
    }
  }

  Future<void> _reloadOverviewData(int days) async {
    final generation = _loadGeneration;
    final state = CompanyProvider.of(context);
    final scopeKey = state.scopeKey;
    final isCombined = state.isCombinedMode;
    final company = state.selectedCompany;
    _overviewDays = days;
    if (!_hasValidScope(state)) return;
    try {
      final costs = state.isFeatureEnabled('stock_cost');
      final sales = state.isFeatureEnabled('rep_sales') && costs;
      if (!sales) return;
      final profit = isCombined
          ? await _service.getCombinedDailyProfit(
              companyNames: state.selectedCompanies, days: _overviewDays)
          : await _service.getDailyProfit(
              companyName: company, days: _overviewDays);
      if (!_scopeStillActive(generation, scopeKey)) return;
      setState(() {
        _profitData = profit;
        _useLineChart = _overviewDays > 30;
      });
    } catch (e) {
      if (_scopeStillActive(generation, scopeKey)) {
        setState(() => _error = AppErrorHandler.getFriendlyError(e));
      }
    }
  }

  Future<void> _reloadLedgers(int cutoffDays) async {
    if (cutoffDays == _ledgerCutoffDays && _dormantLoaded) return;
    setState(() => _ledgerCutoffDays = cutoffDays);
    // Keep prior rows visible while reloading (avoid full-tab spinner flash).
    await _loadDormantIfNeeded(force: true);
  }

  Future<void> _reloadItems(int cutoffDays) async {
    if (cutoffDays == _itemCutoffDays && _dormantLoaded) return;
    setState(() => _itemCutoffDays = cutoffDays);
    await _loadDormantIfNeeded(force: true);
  }

  Future<void> _reloadVelocity(int cutoffDays) async {
    if (cutoffDays == _velocityCutoffDays && _velocityLoaded) return;
    setState(() => _velocityCutoffDays = cutoffDays);
    // Do not clear _velocityLoaded — that replaced the whole tab with a spinner.
    await _loadVelocityIfNeeded(force: true);
  }

  Future<void> _refreshCurrentTab() async {
    final index = _tabController.index;
    if (index < 0 || index >= _visibleTabLabels.length) {
      await _loadData();
      return;
    }
    switch (_visibleTabLabels[index]) {
      case 'Overview':
        await _loadData();
        break;
      case 'Velocity':
        await _loadVelocityIfNeeded(force: true);
        break;
      case 'Dormant':
        await _loadDormantIfNeeded(force: true);
        break;
      default:
        await _loadData();
    }
  }

  Widget _analyticsTitle(bool showCombined, List<String> companies) {
    if (!showCombined) {
      return const Text('Analytics', style: TextStyle(fontWeight: FontWeight.bold));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Analytics', style: TextStyle(fontWeight: FontWeight.bold)),
        Text(
          companies.join('  ·  '),
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w500,
            height: 1.25,
            color: AppTheme.textSecondary,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------
  // Derived KPI numbers
  // ---------------------------------------------------------------------
  double get _totalRevenue => _profitData.fold(
      0.0, (s, d) => s + (double.tryParse(d['total_revenue']?.toString() ?? '0') ?? 0));

  double get _totalProfit => _profitData.fold(
      0.0, (s, d) => s + (double.tryParse(d['estimated_profit']?.toString() ?? '0') ?? 0));

  double get _deadStockValue {
    if (_dormantLoaded) {
      return _unusedItems.fold(
        0.0,
        (s, d) =>
            s + (double.tryParse(d['stock_value']?.toString() ?? '0') ?? 0),
      );
    }
    return _deadStockKpiValue;
  }

  Future<void> _loadOverviewKpisIfNeeded({bool force = false}) async {
    if (_overviewKpisLoading && !force) return;
    if (_overviewKpisLoaded && !force) return;
    final state = CompanyProvider.of(context);
    if (!state.isFeatureEnabled('rep_ledgers')) {
      if (!mounted) return;
      setState(() {
        _totalUnusedLedgersCount = 0;
        _totalUnusedItemsCount = 0;
        _deadStockKpiValue = 0;
        _overviewKpisLoaded = true;
        _overviewKpisLoading = false;
      });
      return;
    }
    if (!_hasValidScope(state)) return;

    final generation = _loadGeneration;
    final scopeKey = state.scopeKey;
    setState(() => _overviewKpisLoading = true);
    try {
      final kpis = state.isCombinedMode
          ? await _service.getCombinedDormantOverviewKpis(
              companyNames: state.selectedCompanies,
              ledgerDays: _ledgerCutoffDays,
              itemDays: _itemCutoffDays,
            )
          : await _service.getDormantOverviewKpis(
              companyName: state.selectedCompany,
              ledgerDays: _ledgerCutoffDays,
              itemDays: _itemCutoffDays,
            );
      if (!_scopeStillActive(generation, scopeKey)) return;
      setState(() {
        _totalUnusedLedgersCount =
            int.tryParse('${kpis['unused_ledgers_count']}') ?? 0;
        _totalUnusedItemsCount =
            int.tryParse('${kpis['unused_items_count']}') ?? 0;
        _deadStockKpiValue =
            double.tryParse('${kpis['dead_stock_value']}') ?? 0;
        _overviewKpisLoaded = true;
        _overviewKpisLoading = false;
      });
    } catch (e) {
      if (_scopeStillActive(generation, scopeKey)) {
        setState(() {
          _overviewKpisLoading = false;
          _error = AppErrorHandler.getFriendlyError(e);
        });
      }
    }
  }

  /// True when [saleDate] is the user's local calendar today (not merely last chart point).
  bool _isCalendarToday(String? saleDate) {
    final parsed = DateTime.tryParse(saleDate ?? '');
    if (parsed == null) return false;
    final now = DateTime.now();
    return parsed.year == now.year &&
        parsed.month == now.month &&
        parsed.day == now.day;
  }

  @override
  Widget build(BuildContext context) {
    final companyState = CompanyProvider.of(context);
    final showCosts = companyState.isFeatureEnabled('stock_cost');
    if (!showCosts && _velocityFilter == 'value') _velocityFilter = 'fast';
    final showSales = companyState.isFeatureEnabled('rep_sales') && showCosts;
    // Velocity uses sales invoice movement (fast/slow) + optional high-value stock.
    final showVelocity = companyState.isFeatureEnabled('rep_sales');
    final showLedgers = companyState.isFeatureEnabled('rep_ledgers');

    // Build visible tab labels
    final visibleTabLabels = <String>[];

    // We will fill the views after we know the tab data - use placeholders for now
    if (showSales) visibleTabLabels.add('Overview');
    if (showVelocity) visibleTabLabels.add('Velocity');
    if (showLedgers) visibleTabLabels.add('Dormant');

    _visibleTabLabels = visibleTabLabels;
    _rebuildTabController(visibleTabLabels.isEmpty ? 1 : visibleTabLabels.length);

    final isCombined = companyState.isCombinedMode;
    final combinedCompanies = companyState.selectedCompanies;
    final showCombinedCompanies =
        isCombined && combinedCompanies.isNotEmpty;

    if (visibleTabLabels.isEmpty) {
      return Scaffold(
        backgroundColor: _Palette.paper,
        appBar: AppBar(
          leading: IconButton(
            icon: Icon(Icons.arrow_back),
            onPressed: widget.onBack ?? () => Navigator.of(context).pop(),
          ),
          title: _analyticsTitle(showCombinedCompanies, combinedCompanies),
          backgroundColor: AppTheme.cardColor,
          surfaceTintColor: AppTheme.cardColor,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock_rounded, size: 48, color: Color(0xFF2453FF)),
              const SizedBox(height: 12),
              Text('Feature Locked', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18, color: AppTheme.textPrimary)),
              const SizedBox(height: 8),
              Text('Analytics & Reports are disabled for this company.', textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.textSecondary)),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: _Palette.paper,
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.arrow_back),
          onPressed: widget.onBack ?? () => Navigator.of(context).pop(),
        ),
        title: _analyticsTitle(showCombinedCompanies, combinedCompanies),
        toolbarHeight: showCombinedCompanies ? 64 : kToolbarHeight,
        backgroundColor: AppTheme.cardColor,
        surfaceTintColor: AppTheme.cardColor,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _refreshCurrentTab,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: _Palette.blue,
          unselectedLabelColor: _Palette.ink500,
          indicatorColor: _Palette.blue,
          indicatorSize: TabBarIndicatorSize.tab,
          tabs: visibleTabLabels.map((l) => Tab(text: l)).toList(),
        ),
      ),
      body: _error != null ? ErrorStateWidget(error: _error!, onRetry: _loadData) : _isLoading
          ? const ShimmerGridLoading(itemCount: 5)
          : Builder(builder: (context) {
            // Build views in order matching visible tabs
            final views = <Widget>[];
            if (showSales) {
              views.add(
                // TAB 1: OVERVIEW & PROFIT
                RefreshIndicator(
                  onRefresh: _loadData,
                  color: _Palette.blue,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final isWide = constraints.maxWidth >= 720;
                      return ListView(
                        padding: const EdgeInsets.all(16),
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Overview Analysis',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _Palette.ink900),
                              ),
                              DropdownButton<int>(
                                value: _overviewDays,
                                items: const [
                                  DropdownMenuItem(value: 7, child: Text('7 Days')),
                                  DropdownMenuItem(value: 14, child: Text('14 Days')),
                                  DropdownMenuItem(value: 30, child: Text('30 Days')),
                                  DropdownMenuItem(value: 90, child: Text('90 Days')),
                                  DropdownMenuItem(value: 180, child: Text('180 Days')),
                                  DropdownMenuItem(value: 365, child: Text('365 Days')),
                                ],
                                onChanged: (val) {
                                  if (val != null) {
                                    _reloadOverviewData(val);
                                  }
                                },
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: _Palette.blue),
                                underline: const SizedBox.shrink(),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _buildKpiRow(isWide),
                          const SizedBox(height: 20),
                          _sectionCard(
                            title: 'Sales & Profit Trend',
                            tag: _SectionTag(label: '$_overviewDays day trend', color: _Palette.blue, bg: _Palette.blueSoft),
                            child: _buildProfitChart(),
                          ),
                        ],
                      );
                    },
                  ),
              ));
            }

                // TAB 2: VELOCITY
                if (showVelocity) {
                  views.add(Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              ChoiceChip(
                                label: const Text('Fast Moving'),
                                selected: _velocityFilter == 'fast',
                                onSelected: (_) => setState(() => _velocityFilter = 'fast'),
                                selectedColor: _Palette.teal,
                                backgroundColor: _Palette.paper,
                                labelStyle: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: _velocityFilter == 'fast' ? Colors.white : _Palette.ink700,
                                ),
                                side: BorderSide(color: _Palette.line),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                              ),
                              ChoiceChip(
                                label: const Text('Slow Moving'),
                                selected: _velocityFilter == 'slow',
                                onSelected: (_) => setState(() => _velocityFilter = 'slow'),
                                selectedColor: _Palette.amber,
                                backgroundColor: _Palette.paper,
                                labelStyle: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: _velocityFilter == 'slow' ? Colors.white : _Palette.ink700,
                                ),
                                side: BorderSide(color: _Palette.line),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                              ),
                              if (showCosts) ChoiceChip(
                                label: const Text('High Value'),
                                selected: _velocityFilter == 'value',
                                onSelected: (_) => setState(() => _velocityFilter = 'value'),
                                selectedColor: _Palette.blue,
                                backgroundColor: _Palette.paper,
                                labelStyle: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: _velocityFilter == 'value' ? Colors.white : _Palette.ink700,
                                ),
                                side: BorderSide(color: _Palette.line),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                              ),
                            ],
                          ),
                          if (_velocityFilter != 'value') ...[
                            const SizedBox(height: 12),
                            _cutoffChips(_velocityCutoffDays, _reloadVelocity),
                          ],
                        ],
                      ),
                    ),
                    Expanded(
                      child: Stack(
                        children: [
                          if (!_velocityLoaded && _velocityLoading)
                            const Center(child: CircularProgressIndicator())
                          else
                            RefreshIndicator(
                        onRefresh: () => _loadVelocityIfNeeded(force: true),
                        color: _Palette.blue,
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final isWide = constraints.maxWidth >= 720;
                            final currentList = _velocityFilter == 'fast' ? _fastItems : (_velocityFilter == 'slow' ? _slowItems : _highValueItems);
                            
                            String title = 'Fast Moving Distribution';
                            Color mainColor = _Palette.teal;
                            Color bgColor = _Palette.tealSoft;
                            String listTitle = 'All Fast Moving Items';
                            String qtyHeader = 'Qty sold';
                            
                            if (_velocityFilter == 'slow') {
                              title = 'Slow Moving Distribution';
                              mainColor = _Palette.amber;
                              bgColor = _Palette.amberSoft;
                              listTitle = 'Slow movers (< 5 sold in period)';
                            } else if (_velocityFilter == 'value') {
                              title = 'High Value Inventory Distribution';
                              mainColor = _Palette.blue;
                              bgColor = _Palette.blue.withValues(alpha: 0.1);
                              listTitle = 'All High Value Inventory';
                              qtyHeader = 'Stock Value';
                            }

                            return CustomScrollView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              slivers: [
                                SliverPadding(
                                  padding: const EdgeInsets.all(16),
                                  sliver: SliverToBoxAdapter(
                                    child: AnimatedSwitcher(
                                      duration: const Duration(milliseconds: 300),
                                      child: _sectionCard(
                                        key: ValueKey('velocity_chart_${_velocityFilter}_$_velocityCutoffDays'),
                                        title: title,
                                        tag: _SectionTag(
                                          label: 'Top 7 threshold',
                                          color: mainColor,
                                          bg: bgColor,
                                        ),
                                        child: _buildVelocityChart(isWide, _velocityFilter),
                                      ),
                                    ),
                                  ),
                                ),
                                SliverPadding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16),
                                  sliver: SliverList.builder(
                                    itemCount: currentList.isEmpty ? 2 : currentList.length + 2,
                                    itemBuilder: (context, index) {
                                      if (index == 0) {
                                        return Container(
                                          decoration: BoxDecoration(
                                            color: AppTheme.cardColor,
                                            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                                            border: Border(
                                              top: BorderSide(color: _Palette.line),
                                              left: BorderSide(color: _Palette.line),
                                              right: BorderSide(color: _Palette.line),
                                            ),
                                          ),
                                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                                          child: Column(
                                            children: [
                                              Row(
                                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                children: [
                                                  Expanded(child: Text(listTitle, style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: _Palette.ink900))),
                                                  _SectionTag(label: 'All filtered items', color: mainColor, bg: bgColor),
                                                ],
                                              ),
                                              const SizedBox(height: 14),
                                              if (currentList.isNotEmpty) ...[
                                                Row(
                                                  children: [
                                                    Expanded(flex: 3, child: Text('Item', style: _headerStyle)),
                                                    Expanded(flex: 1, child: Text(qtyHeader, textAlign: TextAlign.right, style: _headerStyle)),
                                                    if (isWide) const SizedBox(width: 80) else const SizedBox(width: 12),
                                                  ],
                                                ),
                                                Divider(height: 18, color: _Palette.line),
                                              ]
                                            ],
                                          ),
                                        );
                                      }
                                      if (index == (currentList.isEmpty ? 1 : currentList.length + 1)) {
                                        return Container(
                                          height: 16,
                                          decoration: BoxDecoration(
                                            color: AppTheme.cardColor,
                                            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
                                            border: Border(
                                              bottom: BorderSide(color: _Palette.line),
                                              left: BorderSide(color: _Palette.line),
                                              right: BorderSide(color: _Palette.line),
                                            ),
                                            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8, offset: const Offset(0, 3))],
                                          ),
                                          child: currentList.isEmpty ? Center(child: Text('No items found for this filter.', style: TextStyle(color: _Palette.ink500, fontSize: 13))) : null,
                                        );
                                      }
                                      final item = currentList[index - 1];
                                      return Container(
                                        color: AppTheme.cardColor,
                                        padding: const EdgeInsets.symmetric(horizontal: 16),
                                        child: Container(
                                          decoration: BoxDecoration(
                                            border: Border(left: BorderSide(color: _Palette.line), right: BorderSide(color: _Palette.line)),
                                          ),
                                          padding: const EdgeInsets.symmetric(vertical: 8),
                                          child: Row(
                                            children: [
                                              Expanded(
                                                flex: 3,
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      item['product_name'] ?? '-',
                                                      style: TextStyle(
                                                        fontWeight: FontWeight.w600,
                                                        color: _Palette.ink900,
                                                        fontSize: 13,
                                                      ),
                                                    ),
                                                    if ((item['company_name'] ?? '')
                                                        .toString()
                                                        .trim()
                                                        .isNotEmpty)
                                                      Text(
                                                        item['company_name'].toString(),
                                                        style: TextStyle(
                                                          fontSize: 11,
                                                          color: _Palette.ink500,
                                                          fontWeight: FontWeight.w500,
                                                        ),
                                                      ),
                                                  ],
                                                ),
                                              ),
                                              Expanded(
                                                flex: 1,
                                                child: Text(_velocityFilter == 'value' ? formatCompactCurrency(double.tryParse(item['stock_value']?.toString() ?? '0') ?? 0) : '${item['total_sold']}', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.w700, color: _Palette.ink700, fontSize: 13)),
                                              ),
                                              if (isWide) const SizedBox(width: 80) else const SizedBox(width: 12),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                                const SliverPadding(padding: EdgeInsets.only(bottom: 16)),
                              ],
                            );
                          },
                        ),
                      ),
                          if (_velocityLoading && _velocityLoaded)
                            const Positioned(
                              top: 0,
                              left: 0,
                              right: 0,
                              child: LinearProgressIndicator(minHeight: 2),
                            ),
                        ],
                      ),
                    ),
                  ],
                  ));
                }

                // TAB 3: DORMANT
                if (showLedgers) {
                  views.add(Padding(
                  padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                      Row(
                        children: [
                          ChoiceChip(
                            label: const Text('Unused Ledgers'),
                            selected: _dormantFilter == 'ledgers',
                            onSelected: (_) => setState(() => _dormantFilter = 'ledgers'),
                            selectedColor: _Palette.blue,
                            backgroundColor: _Palette.paper,
                            labelStyle: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: _dormantFilter == 'ledgers' ? Colors.white : _Palette.ink700,
                            ),
                            side: BorderSide(color: _Palette.line),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          ),
                          const SizedBox(width: 8),
                          ChoiceChip(
                            label: const Text('Unused Items'),
                            selected: _dormantFilter == 'items',
                            onSelected: (_) => setState(() => _dormantFilter = 'items'),
                            selectedColor: _Palette.red,
                            backgroundColor: _Palette.paper,
                            labelStyle: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: _dormantFilter == 'items' ? Colors.white : _Palette.ink700,
                            ),
                            side: BorderSide(color: _Palette.line),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: Stack(
                          children: [
                            if (!_dormantLoaded && _dormantLoading)
                              const Center(child: CircularProgressIndicator())
                            else
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 300),
                                child: _dormantFilter == 'ledgers'
                                    ? _sectionCard(
                                        key: const ValueKey('dormant_ledgers'),
                                        title:
                                            'Unused Ledgers ($_totalUnusedLedgersCount)',
                                        tag: _SectionTag(
                                          label: 'No activity',
                                          color: _Palette.blue,
                                          bg: _Palette.blueSoft,
                                        ),
                                        expanded: true,
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            _cutoffChips(
                                              _ledgerCutoffDays,
                                              _reloadLedgers,
                                            ),
                                            const SizedBox(height: 12),
                                            Expanded(child: _buildLedgersTable()),
                                          ],
                                        ),
                                      )
                                    : _sectionCard(
                                        key: const ValueKey('dormant_items'),
                                        title:
                                            'Unused Items ($_totalUnusedItemsCount)',
                                        tag: _SectionTag(
                                          label: 'In stock, no sale',
                                          color: _Palette.red,
                                          bg: _Palette.redSoft,
                                        ),
                                        expanded: true,
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            _cutoffChips(
                                              _itemCutoffDays,
                                              _reloadItems,
                                            ),
                                            const SizedBox(height: 12),
                                            Expanded(child: _buildItemsTable()),
                                          ],
                                        ),
                                      ),
                              ),
                            if (_dormantLoading && _dormantLoaded)
                              const Positioned(
                                top: 0,
                                left: 0,
                                right: 0,
                                child: LinearProgressIndicator(minHeight: 2),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ));
                }

            return TabBarView(
              controller: _tabController,
              children: views,
            );
          }),
    );
  }

  // ---------------------------------------------------------------------
  // KPI row
  // ---------------------------------------------------------------------
  Widget _buildKpiRow(bool isWide) {
    final dormantValue = (_overviewKpisLoaded || _dormantLoaded)
        ? null
        : ((_overviewKpisLoading || _dormantLoading) ? '…' : '—');
    final cards = [
      _KpiCard(label: 'Revenue ($_overviewDays d)', value: formatCompactCurrency(_totalRevenue)),
      _KpiCard(label: 'Profit ($_overviewDays d)', value: formatCompactCurrency(_totalProfit)),
      _KpiCard(
        label: 'Dead stock value',
        value: dormantValue ?? formatCompactCurrency(_deadStockValue),
      ),
      _KpiCard(
        label: 'Unused ledgers',
        value: dormantValue ?? '$_totalUnusedLedgersCount',
      ),
      _KpiCard(
        label: 'Unused items',
        value: dormantValue ?? '$_totalUnusedItemsCount',
      ),
    ];
    final columns = isWide ? 5 : 2;
    return GridView.count(
      crossAxisCount: columns,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: isWide ? 1.5 : 1.6,
      children: cards,
    );
  }

  // ---------------------------------------------------------------------
  // Sales & Profit Daily chart
  // ---------------------------------------------------------------------
  Widget _buildLineChart(
    List<Map<String, dynamic>> chartData,
    double maxY, {
    double minY = 0,
  }) {
    final revenueSpots = <FlSpot>[];
    final profitSpots = <FlSpot>[];
    for (int i = 0; i < chartData.length; i++) {
      final rev = double.tryParse(chartData[i]['total_revenue']?.toString() ?? '0') ?? 0;
      final prof = double.tryParse(chartData[i]['estimated_profit']?.toString() ?? '0') ?? 0;
      revenueSpots.add(FlSpot(i.toDouble(), rev));
      profitSpots.add(FlSpot(i.toDouble(), prof));
    }

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (value) => FlLine(color: _Palette.line, strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          show: true,
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 32,
              interval: 1, // Enforce FLChart to step by 1
              getTitlesWidget: (value, meta) {
                // Ensure we only process integer indices
                if (value != value.toInt()) return const SizedBox.shrink();
                
                final index = value.toInt();
                if (index >= 0 && index < chartData.length) {
                  int labelInterval = 1;
                  String formatStr = 'dd/MM';
                  
                  if (chartData.length > 90) {
                    labelInterval = 30;
                    formatStr = 'MMM yyyy';
                  } else if (chartData.length > 45) {
                    labelInterval = 15;
                    formatStr = 'dd MMM';
                  } else if (chartData.length > 15) {
                    labelInterval = 5;
                    formatStr = 'dd MMM';
                  } else if (chartData.length > 7) {
                    labelInterval = 2;
                  }

                  final dateStr = chartData[index]['sale_date'].toString();
                  final isToday = _isCalendarToday(dateStr);
                  final isIntervalMatch = index % labelInterval == 0;
                  final isLast = index == chartData.length - 1;
                  final isTooCloseToEnd = (chartData.length - 1 - index) < (labelInterval / 2);

                  if (index == 0 || isToday || isLast || (isIntervalMatch && !isTooCloseToEnd)) {
                    final date = DateTime.tryParse(dateStr);
                    if (date != null) {
                      return Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text(
                          isToday ? 'Today' : DateFormat(formatStr).format(date),
                          style: TextStyle(
                            fontSize: 10,
                            color: isToday ? _Palette.ink900 : _Palette.ink500,
                            fontWeight: isToday ? FontWeight.w800 : FontWeight.w600,
                          ),
                        ),
                      );
                    }
                  }
                }
                return const SizedBox.shrink();
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 48,
              interval: (maxY - minY).abs() > 0 ? (maxY - minY).abs() / 4 : 20,
              getTitlesWidget: (value, meta) {
                if (value == 0) return const Text('');
                return Padding(
                  padding: const EdgeInsets.only(right: 6.0),
                  child: Text(
                     NumberFormat.compactCurrency(locale: 'en_IN', symbol: '₹').format(value).replaceAll('T', 'K'),
                     style: TextStyle(fontSize: 10, color: _Palette.ink500),
                     textAlign: TextAlign.right,
                  ),
                );
              },
            ),
          ),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        minX: 0,
        maxX: (chartData.length - 1).toDouble(),
        minY: minY,
        maxY: maxY > minY ? maxY : (minY + 100),
        lineBarsData: [
          LineChartBarData(
            spots: revenueSpots,
            isCurved: true,
            curveSmoothness: 0.25,
            color: _Palette.blue,
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: FlDotData(show: chartData.length <= 15),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                colors: [
                  _Palette.blue.withValues(alpha: 0.3),
                  _Palette.blue.withValues(alpha: 0.0),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
          LineChartBarData(
            spots: profitSpots,
            isCurved: true,
            curveSmoothness: 0.25,
            color: _Palette.teal,
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: FlDotData(show: chartData.length <= 15),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                colors: [
                  _Palette.teal.withValues(alpha: 0.3),
                  _Palette.teal.withValues(alpha: 0.0),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        ],
        lineTouchData: LineTouchData(
          enabled: true,
          handleBuiltInTouches: true,
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (group) => _Palette.chartTooltipBg,
            tooltipPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            tooltipRoundedRadius: 12,
            tooltipMargin: 8,
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((spot) {
                final dateStr = chartData[spot.x.toInt()]['sale_date'].toString();
                final date = DateTime.tryParse(dateStr);
                final formattedDate = date != null ? DateFormat('MMM dd, yyyy').format(date) : '';
                
                final currency = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
                final isRev = spot.barIndex == 0;
                
                return LineTooltipItem(
                  isRev ? '$formattedDate\n' : '',
                  TextStyle(
                    color: _Palette.chartTooltipLabel,
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                  ),
                  children: [
                    TextSpan(
                      text: '${isRev ? 'Revenue' : 'Profit'}: ${currency.format(spot.y)}',
                      style: TextStyle(
                        color: isRev ? _Palette.blue : _Palette.teal,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),
                  ],
                );
              }).toList();
            },
          ),
        ),
      ),
    );
  }

  Widget _buildProfitChart() {
    if (_profitData.isEmpty) {
      return SizedBox(
        height: 160,
        child: Center(child: Text('Not enough data to compute profit trend.', style: TextStyle(color: _Palette.ink500))),
      );
    }
    final chartData = _profitData.reversed.toList();
    double maxY = 0;
    double minY = 0;
    for (var d in chartData) {
      final rev = double.tryParse(d['total_revenue']?.toString() ?? '0') ?? 0;
      final prof = double.tryParse(d['estimated_profit']?.toString() ?? '0') ?? 0;
      if (rev > maxY) maxY = rev;
      if (prof > maxY) maxY = prof;
      if (rev < minY) minY = rev;
      if (prof < minY) minY = prof;
    }
    if (minY < 0) {
      minY = minY * 1.15;
    }
    maxY = maxY > 0 ? maxY * 1.2 : 100;

    double rodWidth = 8;
    if (chartData.length > 90) {
      rodWidth = 1.5;
    } else if (chartData.length > 45) {
      rodWidth = 3;
    } else if (chartData.length > 15) {
      rodWidth = 5;
    } else if (chartData.length > 7) {
      rodWidth = 10;
    }

    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Wrap(
                spacing: 12,
                runSpacing: 6,
                children: const [
                  _LegendItem(color: _Palette.blue, label: 'Gross revenue'),
                  _LegendItem(color: _Palette.teal, label: 'Est. profit (std cost)'),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: () => setState(() => _useLineChart = false),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: !_useLineChart ? _Palette.blue.withValues(alpha: 0.1) : Colors.transparent,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Icon(Icons.bar_chart_rounded, size: 16, color: !_useLineChart ? _Palette.blue : _Palette.ink500),
                  ),
                ),
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: () => setState(() => _useLineChart = true),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _useLineChart ? _Palette.blue.withValues(alpha: 0.1) : Colors.transparent,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Icon(Icons.show_chart_rounded, size: 16, color: _useLineChart ? _Palette.blue : _Palette.ink500),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 220,
          child: _useLineChart
              ? _buildLineChart(chartData, maxY, minY: minY)
              : BarChart(
                  BarChartData(
                    alignment: BarChartAlignment.spaceAround,
                    minY: minY,
                    maxY: maxY,
                    barTouchData: BarTouchData(
                      enabled: true,
                      touchTooltipData: BarTouchTooltipData(
                        getTooltipColor: (group) => _Palette.chartTooltipBg,
                        tooltipPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        tooltipMargin: 8,
                        getTooltipItem: (group, groupIndex, rod, rodIndex) {
                          if (rodIndex != 0) return null; // Only show one combined tooltip per group
                          
                          final currency = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
                          final rev = group.barRods.isNotEmpty ? group.barRods[0].toY : 0;
                          final prof = group.barRods.length > 1 ? group.barRods[1].toY : 0;
                          
                          return BarTooltipItem(
                            'Rev : ${currency.format(rev)} \n',
                            TextStyle(
                              color: _Palette.blue,
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                            children: [
                              TextSpan(
                                text: 'Profit : ${currency.format(prof)}',
                                style: TextStyle(
                                  color: _Palette.teal,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                    titlesData: FlTitlesData(
                      show: true,
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (value, meta) {
                            final index = value.toInt();
                            if (index >= 0 && index < chartData.length) {
                              int labelInterval = 1;
                              if (chartData.length > 90) {
                                labelInterval = 30;
                              } else if (chartData.length > 45) {
                                labelInterval = 15;
                              } else if (chartData.length > 15) {
                                labelInterval = 5;
                              } else if (chartData.length > 7) {
                                labelInterval = 2;
                              }

                              final dateStr = chartData[index]['sale_date'].toString();
                              final isToday = _isCalendarToday(dateStr);
                              final isIntervalMatch = index % labelInterval == 0;
                              final isLast = index == chartData.length - 1;
                              final isTooCloseToEnd = (chartData.length - 1 - index) < (labelInterval / 2);

                              if (index == 0 || isToday || isLast || (isIntervalMatch && !isTooCloseToEnd)) {
                                final date = DateTime.tryParse(dateStr);
                                if (date != null) {
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 8.0),
                                    child: Text(
                                      isToday ? 'Today' : DateFormat('dd/MM').format(date),
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: isToday ? _Palette.ink900 : _Palette.ink500,
                                        fontWeight: isToday ? FontWeight.w800 : FontWeight.w600,
                                      ),
                                    ),
                                  );
                                }
                              }
                            }
                            return const SizedBox.shrink();
                          },
                        ),
                      ),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 48,
                          interval: (maxY - minY).abs() > 0 ? (maxY - minY).abs() / 4 : 20,
                          getTitlesWidget: (value, meta) {
                            if (value == 0) return const Text('');
                            return Padding(
                              padding: const EdgeInsets.only(right: 6.0),
                              child: Text(
                                NumberFormat.compactCurrency(locale: 'en_IN', symbol: '₹').format(value),
                                style: TextStyle(fontSize: 10, color: _Palette.ink500),
                                textAlign: TextAlign.right,
                              ),
                            );
                          },
                        ),
                      ),
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    ),
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      getDrawingHorizontalLine: (value) => FlLine(color: _Palette.line, strokeWidth: 1),
                    ),
                    borderData: FlBorderData(show: false),
                    barGroups: List.generate(chartData.length, (i) {
                      final rev = double.tryParse(chartData[i]['total_revenue']?.toString() ?? '0') ?? 0;
                      final prof = double.tryParse(chartData[i]['estimated_profit']?.toString() ?? '0') ?? 0;
                      final isToday = i == chartData.length - 1;
                      
                      return BarChartGroupData(x: i, barRods: [
                        BarChartRodData(
                          toY: rev,
                          color: isToday ? _Palette.blue : _Palette.blue.withValues(alpha: 0.3),
                          width: rodWidth,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                        ),
                        BarChartRodData(
                          toY: prof,
                          color: isToday ? _Palette.teal : _Palette.teal.withValues(alpha: 0.3),
                          width: rodWidth,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                        ),
                      ]);
                    }),
                  ),
                ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------
  // Velocity Chart: donut with center total + table for Top 7
  // ---------------------------------------------------------------------
  Widget _buildVelocityChart(bool isWide, String filter) {
    final list = filter == 'fast' ? _fastItems : (filter == 'slow' ? _slowItems : _highValueItems);
    if (list.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(child: Text('No data recorded in this period.', style: TextStyle(color: _Palette.ink500))),
      );
    }
    final colors = [_Palette.blue, _Palette.teal, _Palette.amber, const Color(0xFF7B5CFA), _Palette.red, Colors.pink, Colors.lime];
    final top7 = list.take(7).toList();
    final valueKey = filter == 'value' ? 'stock_value' : 'total_sold';
    final total = top7.fold<double>(0, (s, d) => s + (double.tryParse(d[valueKey].toString()) ?? 0));

    final donut = SizedBox(
      height: 170,
      width: 170,
      child: Stack(
        alignment: Alignment.center,
        children: [
          PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 46,
              sections: total == 0
                  ? [PieChartSectionData(color: _Palette.line, value: 1, title: '', radius: 26)]
                  : List.generate(top7.length, (i) {
                      final val = double.tryParse(top7[i][valueKey].toString()) ?? 0;
                      return PieChartSectionData(color: colors[i % colors.length], value: val, title: '', radius: 26);
                    }),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(filter == 'value' ? formatCompactCurrency(total) : total.toStringAsFixed(0),
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20, color: _Palette.ink900)),
              Text(filter == 'value' ? 'stock value' : 'units sold', style: TextStyle(fontSize: 11, color: _Palette.ink500)),
            ],
          ),
        ],
      ),
    );

    final table = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(top7.length, (i) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Container(width: 9, height: 9, margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(color: colors[i % colors.length], shape: BoxShape.circle)),
              Expanded(
                child: Text(top7[i]['product_name'] ?? 'Unknown',
                    style: TextStyle(fontSize: 13, color: _Palette.ink900, fontWeight: FontWeight.w600),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              Text(filter == 'value' ? formatCompactCurrency(double.tryParse(top7[i][valueKey]?.toString() ?? '0') ?? 0) : '${top7[i][valueKey]}',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _Palette.ink900)),
              if (isWide) const SizedBox(width: 80) else const SizedBox(width: 12),
            ],
          ),
        );
      }),
    );

    if (isWide) {
      return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        donut,
        const SizedBox(width: 24),
        Expanded(child: table),
      ]);
    }
    return Column(children: [
      Center(child: donut),
      const SizedBox(height: 14),
      table,
    ]);
  }

  // ---------------------------------------------------------------------
  // Generic simple table (used for Slow Moving)
  // ---------------------------------------------------------------------
  Widget _buildSimpleTable({
    required List<Map<String, dynamic>> data,
    required String emptyMessage,
    required String valueKey,
    required String valueLabel,
    bool isWide = true,
  }) {
    if (data.isEmpty) {
      return _emptyState(emptyMessage);
    }
    return Column(
      children: [
        Row(
          children: [
            Expanded(flex: 3, child: Text('Item', style: _headerStyle)),
            Expanded(flex: 1, child: Text(valueLabel, textAlign: TextAlign.right, style: _headerStyle)),
            if (isWide) const SizedBox(width: 80) else const SizedBox(width: 12),
          ],
        ),
        Divider(height: 18, color: _Palette.line),
        ...data.map((item) {
          return RepaintBoundary(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Text(item['product_name'] ?? '-',
                        style: TextStyle(fontWeight: FontWeight.w600, color: _Palette.ink900, fontSize: 13)),
                  ),
                  Expanded(
                    flex: 1,
                    child: Text('${item[valueKey]}',
                        textAlign: TextAlign.right,
                        style: TextStyle(fontWeight: FontWeight.w700, color: _Palette.ink700, fontSize: 13)),
                  ),
                  if (isWide) const SizedBox(width: 80) else const SizedBox(width: 12),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  // ---------------------------------------------------------------------
  // Unused Ledgers table
  // ---------------------------------------------------------------------
  Widget _buildLedgersTable() {
    if (_unusedLedgers.isEmpty) {
      return _emptyState('No ledgers idle for $_ledgerCutoffDays+ days.');
    }
    return Column(
      children: [
        Row(
          children: [
            Expanded(flex: 2, child: Text('Customer', style: _headerStyle)),
            Expanded(flex: 1, child: Text('Phone', textAlign: TextAlign.right, style: _headerStyle)),
          ],
        ),
        Divider(height: 18, color: _Palette.line),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => _loadDormantIfNeeded(force: true),
            color: _Palette.blue,
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: _unusedLedgers.length,
              itemBuilder: (context, index) {
              final item = _unusedLedgers[index];
              final company = (item['company_name'] ?? '').toString();
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item['customer_name'] ?? '-',
                              style: TextStyle(fontWeight: FontWeight.w600, color: _Palette.ink900, fontSize: 13)),
                          if (company.isNotEmpty)
                            Text(company,
                                style: TextStyle(fontWeight: FontWeight.w500, color: _Palette.ink500, fontSize: 10),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                    Expanded(
                      flex: 1,
                      child: Text(item['mobile_number']?.toString() ?? item['phone']?.toString() ?? '-',
                          textAlign: TextAlign.right,
                          style: TextStyle(fontWeight: FontWeight.w600, color: _Palette.ink500, fontSize: 13)),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------
  // Unused Items table
  // ---------------------------------------------------------------------
  Widget _buildItemsTable() {
    if (_unusedItems.isEmpty) {
      return _emptyState('No items idle for $_itemCutoffDays+ days.');
    }
    final currency = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
    return Column(
      children: [
        Row(
          children: [
            Expanded(flex: 3, child: Text('Product', style: _headerStyle)),
            Expanded(flex: 1, child: Text('Qty', textAlign: TextAlign.right, style: _headerStyle)),
            Expanded(flex: 2, child: Text('Stock value', textAlign: TextAlign.right, style: _headerStyle)),
          ],
        ),
        Divider(height: 18, color: _Palette.line),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => _loadDormantIfNeeded(force: true),
            color: _Palette.blue,
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: _unusedItems.length,
              itemBuilder: (context, index) {
              final item = _unusedItems[index];
              final val = double.tryParse(item['stock_value']?.toString() ?? '0') ?? 0;
              final company = (item['company_name'] ?? '').toString();
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item['product_name'] ?? '-',
                              style: TextStyle(fontWeight: FontWeight.w600, color: _Palette.ink900, fontSize: 13)),
                          if (company.isNotEmpty)
                            Text(company,
                                style: TextStyle(fontWeight: FontWeight.w500, color: _Palette.ink500, fontSize: 10),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                    Expanded(
                      flex: 1,
                      child: Text('${item['quantity']}', textAlign: TextAlign.right, style: TextStyle(color: _Palette.ink500, fontSize: 13)),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(CompanyProvider.of(context).isFeatureEnabled('stock_cost') ? currency.format(val) : '—',
                          textAlign: TextAlign.right,
                          style: TextStyle(fontWeight: FontWeight.w700, color: _Palette.red, fontSize: 13)),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------
  // Shared bits
  // ---------------------------------------------------------------------
  Widget _cutoffChips(int selected, void Function(int) onSelect) {
    return Wrap(
      spacing: 6,
      children: _kCutoffOptions.map((d) {
        final isSelected = d == selected;
        return ChoiceChip(
          label: Text('${d}d'),
          selected: isSelected,
          onSelected: (sel) {
            if (!sel || d == selected) return;
            onSelect(d);
          },
          labelStyle: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: isSelected ? Colors.white : _Palette.ink700,
          ),
          selectedColor: _Palette.blue,
          backgroundColor: _Palette.paper,
          side: BorderSide(color: _Palette.line),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        );
      }).toList(),
    );
  }

  Widget _emptyState(String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Text(message, style: TextStyle(color: _Palette.ink500, fontSize: 13), textAlign: TextAlign.center),
      ),
    );
  }

  Widget _sectionCard({Key? key, required String title, required Widget tag, required Widget child, bool expanded = false}) {
    Widget content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(title, style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: _Palette.ink900)),
            ),
            tag,
          ],
        ),
        const SizedBox(height: 14),
        expanded ? Expanded(child: child) : child,
      ],
    );

    return RepaintBoundary(
      child: Container(
        key: key,
        width: double.infinity,
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.cardColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _Palette.line),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8, offset: const Offset(0, 3))],
        ),
        child: content,
      ),
    );
  }
}

TextStyle get _headerStyle => TextStyle(
  fontSize: 11,
  fontWeight: FontWeight.w700,
  color: _Palette.ink500,
  letterSpacing: 0.3,
);

// ---------------------------------------------------------------------------
// Small reusable widgets
// ---------------------------------------------------------------------------
class _KpiCard extends StatelessWidget {
  final String label;
  final String value;
  const _KpiCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _Palette.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label.toUpperCase(),
              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: _Palette.ink500, letterSpacing: 0.3)),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: _Palette.ink900)),
          ),
        ],
      ),
    );
  }
}

class _SectionTag extends StatelessWidget {
  final String label;
  final Color color;
  final Color bg;
  const _SectionTag({required this.label, required this.color, required this.bg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: color)),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  final Color bg;
  const _StatusBadge({required this.label, required this.color, required this.bg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(label, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: color)),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendItem({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _Palette.ink900)),
      ],
    );
  }
}
