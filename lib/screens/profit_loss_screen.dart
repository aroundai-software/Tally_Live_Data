import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/financial_report.dart';
import '../providers/company_provider.dart';
import '../services/supabase_service.dart';
import '../utils/company_scope.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_state_widget.dart';
import '../widgets/shimmer_loading.dart';
import '../widgets/summary_card.dart';
import '../widgets/tally_report_table.dart';
import '../widgets/combined_mode_unavailable.dart';
import 'financial_group_detail_screen.dart';

class ProfitLossScreen extends StatefulWidget {
  const ProfitLossScreen({super.key});

  @override
  State<ProfitLossScreen> createState() => _ProfitLossScreenState();
}

class _ProfitLossScreenState extends State<ProfitLossScreen> {
  final SupabaseService _service = SupabaseService();
  bool _isLoading = true;
  String? _error;
  ProfitLossReport? _report;
  bool _hasLoaded = false;
  int? _lastCompanyRevision;
  int? _lastSyncTrigger;
  int _loadGeneration = 0;

  final _dateFmt = DateFormat('dd MMM yyyy');

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
      // Background refresh after sync — keep current numbers on screen.
      _loadData(showLoading: false);
    }
  }

  bool _sameReport(ProfitLossReport? a, ProfitLossReport? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return false;
    if (a.id != b.id || a.syncedAt != b.syncedAt) return false;
    if (a.nettProfit != b.nettProfit || a.grossProfit != b.grossProfit) {
      return false;
    }
    if (a.fromDate != b.fromDate || a.toDate != b.toDate) return false;
    if (a.lines.length != b.lines.length) return false;
    for (var i = 0; i < a.lines.length; i++) {
      final x = a.lines[i];
      final y = b.lines[i];
      if (x.particulars != y.particulars ||
          x.amount != y.amount ||
          x.sortOrder != y.sortOrder) {
        return false;
      }
    }
    return true;
  }

  Future<void> _loadData({bool showLoading = true}) async {
    final generation = ++_loadGeneration;
    final companyName = CompanyProvider.of(context).selectedCompany;
    if (!CompanyScope.isValid(companyName)) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'No company selected';
          _report = null;
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
      final report = await _service.getProfitLossReport(companyName!);
      if (!mounted ||
          generation != _loadGeneration ||
          !CompanyScope.stillActive(
            companyName,
            CompanyProvider.of(context).selectedCompany,
          )) {
        return;
      }
      final unchanged = _sameReport(_report, report);
      if (unchanged && !showLoading && _error == null) {
        return;
      }
      setState(() {
        if (!unchanged) _report = report;
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
          // Keep prior report visible on background refresh failures.
          if (showLoading || _report == null) {
            _error = e.toString();
          }
          _isLoading = false;
        });
      }
    }
  }

  void _openSummary(TallyReportRow row) {
    final group = row.drillGroupName;
    if (group == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FinancialGroupDetailScreen(
          groupName: group,
          groupAmount: row.amount,
          reportTitle: 'Profit & Loss',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (CompanyProvider.of(context).isCombinedMode) {
      return const CombinedModeUnavailable(featureName: 'Profit & Loss');
    }
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        title: const Text(
          'Profit & Loss',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: Color(0xFF0F1A2B),
            fontSize: 16,
          ),
        ),
        elevation: 0,
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF0F1A2B)),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Color(0xFF0F1A2B)),
            tooltip: 'Refresh',
            onPressed: _isLoading ? null : _loadData,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: ShimmerLoading(itemCount: 8),
      );
    }
    if (_error != null) {
      return ErrorStateWidget(error: _error, onRetry: _loadData);
    }
    final report = _report;
    if (report == null || report.lines.isEmpty) {
      return EmptyState(
        icon: Icons.trending_up_rounded,
        title: 'No Profit & Loss yet',
        subtitle: 'Run a sync with Tally open to load this report.',
        onRetry: _loadData,
      );
    }

    final cols = buildProfitLossColumns(report.lines);
    final isLoss = cols.nettProfit < 0;
    final nettLabel = isLoss ? 'Nett Loss' : 'Nett Profit';
    final nettColor =
        isLoss ? const Color(0xFFC2372A) : const Color(0xFF0DA6A0);

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 32),
        children: [
          _buildMetaCard(report),
          const SizedBox(height: 12),
          _buildNettBanner(nettLabel, cols.nettProfit.abs(), nettColor),
          const SizedBox(height: 14),
          TallyReportTable(
            leftTitle: 'Particulars',
            rightTitle: 'Particulars',
            leftLines: cols.left,
            rightLines: cols.right,
            leftTotalLabel: 'Total',
            rightTotalLabel: 'Total',
            leftTotal: cols.leftTotal,
            rightTotal: cols.rightTotal,
            leftAccent: const Color(0xFFC2372A),
            rightAccent: const Color(0xFF0DA6A0),
            onOpenSummary: _openSummary,
          ),
        ],
      ),
    );
  }

  Widget _buildMetaCard(ProfitLossReport report) {
    final synced = report.syncedAt != null
        ? _dateFmt.format(report.syncedAt!.toLocal())
        : '—';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE4E9F1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            report.companyName,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F1A2B),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${_dateFmt.format(report.fromDate)}  →  ${_dateFmt.format(report.toDate)}',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Color(0xFF6B7A94),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Synced $synced',
            style: const TextStyle(fontSize: 11, color: Color(0xFF6B7A94)),
          ),
        ],
      ),
    );
  }

  Widget _buildNettBanner(String label, double value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE4E9F1)),
      ),
      child: Row(
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
              color: color,
            ),
          ),
          const Spacer(),
          Text(
            formatCurrency(value),
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F1A2B),
            ),
          ),
        ],
      ),
    );
  }
}
