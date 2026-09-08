import 'package:flutter/material.dart';
import '../utils/error_handler.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:intl/intl.dart';
import '../config/app_theme.dart';
import '../models/receivable_payable.dart';
import '../providers/company_provider.dart';
import '../services/supabase_service.dart';
import '../services/user_preferences_service.dart';
import '../widgets/search_bar_widget.dart';
import '../widgets/summary_card.dart';
import '../widgets/shimmer_loading.dart';
import '../widgets/empty_state.dart';

class ReceivablesPayablesScreen extends StatefulWidget {
  final VoidCallback? onBack;
  final String initialFilter;
  final int initialTabIndex;
  const ReceivablesPayablesScreen({
    super.key,
    this.onBack,
    this.initialFilter = 'all',
    this.initialTabIndex = 0,
  });

  @override
  State<ReceivablesPayablesScreen> createState() => _ReceivablesPayablesScreenState();
}

class _ReceivablesPayablesScreenState extends State<ReceivablesPayablesScreen>
    with TickerProviderStateMixin {
  final SupabaseService _service = SupabaseService();
  late TabController _tabController;

  List<OutstandingRecord> _allReceivables = [];
  List<OutstandingRecord> _filteredReceivables = [];
  List<OutstandingRecord> _allPayables = [];
  List<OutstandingRecord> _filteredPayables = [];
  bool _isLoading = true;
  String? _error;
  final TextEditingController _searchController = TextEditingController();

  late String _activeFilter;
  bool _sortByAmount = true;
  bool _sortByDate = false;
  DateTime? _selectedDateFilter;



  List<OutstandingRecord> get _receivables => _filteredReceivables;
  List<OutstandingRecord> get _payables => _filteredPayables;

  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _activeFilter = widget.initialFilter;
    // Tab count is determined after build reads feature flags; defer to didChangeDependencies
    _tabController = TabController(length: 2, vsync: this, initialIndex: widget.initialTabIndex);
    _tabController.addListener(() => setState(() {}));
    _searchController.addListener(_onSearchChanged);
  }



  @override
  void didUpdateWidget(covariant ReceivablesPayablesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialTabIndex != oldWidget.initialTabIndex) {
      _tabController.animateTo(widget.initialTabIndex);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  bool _isRecordOverdue(OutstandingRecord o) {
    if (o.isOverdue) return true;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (o.dueDate != null && o.dueDate!.isBefore(today)) return true;
    return false;
  }

  bool _isRecordToday(OutstandingRecord o) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (o.date != null) {
      final d = DateTime(o.date!.year, o.date!.month, o.date!.day);
      if (d.isAtSameMomentAs(today)) return true;
    }
    if (o.dueDate != null) {
      final dd = DateTime(o.dueDate!.year, o.dueDate!.month, o.dueDate!.day);
      if (dd.isAtSameMomentAs(today)) return true;
    }
    return false;
  }

  Future<void> _pickDateFilter() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDateFilter ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF2453FF),
              onPrimary: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _selectedDateFilter = picked;
      });
      _onSearchChanged();
    }
  }

  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase();
    final dateFormat = DateFormat('dd MMM yyyy');
    final monthFormat = DateFormat('MMMM');

    bool matchesQuery(OutstandingRecord o) {
      if (query.isEmpty) return true;
      final matchesName = o.customerName.toLowerCase().contains(query);
      final matchesInvoice = o.invoiceNumber.toLowerCase().contains(query);
      final matchesAmount = o.amount.toString().contains(query) || 
        o.closingBalance.toString().contains(query);
      
      bool matchesDate = false;
      if (o.date != null) {
        final dateStr = dateFormat.format(o.date!).toLowerCase();
        final monthStr = monthFormat.format(o.date!).toLowerCase();
        matchesDate = dateStr.contains(query) || monthStr.contains(query);
      }

      return matchesName || matchesInvoice || matchesAmount || matchesDate;
    }

    bool passesFilter(OutstandingRecord o) {
      if (!matchesQuery(o)) return false;
      if (_selectedDateFilter != null) {
        if (o.date == null) return false;
        final d1 = DateTime(o.date!.year, o.date!.month, o.date!.day);
        final d2 = DateTime(_selectedDateFilter!.year, _selectedDateFilter!.month, _selectedDateFilter!.day);
        if (!d1.isAtSameMomentAs(d2)) return false;
      }
      if (_activeFilter == 'today') return _isRecordToday(o);
      if (_activeFilter == 'overdue') return _isRecordOverdue(o);
      return true;
    }

    final filteredRecs = _allReceivables.where(passesFilter).toList();
    final filteredPays = _allPayables.where(passesFilter).toList();

    int compareRecords(OutstandingRecord a, OutstandingRecord b) {
      if (_sortByAmount && _sortByDate) {
        if (a.dueDate != null || b.dueDate != null) {
          if (a.dueDate == null) return 1;
          if (b.dueDate == null) return -1;
          final dateCompare = b.dueDate!.compareTo(a.dueDate!);
          if (dateCompare != 0) return dateCompare;
        }
        final aVal = a.closingBalance != 0 ? a.closingBalance.abs() : a.amount.abs();
        final bVal = b.closingBalance != 0 ? b.closingBalance.abs() : b.amount.abs();
        return bVal.compareTo(aVal);
      }
      if (_sortByAmount) {
        final aVal = a.closingBalance != 0 ? a.closingBalance.abs() : a.amount.abs();
        final bVal = b.closingBalance != 0 ? b.closingBalance.abs() : b.amount.abs();
        return bVal.compareTo(aVal);
      }
      if (_sortByDate) {
        if (a.dueDate == null && b.dueDate == null) return 0;
        if (a.dueDate == null) return 1;
        if (b.dueDate == null) return -1;
        return b.dueDate!.compareTo(a.dueDate!);
      }
      return a.customerName.toLowerCase().compareTo(b.customerName.toLowerCase());
    }

    filteredRecs.sort(compareRecords);
    filteredPays.sort(compareRecords);

    setState(() {
      _filteredReceivables = filteredRecs;
      _filteredPayables = filteredPays;
    });
  }

  int? _lastSyncTrigger;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    
    final companyState = CompanyProvider.of(context);
    final showReceivables = companyState.isFeatureEnabled('out_receivables');
    final showPayables = companyState.isFeatureEnabled('out_payables');
    final syncTrigger = companyState.syncTrigger;

    int tabCount = 0;
    if (showReceivables) tabCount++;
    if (showPayables) tabCount++;
    if (tabCount == 0) tabCount = 1; // Fallback

    if (_tabController.length != tabCount) {
      _tabController.dispose();
      _tabController = TabController(
        length: tabCount,
        vsync: this,
        initialIndex: widget.initialTabIndex.clamp(0, tabCount - 1),
      );
      _tabController.addListener(() => setState(() {}));
    }

    if (!_initialized) {
      _initialized = true;
      _lastSyncTrigger = syncTrigger;
      _loadPreferencesAndData();
    } else if (_lastSyncTrigger != syncTrigger) {
      _lastSyncTrigger = syncTrigger;
      _silentRefresh();
    }
  }

  Future<void> _loadPreferencesAndData() async {
    final saved = await UserPreferencesService.loadOutstandingSort();
    if (mounted) {
      setState(() {
        _sortByAmount = saved.sortByAmount;
        _sortByDate = saved.sortByDate;
      });
    }
    _loadData();
  }

  Future<void> _silentRefresh() async {
    try {
      final company = CompanyProvider.of(context).selectedCompany;
      final recs = await _service.getOutstandingReceivables(companyName: company);
      final pays = await _service.getOutstandingPayables(companyName: company);
      if (mounted) {
        setState(() {
          _allReceivables = recs;
          _allPayables = pays;
        });
        _onSearchChanged();
      }
    } catch (_) {}
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
      String errorMsg = AppErrorHandler.getFriendlyError(e);
      if (mounted) setState(() { _error = errorMsg; _isLoading = false; });
    }
  }

  double get _totalReceivable => _allReceivables.fold(0, (sum, o) => sum + (o.closingBalance != 0 ? o.closingBalance.abs() : o.amount.abs()));
  
  double get _totalOverdueReceivables {
    double total = 0;
    for (var o in _allReceivables) {
      if (_isRecordOverdue(o)) {
        total += (o.closingBalance != 0 ? o.closingBalance.abs() : o.amount.abs());
      }
    }
    return total;
  }

  int get _overdueReceivablesCount {
    int count = 0;
    for (var o in _allReceivables) {
      if (_isRecordOverdue(o)) count++;
    }
    return count;
  }

  double get _totalPayable => _allPayables.fold(0, (sum, o) => sum + (o.closingBalance != 0 ? o.closingBalance.abs() : o.amount.abs()));

  double get _totalOverduePayables {
    double total = 0;
    for (var o in _allPayables) {
      if (_isRecordOverdue(o)) {
        total += (o.closingBalance != 0 ? o.closingBalance.abs() : o.amount.abs());
      }
    }
    return total;
  }

  int get _overduePayablesCount {
    int count = 0;
    for (var o in _allPayables) {
      if (_isRecordOverdue(o)) count++;
    }
    return count;
  }

  @override
  Widget build(BuildContext context) {
    final companyState = CompanyProvider.of(context);
    final showReceivables = companyState.isFeatureEnabled('out_receivables');
    final showPayables = companyState.isFeatureEnabled('out_payables');

    // If both tabs are disabled, show a locked screen
    if (!showReceivables && !showPayables) {
      return Scaffold(
        primary: false,
        backgroundColor: AppTheme.surfaceColor,
        appBar: AppBar(
          leading: widget.onBack != null ? IconButton(icon: const Icon(Icons.arrow_back), onPressed: widget.onBack) : null,
          title: const Text('Outstanding'),
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_rounded, size: 48, color: Color(0xFF2453FF)),
              SizedBox(height: 12),
              Text('Feature Locked', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
              SizedBox(height: 8),
              Text('Outstanding Reports are disabled for this company.', textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF6B7A94))),
            ],
          ),
        ),
      );
    }

    // Build the list of visible tabs
    final visibleTabs = <Tab>[];
    final visibleViews = <Widget>[];
    if (showReceivables) {
      visibleTabs.add(const Tab(child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.arrow_downward_rounded, size: 16), SizedBox(width: 6), Text('Receivables')])));
      visibleViews.add(_buildList(_receivables, 'receivable'));
    }
    if (showPayables) {
      visibleTabs.add(const Tab(child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.arrow_upward_rounded, size: 16), SizedBox(width: 6), Text('Payables')])));
      visibleViews.add(_buildList(_payables, 'payable'));
    }

    // Visible tabs count and layout built dynamically


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
          IconButton(
            onPressed: _pickDateFilter,
            icon: Icon(Icons.calendar_today_rounded, color: _selectedDateFilter != null ? const Color(0xFF2453FF) : Colors.black87),
          ),
          if (_selectedDateFilter != null)
            IconButton(
              onPressed: () {
                setState(() => _selectedDateFilter = null);
                _onSearchChanged();
              },
              icon: const Icon(Icons.clear_rounded, color: Colors.red),
            ),
          IconButton(onPressed: _loadData, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      body: Column(
        children: [
          // --- Sticky: Receivables / Payables tab bar (only shown if both tabs are visible) ---
          if (visibleTabs.length > 1)
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Container(
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
                  tabs: visibleTabs,
                ),
              ),
            ),
          // --- Sticky: Search bar and Sort option ---
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: SearchBarWidget(
                    margin: EdgeInsets.zero,
                    hintText: 'Search by name, invoice, date...',
                    controller: _searchController,
                    onChanged: (_) {},
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.grey.shade200),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: PopupMenuButton<String>(
                    icon: const Icon(Icons.sort_rounded, color: AppTheme.primaryColor),
                    tooltip: 'Sort Options',
                    onSelected: (value) {
                      setState(() {
                        if (value == 'amount') {
                          _sortByAmount = !_sortByAmount;
                        } else if (value == 'date') {
                          _sortByDate = !_sortByDate;
                        }
                      });
                      UserPreferencesService.saveOutstandingSort(
                        sortByAmount: _sortByAmount,
                        sortByDate: _sortByDate,
                      );
                      _onSearchChanged();
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'amount',
                        child: Row(
                          children: [
                            Icon(
                              _sortByAmount ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                              color: _sortByAmount ? AppTheme.primaryColor : Colors.grey,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            const Text('Sort by Amount', style: TextStyle(fontSize: 14)),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'date',
                        child: Row(
                          children: [
                            Icon(
                              _sortByDate ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                              color: _sortByDate ? AppTheme.primaryColor : Colors.grey,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            const Text('Sort by Due Date', style: TextStyle(fontSize: 14)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // --- Sticky: Filter pills ---
          _buildFilterPills(),
          const Divider(height: 1, thickness: 0.5),
          // --- Scrollable area: Summary tiles + Bill list ---
          Expanded(
            child: NestedScrollView(
              headerSliverBuilder: (context, innerBoxIsScrolled) => [
                // Summary tiles scroll away
                SliverToBoxAdapter(child: _buildSummaryBar()),
              ],
              body: TabBarView(
                controller: _tabController,
                children: visibleViews,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryBar() {
    final isReceivablesTab = _tabController.index == 0;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: _SummaryTile(
              title: isReceivablesTab ? 'Receivables' : 'Payables',
              amount: isReceivablesTab ? _totalReceivable : _totalPayable,
              color: isReceivablesTab ? AppTheme.receivableColor : AppTheme.payableColor,
              icon: isReceivablesTab ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
              count: isReceivablesTab ? _allReceivables.length : _allPayables.length,
              isSelected: _activeFilter == 'all',
              onTap: () {
                setState(() => _activeFilter = 'all');
                _onSearchChanged();
              },
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _SummaryTile(
              title: 'Overdue',
              amount: isReceivablesTab ? _totalOverdueReceivables : _totalOverduePayables,
              color: const Color(0xFFD32F2F),
              icon: Icons.warning_amber_rounded,
              count: isReceivablesTab ? _overdueReceivablesCount : _overduePayablesCount,
              isSelected: _activeFilter == 'overdue',
              onTap: () {
                setState(() => _activeFilter = 'overdue');
                _onSearchChanged();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterPills() {
    final isReceivablesTab = _tabController.index == 0;
    final sourceList = isReceivablesTab ? _allReceivables : _allPayables;
    final allCount = sourceList.length;
    final todayCount = sourceList.where(_isRecordToday).length;
    final overdueCount = isReceivablesTab ? _overdueReceivablesCount : _overduePayablesCount;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
          _buildPillChip('All Bills', 'all', Icons.receipt_long_rounded, badgeCount: allCount),
          _buildPillChip("Today's Bills", 'today', Icons.today_rounded, badgeCount: todayCount),
          _buildPillChip('Overdue Bills', 'overdue', Icons.warning_amber_rounded, badgeCount: overdueCount),
        ],
        ),
      ),
    );
  }

  Widget _buildPillChip(String label, String filterKey, IconData icon, {int? badgeCount}) {
    final isSelected = _activeFilter == filterKey;
    final activeColor = filterKey == 'overdue' ? const Color(0xFFD32F2F) : AppTheme.primaryColor;

    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InkWell(
        onTap: () {
          setState(() => _activeFilter = filterKey);
          _onSearchChanged();
        },
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(
            color: isSelected ? activeColor : const Color(0xFFF1F3F9),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: isSelected ? activeColor : Colors.transparent),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: activeColor.withValues(alpha: 0.25),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : [],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: isSelected ? Colors.white : Colors.grey.shade600),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? Colors.white : Colors.grey.shade700,
                ),
              ),
              if (badgeCount != null && badgeCount > 0) ...[
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.white.withValues(alpha: 0.25) : activeColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$badgeCount',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? Colors.white : activeColor,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildList(List<OutstandingRecord> items, String type) {
    if (_isLoading) return const ShimmerLoading();
    if (_error != null) return ErrorState(message: _error!, onRetry: _loadData);
    if (items.isEmpty) {
      String subtitle = 'Data will appear here once synced from Tally';
      if (_searchController.text.isNotEmpty) {
        subtitle = 'Try a different search term or check filters';
      } else if (_activeFilter == 'overdue') {
        subtitle = 'No overdue ' + (type == 'receivable' ? 'receivables' : 'payables') + ' found';
      } else if (_activeFilter == 'today') {
        subtitle = 'No ' + (type == 'receivable' ? 'receivables' : 'payables') + ' for today';
      }

      return EmptyState(
        icon: type == 'receivable' ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
        title: 'No ' + (type == 'receivable' ? 'Receivables' : 'Payables') + ' Found',
        subtitle: subtitle,
        onRetry: _loadData,
      );
    }
    return AnimationLimiter(
      child: ListView.builder(
        key: PageStorageKey(type),
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


}

class _SummaryTile extends StatelessWidget {
  final String title;
  final double amount;
  final Color color;
  final IconData icon;
  final int count;
  final bool isSelected;
  final VoidCallback? onTap;
  const _SummaryTile({
    required this.title,
    required this.amount,
    required this.color,
    required this.icon,
    required this.count,
    this.isSelected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.15) : color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isSelected ? color : color.withValues(alpha: 0.2), width: isSelected ? 1.5 : 1.0),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 13),
                const SizedBox(width: 3),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              formatCompactCurrency(amount),
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color),
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              '$count items',
              style: TextStyle(fontSize: 10, color: color.withValues(alpha: 0.8)),
            ),
          ],
        ),
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
    final displayAmount = item.closingBalance != 0 ? item.closingBalance.abs() : item.amount.abs();
    final dateFormat = DateFormat('dd MMM yyyy');

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final isOverdue = item.isOverdue || (item.dueDate != null && item.dueDate!.isBefore(today));
    
    int overdueDays = item.overdueDays ?? 0;
    if (overdueDays <= 0 && item.dueDate != null && item.dueDate!.isBefore(today)) {
      overdueDays = today.difference(DateTime(item.dueDate!.year, item.dueDate!.month, item.dueDate!.day)).inDays;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isOverdue ? Colors.red.shade300 : Colors.grey.shade200, width: isOverdue ? 1.2 : 1.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: (isOverdue ? const Color(0xFFD32F2F) : color).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                child: Icon(isOverdue ? Icons.warning_amber_rounded : (isReceivable ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded), color: isOverdue ? const Color(0xFFD32F2F) : color, size: 18),
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
                  Text(formatCurrency(displayAmount), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: isOverdue ? const Color(0xFFD32F2F) : color)),
                  if (isOverdue)
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(6)),
                      child: Text('🚨 ' + (overdueDays > 0 ? ('$overdueDays d overdue') : 'Overdue'), style: TextStyle(fontSize: 10, color: Colors.red.shade700, fontWeight: FontWeight.bold)),
                    ),
                ],
              ),
            ],
          ),
          if (item.date != null || item.dueDate != null || item.billType != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: isOverdue ? Colors.red.shade50.withValues(alpha: 0.5) : const Color(0xFFF8F9FE), borderRadius: BorderRadius.circular(10)),
              child: Wrap(
                spacing: 12,
                runSpacing: 6,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (item.date != null)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.calendar_today_rounded, size: 13, color: Colors.grey.shade500),
                        const SizedBox(width: 4),
                        Text(dateFormat.format(item.date!), style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
                      ],
                    ),
                  if (item.dueDate != null)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.event_rounded, size: 13, color: isOverdue ? Colors.red.shade700 : Colors.grey.shade500),
                        const SizedBox(width: 4),
                        Text('Due: ${dateFormat.format(item.dueDate!)}', style: TextStyle(fontSize: 11, fontWeight: isOverdue ? FontWeight.bold : FontWeight.normal, color: isOverdue ? Colors.red.shade800 : Colors.grey.shade700)),
                      ],
                    ),
                  if (item.billType != null && item.billType!.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                      child: Text(item.billType!, style: TextStyle(fontSize: 9, color: color, fontWeight: FontWeight.w600)),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
