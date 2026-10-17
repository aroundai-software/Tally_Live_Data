import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../config/app_theme.dart';
import '../providers/company_provider.dart';
import '../services/supabase_service.dart';
import '../utils/company_scope.dart';
import '../widgets/combined_mode_unavailable.dart';
import '../widgets/empty_state.dart';
import 'cash_flow_summary_screen.dart';

class CashFlowScreen extends StatefulWidget {
  const CashFlowScreen({super.key});

  @override
  State<CashFlowScreen> createState() => _CashFlowScreenState();
}

class _CashFlowScreenState extends State<CashFlowScreen> {
  final SupabaseService _service = SupabaseService();
  bool _isLoading = true;
  String? _error;
  Map<String, dynamic>? _snapshot;
  bool _hasLoaded = false;
  int? _lastCompanyRevision;
  int? _lastSyncTrigger;
  int _loadGeneration = 0;

  final _dateFmt = DateFormat('d MMM yyyy');
  final _amtFmt = NumberFormat('#,##0.00');

  static const _inflowColor = Color(0xFFE11D48);
  static const _outflowColor = Color(0xFF2563EB);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = CompanyProvider.of(context);
    final revision = state.companyRevision;
    final syncTrigger = state.syncTrigger;
    if (!_hasLoaded) {
      _hasLoaded = true;
      _lastCompanyRevision = revision;
      _lastSyncTrigger = syncTrigger;
      _loadData(showLoading: true);
    } else if (_lastCompanyRevision != revision) {
      _lastCompanyRevision = revision;
      _lastSyncTrigger = syncTrigger;
      _loadData(showLoading: true);
    } else if (_lastSyncTrigger != syncTrigger) {
      _lastSyncTrigger = syncTrigger;
      _loadData(showLoading: false);
    }
  }

  Future<void> _loadData({bool showLoading = true}) async {
    final generation = ++_loadGeneration;
    final companyName = CompanyProvider.of(context).selectedCompany;
    if (!CompanyScope.isValid(companyName)) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'No company selected';
          _snapshot = null;
        });
      }
      return;
    }

    if (showLoading) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      final snap = await _service.getTallyCashFlow(companyName!);
      if (!mounted ||
          generation != _loadGeneration ||
          !CompanyScope.stillActive(
            companyName,
            CompanyProvider.of(context).selectedCompany,
          )) {
        return;
      }
      setState(() {
        _snapshot = snap;
        _isLoading = false;
        _error = null;
      });
    } catch (e) {
      if (mounted &&
          generation == _loadGeneration &&
          CompanyScope.stillActive(
            companyName,
            CompanyProvider.of(context).selectedCompany,
          )) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  List<Map<String, dynamic>> get _months {
    final raw = _snapshot?['months'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  double _num(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return DateTime(value.year, value.month, value.day);
    final s = value.toString();
    if (s.length < 10) return null;
    return DateTime.tryParse(s.substring(0, 10));
  }

  String _fmtAmt(double v) {
    if (v == 0) return '';
    return _amtFmt.format(v);
  }

  bool _hasSummary(Map<String, dynamic> m) {
    final summary = m['summary'];
    if (summary is! Map) return false;
    final inLines = summary['inflow_lines'];
    final outLines = summary['outflow_lines'];
    return (inLines is List && inLines.isNotEmpty) ||
        (outLines is List && outLines.isNotEmpty) ||
        _num(summary['total_inflow']) > 0 ||
        _num(summary['total_outflow']) > 0;
  }

  void _openSummary(Map<String, dynamic> m) {
    if (!_hasSummary(m)) return;
    final period = m['period']?.toString() ?? '';
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CashFlowSummaryScreen(
          periodLabel: period,
          summary: Map<String, dynamic>.from(m['summary'] as Map),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final companyState = CompanyProvider.of(context);
    if (companyState.isCombinedMode) {
      return CombinedModeUnavailable(featureName: 'Cash Flow');
    }
    final isEnabled = companyState.isFeatureEnabled('tally_cash_flow');

    if (!isEnabled) {
      return Scaffold(
        backgroundColor: AppTheme.surfaceColor,
        appBar: AppBar(
          title: Text(
            'Cash Flow',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 18,
              color: AppTheme.textPrimary,
            ),
          ),
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
              Text(
                'Feature Locked',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Cash Flow is disabled for this company.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textSecondary),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.surfaceColor,
      appBar: AppBar(
        title: Text(
          'Cash Flow',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: AppTheme.textPrimary,
          ),
        ),
        backgroundColor: AppTheme.cardColor,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: AppTheme.textPrimary),
        actions: [
          if (!_isLoading)
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              onPressed: () => _loadData(showLoading: true),
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primaryColor),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => _loadData(showLoading: true),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final months = _months;
    if (_snapshot == null || months.isEmpty) {
      return const EmptyState(
        icon: Icons.waterfall_chart_outlined,
        title: 'No Cash Flow data yet',
        subtitle: 'Data appears after the next sync from Tally.',
      );
    }

    final from = _parseDate(_snapshot!['from_date']);
    final to = _parseDate(_snapshot!['to_date']);
    final periodLabel = (from != null && to != null)
        ? '${_dateFmt.format(from)} to ${_dateFmt.format(to)}'
        : '';
    final totalIn = _num(_snapshot!['total_inflow']);
    final totalOut = _num(_snapshot!['total_outflow']);
    final totalNett = _num(_snapshot!['total_nett']);

    return RefreshIndicator(
      onRefresh: () => _loadData(showLoading: false),
      color: AppTheme.primaryColor,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          if (periodLabel.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                periodLabel,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary,
                ),
              ),
            ),
          _buildTable(months, totalIn, totalOut, totalNett),
          const SizedBox(height: 20),
          _buildChart(months),
        ],
      ),
    );
  }

  Widget _buildTable(
    List<Map<String, dynamic>> months,
    double totalIn,
    double totalOut,
    double totalNett,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.dividerColor),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.isDark
                  ? const Color(0xFF243044)
                  : const Color(0xFFF1F5F9),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text(
                    'Particulars',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
                Expanded(
                  flex: 5,
                  child: Column(
                    children: [
                      Text(
                        'Cash Movement',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Inflow',
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 11,
                                color: _inflowColor,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              'Outflow',
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 11,
                                color: _outflowColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    'Nett Flow',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          ...months.map((m) {
            final inflow = _num(m['inflow']);
            final outflow = _num(m['outflow']);
            final nett = _num(m['nett']);
            final period = m['period']?.toString() ?? '';
            final hasSummary = _hasSummary(m);
            return _row(
              period,
              inflow,
              outflow,
              nett,
              bold: false,
              showChevron: hasSummary,
              onTap: hasSummary ? () => _openSummary(m) : null,
            );
          }),
          Divider(height: 1, color: AppTheme.dividerColor),
          _row('Grand Total', totalIn, totalOut, totalNett, bold: true),
        ],
      ),
    );
  }

  Widget _row(
    String label,
    double inflow,
    double outflow,
    double nett, {
    required bool bold,
    bool showChevron = false,
    VoidCallback? onTap,
  }) {
    final weight = bold ? FontWeight.w800 : FontWeight.w500;
    final nettColor = nett >= 0 ? const Color(0xFF16A34A) : const Color(0xFFDC2626);
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontWeight: weight,
                      fontSize: 13,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
                if (showChevron)
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: AppTheme.textSecondary,
                  ),
              ],
            ),
          ),
          Expanded(
            flex: 5,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _fmtAmt(inflow),
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontWeight: weight,
                      fontSize: 12.5,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    _fmtAmt(outflow),
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontWeight: weight,
                      fontSize: 12.5,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              nett == 0 && !bold ? '' : _amtFmt.format(nett),
              textAlign: TextAlign.right,
              style: TextStyle(
                fontWeight: weight,
                fontSize: 12.5,
                color: bold ? AppTheme.textPrimary : nettColor,
              ),
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return row;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: row,
      ),
    );
  }

  Widget _buildChart(List<Map<String, dynamic>> months) {
    if (months.isEmpty) return const SizedBox.shrink();

    double maxY = 0;
    for (final m in months) {
      maxY = [maxY, _num(m['inflow']), _num(m['outflow'])].reduce((a, b) => a > b ? a : b);
    }
    if (maxY <= 0) maxY = 1;
    maxY *= 1.15;

    final short = months.map((m) {
      final p = (m['period']?.toString() ?? '');
      return p.length >= 3 ? p.substring(0, 3) : p;
    }).toList();

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Cash Movement',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _legendDot(_inflowColor, 'Inflow'),
              const SizedBox(width: 16),
              _legendDot(_outflowColor, 'Outflow'),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 220,
            child: BarChart(
              BarChartData(
                maxY: maxY,
                alignment: BarChartAlignment.spaceAround,
                barTouchData: BarTouchData(
                  touchCallback: (event, response) {
                    if (!event.isInterestedForInteractions) return;
                    final i = response?.spot?.touchedBarGroupIndex;
                    if (i == null || i < 0 || i >= months.length) return;
                    if (event is FlTapUpEvent) {
                      _openSummary(months[i]);
                    }
                  },
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      final label = rodIndex == 0 ? 'Inflow' : 'Outflow';
                      return BarTooltipItem(
                        '$label\n${_amtFmt.format(rod.toY)}',
                        const TextStyle(color: Colors.white, fontSize: 11),
                      );
                    },
                  ),
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 42,
                      getTitlesWidget: (value, meta) {
                        if (value <= 0 || value >= maxY) {
                          return const SizedBox.shrink();
                        }
                        final k = value / 1000;
                        final label = k >= 1000
                            ? '${(k / 1000).toStringAsFixed(1)}M'
                            : '${k.toStringAsFixed(0)}K';
                        return Text(
                          label,
                          style: TextStyle(fontSize: 9, color: AppTheme.textSecondary),
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        final i = value.toInt();
                        if (i < 0 || i >= short.length) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            short[i],
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: AppTheme.dividerColor.withValues(alpha: 0.6),
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
                barGroups: List.generate(months.length, (i) {
                  return BarChartGroupData(
                    x: i,
                    barsSpace: 2,
                    barRods: [
                      BarChartRodData(
                        toY: _num(months[i]['inflow']),
                        color: _inflowColor,
                        width: 7,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                      ),
                      BarChartRodData(
                        toY: _num(months[i]['outflow']),
                        color: _outflowColor,
                        width: 7,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                      ),
                    ],
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
        ),
      ],
    );
  }
}
