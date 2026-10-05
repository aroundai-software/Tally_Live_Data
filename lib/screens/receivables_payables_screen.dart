import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/error_handler.dart';
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
  final bool isActive;
  const ReceivablesPayablesScreen({
    super.key,
    this.onBack,
    this.initialFilter = 'all',
    this.initialTabIndex = 0,
    this.isActive = true,
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

  final Set<String> _expandedItemKeys = {};

  void _collapseAll() {
    if (_expandedItemKeys.isNotEmpty) {
      setState(() {
        _expandedItemKeys.clear();
      });
    }
  }

  late String _activeFilter;
  String _selectedGroup = 'All Items';
  String? _selectedLedger;
  bool _sortByAmount = true;
  bool _sortByDate = false;
  DateTimeRange? _selectedDateRange;



  List<OutstandingRecord> get _receivables => _filteredReceivables;
  List<OutstandingRecord> get _payables => _filteredPayables;

  bool _initialized = false;

  int _lastTabIndex = 0;
  String? _permissionKey;
  int _loadGeneration = 0;
  bool get _isReceivablesTab => CompanyProvider.of(context).isFeatureEnabled('out_receivables') && _lastTabIndex == 0;

  void _onTabChanged() {
    if (!_tabController.indexIsChanging && _tabController.index != _lastTabIndex) {
      _lastTabIndex = _tabController.index;
      _expandedItemKeys.clear();
      _selectedGroup = 'All Items';
      _selectedLedger = null;
      _recomputeTotals();
      _onSearchChanged();
      setState(() {});
    }
  }

  @override
  void initState() {
    super.initState();
    _activeFilter = widget.initialFilter;
    _lastTabIndex = widget.initialTabIndex;
    // Tab count is determined after build reads feature flags; defer to didChangeDependencies
    _tabController = TabController(length: 2, vsync: this, initialIndex: widget.initialTabIndex);
    _tabController.addListener(_onTabChanged);
    _searchController.addListener(_onSearchChanged);
  }



  @override
  void didUpdateWidget(covariant ReceivablesPayablesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final targetTab = widget.initialTabIndex.clamp(0, _tabController.length - 1);
    final tabNeedsChange = _tabController.index != targetTab;
    final filterNeedsChange = _activeFilter != widget.initialFilter;
    final becameActive = widget.isActive && !oldWidget.isActive;

    if (becameActive || filterNeedsChange) {
      _activeFilter = widget.initialFilter;
    }

    if (tabNeedsChange) {
      _tabController.animateTo(targetTab);
      _lastTabIndex = targetTab;
      _expandedItemKeys.clear();
      _selectedGroup = 'All Items';
      _selectedLedger = null;
      _recomputeTotals();
    }

    if (becameActive) {
      _selectedGroup = 'All Items';
      _selectedLedger = null;
      _selectedDateRange = null;
      if (_searchController.text.isNotEmpty) {
        _searchController.clear();
      } else {
        _onSearchChanged();
      }
    } else if (filterNeedsChange) {
      _onSearchChanged();
    }

    if (oldWidget.isActive != widget.isActive) {
      _collapseAll();
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
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
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: _selectedDateRange,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: 'Select Date Range',
      cancelText: 'Cancel',
      confirmText: 'Apply',
      saveText: 'Apply',
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF2453FF),
              onPrimary: Colors.white,
              onSurface: Colors.black87,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _selectedDateRange = picked;
      });
      _recomputeTotals();
      _onSearchChanged();
    }
  }

  void _onSearchChanged() {
    _collapseAll();
    final query = _searchController.text.toLowerCase();
    final dateFormat = DateFormat('dd MMM yyyy');
    final monthFormat = DateFormat('MMMM');

    bool matchesQuery(OutstandingRecord o) {
      if (query.isEmpty) return true;
      final matchesName = o.customerName.toLowerCase().contains(query);
      final matchesGroup = o.groupName != null && o.groupName!.toLowerCase().contains(query);
      final matchesInvoice = o.invoiceNumber.toLowerCase().contains(query);
      final matchesAmount = o.amount.toString().contains(query) || 
        o.closingBalance.toString().contains(query);
      
      bool matchesDate = false;
      if (o.date != null) {
        final dateStr = dateFormat.format(o.date!).toLowerCase();
        final monthStr = monthFormat.format(o.date!).toLowerCase();
        matchesDate = dateStr.contains(query) || monthStr.contains(query);
      }

      return matchesName || matchesGroup || matchesInvoice || matchesAmount || matchesDate;
    }

    bool passesFilter(OutstandingRecord o) {
      if (_selectedGroup != 'All Items') {
        final g = (o.groupName != null && o.groupName!.trim().isNotEmpty)
            ? o.groupName!.trim()
            : (_isReceivablesTab ? 'Sundry Debtors' : 'Sundry Creditors');
        if (g != _selectedGroup) return false;
      }
      if (_selectedLedger != null && _selectedLedger!.isNotEmpty) {
        if (o.customerName.trim() != _selectedLedger!.trim()) return false;
      }
      if (!matchesQuery(o)) return false;
      if (_selectedDateRange != null) {
        final d = o.date != null
            ? DateTime(o.date!.year, o.date!.month, o.date!.day)
            : (o.dueDate != null ? DateTime(o.dueDate!.year, o.dueDate!.month, o.dueDate!.day) : null);
        if (d == null) return false;
        final start = DateTime(_selectedDateRange!.start.year, _selectedDateRange!.start.month, _selectedDateRange!.start.day);
        final end = DateTime(_selectedDateRange!.end.year, _selectedDateRange!.end.month, _selectedDateRange!.end.day);
        if (d.isBefore(start) || d.isAfter(end)) return false;
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
    final permissionKey = '${companyState.selectedCompany}:$showReceivables:$showPayables';
    final permissionsChanged = _permissionKey != permissionKey;
    _permissionKey = permissionKey;
    if (permissionsChanged) {
      _loadGeneration++;
      _allReceivables = []; _filteredReceivables = [];
      _allPayables = []; _filteredPayables = [];
      if (!showReceivables) { _allReceivables = []; _filteredReceivables = []; }
      if (!showPayables) { _allPayables = []; _filteredPayables = []; }
      _selectedGroup = 'All Items';
      _selectedLedger = null;
      _recomputeTotals();
    }

    int tabCount = 0;
    if (showReceivables) tabCount++;
    if (showPayables) tabCount++;
    if (tabCount == 0) tabCount = 1; // Fallback

    if (_tabController.length != tabCount) {
      _tabController.removeListener(_onTabChanged);
      _tabController.dispose();
      _tabController = TabController(
        length: tabCount,
        vsync: this,
        initialIndex: widget.initialTabIndex.clamp(0, tabCount - 1),
      );
      _lastTabIndex = _tabController.index;
      _tabController.addListener(_onTabChanged);
    }

    if (!_initialized) {
      _initialized = true;
      _lastSyncTrigger = syncTrigger;
      _loadPreferencesAndData();
    } else if (permissionsChanged || _lastSyncTrigger != syncTrigger) {
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
    if (mounted) _loadData();
  }

  double _cachedTotalReceivable = 0;
  double _cachedTotalOverdueReceivables = 0;
  int _cachedOverdueReceivablesCount = 0;
  int _cachedTodayReceivablesCount = 0;

  double _cachedTotalPayable = 0;
  double _cachedTotalOverduePayables = 0;
  int _cachedOverduePayablesCount = 0;
  int _cachedTodayPayablesCount = 0;

  void _recomputeTotals() {
    double recTotal = 0;
    double recOverdueTotal = 0;
    int recOverdueCount = 0;
    int recTodayCount = 0;

    for (var o in _allReceivables) {
      if (_selectedGroup != 'All Items') {
        final g = (o.groupName != null && o.groupName!.trim().isNotEmpty)
            ? o.groupName!.trim()
            : 'Sundry Debtors';
        if (g != _selectedGroup) continue;
      }
      if (_selectedLedger != null && _selectedLedger!.isNotEmpty) {
        if (o.customerName.trim() != _selectedLedger!.trim()) continue;
      }
      if (_selectedDateRange != null) {
        final d = o.date != null
            ? DateTime(o.date!.year, o.date!.month, o.date!.day)
            : (o.dueDate != null ? DateTime(o.dueDate!.year, o.dueDate!.month, o.dueDate!.day) : null);
        if (d == null) continue;
        final start = DateTime(_selectedDateRange!.start.year, _selectedDateRange!.start.month, _selectedDateRange!.start.day);
        final end = DateTime(_selectedDateRange!.end.year, _selectedDateRange!.end.month, _selectedDateRange!.end.day);
        if (d.isBefore(start) || d.isAfter(end)) continue;
      }

      final amt = o.closingBalance != 0 ? o.closingBalance.abs() : o.amount.abs();
      recTotal += amt;
      if (_isRecordOverdue(o)) {
        recOverdueTotal += amt;
        recOverdueCount++;
      }
      if (_isRecordToday(o)) {
        recTodayCount++;
      }
    }

    double payTotal = 0;
    double payOverdueTotal = 0;
    int payOverdueCount = 0;
    int payTodayCount = 0;

    for (var o in _allPayables) {
      if (_selectedGroup != 'All Items') {
        final g = (o.groupName != null && o.groupName!.trim().isNotEmpty)
            ? o.groupName!.trim()
            : 'Sundry Creditors';
        if (g != _selectedGroup) continue;
      }
      if (_selectedLedger != null && _selectedLedger!.isNotEmpty) {
        if (o.customerName.trim() != _selectedLedger!.trim()) continue;
      }
      if (_selectedDateRange != null) {
        final d = o.date != null
            ? DateTime(o.date!.year, o.date!.month, o.date!.day)
            : (o.dueDate != null ? DateTime(o.dueDate!.year, o.dueDate!.month, o.dueDate!.day) : null);
        if (d == null) continue;
        final start = DateTime(_selectedDateRange!.start.year, _selectedDateRange!.start.month, _selectedDateRange!.start.day);
        final end = DateTime(_selectedDateRange!.end.year, _selectedDateRange!.end.month, _selectedDateRange!.end.day);
        if (d.isBefore(start) || d.isAfter(end)) continue;
      }

      final amt = o.closingBalance != 0 ? o.closingBalance.abs() : o.amount.abs();
      payTotal += amt;
      if (_isRecordOverdue(o)) {
        payOverdueTotal += amt;
        payOverdueCount++;
      }
      if (_isRecordToday(o)) {
        payTodayCount++;
      }
    }

    _cachedTotalReceivable = recTotal;
    _cachedTotalOverdueReceivables = recOverdueTotal;
    _cachedOverdueReceivablesCount = recOverdueCount;
    _cachedTodayReceivablesCount = recTodayCount;

    _cachedTotalPayable = payTotal;
    _cachedTotalOverduePayables = payOverdueTotal;
    _cachedOverduePayablesCount = payOverdueCount;
    _cachedTodayPayablesCount = payTodayCount;
  }

  Future<void> _silentRefresh() => _loadData();

  Future<void> _loadData() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final state = CompanyProvider.of(context);
      final company = state.selectedCompany;
      final generation = ++_loadGeneration;
      final recs = state.isFeatureEnabled('out_receivables')
          ? await _service.getOutstandingReceivables(companyName: company) : <OutstandingRecord>[];
      final pays = state.isFeatureEnabled('out_payables')
          ? await _service.getOutstandingPayables(companyName: company) : <OutstandingRecord>[];
      if (!mounted || generation != _loadGeneration || company != state.selectedCompany) return;
      if (mounted) {
        setState(() { 
          _allReceivables = recs; 
          _filteredReceivables = recs;
          _allPayables = pays;
          _filteredPayables = pays;
          _isLoading = false; 
        });
        _recomputeTotals();
        _onSearchChanged();
      }
    } catch (e) {
      String errorMsg = AppErrorHandler.getFriendlyError(e);
      if (mounted) setState(() { _error = errorMsg; _isLoading = false; });
    }
  }

  double get _totalReceivable => _cachedTotalReceivable;
  double get _totalOverdueReceivables => _cachedTotalOverdueReceivables;
  int get _overdueReceivablesCount => _cachedOverdueReceivablesCount;

  double get _totalPayable => _cachedTotalPayable;
  double get _totalOverduePayables => _cachedTotalOverduePayables;
  int get _overduePayablesCount => _cachedOverduePayablesCount;

  @override
  Widget build(BuildContext context) {
    final companyState = CompanyProvider.of(context);
    final showReceivables = companyState.isFeatureEnabled('out_receivables');
    final showPayables = companyState.isFeatureEnabled('out_payables');

    // If both tabs are disabled, show a locked screen
    if (!showReceivables && !showPayables) {
      return Scaffold(
        resizeToAvoidBottomInset: false,
        primary: false,
        backgroundColor: AppTheme.surfaceColor,
        appBar: AppBar(
          leading: widget.onBack != null
              ? IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () {
                    _collapseAll();
                    widget.onBack!();
                  },
                )
              : null,
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
      visibleTabs.add(
        const Tab(
          height: 32,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.arrow_downward_rounded, size: 14),
              SizedBox(width: 5),
              Text('Receivables', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            ],
          ),
        ),
      );
      visibleViews.add(_KeepAliveTab(child: _buildList(_receivables, 'receivable')));
    }
    if (showPayables) {
      visibleTabs.add(
        const Tab(
          height: 32,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.arrow_upward_rounded, size: 14),
              SizedBox(width: 5),
              Text('Payables', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            ],
          ),
        ),
      );
      visibleViews.add(_KeepAliveTab(child: _buildList(_payables, 'payable')));
    }

    // Visible tabs count and layout built dynamically


    return Scaffold(
      resizeToAvoidBottomInset: false,
      primary: false,
      backgroundColor: AppTheme.surfaceColor,
      appBar: AppBar(
        leading: widget.onBack != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  _collapseAll();
                  widget.onBack!();
                },
              )
            : null,
        title: const Text('Outstanding'),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        actions: [
          IconButton(
            onPressed: _pickDateFilter,
            tooltip: _selectedDateRange != null
                ? 'Date Range: ${DateFormat('dd MMM yyyy').format(_selectedDateRange!.start)} - ${DateFormat('dd MMM yyyy').format(_selectedDateRange!.end)}'
                : 'Filter by date range',
            icon: Icon(
              Icons.date_range_rounded,
              color: _selectedDateRange != null ? const Color(0xFF2453FF) : Colors.black87,
            ),
          ),
          if (_selectedDateRange != null)
            IconButton(
              onPressed: () {
                setState(() => _selectedDateRange = null);
                _recomputeTotals();
                _onSearchChanged();
              },
              tooltip: 'Clear date filter',
              icon: const Icon(Icons.clear_rounded, color: Colors.red),
            ),
          IconButton(
            onPressed: _loadData,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Column(
        children: [
          // --- Sticky: Receivables / Payables tab bar (only shown if both tabs are visible) ---
          if (visibleTabs.length > 1)
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Container(
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F3F9),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: TabBar(
                  controller: _tabController,
                  indicatorSize: TabBarIndicatorSize.tab,
                  dividerColor: Colors.transparent,
                  padding: const EdgeInsets.all(2),
                  indicator: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  labelColor: AppTheme.primaryColor,
                  unselectedLabelColor: Colors.grey.shade500,
                  labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
                  tabs: visibleTabs,
                ),
              ),
            ),
          // --- Sticky: Search bar and Sort option ---
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
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
          // --- Group & Ledger Filter Bar ---
          _buildGroupAndLedgerBar(),
          // --- Sticky: Filter pills ---
          _buildFilterPills(),
          // --- Sticky: Summary tiles ---
          _buildSummaryBar(),
          const Divider(height: 1, thickness: 0.5),
          // --- Bill list ---
          Expanded(
            child: TabBarView(
              controller: _tabController,
              physics: const ClampingScrollPhysics(),
              children: visibleViews,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryBar() {
    final isReceivablesTab = _isReceivablesTab;
    final totalCount = isReceivablesTab ? _filteredReceivables.length : _filteredPayables.length;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 2, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: _SummaryTile(
              title: isReceivablesTab ? 'Receivables' : 'Payables',
              amount: isReceivablesTab ? _totalReceivable : _totalPayable,
              color: isReceivablesTab ? AppTheme.receivableColor : AppTheme.payableColor,
              icon: isReceivablesTab ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
              count: totalCount,
              isSelected: _activeFilter == 'all',
              onTap: () {
                setState(() => _activeFilter = 'all');
                _onSearchChanged();
              },
            ),
          ),
          const SizedBox(width: 8),
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

  Widget _buildGroupAndLedgerBar() {
    final hasGroupFilter = _selectedGroup != 'All Items';
    final hasLedgerFilter = _selectedLedger != null && _selectedLedger!.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
      child: Row(
        children: [
          // --- Group Selector Chip (like Tally F4: Group) ---
          Expanded(
            child: InkWell(
              onTap: _showGroupPickerSheet,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: hasGroupFilter ? AppTheme.primaryColor.withValues(alpha: 0.08) : const Color(0xFFF4F6FA),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: hasGroupFilter ? AppTheme.primaryColor : Colors.grey.shade300,
                    width: hasGroupFilter ? 1.2 : 0.8,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.folder_outlined,
                      size: 15,
                      color: hasGroupFilter ? AppTheme.primaryColor : Colors.grey.shade600,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        hasGroupFilter ? 'Group: $_selectedGroup' : 'All Groups',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: hasGroupFilter ? FontWeight.w600 : FontWeight.w500,
                          color: hasGroupFilter ? AppTheme.primaryColor : const Color(0xFF2C3242),
                        ),
                      ),
                    ),
                    if (hasGroupFilter)
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedGroup = 'All Items';
                          });
                          _recomputeTotals();
                          _onSearchChanged();
                        },
                        child: const Padding(
                          padding: EdgeInsets.only(left: 4),
                          child: Icon(Icons.close_rounded, size: 14, color: AppTheme.primaryColor),
                        ),
                      )
                    else
                      Icon(Icons.arrow_drop_down_rounded, size: 18, color: Colors.grey.shade600),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),

          // --- Ledger / Party Selector Chip ---
          Expanded(
            child: InkWell(
              onTap: _showLedgerPickerSheet,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: hasLedgerFilter ? AppTheme.primaryColor.withValues(alpha: 0.08) : const Color(0xFFF4F6FA),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: hasLedgerFilter ? AppTheme.primaryColor : Colors.grey.shade300,
                    width: hasLedgerFilter ? 1.2 : 0.8,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.person_outline_rounded,
                      size: 15,
                      color: hasLedgerFilter ? AppTheme.primaryColor : Colors.grey.shade600,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        hasLedgerFilter ? _selectedLedger! : 'All Ledgers',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: hasLedgerFilter ? FontWeight.w600 : FontWeight.w500,
                          color: hasLedgerFilter ? AppTheme.primaryColor : const Color(0xFF2C3242),
                        ),
                      ),
                    ),
                    if (hasLedgerFilter)
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedLedger = null;
                          });
                          _recomputeTotals();
                          _onSearchChanged();
                        },
                        child: const Padding(
                          padding: EdgeInsets.only(left: 4),
                          child: Icon(Icons.close_rounded, size: 14, color: AppTheme.primaryColor),
                        ),
                      )
                    else
                      Icon(Icons.arrow_drop_down_rounded, size: 18, color: Colors.grey.shade600),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showGroupPickerSheet() {
    final isReceivablesTab = _isReceivablesTab;
    final allRecords = isReceivablesTab ? _allReceivables : _allPayables;

    final Map<String, int> groupCounts = {};
    for (var r in allRecords) {
      final g = (r.groupName != null && r.groupName!.trim().isNotEmpty)
          ? r.groupName!.trim()
          : (isReceivablesTab ? 'Sundry Debtors' : 'Sundry Creditors');
      groupCounts[g] = (groupCounts[g] ?? 0) + 1;
    }

    final groups = groupCounts.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    String query = '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final filteredGroups = groups
                .where((g) => g.toLowerCase().contains(query.toLowerCase()))
                .toList();

            return Container(
              height: MediaQuery.of(context).size.height * 0.7,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 12, 10),
                    child: Row(
                      children: [
                        const Icon(Icons.folder_open_rounded, color: AppTheme.primaryColor, size: 22),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Select Group',
                                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Color(0xFF1A1F36)),
                              ),
                              Text(
                                'Filter outstandings by Tally group',
                                style: TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 22),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                    child: TextField(
                      decoration: InputDecoration(
                        hintText: 'Search groups...',
                        prefixIcon: const Icon(Icons.search_rounded, size: 20),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        filled: true,
                        fillColor: const Color(0xFFF5F6FA),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onChanged: (val) {
                        setModalState(() {
                          query = val;
                        });
                      },
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      children: [
                        ListTile(
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: _selectedGroup == 'All Items'
                                  ? AppTheme.primaryColor.withValues(alpha: 0.1)
                                  : const Color(0xFFF1F3F9),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.all_inclusive_rounded,
                              size: 18,
                              color: _selectedGroup == 'All Items' ? AppTheme.primaryColor : Colors.grey.shade600,
                            ),
                          ),
                          title: const Text('All Items', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                          subtitle: Text('${allRecords.length} total bills', style: const TextStyle(fontSize: 12)),
                          trailing: _selectedGroup == 'All Items'
                              ? const Icon(Icons.check_circle_rounded, color: AppTheme.primaryColor, size: 20)
                              : null,
                          onTap: () {
                            setState(() {
                              _selectedGroup = 'All Items';
                            });
                            _recomputeTotals();
                            _onSearchChanged();
                            Navigator.pop(context);
                          },
                        ),
                        const Divider(height: 1, indent: 64),
                        ...filteredGroups.map((g) {
                          final isSelected = _selectedGroup == g;
                          final count = groupCounts[g] ?? 0;
                          return ListTile(
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? AppTheme.primaryColor.withValues(alpha: 0.1)
                                    : const Color(0xFFF1F3F9),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.folder_rounded,
                                size: 18,
                                color: isSelected ? AppTheme.primaryColor : Colors.grey.shade600,
                              ),
                            ),
                            title: Text(g, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                            subtitle: Text('$count bill${count == 1 ? '' : 's'}', style: const TextStyle(fontSize: 12)),
                            trailing: isSelected
                                ? const Icon(Icons.check_circle_rounded, color: AppTheme.primaryColor, size: 20)
                                : null,
                            onTap: () {
                              setState(() {
                                _selectedGroup = g;
                                _selectedLedger = null;
                              });
                              _recomputeTotals();
                              _onSearchChanged();
                              Navigator.pop(context);
                            },
                          );
                        }),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showLedgerPickerSheet() {
    final isReceivablesTab = _isReceivablesTab;
    final allRecords = isReceivablesTab ? _allReceivables : _allPayables;

    final scopedRecords = _selectedGroup == 'All Items'
        ? allRecords
        : allRecords.where((r) {
            final g = (r.groupName != null && r.groupName!.trim().isNotEmpty)
                ? r.groupName!.trim()
                : (isReceivablesTab ? 'Sundry Debtors' : 'Sundry Creditors');
            return g == _selectedGroup;
          }).toList();

    final Map<String, (int, double)> ledgerData = {};
    for (var r in scopedRecords) {
      final name = r.customerName.trim();
      final amt = r.closingBalance != 0 ? r.closingBalance.abs() : r.amount.abs();
      final existing = ledgerData[name];
      if (existing != null) {
        ledgerData[name] = (existing.$1 + 1, existing.$2 + amt);
      } else {
        ledgerData[name] = (1, amt);
      }
    }

    final ledgers = ledgerData.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    String query = '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final filteredLedgers = ledgers
                .where((l) => l.toLowerCase().contains(query.toLowerCase()))
                .toList();

            return Container(
              height: MediaQuery.of(context).size.height * 0.75,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 12, 10),
                    child: Row(
                      children: [
                        const Icon(Icons.person_search_rounded, color: AppTheme.primaryColor, size: 22),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Select Party / Ledger',
                                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Color(0xFF1A1F36)),
                              ),
                              Text(
                                _selectedGroup == 'All Items'
                                    ? 'All parties (${ledgers.length} total)'
                                    : 'Parties in $_selectedGroup (${ledgers.length})',
                                style: const TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 22),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                    child: TextField(
                      decoration: InputDecoration(
                        hintText: 'Search party name...',
                        prefixIcon: const Icon(Icons.search_rounded, size: 20),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        filled: true,
                        fillColor: const Color(0xFFF5F6FA),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onChanged: (val) {
                        setModalState(() {
                          query = val;
                        });
                      },
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      children: [
                        ListTile(
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: _selectedLedger == null
                                  ? AppTheme.primaryColor.withValues(alpha: 0.1)
                                  : const Color(0xFFF1F3F9),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.groups_rounded,
                              size: 18,
                              color: _selectedLedger == null ? AppTheme.primaryColor : Colors.grey.shade600,
                            ),
                          ),
                          title: const Text('All Ledgers', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                          subtitle: Text('${scopedRecords.length} bills', style: const TextStyle(fontSize: 12)),
                          trailing: _selectedLedger == null
                              ? const Icon(Icons.check_circle_rounded, color: AppTheme.primaryColor, size: 20)
                              : null,
                          onTap: () {
                            setState(() {
                              _selectedLedger = null;
                            });
                            _recomputeTotals();
                            _onSearchChanged();
                            Navigator.pop(context);
                          },
                        ),
                        const Divider(height: 1, indent: 64),
                        ...filteredLedgers.map((l) {
                          final isSelected = _selectedLedger == l;
                          final data = ledgerData[l];
                          final count = data?.$1 ?? 0;
                          final totalAmt = data?.$2 ?? 0;
                          return ListTile(
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? AppTheme.primaryColor.withValues(alpha: 0.1)
                                    : const Color(0xFFF1F3F9),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.person_rounded,
                                size: 18,
                                color: isSelected ? AppTheme.primaryColor : Colors.grey.shade600,
                              ),
                            ),
                            title: Text(l, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                            subtitle: Text(
                              '$count bill${count == 1 ? '' : 's'} • ${formatCurrency(totalAmt)}',
                              style: const TextStyle(fontSize: 12),
                            ),
                            trailing: isSelected
                                ? const Icon(Icons.check_circle_rounded, color: AppTheme.primaryColor, size: 20)
                                : null,
                            onTap: () {
                              setState(() {
                                _selectedLedger = l;
                              });
                              _recomputeTotals();
                              _onSearchChanged();
                              Navigator.pop(context);
                            },
                          );
                        }),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildFilterPills() {
    final isReceivablesTab = _isReceivablesTab;
    final allCount = isReceivablesTab ? _filteredReceivables.length : _filteredPayables.length;
    final todayCount = isReceivablesTab ? _cachedTodayReceivablesCount : _cachedTodayPayablesCount;
    final overdueCount = isReceivablesTab ? _cachedOverdueReceivablesCount : _cachedOverduePayablesCount;
    return Container(
      margin: const EdgeInsets.only(top: 2, bottom: 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            _buildPillChip('All Bills', 'all', Icons.receipt_long_rounded, badgeCount: allCount),
            _buildPillChip("Today's Bills", 'today', Icons.today_rounded, badgeCount: todayCount),
            _buildPillChip('Overdue Bills', 'overdue', Icons.warning_amber_rounded, badgeCount: overdueCount),
            if (_selectedDateRange != null)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2453FF).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF2453FF), width: 1.2),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      InkWell(
                        onTap: _pickDateFilter,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.date_range_rounded, size: 15, color: Color(0xFF2453FF)),
                            const SizedBox(width: 5),
                            Text(
                              '${DateFormat('dd MMM').format(_selectedDateRange!.start)} – ${DateFormat('dd MMM').format(_selectedDateRange!.end)}',
                              style: const TextStyle(
                                color: Color(0xFF2453FF),
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      InkWell(
                        onTap: () {
                          setState(() => _selectedDateRange = null);
                          _recomputeTotals();
                          _onSearchChanged();
                        },
                        child: const Icon(Icons.close_rounded, size: 16, color: Color(0xFF2453FF)),
                      ),
                    ],
                  ),
                ),
              ),
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
      final typeStr = type == 'receivable' ? 'receivables' : 'payables';
      final typeCap = type == 'receivable' ? 'Receivables' : 'Payables';
      String subtitle = 'Data will appear here once synced from Tally';
      if (_searchController.text.isNotEmpty) {
        subtitle = 'Try a different search term or check filters';
      } else if (_selectedLedger != null && _selectedLedger!.isNotEmpty) {
        subtitle = 'No $typeStr found for $_selectedLedger';
      } else if (_selectedGroup != 'All Items') {
        subtitle = 'No $typeStr found in group $_selectedGroup';
      } else if (_activeFilter == 'overdue') {
        subtitle = 'No overdue $typeStr found';
      } else if (_activeFilter == 'today') {
        subtitle = 'No $typeStr for today';
      } else if (_selectedDateRange != null) {
        subtitle = 'No $typeStr found for the selected date range';
      }

      return EmptyState(
        icon: type == 'receivable' ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
        title: 'No $typeCap Found',
        subtitle: subtitle,
        onRetry: _loadData,
      );
    }
    return ListView.builder(
      key: PageStorageKey(type),
      cacheExtent: 1500,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final itemKey = '${type}_${item.id ?? item.invoiceNumber}_$index';
        final isExpanded = _expandedItemKeys.contains(itemKey);
        return _OutstandingCard(
          key: ValueKey(itemKey),
          item: item,
          type: type,
          isExpanded: isExpanded,
          onToggle: () {
            setState(() {
              if (_expandedItemKeys.contains(itemKey)) {
                _expandedItemKeys.remove(itemKey);
              } else {
                _expandedItemKeys.add(itemKey);
              }
            });
          },
        );
      },
    );
  }


}

class _KeepAliveTab extends StatefulWidget {
  final Widget child;
  const _KeepAliveTab({required this.child});

  @override
  State<_KeepAliveTab> createState() => _KeepAliveTabState();
}

class _KeepAliveTabState extends State<_KeepAliveTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
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
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.15) : color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? color : color.withValues(alpha: 0.2),
            width: isSelected ? 1.4 : 1.0,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 12),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '$count items',
                  style: TextStyle(fontSize: 10, color: color.withValues(alpha: 0.8), fontWeight: FontWeight.w500),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              formatCompactCurrency(amount),
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _OutstandingCard extends StatelessWidget {
  static final _dateFormat = DateFormat('dd MMM yyyy');
  final OutstandingRecord item;
  final String type;
  final bool isExpanded;
  final VoidCallback onToggle;

  const _OutstandingCard({
    super.key,
    required this.item,
    required this.type,
    required this.isExpanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final isReceivable = type == 'receivable';
    final color = isReceivable ? AppTheme.receivableColor : AppTheme.payableColor;
    final displayAmount = item.closingBalance != 0 ? item.closingBalance.abs() : item.amount.abs();

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final isOverdue = item.isOverdue || (item.dueDate != null && item.dueDate!.isBefore(today));
    
    int overdueDays = item.overdueDays ?? 0;
    if (overdueDays <= 0 && item.dueDate != null && item.dueDate!.isBefore(today)) {
      overdueDays = today.difference(DateTime(item.dueDate!.year, item.dueDate!.month, item.dueDate!.day)).inDays;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isOverdue ? Colors.red.shade300 : Colors.grey.shade200,
          width: isOverdue ? 1.2 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Collapsed header row: Party Name and Amount
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.customerName,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF1A1F36),
                            ),
                          ),
                          if (item.groupName != null && item.groupName!.trim().isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F3F9),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                item.groupName!,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      formatCurrency(displayAmount),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: isOverdue ? const Color(0xFFD32F2F) : color,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                      size: 20,
                      color: Colors.grey.shade400,
                    ),
                  ],
                ),

                // Expanded details
                if (isExpanded) ...[
                  const SizedBox(height: 10),
                  const Divider(height: 1, thickness: 0.7, color: Color(0xFFF0F1F5)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      if (item.invoiceNumber.isNotEmpty)
                        Expanded(
                          child: Text(
                            'Inv: ${item.invoiceNumber}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      if (isOverdue)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '🚨 ${overdueDays > 0 ? '$overdueDays d overdue' : 'Overdue'}',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.red.shade700,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (item.date != null || item.dueDate != null || (item.billType != null && item.billType!.isNotEmpty)) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: isOverdue ? Colors.red.shade50.withValues(alpha: 0.5) : const Color(0xFFF8F9FE),
                        borderRadius: BorderRadius.circular(10),
                      ),
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
                                Text(_dateFormat.format(item.date!), style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
                              ],
                            ),
                          if (item.dueDate != null)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.event_rounded, size: 13, color: isOverdue ? Colors.red.shade700 : Colors.grey.shade500),
                                const SizedBox(width: 4),
                                Text(
                                  'Due: ${_dateFormat.format(item.dueDate!)}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: isOverdue ? FontWeight.bold : FontWeight.normal,
                                    color: isOverdue ? Colors.red.shade800 : Colors.grey.shade700,
                                  ),
                                ),
                              ],
                            ),
                          if (item.billType != null && item.billType!.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                item.billType!,
                                style: TextStyle(fontSize: 9, color: color, fontWeight: FontWeight.w600),
                              ),
                            ),
                          if (item.mobile != null && item.mobile!.trim().isNotEmpty)
                            InkWell(
                              onTap: () {
                                Clipboard.setData(ClipboardData(text: item.mobile!.trim()));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Copied phone: ${item.mobile}'),
                                    duration: const Duration(seconds: 2),
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              },
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.phone_rounded, size: 12, color: Colors.blue.shade600),
                                  const SizedBox(width: 4),
                                  Text(
                                    item.mobile!,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.blue.shade700,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
