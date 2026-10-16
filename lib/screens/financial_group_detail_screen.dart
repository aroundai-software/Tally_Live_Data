import 'package:flutter/material.dart';
import '../models/ledger.dart';
import '../providers/company_provider.dart';
import '../services/supabase_service.dart';
import '../utils/company_scope.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_state_widget.dart';
import '../widgets/shimmer_loading.dart';
import '../widgets/summary_card.dart';
import '../widgets/combined_mode_unavailable.dart';
import 'ledger_statement_screen.dart';
import '../config/app_theme.dart';

/// Tally Group Summary style: one row per ledger, Closing Balance Debit | Credit.
class FinancialGroupDetailScreen extends StatefulWidget {
  final String groupName;
  final double? groupAmount;
  final String reportTitle;

  const FinancialGroupDetailScreen({
    super.key,
    required this.groupName,
    this.groupAmount,
    this.reportTitle = 'Group Detail',
  });

  @override
  State<FinancialGroupDetailScreen> createState() =>
      _FinancialGroupDetailScreenState();
}

class _FinancialGroupDetailScreenState extends State<FinancialGroupDetailScreen> {
  final SupabaseService _service = SupabaseService();
  bool _isLoading = true;
  String? _error;
  List<Ledger> _children = [];
  final Set<String> _expandableNames = {};
  bool _hasLoaded = false;
  int? _lastCompanyRevision;
  int _loadGeneration = 0;

  static const _debitColWidth = 110.0;
  static const _creditColWidth = 110.0;

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
          _children = [];
        });
      }
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final result = await _service.getLedgersUnderGroupWithMeta(
        companyName: companyName!,
        groupName: widget.groupName,
      );

      if (!mounted ||
          generation != _loadGeneration ||
          !CompanyScope.stillActive(
            companyName,
            CompanyProvider.of(context).selectedCompany,
          )) {
        return;
      }

      setState(() {
        _children = result.children;
        _expandableNames
          ..clear()
          ..addAll(result.expandableNames);
        _isLoading = false;
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

  /// Company-GUID sync: positive closing → Debit, negative → Credit.
  double _debitOf(Ledger ledger) =>
      ledger.closingBalance > 0 ? ledger.closingBalance : 0;
  double _creditOf(Ledger ledger) =>
      ledger.closingBalance < 0 ? ledger.closingBalance.abs() : 0;

  void _openChild(Ledger ledger) {
    if (_expandableNames.contains(ledger.name)) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => FinancialGroupDetailScreen(
            groupName: ledger.name,
            groupAmount: ledger.closingBalance.abs(),
            reportTitle: widget.reportTitle,
          ),
        ),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LedgerStatementScreen(ledger: ledger),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (CompanyProvider.of(context).isCombinedMode) {
      return CombinedModeUnavailable(featureName: 'Financial report');
    }
    return Scaffold(
      backgroundColor: AppTheme.surfaceColor,
      appBar: AppBar(
        title: Text(
          widget.groupName,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
            fontSize: 16,
          ),
        ),
        elevation: 0,
        backgroundColor: AppTheme.cardColor,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: AppTheme.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh_rounded, color: AppTheme.textPrimary),
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
    if (_children.isEmpty) {
      return EmptyState(
        icon: Icons.folder_open_rounded,
        title: 'No ledgers under this group',
        subtitle:
            'Synced ledgers with parent “${widget.groupName}” will appear here.',
        onRetry: _loadData,
      );
    }

    final totalDebit =
        _children.fold<double>(0, (s, l) => s + _debitOf(l));
    final totalCredit =
        _children.fold<double>(0, (s, l) => s + _creditOf(l));

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: EdgeInsets.fromLTRB(12, 16, 12, 32),
        children: [
          Container(
            padding: EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.cardColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.dividerColor),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.reportTitle,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.groupName,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.groupAmount != null)
                  Text(
                    formatCurrency(widget.groupAmount!),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF2453FF),
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(height: 14),
          Container(
            decoration: BoxDecoration(
              color: AppTheme.cardColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.dividerColor),
            ),
            child: Column(
              children: [
                _buildTableHeader(),
                Divider(height: 1, color: AppTheme.dividerColor),
                ..._children.map(_buildChildRow),
                Divider(height: 1, color: AppTheme.dividerColor),
                _buildGrandTotalRow(totalDebit, totalCredit),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 8),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'PARTICULARS',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
              SizedBox(
                width: _debitColWidth + _creditColWidth,
                child: Text(
                  'CLOSING BALANCE',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 22),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Expanded(child: SizedBox()),
              SizedBox(
                width: _debitColWidth,
                child: Text(
                  'Debit',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
              SizedBox(
                width: _creditColWidth,
                child: Text(
                  'Credit',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 22),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildChildRow(Ledger ledger) {
    final isGroup = _expandableNames.contains(ledger.name);
    final debit = _debitOf(ledger);
    final credit = _creditOf(ledger);

    return InkWell(
      onTap: () => _openChild(ledger),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 11, 8, 11),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(
                isGroup
                    ? Icons.folder_outlined
                    : Icons.account_balance_wallet_outlined,
                size: 18,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                ledger.name,
                softWrap: true,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isGroup ? FontWeight.w700 : FontWeight.w500,
                  color: AppTheme.textPrimary,
                  height: 1.25,
                ),
              ),
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: _debitColWidth,
              child: Text(
                debit > 0 ? formatCurrency(debit) : '',
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
            SizedBox(
              width: _creditColWidth,
              child: Text(
                credit > 0 ? formatCurrency(credit) : '',
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: AppTheme.textSecondary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGrandTotalRow(double totalDebit, double totalCredit) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Grand Total',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
          SizedBox(
            width: _debitColWidth,
            child: Text(
              totalDebit > 0 ? formatCurrency(totalDebit) : '',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: AppTheme.textPrimary,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          SizedBox(
            width: _creditColWidth,
            child: Text(
              totalCredit > 0 ? formatCurrency(totalCredit) : '',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: AppTheme.textPrimary,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(width: 18),
        ],
      ),
    );
  }
}
