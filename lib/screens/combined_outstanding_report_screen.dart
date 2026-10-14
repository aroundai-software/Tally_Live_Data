import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../config/app_theme.dart';
import '../models/receivable_payable.dart';
import '../services/supabase_service.dart';
import '../utils/combined_company_selection.dart';
import '../widgets/combined_report_widgets.dart';
import '../widgets/outstanding_detail_sheet.dart';
import '../widgets/summary_card.dart';

class CombinedOutstandingReportScreen extends StatefulWidget {
  final List<String> companyNames;
  final bool embedded;

  const CombinedOutstandingReportScreen({
    super.key,
    required this.companyNames,
    this.embedded = false,
  });

  @override
  State<CombinedOutstandingReportScreen> createState() =>
      _CombinedOutstandingReportScreenState();
}

class _CombinedOutstandingReportScreenState
    extends State<CombinedOutstandingReportScreen>
    with SingleTickerProviderStateMixin {
  final SupabaseService _service = SupabaseService();
  final _dateFormat = DateFormat('dd MMM yyyy');

  late final List<String> _companies;
  late final String _selectionKey;
  late final TabController _tabs;

  bool _loading = true;
  Object? _error;
  List<OutstandingRecord> _receivables = [];
  List<OutstandingRecord> _payables = [];
  String _search = '';

  @override
  void initState() {
    super.initState();
    _companies = CombinedCompanySelection.normalizeList(widget.companyNames);
    _selectionKey = CombinedCompanySelection.selectionKey(_companies);
    _tabs = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  double _billAmount(OutstandingRecord r) {
    final closing = r.closingBalance.abs();
    if (closing != 0) return closing;
    return r.amount.abs();
  }

  Future<void> _load() async {
    if (!CombinedCompanySelection.isReady(_companies)) {
      setState(() {
        _loading = false;
        _error = 'Select at least 2 companies';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final keyAtStart = _selectionKey;
    try {
      final results = await Future.wait([
        _service.getCombinedOutstandingReceivables(
          companyNames: _companies,
          onFirstPage: (first) {
            if (!mounted || keyAtStart != _selectionKey) return;
            setState(() {
              _receivables = first;
              _loading = false;
            });
          },
        ),
        _service.getCombinedOutstandingPayables(
          companyNames: _companies,
          onFirstPage: (first) {
            if (!mounted || keyAtStart != _selectionKey) return;
            setState(() {
              _payables = first;
              _loading = false;
            });
          },
        ),
      ]);
      if (!mounted || keyAtStart != _selectionKey) return;
      setState(() {
        _receivables = results[0];
        _payables = results[1];
        _loading = false;
      });
    } catch (e) {
      if (!mounted || keyAtStart != _selectionKey) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  List<OutstandingRecord> _filter(List<OutstandingRecord> source) {
    final q = _search.trim().toLowerCase();
    return source.where((r) {
      final company = r.companyName?.trim() ?? '';
      if (company.isNotEmpty && !_companies.contains(company)) return false;
      if (q.isEmpty) return true;
      return r.customerName.toLowerCase().contains(q) ||
          r.invoiceNumber.toLowerCase().contains(q) ||
          company.toLowerCase().contains(q);
    }).toList();
  }

  Map<String, double> _totalsByCompany(List<OutstandingRecord> rows) {
    final map = <String, double>{};
    for (final r in rows) {
      final c = r.companyName?.trim();
      if (c == null || c.isEmpty || !_companies.contains(c)) continue;
      map[c] = (map[c] ?? 0) + _billAmount(r);
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final recv = _filter(_receivables);
    final pay = _filter(_payables);
    final recvTotal =
        _totalsByCompany(recv).values.fold<double>(0, (a, b) => a + b);
    final payTotal =
        _totalsByCompany(pay).values.fold<double>(0, (a, b) => a + b);

    final tabBar = TabBar(
      controller: _tabs,
      labelColor: AppTheme.primaryColor,
      unselectedLabelColor: AppTheme.textSecondary,
      indicatorColor: AppTheme.primaryColor,
      tabs: [
        Tab(text: 'Receivables (${recv.length})'),
        Tab(text: 'Payables (${pay.length})'),
      ],
    );

    final content = _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('$_error'),
                    TextButton(onPressed: _load, child: const Text('Retry')),
                  ],
                ),
              )
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!widget.embedded) ...[
                          Text(
                            _companies.join(' • '),
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],
                        TextField(
                          decoration: InputDecoration(
                            hintText: 'Search party, bill, company',
                            prefixIcon: const Icon(Icons.search),
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide:
                                  BorderSide(color: Colors.grey.shade200),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide:
                                  BorderSide(color: Colors.grey.shade200),
                            ),
                          ),
                          onChanged: (v) => setState(() => _search = v),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: TabBarView(
                      controller: _tabs,
                      children: [
                        _listPane(
                          rows: recv,
                          grandTotal: recvTotal,
                          totalsByCompany: _totalsByCompany(recv),
                          accent: AppTheme.receivableColor,
                          emptyLabel: 'No receivables in this selection',
                          isReceivable: true,
                        ),
                        _listPane(
                          rows: pay,
                          grandTotal: payTotal,
                          totalsByCompany: _totalsByCompany(pay),
                          accent: AppTheme.payableColor,
                          emptyLabel: 'No payables in this selection',
                          isReceivable: false,
                        ),
                      ],
                    ),
                  ),
                ],
              );

    if (widget.embedded) {
      return ColoredBox(
        color: AppTheme.surfaceColor,
        child: Column(
          children: [
            Material(color: Colors.white, child: tabBar),
            Expanded(child: content),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.surfaceColor,
      appBar: AppBar(
        title: const Text(
          'Combined Outstanding',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
            fontSize: 16,
          ),
        ),
        elevation: 0,
        backgroundColor: Colors.white,
        iconTheme: const IconThemeData(color: AppTheme.textPrimary),
        bottom: tabBar,
      ),
      body: content,
    );
  }

  Widget _listPane({
    required List<OutstandingRecord> rows,
    required double grandTotal,
    required Map<String, double> totalsByCompany,
    required Color accent,
    required String emptyLabel,
    required bool isReceivable,
  }) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          CombinedSummaryCard(
            title: 'Grand total',
            value: formatCurrency(grandTotal),
            icon: Icons.account_balance_wallet_outlined,
            color: accent,
            subtitle: '${rows.length} bill${rows.length == 1 ? '' : 's'}',
          ),
          const SizedBox(height: 6),
          CombinedReportBreakdown(
            totalsByCompany: totalsByCompany,
            accent: accent,
          ),
          const SizedBox(height: 8),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Text(
                  emptyLabel,
                  style: const TextStyle(color: AppTheme.textSecondary),
                ),
              ),
            )
          else
            ...rows.map((r) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => showOutstandingDetailSheet(
                      context: context,
                      record: r,
                      isReceivable: isReceivable,
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  r.customerName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                              Text(
                                formatCurrency(_billAmount(r)),
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: accent,
                                ),
                              ),
                            ],
                          ),
                          if (r.invoiceNumber.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              'Bill ${r.invoiceNumber}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ],
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              if ((r.companyName ?? '').isNotEmpty)
                                Flexible(
                                  child: CombinedCompanyChip(
                                    companyName: r.companyName!,
                                    color: accent,
                                  ),
                                ),
                              const Spacer(),
                              if (r.isOverdue)
                                Text(
                                  'Overdue ${r.overdueDays}d',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.errorColor,
                                  ),
                                )
                              else if (r.dueDate != null)
                                Text(
                                  'Due ${_dateFormat.format(r.dueDate!)}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade500,
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}
