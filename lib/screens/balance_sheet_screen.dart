import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/financial_report.dart';
import '../providers/company_provider.dart';
import '../services/supabase_service.dart';
import '../utils/company_scope.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_state_widget.dart';
import '../widgets/shimmer_loading.dart';
import '../widgets/tally_report_table.dart';
import 'financial_group_detail_screen.dart';
import 'ledger_statement_screen.dart';
import '../models/ledger.dart';

class BalanceSheetScreen extends StatefulWidget {
  const BalanceSheetScreen({super.key});

  @override
  State<BalanceSheetScreen> createState() => _BalanceSheetScreenState();
}

class _BalanceSheetScreenState extends State<BalanceSheetScreen> {
  final SupabaseService _service = SupabaseService();
  bool _isLoading = true;
  String? _error;
  BalanceSheetReport? _report;
  bool _hasLoaded = false;
  int? _lastCompanyRevision;
  int? _lastSyncTrigger;
  int _loadGeneration = 0;

  final Set<String> _expandedGroups = {};
  final Set<String> _loadingGroups = {};
  final Map<String, List<TallyChildRow>> _groupChildren = {};
  final Map<String, Ledger> _childLedgersByName = {};

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
      _loadData();
    } else if (_lastCompanyRevision != revision || _lastSyncTrigger != syncTrigger) {
      _lastCompanyRevision = revision;
      _lastSyncTrigger = syncTrigger;
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
          _report = null;
        });
      }
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final report = await _service.getBalanceSheetReport(companyName!);
      if (!mounted ||
          generation != _loadGeneration ||
          !CompanyScope.stillActive(
            companyName,
            CompanyProvider.of(context).selectedCompany,
          )) {
        return;
      }
      setState(() {
        _report = report;
        _isLoading = false;
        _expandedGroups.clear();
        _loadingGroups.clear();
        _groupChildren.clear();
        _childLedgersByName.clear();
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

  Future<void> _toggleExpand(String groupName) async {
    if (_expandedGroups.contains(groupName)) {
      setState(() => _expandedGroups.remove(groupName));
      return;
    }

    setState(() {
      _expandedGroups.add(groupName);
      if (!_groupChildren.containsKey(groupName)) {
        _loadingGroups.add(groupName);
      }
    });

    if (_groupChildren.containsKey(groupName)) return;

    final companyName = CompanyProvider.of(context).selectedCompany;
    if (!CompanyScope.isValid(companyName)) {
      setState(() => _loadingGroups.remove(groupName));
      return;
    }

    try {
      final result = await _service.getLedgersUnderGroupWithMeta(
        companyName: companyName!,
        groupName: groupName,
      );
      if (!mounted) return;
      setState(() {
        _loadingGroups.remove(groupName);
        _groupChildren[groupName] = result.children
            .map((l) {
              _childLedgersByName[l.name] = l;
              // Company-GUID closing: +Debit / −Credit; BS Gateway shows opposite sign.
              return TallyChildRow(
                name: l.name,
                signedAmount: -l.closingBalance,
                isGroup: result.expandableNames.contains(l.name),
              );
            })
            .toList();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingGroups.remove(groupName);
        _groupChildren[groupName] = const [];
      });
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
          reportTitle: 'Balance Sheet',
        ),
      ),
    );
  }

  void _onChildTap(TallyChildRow child) {
    if (child.isGroup) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => FinancialGroupDetailScreen(
            groupName: child.name,
            groupAmount: child.signedAmount.abs(),
            reportTitle: 'Balance Sheet',
          ),
        ),
      );
      return;
    }
    final ledger = _childLedgersByName[child.name];
    if (ledger == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LedgerStatementScreen(ledger: ledger),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        title: const Text(
          'Balance Sheet',
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
        icon: Icons.account_balance_outlined,
        title: 'No Balance Sheet yet',
        subtitle: 'Run a sync with Tally open to load this report.',
        onRetry: _loadData,
      );
    }

    final cols = buildBalanceSheetColumns(report.lines);

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 32),
        children: [
          _buildMetaCard(report),
          const SizedBox(height: 14),
          TallyReportTable(
            leftTitle: 'Liabilities',
            rightTitle: 'Assets',
            leftLines: cols.left,
            rightLines: cols.right,
            leftTotalLabel: 'Total',
            rightTotalLabel: 'Total',
            leftTotal: cols.leftTotal,
            rightTotal: cols.rightTotal,
            leftAccent: const Color(0xFFB45309),
            rightAccent: const Color(0xFF0F766E),
            expandedGroups: _expandedGroups,
            loadingGroups: _loadingGroups,
            groupChildren: _groupChildren,
            onToggleExpand: _toggleExpand,
            onOpenSummary: _openSummary,
            onChildTap: _onChildTap,
          ),
        ],
      ),
    );
  }

  Widget _buildMetaCard(BalanceSheetReport report) {
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
            'As on ${_dateFmt.format(report.asOnDate)}',
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
}
