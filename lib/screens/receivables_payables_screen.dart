import 'package:flutter/material.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:intl/intl.dart';
import '../config/app_theme.dart';
import '../models/receivable_payable.dart';
import '../providers/company_provider.dart';
import '../services/supabase_service.dart';
import '../widgets/search_bar_widget.dart';
import '../widgets/summary_card.dart';
import '../widgets/shimmer_loading.dart';
import '../widgets/empty_state.dart';

class ReceivablesPayablesScreen extends StatefulWidget {
  final VoidCallback? onBack;
  const ReceivablesPayablesScreen({super.key, this.onBack});

  @override
  State<ReceivablesPayablesScreen> createState() => _ReceivablesPayablesScreenState();
}

class _ReceivablesPayablesScreenState extends State<ReceivablesPayablesScreen>
    with SingleTickerProviderStateMixin {
  final SupabaseService _service = SupabaseService();
  late TabController _tabController;

  List<OutstandingRecord> _allReceivables = [];
  List<OutstandingRecord> _filteredReceivables = [];
  List<OutstandingRecord> _allPayables = [];
  List<OutstandingRecord> _filteredPayables = [];
  bool _isLoading = true;
  String? _error;
  final TextEditingController _searchController = TextEditingController();

  // Search filter flags
  bool _searchInName = true;
  bool _searchInInvoice = true;
  bool _searchInAmount = true;
  bool _searchInDate = true;

  List<OutstandingRecord> get _receivables => _filteredReceivables;
  List<OutstandingRecord> get _payables => _filteredPayables;

  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase();
    if (query.isEmpty) {
      setState(() {
        _filteredReceivables = _allReceivables;
        _filteredPayables = _allPayables;
      });
      return;
    }

    final dateFormat = DateFormat('dd MMM yyyy');
    final monthFormat = DateFormat('MMMM');

    bool matches(OutstandingRecord o) {
      final matchesName = _searchInName && o.customerName.toLowerCase().contains(query);
      final matchesInvoice = _searchInInvoice && o.invoiceNumber.toLowerCase().contains(query);
      final matchesAmount = _searchInAmount && (
        o.amount.toString().contains(query) || 
        o.closingBalance.toString().contains(query)
      );
      
      bool matchesDate = false;
      if (_searchInDate && o.date != null) {
        final dateStr = dateFormat.format(o.date!).toLowerCase();
        final monthStr = monthFormat.format(o.date!).toLowerCase();
        matchesDate = dateStr.contains(query) || monthStr.contains(query);
      }

      return matchesName || matchesInvoice || matchesAmount || matchesDate;
    }

    setState(() {
      _filteredReceivables = _allReceivables.where(matches).toList();
      _filteredPayables = _allPayables.where(matches).toList();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      _loadData();
    }
  }

  Future<void> _loadData() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final company = CompanyProvider.of(context).selectedCompany;
      final recs = await _service.getOutstandingReceivables(companyName: company);
      final pays = await _service.getOutstandingPayables(companyName: company);
      if (mounted) {
        setState(() { 
          _allReceivables = recs; 
          _filteredReceivables = recs;
          _allPayables = pays;
          _filteredPayables = pays;
          _isLoading = false; 
        });
        _onSearchChanged();
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _isLoading = false; });
    }
  }

  double get _totalReceivable => _receivables.fold(0, (sum, o) => sum + (o.closingBalance != 0 ? o.closingBalance.abs() : o.amount.abs()));
  double get _totalPayable => _payables.fold(0, (sum, o) => sum + (o.closingBalance != 0 ? o.closingBalance.abs() : o.amount.abs()));

  Widget build(BuildContext context) {
    return Scaffold(
      primary: false,
      backgroundColor: AppTheme.surfaceColor,
      appBar: AppBar(
        leading: widget.onBack != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: widget.onBack,
              )
            : null,
        title: const Text('Outstanding'),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        actions: [
          IconButton(onPressed: _loadData, icon: const Icon(Icons.refresh_rounded)),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F3F9),
              borderRadius: BorderRadius.circular(12),
            ),
            child: TabBar(
              controller: _tabController,
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              indicator: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              labelColor: AppTheme.primaryColor,
              unselectedLabelColor: Colors.grey.shade500,
              labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
              tabs: const [
                Tab(child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.arrow_downward_rounded, size: 16), SizedBox(width: 6), Text('Receivables')])),
                Tab(child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.arrow_upward_rounded, size: 16), SizedBox(width: 6), Text('Payables')])),
              ],
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          _buildSummaryBar(),
          SearchBarWidget(
            hintText: 'Search by name, invoice, date...',
            controller: _searchController,
            onChanged: (_) {}, // Handled by listener
            trailing: PopupMenuButton<String>(
              icon: const Icon(Icons.tune_rounded, color: AppTheme.primaryColor),
              onSelected: (value) {
                setState(() {
                  if (value == 'name') _searchInName = !_searchInName;
                  if (value == 'invoice') _searchInInvoice = !_searchInInvoice;
                  if (value == 'amount') _searchInAmount = !_searchInAmount;
                  if (value == 'date') _searchInDate = !_searchInDate;
                });
                _onSearchChanged();
              },
              itemBuilder: (context) => [
                _buildFilterItem('Customer Name', _searchInName, 'name'),
                _buildFilterItem('Invoice Number', _searchInInvoice, 'invoice'),
                _buildFilterItem('Amount', _searchInAmount, 'amount'),
                _buildFilterItem('Date / Month', _searchInDate, 'date'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildList(_receivables, 'receivable'),
                _buildList(_payables, 'payable'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          Expanded(child: _SummaryTile(title: 'Total Receivable', amount: _totalReceivable, color: AppTheme.receivableColor, icon: Icons.arrow_downward_rounded, count: _receivables.length)),
          const SizedBox(width: 12),
          Expanded(child: _SummaryTile(title: 'Total Payable', amount: _totalPayable, color: AppTheme.payableColor, icon: Icons.arrow_upward_rounded, count: _payables.length)),
        ],
      ),
    );
  }

  Widget _buildList(List<OutstandingRecord> items, String type) {
    if (_isLoading) return const ShimmerLoading();
    if (_error != null) return ErrorState(message: _error!, onRetry: _loadData);
    if (items.isEmpty) {
      return EmptyState(
        icon: type == 'receivable' ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
        title: 'No ${type == 'receivable' ? 'Receivables' : 'Payables'} Found',
        subtitle: _searchController.text.isNotEmpty ? 'Try a different search term or check filters' : 'Data will appear here once synced from Tally',
        onRetry: _loadData,
      );
    }
    return AnimationLimiter(
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: items.length,
        itemBuilder: (context, index) {
          return AnimationConfiguration.staggeredList(
            position: index,
            duration: const Duration(milliseconds: 350),
            child: SlideAnimation(verticalOffset: 30, child: FadeInAnimation(child: _OutstandingCard(item: items[index], type: type))),
          );
        },
      ),
    );
  }

  PopupMenuItem<String> _buildFilterItem(String label, bool isSelected, String value) {
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(
            isSelected ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
            color: isSelected ? AppTheme.primaryColor : Colors.grey,
            size: 20,
          ),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(fontSize: 14)),
        ],
      ),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  final String title;
  final double amount;
  final Color color;
  final IconData icon;
  final int count;
  const _SummaryTile({required this.title, required this.amount, required this.color, required this.icon, required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [Icon(icon, color: color, size: 16), const SizedBox(width: 4), Expanded(child: Text(title, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)))]),
          const SizedBox(height: 6),
          Text(formatCompactCurrency(amount), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: color)),
          Text('$count entries', style: TextStyle(fontSize: 11, color: color.withValues(alpha: 0.7))),
        ],
      ),
    );
  }
}

class _OutstandingCard extends StatelessWidget {
  final OutstandingRecord item;
  final String type;
  const _OutstandingCard({required this.item, required this.type});

  @override
  Widget build(BuildContext context) {
    final isReceivable = type == 'receivable';
    final color = isReceivable ? AppTheme.receivableColor : AppTheme.payableColor;
    final dateFormat = DateFormat('dd MMM yyyy');
    final displayAmount = item.closingBalance != 0 ? item.closingBalance.abs() : item.amount.abs();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                child: Icon(isReceivable ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded, color: color, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.customerName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF1A1F36))),
                    if (item.invoiceNumber.isNotEmpty)
                      Text('Inv: ${item.invoiceNumber}', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(formatCurrency(displayAmount), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: color)),
                  if (item.isOverdue)
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(6)),
                      child: Text('Overdue ${item.overdueDays}d', style: TextStyle(fontSize: 10, color: Colors.red.shade700, fontWeight: FontWeight.w600)),
                    ),
                ],
              ),
            ],
          ),
          if (item.date != null || item.dueDate != null || item.billType != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: const Color(0xFFF8F9FE), borderRadius: BorderRadius.circular(10)),
              child: Row(
                children: [
                  if (item.date != null) ...[
                    Icon(Icons.calendar_today_rounded, size: 14, color: Colors.grey.shade400),
                    const SizedBox(width: 4),
                    Text(dateFormat.format(item.date!), style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                  ],
                  if (item.dueDate != null) ...[
                    if (item.date != null) const Spacer(),
                    Icon(Icons.event_rounded, size: 14, color: Colors.grey.shade400),
                    const SizedBox(width: 4),
                    Text('Due: ${dateFormat.format(item.dueDate!)}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                  ],
                  if (item.billType != null && item.billType!.isNotEmpty) ...[
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                      child: Text(item.billType!, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
