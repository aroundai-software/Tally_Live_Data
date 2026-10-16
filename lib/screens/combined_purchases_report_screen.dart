import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../config/app_theme.dart';
import '../models/purchase_invoice.dart';
import '../services/supabase_service.dart';
import '../utils/combined_company_selection.dart';
import '../widgets/combined_report_widgets.dart';
import '../widgets/purchase_invoice_detail_sheet.dart';
import '../widgets/summary_card.dart';

class CombinedPurchasesReportScreen extends StatefulWidget {
  final List<String> companyNames;
  final bool embedded;

  const CombinedPurchasesReportScreen({
    super.key,
    required this.companyNames,
    this.embedded = false,
  });

  @override
  State<CombinedPurchasesReportScreen> createState() =>
      _CombinedPurchasesReportScreenState();
}

class _CombinedPurchasesReportScreenState
    extends State<CombinedPurchasesReportScreen> {
  final SupabaseService _service = SupabaseService();
  final _dateFormat = DateFormat('dd MMM yyyy');

  late final List<String> _companies;
  late final String _selectionKey;
  bool _loading = true;
  Object? _error;
  List<PurchaseInvoice> _all = [];
  String _dateFilter = 'thisMonth';
  String _search = '';

  @override
  void initState() {
    super.initState();
    _companies = CombinedCompanySelection.normalizeList(widget.companyNames);
    _selectionKey = CombinedCompanySelection.selectionKey(_companies);
    _load();
  }

  Future<void> _load() async {
    if (!CombinedCompanySelection.isReady(_companies)) {
      setState(() {
        _loading = false;
        _all = [];
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
      final rows = await _service.getCombinedPurchaseInvoices(
        companyNames: _companies,
        onFirstPage: (first) {
          if (!mounted || keyAtStart != _selectionKey) return;
          setState(() {
            _all = first;
            _loading = false;
          });
        },
      );
      if (!mounted || keyAtStart != _selectionKey) return;
      setState(() {
        _all = rows;
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

  List<PurchaseInvoice> get _filtered {
    final q = _search.trim().toLowerCase();
    return _all.where((inv) {
      if (!combinedDateMatches(inv.invoiceDate, _dateFilter)) return false;
      if (q.isEmpty) return true;
      return inv.invoiceNumber.toLowerCase().contains(q) ||
          inv.supplierName.toLowerCase().contains(q) ||
          (inv.companyName ?? '').toLowerCase().contains(q);
    }).toList();
  }

  Map<String, double> get _totalsByCompany {
    final map = <String, double>{};
    for (final inv in _filtered) {
      final c = inv.companyName?.trim();
      if (c == null || c.isEmpty || !_companies.contains(c)) continue;
      map[c] = (map[c] ?? 0) + inv.totalAmount;
    }
    return map;
  }

  double get _grandTotal =>
      _totalsByCompany.values.fold<double>(0, (a, b) => a + b);

  void _showDetail(PurchaseInvoice invoice) {
    showPurchaseInvoiceDetailSheet(
      context: context,
      invoice: invoice,
      service: _service,
    );
  }

  Widget _buildPinnedFilters() {
    return Material(
      color: AppTheme.surfaceColor,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: AppTheme.dividerColor),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!widget.embedded) ...[
              Text(
                _companies.join(' • '),
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 10),
            ],
            CombinedDateFilterPills(
              selected: _dateFilter,
              onChanged: (v) => setState(() => _dateFilter = v),
            ),
            SizedBox(height: 10),
            TextField(
              decoration: InputDecoration(
                hintText: 'Search bill, supplier, company',
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 10),
                prefixIcon: Icon(Icons.search, size: 20),
                filled: true,
                fillColor: AppTheme.cardColor,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppTheme.dividerColor),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppTheme.dividerColor),
                ),
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInvoiceTile(PurchaseInvoice inv) {
    return Padding(
      padding: EdgeInsets.only(bottom: 8),
      child: Material(color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _showDetail(inv),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.dividerColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '#${inv.invoiceNumber}',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    Text(
                      formatCurrency(inv.totalAmount),
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppTheme.purchaseColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  inv.supplierName,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    if ((inv.companyName ?? '').isNotEmpty)
                      Flexible(
                        child: CombinedCompanyChip(
                          companyName: inv.companyName!,
                          color: AppTheme.purchaseColor,
                        ),
                      ),
                    const Spacer(),
                    if (inv.invoiceDate != null)
                      Text(
                        _dateFormat.format(inv.invoiceDate!),
                        style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.textSecondary,
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
  }

  @override
  Widget build(BuildContext context) {
    final rows = _filtered;
    final Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error != null) {
      body = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$_error'),
            TextButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    } else {
      body = Column(
        children: [
          _buildPinnedFilters(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
                children: [
                  CombinedSummaryCard(
                    title: 'Grand total',
                    value: formatCurrency(_grandTotal),
                    icon: Icons.shopping_bag_outlined,
                    color: AppTheme.purchaseColor,
                    subtitle:
                        '${rows.length} bill${rows.length == 1 ? '' : 's'}',
                  ),
                  const SizedBox(height: 6),
                  CombinedReportBreakdown(
                    totalsByCompany: _totalsByCompany,
                    accent: AppTheme.purchaseColor,
                  ),
                  SizedBox(height: 8),
                  if (rows.isEmpty)
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(
                        child: Text(
                          'No purchases in this selection',
                          style: TextStyle(color: AppTheme.textSecondary),
                        ),
                      ),
                    )
                  else
                    ...rows.map(_buildInvoiceTile),
                ],
              ),
            ),
          ),
        ],
      );
    }

    if (widget.embedded) {
      return ColoredBox(color: AppTheme.surfaceColor, child: body);
    }

    return Scaffold(
      backgroundColor: AppTheme.surfaceColor,
      appBar: AppBar(
        title: Text(
          'Combined Purchases',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
            fontSize: 16,
          ),
        ),
        elevation: 0,
        backgroundColor: AppTheme.cardColor,
        iconTheme: IconThemeData(color: AppTheme.textPrimary),
      ),
      body: body,
    );
  }
}
