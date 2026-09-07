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
import '../config/app_theme.dart';

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
  int _totalBills = 0;
  double _totalAmount = 0;
  List<Map<String, dynamic>> _fastestCustomers = [];
  List<Map<String, dynamic>> _slowestCustomers = [];
  List<Map<String, dynamic>> _allFastestCustomers = [];
  List<Map<String, dynamic>> _allSlowestCustomers = [];
  List<Map<String, dynamic>> _monthlyTrend = [];

  // Filter
  String _selectedPeriod = 'All';
  final List<String> _periods = ['All', 'Last 3 Months', 'Last 6 Months', 'This Year'];

  bool _hasLoaded = false;
  bool _trendIsLine = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_hasLoaded) {
      _hasLoaded = true;
      _loadData();
    }
  }

  Future<void> _loadData() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final companyName = CompanyProvider.of(context).selectedCompany;
      if (companyName == null) throw 'No company selected';

      final data = await _service.getBillSettlements(companyName);

      if (mounted) {
        _applyFilter(data, _selectedPeriod);
        setState(() {
          _allSettlements = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _isLoading = false; });
    }
  }

  void _applyFilter(List<LedgerBillSettlement> data, String period) {
    final now = DateTime.now();
    List<LedgerBillSettlement> filtered;

    switch (period) {
      case 'Last 3 Months':
        final cutoff = DateTime(now.year, now.month - 3, now.day);
        filtered = data.where((s) => s.clearedDate != null && s.clearedDate!.isAfter(cutoff)).toList();
        break;
      case 'Last 6 Months':
        final cutoff = DateTime(now.year, now.month - 6, now.day);
        filtered = data.where((s) => s.clearedDate != null && s.clearedDate!.isAfter(cutoff)).toList();
        break;
      case 'This Year':
        filtered = data.where((s) => s.clearedDate != null && s.clearedDate!.year == now.year).toList();
        break;
      default:
        filtered = data;
    }

    _processData(filtered);
  }

  void _processData(List<LedgerBillSettlement> data) {
    // Only consider bills with daysToClear > 0 to exclude instant/same-day payments from speed ranking
    final billsWithDelay = data.where((s) => s.daysToClear != null).toList();
    final billsForAvg = data.where((s) => s.daysToClear != null && s.daysToClear! > 0).toList();

    double totalDays = 0;
    _fastCount = 0;
    _modCount = 0;
    _slowCount = 0;
    _totalBills = billsWithDelay.length;
    _totalAmount = data.fold(0, (sum, s) => sum + s.billAmount);

    Map<String, List<int>> ledgerDaysMap = {};

    for (var s in billsWithDelay) {
      final days = s.daysToClear!;

      if (days <= 7) {
        _fastCount++;
      } else if (days <= 20) {
        _modCount++;
      } else {
        _slowCount++;
      }

      if (!ledgerDaysMap.containsKey(s.ledgerName)) {
        ledgerDaysMap[s.ledgerName] = [];
      }
      ledgerDaysMap[s.ledgerName]!.add(days);
    }

    for (var s in billsForAvg) {
      totalDays += s.daysToClear!;
    }
    _globalAvgDays = billsForAvg.isNotEmpty ? totalDays / billsForAvg.length : 0;

    // Customer ranking - only use records with >0 days to exclude same-day clears
    List<Map<String, dynamic>> customerAverages = [];
    ledgerDaysMap.forEach((ledger, days) {
      final nonZero = days.where((d) => d > 0).toList();
      if (nonZero.isEmpty) return;
      double avg = nonZero.fold(0, (sum, val) => sum + val) / nonZero.length;
      customerAverages.add({'ledger': ledger, 'avgDays': avg, 'count': nonZero.length});
    });

    customerAverages.sort((a, b) => (a['avgDays'] as double).compareTo(b['avgDays'] as double));
    _allFastestCustomers = List.from(customerAverages);
    _allSlowestCustomers = customerAverages.reversed.toList();
    _fastestCustomers = _allFastestCustomers.take(5).toList();
    _slowestCustomers = _allSlowestCustomers.take(5).toList();

    // Monthly trend (last 6 months)
    final now = DateTime.now();
    Map<String, List<int>> monthlyMap = {};
    for (int i = 5; i >= 0; i--) {
      final month = DateTime(now.year, now.month - i, 1);
      final key = DateFormat('MMM').format(month);
      monthlyMap[key] = [];
    }

    for (var s in billsForAvg) {
      if (s.clearedDate == null) continue;
      final key = DateFormat('MMM').format(s.clearedDate!);
      if (monthlyMap.containsKey(key)) {
        monthlyMap[key]!.add(s.daysToClear!);
      }
    }

    _monthlyTrend = monthlyMap.entries.map((e) {
      final avg = e.value.isEmpty ? 0.0 : e.value.fold(0, (s, v) => s + v) / e.value.length;
      return {'month': e.key, 'avg': avg, 'count': e.value.length};
    }).toList();
  }

  Color _getHealthColor(double days) {
    if (days <= 7) return const Color(0xFF22C55E);
    if (days <= 20) return const Color(0xFFF59E0B);
    return const Color(0xFFEF4444);
  }

  String _getHealthText(double days) {
    if (days <= 7) return "Excellent";
    if (days <= 20) return "Moderate";
    return "Needs Attention";
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
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      appBar: AppBar(
        title: const Text('Cash Flow Insights',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18, color: Color(0xFF1A1F36))),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Color(0xFF1A1F36)),
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
              Text(_error!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _loadData, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    if (_allSettlements.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.account_balance_wallet_outlined, size: 64, color: Colors.grey),
            SizedBox(height: 12),
            Text("No settlement data available.", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            SizedBox(height: 6),
            Text("Data will appear here once bills are settled.", style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      color: AppTheme.primaryColor,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _buildPeriodFilter(),
          const SizedBox(height: 16),
          _buildSummaryRow(),
          const SizedBox(height: 16),
          _buildGlobalOverview(),
          const SizedBox(height: 16),
          _buildDistributionChart(),
          const SizedBox(height: 16),
          _buildTrendChart(),
          const SizedBox(height: 16),
          _buildLeaderboard('🏆 Fastest Paying Customers', _fastestCustomers, _allFastestCustomers, const Color(0xFF22C55E)),
          const SizedBox(height: 16),
          _buildLeaderboard('⚠️ Slowest Paying Customers', _slowestCustomers, _allSlowestCustomers, const Color(0xFFEF4444)),
        ],
      ),
    );
  }

  Widget _buildPeriodFilter() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: _periods.map((p) {
          final selected = _selectedPeriod == p;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(p),
              selected: selected,
              onSelected: (_) {
                setState(() { _selectedPeriod = p; });
                _applyFilter(_allSettlements, p);
                setState(() {});
              },
              selectedColor: AppTheme.primaryColor,
              labelStyle: TextStyle(
                color: selected ? Colors.white : Colors.grey.shade700,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                fontSize: 13,
              ),
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
          );
        }).toList(),
      ),
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1A1F36)),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
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
          const Text('Average Collection Speed',
              style: TextStyle(fontSize: 13, color: Colors.white70, fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          Text('${_globalAvgDays.toStringAsFixed(1)} Days',
              style: const TextStyle(fontSize: 38, fontWeight: FontWeight.w800, color: Colors.white)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(_getHealthText(_globalAvgDays),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12)),
          ),
        ],
      ),
    );
  }



  Widget _buildDistributionChart() {
    final total = _fastCount + _modCount + _slowCount;
    if (total == 0) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Clearance Speed Distribution',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF1A1F36))),
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
                        title: '${((_fastCount / total) * 100).toStringAsFixed(0)}%',
                        radius: 45,
                        titleStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      PieChartSectionData(
                        color: const Color(0xFFF59E0B),
                        value: _modCount.toDouble(),
                        title: '${((_modCount / total) * 100).toStringAsFixed(0)}%',
                        radius: 45,
                        titleStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      PieChartSectionData(
                        color: const Color(0xFFEF4444),
                        value: _slowCount.toDouble(),
                        title: '${((_slowCount / total) * 100).toStringAsFixed(0)}%',
                        radius: 45,
                        titleStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
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
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
              Text('$count bills', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1A1F36))),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTrendChart() {
    final hasData = _monthlyTrend.any((m) => (m['count'] as int) > 0);
    if (!hasData) return const SizedBox.shrink();

    final maxY = _monthlyTrend
        .map((m) => (m['avg'] as double))
        .fold(0.0, (a, b) => a > b ? a : b);
    final effectiveMaxY = maxY > 0 ? maxY * 1.3 : 30.0;

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
                  style: const TextStyle(fontSize: 10, color: Colors.grey)),
            );
          },
        ),
      ),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 32,
          getTitlesWidget: (value, meta) =>
              Text(value.toInt().toString(), style: const TextStyle(fontSize: 10, color: Colors.grey)),
        ),
      ),
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    );

    final sharedGridData = FlGridData(
      show: true,
      drawVerticalLine: false,
      getDrawingHorizontalLine: (v) =>
          FlLine(color: Colors.grey.withValues(alpha: 0.15), strokeWidth: 1),
    );

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Monthly Trend',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF1A1F36))),
                    Text('Avg. collection days per month',
                        style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ),
              // Toggle bar / line
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF4F6FB),
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
                        minY: 0,
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
                                  const TextStyle(color: Colors.white, fontSize: 12),
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
                        barTouchData: BarTouchData(
                          touchTooltipData: BarTouchTooltipData(
                            getTooltipItem: (group, groupIndex, rod, rodIndex) {
                              final m = _monthlyTrend[groupIndex];
                              return BarTooltipItem(
                                '${m['month']}\n${(m['avg'] as double).toStringAsFixed(1)} days\n${m['count']} bills',
                                const TextStyle(color: Colors.white, fontSize: 12),
                              );
                            },
                          ),
                        ),
                        titlesData: sharedTitlesData,
                        gridData: sharedGridData,
                        borderData: FlBorderData(show: false),
                        barGroups: _monthlyTrend.asMap().entries.map((e) {
                          final avg = e.value['avg'] as double;
                          return BarChartGroupData(
                            x: e.key,
                            barRods: [
                              BarChartRodData(
                                toY: avg,
                                color: _getHealthColor(avg),
                                width: 22,
                                borderRadius: const BorderRadius.only(
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
        child: Icon(icon, size: 18, color: selected ? Colors.white : Colors.grey),
      ),
    );
  }

  Widget _buildLeaderboard(String title, List<Map<String, dynamic>> topCustomers, List<Map<String, dynamic>> allCustomers, Color accentColor) {
    if (topCustomers.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
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
                    Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF1A1F36))),
                    const SizedBox(height: 4),
                    const Text('Tap to view ledger', style: TextStyle(fontSize: 11, color: Colors.grey)),
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
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1A1F36)),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text('$count bills settled', style: const TextStyle(fontSize: 11, color: Colors.grey)),
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
            const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}
