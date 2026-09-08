import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../models/ledger_bill_settlement.dart';
import '../services/supabase_service.dart';
import '../providers/company_provider.dart';
import '../config/app_theme.dart';

class LedgerPerformanceTab extends StatefulWidget {
  final String ledgerName;
  
  const LedgerPerformanceTab({super.key, required this.ledgerName});

  @override
  State<LedgerPerformanceTab> createState() => _LedgerPerformanceTabState();
}

class _LedgerPerformanceTabState extends State<LedgerPerformanceTab> {
  final SupabaseService _service = SupabaseService();
  bool _isLoading = true;
  String? _error;
  List<LedgerBillSettlement> _settlements = [];
  double _avgDaysToClear = 0;
  double _avgDelay = 0;
  List<Map<String, dynamic>> _monthlyTrend = [];
  bool _hasLoaded = false;

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
      final companyState = CompanyProvider.of(context);
      final data = await _service.getBillSettlementsForLedger(companyState.selectedCompany!, widget.ledgerName);
      
      final now = DateTime.now();
      Map<String, List<int>> monthlyMap = {};
      for (int i = 5; i >= 0; i--) {
        final month = DateTime(now.year, now.month - i, 1);
        final key = DateFormat('MMM yy').format(month);
        monthlyMap[key] = [];
      }

      double totalDaysToClear = 0;
      int validClear = 0;
      double totalDelay = 0;
      int validDelay = 0;
      for (var s in data) {
        if (s.daysToClear != null && s.daysToClear! > 0) {
          totalDaysToClear += s.daysToClear!;
          validClear++;
        }
        if (s.daysFromDueDate != null) {
          totalDelay += s.daysFromDueDate!;
          validDelay++;
          
          if (s.clearedDate != null) {
            final key = DateFormat('MMM yy').format(s.clearedDate!);
            if (monthlyMap.containsKey(key)) {
              monthlyMap[key]!.add(s.daysFromDueDate!);
            }
          }
        }
      }

      final monthlyTrend = monthlyMap.entries.map((e) {
        final avg = e.value.isEmpty ? 0.0 : e.value.fold(0, (sum, val) => sum + val) / e.value.length;
        return {'month': e.key, 'avg': avg, 'count': e.value.length};
      }).toList();
      
      setState(() {
        _settlements = data;
        _avgDaysToClear = validClear > 0 ? totalDaysToClear / validClear : 0;
        _avgDelay = validDelay > 0 ? totalDelay / validDelay : 0;
        _monthlyTrend = monthlyTrend;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _isLoading = false; });
    }
  }

  Color _getHealthColor(double days) {
    if (days <= 7) return Colors.green;
    if (days <= 20) return Colors.orange;
    return Colors.red;
  }

  String _getHealthText(double days) {
    if (days <= 7) return "Excellent Payer";
    if (days <= 20) return "Moderate Delay";
    return "High Risk / Late Payer";
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text(_error!, style: const TextStyle(color: Colors.red)));
    if (_settlements.isEmpty) {
      return const Center(child: Text("No settlement history available for this ledger."));
    }

    final companyState = CompanyProvider.of(context);
    final showSpeed   = companyState.isFeatureEnabled('ls_perf_speed');
    final showDelay   = companyState.isFeatureEnabled('ls_perf_delay');
    final showTrend   = companyState.isFeatureEnabled('ls_perf_trend');
    final showHistory = companyState.isFeatureEnabled('ls_perf_history');

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (showSpeed || showDelay) ...[
          _buildSummaryCard(showSpeed: showSpeed, showDelay: showDelay),
          const SizedBox(height: 24),
        ],
        if (showTrend) ...[
          _buildTrendChart(),
          const SizedBox(height: 24),
        ],
        if (showHistory) ...[
          const Text('Settlement History', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A1F36))),
          const SizedBox(height: 12),
          ..._settlements.map((s) => _buildSettlementCard(s)).toList(),
        ],
      ],
    );
  }

  Widget _buildSummaryCard({bool showSpeed = true, bool showDelay = true}) {
    if (showSpeed && showDelay) {
      return Row(
        children: [
          Expanded(child: _buildMetricCard('Avg Collection Speed', _avgDaysToClear, true)),
          const SizedBox(width: 12),
          Expanded(child: _buildMetricCard('Avg Payment Delay', _avgDelay, false)),
        ],
      );
    } else if (showSpeed) {
      return _buildMetricCard('Avg Collection Speed', _avgDaysToClear, true);
    } else {
      return _buildMetricCard('Avg Payment Delay', _avgDelay, false);
    }
  }

  Widget _buildMetricCard(String title, double days, bool isCollectionSpeed) {
    // For delay, <=0 is excellent (paid on time or early)
    // For collection speed, <= 7 is excellent.
    Color healthColor;
    String healthText;
    
    if (isCollectionSpeed) {
      healthColor = _getHealthColor(days);
      healthText = _getHealthText(days);
    } else {
      if (days <= 0) {
        healthColor = Colors.green;
        healthText = "On Time";
      } else if (days <= 10) {
        healthColor = Colors.orange;
        healthText = "Slight Delay";
      } else {
        healthColor = Colors.red;
        healthText = "High Delay";
      }
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        children: [
          Text(title, style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500), textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(
            '${days.round()} Days',
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF1A1F36)),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: healthColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
            child: Text(
              healthText,
              style: TextStyle(color: healthColor, fontWeight: FontWeight.bold, fontSize: 11),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrendChart() {
    if (_monthlyTrend.isEmpty || _monthlyTrend.every((m) => m['count'] == 0)) return const SizedBox.shrink();

    final maxY = _monthlyTrend
        .map((m) => (m['avg'] as double))
        .fold(0.0, (a, b) => a > b ? a : b);
    final effectiveMaxY = maxY > 0 ? maxY * 1.3 : 30.0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Payment Delay Trend (6 Months)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A1F36))),
          const SizedBox(height: 24),
          SizedBox(
            height: 200,
            child: LineChart(
              LineChartData(
                maxY: effectiveMaxY,
                minY: 0,
                minX: 0,
                maxX: (_monthlyTrend.length - 1).toDouble(),
                clipData: const FlClipData.all(),
                lineTouchData: LineTouchData(
                  handleBuiltInTouches: true,
                  touchSpotThreshold: 30,
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (touchedSpot) => const Color(0xFF1A1F36).withValues(alpha: 0.9),
                    tooltipPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    tooltipRoundedRadius: 8,
                    getTooltipItems: (touchedSpots) {
                      return touchedSpots.map((s) {
                        final m = _monthlyTrend[s.spotIndex];
                        return LineTooltipItem(
                          '${m['month']}\n',
                          const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w500),
                          children: [
                            TextSpan(
                              text: '${(m['avg'] as double).round()} Days\n',
                              style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                            ),
                            TextSpan(
                              text: '${m['count']} bills',
                              style: const TextStyle(color: Colors.white54, fontSize: 10),
                            ),
                          ],
                        );
                      }).toList();
                    },
                  ),
                ),
                titlesData: FlTitlesData(
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
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (v) =>
                      FlLine(color: Colors.grey.withValues(alpha: 0.15), strokeWidth: 1),
                ),
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
                    dotData: FlDotData(show: true),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        colors: [
                          AppTheme.primaryColor.withValues(alpha: 0.3),
                          AppTheme.primaryColor.withValues(alpha: 0.0),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettlementCard(LedgerBillSettlement s) {
    final formatCurrency = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);
    final formatDate = DateFormat('dd MMM yyyy');
    
    final days = s.daysToClear ?? 0;
    final healthColor = _getHealthColor(days.toDouble());

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(s.billReference, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                Text(formatCurrency.format(s.billAmount), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Billed: ${s.billDate != null ? formatDate.format(s.billDate!) : 'N/A'}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    Text('Cleared: ${s.clearedDate != null ? formatDate.format(s.clearedDate!) : 'N/A'}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: healthColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                  child: Text(
                    'Took $days Days',
                    style: TextStyle(color: healthColor, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}
