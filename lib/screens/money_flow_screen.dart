import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../models/ledger_bill_settlement.dart';
import '../services/supabase_service.dart';
import '../widgets/shimmer_loading.dart';
import '../widgets/empty_state.dart';
import 'customer_ranking_screen.dart';
import 'ledger_statement_screen.dart';
import '../providers/company_provider.dart';
import '../utils/company_scope.dart';
import '../config/app_theme.dart';
import '../widgets/combined_mode_unavailable.dart';

class MoneyFlowScreen extends StatefulWidget {
  const MoneyFlowScreen({super.key});

  @override
  State<MoneyFlowScreen> createState() => _MoneyFlowScreenState();
}

class _MoneyFlowScreenState extends State<MoneyFlowScreen> {
  final SupabaseService _service = SupabaseService();
  bool _isLoading = true;
  String? _error;
  List<LedgerBillSettlement> _allSettlements = [];

  // Aggregated stats
  double _globalAvgDays = 0;
  int _fastCount = 0;
  int _modCount = 0;
  int _slowCount = 0;
  int _fastPct = 0;
  int _modPct = 0;
  int _slowPct = 0;
  int _totalBills = 0;
  double _totalAmount = 0;
  bool _hasAnalyticsData = false;
  /// Tally Ratio Analysis: Recv. Turnover in days (FY start → sync day).
  double? _tallyRecvTurnoverDays;
  DateTime? _tallyRatioFrom;
  DateTime? _tallyRatioTo;
  List<Map<String, dynamic>> _fastestCustomers = [];
  List<Map<String, dynamic>> _slowestCustomers = [];
  List<Map<String, dynamic>> _allFastestCustomers = [];
  List<Map<String, dynamic>> _allSlowestCustomers = [];
  List<Map<String, dynamic>> _monthlyTrend = [];

  // Filter
  String _selectedPeriod = 'All';
  final List<String> _periods = ['All', 'Last 3 Months', 'Last 6 Months', 'This FY'];
  bool _useDueDate = true;

  bool _hasLoaded = false;
  bool _trendIsLine = false;
  int? _lastCompanyRevision;
  int _loadGeneration = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final revision = CompanyProvider.of(context).companyRevision;
    if (!_hasLoaded) {
      _hasLoaded = true;
      _lastCompanyRevision = revision;
      _loadData();
    } else if (_lastCompanyRevision != revision) {
      _lastCompanyRevision = revision;
      _loadGeneration++;
      _allSettlements = [];
      _loadData();
    }
  }

  Future<void> _loadData() async {
    final generation = ++_loadGeneration;
    final companyName = CompanyProvider.of(context).selectedCompany;
    if (!CompanyScope.isValid(companyName)) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'No company selected';
          _allSettlements = [];
          _hasAnalyticsData = false;
        });
      }
      return;
    }
    setState(() { _isLoading = true; _error = null; });
    try {
      final results = await Future.wait([
        _service.getBillSettlements(companyName!),
        _service.getSundryDebtorNames(companyName),
        _service.getTallyRatioAnalysis(companyName),
      ]);
      final raw = results[0] as List<LedgerBillSettlement>;
      final debtors = results[1] as Set<String>;
      final tallyRatio = results[2] as Map<String, dynamic>?;

      // Prefer receivable (customer) settlements when ledger types are known.
      final data = debtors.isEmpty
          ? raw
          : raw
              .where((s) => debtors.contains(s.ledgerName.trim().toLowerCase()))
              .toList();

      if (!mounted ||
          generation != _loadGeneration ||
          !CompanyScope.stillActive(companyName, CompanyProvider.of(context).selectedCompany)) {
        return;
      }
      setState(() {
        _allSettlements = data;
        _applyFilter(data, _selectedPeriod);
        final daysRaw = tallyRatio?['recv_turnover_days'];
        _tallyRecvTurnoverDays = daysRaw == null
            ? null
            : (daysRaw is num
                ? daysRaw.toDouble()
                : double.tryParse(daysRaw.toString()));
        _tallyRatioFrom = _parseDateOnly(tallyRatio?['from_date']);
        _tallyRatioTo = _parseDateOnly(tallyRatio?['to_date']);
        _isLoading = false;
      });
    } catch (e) {
      if (mounted &&
          generation == _loadGeneration &&
          CompanyScope.stillActive(companyName, CompanyProvider.of(context).selectedCompany)) {
        setState(() { _error = e.toString(); _isLoading = false; });
      }
    }
  }

  static DateTime? _parseDateOnly(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) {
      return DateTime(value.year, value.month, value.day);
    }
    final s = value.toString();
    if (s.length < 10) return null;
    return DateTime.tryParse(s.substring(0, 10));
  }

  /// Safe calendar-month subtraction that clamps the day (avoids May 31 − 3 → Mar 2/3).
  static DateTime _monthsAgoClamped(DateTime now, int months) {
    var year = now.year;
    var month = now.month - months;
    while (month <= 0) {
      month += 12;
      year -= 1;
    }
    final lastDay = DateTime(year, month + 1, 0).day;
    final day = now.day > lastDay ? lastDay : now.day;
    return DateTime(year, month, day);
  }

  static DateTime _indianFyStart(DateTime now) =>
      now.month >= 4 ? DateTime(now.year, 4, 1) : DateTime(now.year - 1, 4, 1);

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Inclusive cleared-date window for the selected period.
  List<LedgerBillSettlement> _filterByPeriod(
    List<LedgerBillSettlement> data,
    String period,
  ) {
    final now = DateTime.now();
    switch (period) {
      case 'Last 3 Months':
        final cutoff = _monthsAgoClamped(now, 3);
        return data
            .where((s) =>
                s.clearedDate != null && !_dateOnly(s.clearedDate!).isBefore(cutoff))
            .toList();
      case 'Last 6 Months':
        final cutoff = _monthsAgoClamped(now, 6);
        return data
            .where((s) =>
                s.clearedDate != null && !_dateOnly(s.clearedDate!).isBefore(cutoff))
            .toList();
      case 'This FY':
      case 'This Year': // legacy label
        final fyStart = _indianFyStart(now);
        return data
            .where((s) =>
                s.clearedDate != null && !_dateOnly(s.clearedDate!).isBefore(fyStart))
            .toList();
      default:
        return data;
    }
  }

  int _trendMonthCount(String period) {
    final now = DateTime.now();
    switch (period) {
      case 'Last 3 Months':
        return 3;
      case 'Last 6 Months':
        return 6;
      case 'This FY':
      case 'This Year':
        final fyStart = _indianFyStart(now);
        return (now.year - fyStart.year) * 12 + (now.month - fyStart.month) + 1;
      default:
        return 6;
    }
  }

  /// Same analysis set for totals, average, distribution, and leaderboards.
  bool _isAnalyzable(LedgerBillSettlement s) {
    final days = s.resolvedDelayDays(useDueDate: _useDueDate);
    if (days == null) return false;
    // Invoice→cleared cannot be negative; treat as bad sync and exclude everywhere.
    if (!_useDueDate && days < 0) return false;
    return true;
  }

  /// Largest-remainder percents so pie labels always sum to 100.
  static List<int> _largestRemainderPercents(List<int> counts) {
    final total = counts.fold<int>(0, (a, b) => a + b);
    if (total == 0) return List.filled(counts.length, 0);
    final exact = counts.map((c) => c * 100.0 / total).toList();
    final floors = exact.map((e) => e.floor()).toList();
    var rem = 100 - floors.fold<int>(0, (a, b) => a + b);
    final order = List.generate(counts.length, (i) => i)
      ..sort((a, b) {
        final fa = exact[a] - floors[a];
        final fb = exact[b] - floors[b];
        return fb.compareTo(fa);
      });
    for (var i = 0; i < rem; i++) {
      floors[order[i]]++;
    }
    return floors;
  }

  void _applyFilter(List<LedgerBillSettlement> data, String period) {
    _processData(_filterByPeriod(data, period), period);
  }

  void _processData(List<LedgerBillSettlement> data, String period) {
    final bills = data.where(_isAnalyzable).toList();

    _fastCount = 0;
    _modCount = 0;
    _slowCount = 0;
    _totalBills = bills.length;
    _totalAmount = bills.fold<double>(0, (sum, s) => sum + s.billAmount);
    _hasAnalyticsData = bills.isNotEmpty;

    if (!_hasAnalyticsData) {
      _globalAvgDays = 0;
      _fastPct = _modPct = _slowPct = 0;
      _fastestCustomers = [];
      _slowestCustomers = [];
      _allFastestCustomers = [];
      _allSlowestCustomers = [];
      _monthlyTrend = [];
      return;
    }

    double weightedDays = 0;
    double weightSum = 0;
    final ledgerDays = <String, List<int>>{};
    final ledgerWeights = <String, List<double>>{};

    for (final s in bills) {
      final days = s.resolvedDelayDays(useDueDate: _useDueDate)!;
      final amount = s.billAmount.abs() > 0 ? s.billAmount.abs() : 1.0;

      if (days <= 7) {
        _fastCount++;
      } else if (days <= 20) {
        _modCount++;
      } else {
        _slowCount++;
      }

      weightedDays += days * amount;
      weightSum += amount;

      ledgerDays.putIfAbsent(s.ledgerName, () => []).add(days);
      ledgerWeights.putIfAbsent(s.ledgerName, () => []).add(amount);
    }

    _globalAvgDays = weightSum > 0 ? weightedDays / weightSum : 0;

    final pcts = _largestRemainderPercents([_fastCount, _modCount, _slowCount]);
    _fastPct = pcts[0];
    _modPct = pcts[1];
    _slowPct = pcts[2];

    final customerAverages = <Map<String, dynamic>>[];
    for (final entry in ledgerDays.entries) {
      final days = entry.value;
      final weights = ledgerWeights[entry.key]!;
      double wSum = 0;
      double wDays = 0;
      for (var i = 0; i < days.length; i++) {
        wDays += days[i] * weights[i];
        wSum += weights[i];
      }
      customerAverages.add({
        'ledger': entry.key,
        'avgDays': wSum > 0 ? wDays / wSum : 0.0,
        'count': days.length,
      });
    }

    customerAverages
        .sort((a, b) => (a['avgDays'] as double).compareTo(b['avgDays'] as double));
    _allFastestCustomers = List.from(customerAverages);
    _allSlowestCustomers = customerAverages.reversed.toList();
    _fastestCustomers = _allFastestCustomers.take(5).toList();
    _slowestCustomers = _allSlowestCustomers.take(5).toList();

    // Monthly trend — window matches selected period; averages are amount-weighted.
    final now = DateTime.now();
    final monthCount = _trendMonthCount(period).clamp(1, 24);
    final monthlyDays = <String, List<int>>{};
    final monthlyWeights = <String, List<double>>{};
    final monthKeys = <String>[];
    for (int i = monthCount - 1; i >= 0; i--) {
      final month = DateTime(now.year, now.month - i, 1);
      final key = DateFormat('MMM yy').format(month);
      monthKeys.add(key);
      monthlyDays[key] = [];
      monthlyWeights[key] = [];
    }

    for (final s in bills) {
      if (s.clearedDate == null) continue;
      final key = DateFormat('MMM yy').format(s.clearedDate!);
      if (!monthlyDays.containsKey(key)) continue;
      final days = s.resolvedDelayDays(useDueDate: _useDueDate)!;
      final amount = s.billAmount.abs() > 0 ? s.billAmount.abs() : 1.0;
      monthlyDays[key]!.add(days);
      monthlyWeights[key]!.add(amount);
    }

    _monthlyTrend = monthKeys.map((key) {
      final days = monthlyDays[key]!;
      final weights = monthlyWeights[key]!;
      if (days.isEmpty) {
        return {'month': key, 'avg': 0.0, 'count': 0};
      }
      double wDays = 0;
      double wSum = 0;
      for (var i = 0; i < days.length; i++) {
        wDays += days[i] * weights[i];
        wSum += weights[i];
      }
      return {
        'month': key,
        'avg': wSum > 0 ? wDays / wSum : 0.0,
        'count': days.length,
      };
    }).toList();
  }

  Color _getHealthColor(double days) {
    if (!_hasAnalyticsData) return const Color(0xFF94A3B8);
    if (days <= 7) return const Color(0xFF22C55E);
    if (days <= 20) return const Color(0xFFF59E0B);
    return const Color(0xFFEF4444);
  }

  String _getHealthText(double days) {
    if (!_hasAnalyticsData) return 'No data';
    if (days <= 7) return 'Excellent';
    if (days <= 20) return 'Moderate';
    return 'Needs Attention';
  }

  Future<void> _navigateToLedger(BuildContext context, String ledgerName) async {
    final companyName = CompanyProvider.of(context).selectedCompany;
    if (companyName == null) return;

    // Try to fetch ledger details for navigation
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final ledgers = await _service.getLedgersByName(companyName: companyName, ledgerName: ledgerName);
      if (!context.mounted) return;
      Navigator.pop(context); // close loading
      if (ledgers.isNotEmpty) {
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => LedgerStatementScreen(ledger: ledgers.first),
        ));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not find ledger: $ledgerName')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final companyState = CompanyProvider.of(context);
    if (companyState.isCombinedMode) {
      return CombinedModeUnavailable(featureName: 'Payment Speed');
    }
    final isEnabled = companyState.isFeatureEnabled('cash_flow');

    if (!isEnabled) {
      return Scaffold(
        backgroundColor: AppTheme.surfaceColor,
        appBar: AppBar(
          title: Text('Payment Speed',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18, color: AppTheme.textPrimary)),
          backgroundColor: AppTheme.cardColor,
          elevation: 0,
          centerTitle: true,
          iconTheme: IconThemeData(color: AppTheme.textPrimary),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock_rounded, size: 48, color: Color(0xFF2453FF)),
              const SizedBox(height: 12),
              Text('Feature Locked',
                  style: TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 18, color: AppTheme.textPrimary)),
              const SizedBox(height: 8),
              Text('Payment Speed is disabled for this company.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.textSecondary)),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.surfaceColor,
      appBar: AppBar(
        title: Text('Payment Speed',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18, color: AppTheme.textPrimary)),
        backgroundColor: AppTheme.cardColor,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: AppTheme.textPrimary),
        actions: [
          if (!_isLoading)
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              onPressed: () {
                _hasLoaded = false;
                _loadData();
              },
            ),
        ],
      ),
      body: _buildBody(),
    );

  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.primaryColor));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: Colors.red), textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _loadData, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    if (_allSettlements.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.account_balance_wallet_outlined, size: 64, color: AppTheme.textSecondary),
            const SizedBox(height: 12),
            Text('No settlement data available.',
                style: TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.textPrimary)),
            const SizedBox(height: 6),
            Text('Data will appear here once bills are settled.',
                style: TextStyle(color: AppTheme.textSecondary)),
          ],
        ),
      );
    }

    final companyState = CompanyProvider.of(context);
    final showSummary   = companyState.isFeatureEnabled('cf_summary');
    final showOverview  = companyState.isFeatureEnabled('cf_overview');
    final showPieChart  = companyState.isFeatureEnabled('cf_pie_chart');
    final showTrend     = companyState.isFeatureEnabled('cf_trend');
    final showFastest   = companyState.isFeatureEnabled('cf_fastest');
    final showSlowest   = companyState.isFeatureEnabled('cf_slowest');

    return RefreshIndicator(
      onRefresh: _loadData,
      color: AppTheme.primaryColor,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _buildPeriodFilter(),
          if (_tallyRecvTurnoverDays != null) ...[
            const SizedBox(height: 16),
            _buildTallyRecvTurnoverCard(),
          ],
          if (!_hasAnalyticsData) ...[
            const SizedBox(height: 24),
            const EmptyState(
              icon: Icons.date_range_outlined,
              title: 'No bills in this period',
              subtitle: 'Try a wider date range or switch calculation mode.',
            ),
          ] else ...[
            if (showSummary) ...[
              const SizedBox(height: 16),
              _buildSummaryRow(),
            ],
            if (showOverview) ...[
              const SizedBox(height: 16),
              _buildGlobalOverview(),
            ],
            if (showPieChart) ...[
              const SizedBox(height: 16),
              _buildDistributionChart(),
            ],
            if (showTrend) ...[
              const SizedBox(height: 16),
              _buildTrendChart(),
            ],
            if (showFastest) ...[
              const SizedBox(height: 16),
              _buildLeaderboard('🏆 Fastest Paying Customers', _fastestCustomers, _allFastestCustomers, const Color(0xFF22C55E)),
            ],
            if (showSlowest) ...[
              const SizedBox(height: 16),
              _buildLeaderboard('⚠️ Slowest Paying Customers', _slowestCustomers, _allSlowestCustomers, const Color(0xFFEF4444)),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildPeriodFilter() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: _periods.map((p) {
              final selected = _selectedPeriod == p;
              return Padding(
                padding: const EdgeInsets.only(right: 4),
                child: ChoiceChip(
                  label: Text(p),
                  selected: selected,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  labelPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                  onSelected: (_) {
                    setState(() {
                      _selectedPeriod = p;
                      _applyFilter(_allSettlements, p);
                    });
                  },
                  selectedColor: AppTheme.primaryColor,
                  labelStyle: TextStyle(
                    color: selected ? Colors.white : AppTheme.textPrimary,
                    fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                    fontSize: 11.5,
                  ),
                  backgroundColor: AppTheme.cardColor,
                  side: BorderSide(color: AppTheme.dividerColor),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              );
            }).toList(),
          ),
        ),
        SizedBox(height: 16),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: AppTheme.cardColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.dividerColor),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isSmall = constraints.maxWidth < 420;
              final segmentedButton = SegmentedButton<bool>(
                segments: const [
                  ButtonSegment<bool>(value: true, label: Text('Due Date', style: TextStyle(fontSize: 12))),
                  ButtonSegment<bool>(value: false, label: Text('Invoice Date', style: TextStyle(fontSize: 12))),
                ],
                selected: {_useDueDate},
                onSelectionChanged: (Set<bool> newSelection) {
                  setState(() {
                    _useDueDate = newSelection.first;
                    _applyFilter(_allSettlements, _selectedPeriod);
                  });
                },
                style: SegmentedButton.styleFrom(
                  backgroundColor: AppTheme.isDark ? const Color(0xFF243044) : AppTheme.surfaceColor,
                  foregroundColor: AppTheme.textPrimary,
                  selectedForegroundColor: Colors.white,
                  selectedBackgroundColor: AppTheme.primaryColor,
                  visualDensity: VisualDensity.compact,
                ),
              );

              if (isSmall) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Calculate Speed From:',
                      style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textPrimary, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: segmentedButton,
                    ),
                  ],
                );
              }

              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Calculate Speed From:',
                    style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textPrimary, fontSize: 13),
                  ),
                  segmentedButton,
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryRow() {
    final fmt = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
    return Row(
      children: [
        Expanded(child: _buildStatCard('Total Bills', '$_totalBills', Icons.receipt_long_rounded, const Color(0xFF6366F1))),
        const SizedBox(width: 12),
        Expanded(child: _buildStatCard('Total Amount', fmt.format(_totalAmount), Icons.currency_rupee_rounded, const Color(0xFF0EA5E9))),
      ],
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTallyRecvTurnoverCard() {
    final days = _tallyRecvTurnoverDays!;
    final periodLabel = (_tallyRatioFrom != null && _tallyRatioTo != null)
        ? '${DateFormat('d MMM yyyy').format(_tallyRatioFrom!)} – ${DateFormat('d MMM yyyy').format(_tallyRatioTo!)}'
        : 'Financial year → today';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 18),
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.dividerColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Recv. Turnover in days (Tally)',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${days.toStringAsFixed(2)} Days',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w800,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            periodLabel,
            style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildGlobalOverview() {
    final healthColor = _getHealthColor(_globalAvgDays);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [healthColor.withValues(alpha: 0.85), healthColor],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: healthColor.withValues(alpha: 0.3), blurRadius: 16, offset: const Offset(0, 6))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_useDueDate ? 'Average Payment Delay' : 'Average Collection Speed',
              style: TextStyle(fontSize: 13, color: Colors.white70, fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          Text(
              _hasAnalyticsData ? '${_globalAvgDays.toStringAsFixed(1)} Days' : '—',
              style: TextStyle(fontSize: 38, fontWeight: FontWeight.w800, color: Colors.white)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(_getHealthText(_globalAvgDays),
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12)),
          ),
        ],
      ),
    );
  }



  Widget _buildDistributionChart() {
    final total = _fastCount + _modCount + _slowCount;
    if (total == 0) return const SizedBox.shrink();

    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Clearance Speed Distribution',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
          const SizedBox(height: 20),
          Row(
            children: [
              SizedBox(
                height: 160,
                width: 160,
                child: PieChart(
                  PieChartData(
                    sectionsSpace: 3,
                    centerSpaceRadius: 45,
                    sections: [
                      PieChartSectionData(
                        color: const Color(0xFF22C55E),
                        value: _fastCount.toDouble(),
                        title: '$_fastPct%',
                        radius: 45,
                        titleStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      PieChartSectionData(
                        color: const Color(0xFFF59E0B),
                        value: _modCount.toDouble(),
                        title: '$_modPct%',
                        radius: 45,
                        titleStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      PieChartSectionData(
                        color: const Color(0xFFEF4444),
                        value: _slowCount.toDouble(),
                        title: '$_slowPct%',
                        radius: 45,
                        titleStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildLegendRow(const Color(0xFF22C55E), '0–7 Days', _fastCount),
                    const SizedBox(height: 16),
                    _buildLegendRow(const Color(0xFFF59E0B), '8–20 Days', _modCount),
                    const SizedBox(height: 16),
                    _buildLegendRow(const Color(0xFFEF4444), '21+ Days', _slowCount),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLegendRow(Color color, String label, int count) {
    return Row(
      children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
        SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
              Text('$count bills', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTrendChart() {
    final hasData = _monthlyTrend.any((m) => (m['count'] as int) > 0);
    if (!hasData) return const SizedBox.shrink();

    final avgs = _monthlyTrend
        .where((m) => (m['count'] as int) > 0)
        .map((m) => m['avg'] as double)
        .toList();
    final maxY = avgs.isEmpty ? 0.0 : avgs.reduce((a, b) => a > b ? a : b);
    final minY = avgs.isEmpty ? 0.0 : avgs.reduce((a, b) => a < b ? a : b);
    final effectiveMaxY = maxY > 0 ? maxY * 1.3 : (minY < 0 ? 5.0 : 30.0);
    final effectiveMinY = minY < 0 ? minY * 1.2 : 0.0;

    final sharedTitlesData = FlTitlesData(
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 28,
          interval: 1,
          getTitlesWidget: (value, meta) {
            final idx = value.round();
            if (idx < 0 || idx >= _monthlyTrend.length) return const SizedBox.shrink();
            if (value != idx.toDouble()) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(_monthlyTrend[idx]['month'],
                  style: TextStyle(fontSize: 10, color: AppTheme.textSecondary)),
            );
          },
        ),
      ),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 32,
          getTitlesWidget: (value, meta) =>
              Text(value.toInt().toString(), style: TextStyle(fontSize: 10, color: AppTheme.textSecondary)),
        ),
      ),
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    );

    final sharedGridData = FlGridData(
      show: true,
      drawVerticalLine: false,
      getDrawingHorizontalLine: (v) =>
          FlLine(color: AppTheme.dividerColor, strokeWidth: 1),
    );

    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Monthly Trend',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
                    Text(_useDueDate ? 'Avg. delay days per month' : 'Avg. collection days per month',
                        style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                  ],
                ),
              ),
              // Toggle bar / line
              Container(
                decoration: BoxDecoration(
                  color: AppTheme.surfaceColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    _buildChartToggleBtn(Icons.bar_chart_rounded, false),
                    _buildChartToggleBtn(Icons.show_chart_rounded, true),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            child: SizedBox(
              key: ValueKey(_trendIsLine),
              height: 200,
              child: _trendIsLine
                  ? LineChart(
                      LineChartData(
                        maxY: effectiveMaxY,
                        minY: effectiveMinY,
                        minX: 0,
                        maxX: (_monthlyTrend.length - 1).toDouble(),
                        clipData: const FlClipData.all(),
                        lineTouchData: LineTouchData(
                          touchTooltipData: LineTouchTooltipData(
                            getTooltipItems: (touchedSpots) {
                              return touchedSpots.map((s) {
                                final m = _monthlyTrend[s.spotIndex];
                                return LineTooltipItem(
                                  '${m['month']}\n${(m['avg'] as double).toStringAsFixed(1)} days\n${m['count']} bills',
                                  TextStyle(color: Colors.white, fontSize: 12),
                                );
                              }).toList();
                            },
                          ),
                        ),
                        titlesData: sharedTitlesData,
                        gridData: sharedGridData,
                        borderData: FlBorderData(show: false),
                        lineBarsData: [
                          LineChartBarData(
                            spots: _monthlyTrend.asMap().entries.map((e) {
                              return FlSpot(e.key.toDouble(), e.value['avg'] as double);
                            }).toList(),
                            isCurved: true,
                            curveSmoothness: 0.35,
                            color: AppTheme.primaryColor,
                            barWidth: 3,
                            isStrokeCapRound: true,
                            dotData: FlDotData(
                              show: true,
                              getDotPainter: (spot, percent, barData, index) {
                                final avg = spot.y;
                                return FlDotCirclePainter(
                                  radius: 5,
                                  color: _getHealthColor(avg),
                                  strokeWidth: 2,
                                  strokeColor: Colors.white,
                                );
                              },
                            ),
                            belowBarData: BarAreaData(
                              show: true,
                              gradient: LinearGradient(
                                colors: [
                                  AppTheme.primaryColor.withValues(alpha: 0.25),
                                  AppTheme.primaryColor.withValues(alpha: 0.0),
                                ],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  : BarChart(
                      BarChartData(
                        alignment: BarChartAlignment.spaceAround,
                        maxY: effectiveMaxY,
                        minY: effectiveMinY,
                        barTouchData: BarTouchData(
                          touchTooltipData: BarTouchTooltipData(
                            getTooltipItem: (group, groupIndex, rod, rodIndex) {
                              final m = _monthlyTrend[groupIndex];
                              return BarTooltipItem(
                                '${m['month']}\n${(m['avg'] as double).toStringAsFixed(1)} days\n${m['count']} bills',
                                TextStyle(color: Colors.white, fontSize: 12),
                              );
                            },
                          ),
                        ),
                        titlesData: sharedTitlesData,
                        gridData: sharedGridData,
                        borderData: FlBorderData(show: false),
                        barGroups: _monthlyTrend.asMap().entries.map((e) {
                          final avg = e.value['avg'] as double;
                          final hasCount = (e.value['count'] as int) > 0;
                          return BarChartGroupData(
                            x: e.key,
                            barRods: [
                              BarChartRodData(
                                fromY: avg < 0 ? avg : 0,
                                toY: avg < 0 ? 0 : (hasCount ? avg : 0),
                                color: _getHealthColor(avg),
                                width: 22,
                                borderRadius: avg < 0
                                    ? const BorderRadius.only(
                                        bottomLeft: Radius.circular(6),
                                        bottomRight: Radius.circular(6),
                                      )
                                    : const BorderRadius.only(
                                        topLeft: Radius.circular(6),
                                        topRight: Radius.circular(6),
                                      ),
                              ),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChartToggleBtn(IconData icon, bool isLine) {
    final selected = _trendIsLine == isLine;
    return GestureDetector(
      onTap: () => setState(() => _trendIsLine = isLine),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppTheme.primaryColor : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 18, color: selected ? Colors.white : AppTheme.textSecondary),
      ),
    );
  }

  Widget _buildLeaderboard(String title, List<Map<String, dynamic>> topCustomers, List<Map<String, dynamic>> allCustomers, Color accentColor) {
    if (topCustomers.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
                    const SizedBox(height: 4),
                    Text('Tap to view ledger', style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                  ],
                ),
              ),
              if (allCustomers.length > 5)
                InkWell(
                  onTap: () {
                    bool isFastest = title.contains('Fastest');
                    Navigator.push(context, MaterialPageRoute(
                      builder: (_) => CustomerRankingScreen(
                        fastestCustomers: _allFastestCustomers,
                        slowestCustomers: _allSlowestCustomers,
                        initialIsFastest: isFastest,
                      ),
                    ));
                  },
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    child: Text('View All', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.primaryColor)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          ...topCustomers.asMap().entries.map((e) {
            final rank = e.key + 1;
            return _buildCustomerRow(rank, e.value, accentColor);
          }),
        ],
      ),
    );
  }

  Widget _buildCustomerRow(int rank, Map<String, dynamic> customer, Color accentColor) {
    final name = customer['ledger'] as String;
    final avgDays = customer['avgDays'] as double;
    final count = customer['count'] as int;
    final color = _getHealthColor(avgDays);

    return InkWell(
      onTap: () => _navigateToLedger(context, name),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text('#$rank', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: accentColor)),
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text('$count bills settled', style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${avgDays.round()}d',
                style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, size: 18, color: AppTheme.textSecondary),
          ],
        ),
      ),
    );
  }
}
