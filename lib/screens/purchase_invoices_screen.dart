import 'package:flutter/material.dart';
import '../utils/error_handler.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:intl/intl.dart';
import '../config/app_theme.dart';
import '../models/purchase_invoice.dart';
import '../providers/company_provider.dart';
import '../services/supabase_service.dart';
import '../services/user_preferences_service.dart';
import '../services/pdf_service.dart';
import '../widgets/search_bar_widget.dart';
import '../widgets/summary_card.dart';
import '../widgets/shimmer_loading.dart';
import '../widgets/empty_state.dart';

enum InvoiceSortOption {
  dateNewest,
  dateOldest,
  amountHighest,
  amountLowest,
}

enum DateRangeOption {
  all,
  today,
  thisMonth,
  custom,
}

class PurchaseInvoiceScreen extends StatefulWidget {
  final VoidCallback? onBack;
  const PurchaseInvoiceScreen({super.key, this.onBack});

  @override
  State<PurchaseInvoiceScreen> createState() => _PurchaseInvoiceScreenState();
}

class _PurchaseInvoiceScreenState extends State<PurchaseInvoiceScreen> {
  final SupabaseService _service = SupabaseService();
  List<PurchaseInvoice> _invoices = [];
  List<PurchaseInvoice> _filteredInvoices = [];
  bool _isLoading = true;
  String? _error;
  final TextEditingController _searchController = TextEditingController();

  InvoiceSortOption _currentSort = InvoiceSortOption.dateNewest;
  DateRangeOption _dateRangeOption = DateRangeOption.today;
  DateTimeRange? _selectedDateRange;

  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _applyFiltersAndSort();
  }

  void _setSort(InvoiceSortOption option) {
    setState(() => _currentSort = option);
    final s = option == InvoiceSortOption.dateOldest ? 'dateOldest'
      : option == InvoiceSortOption.amountHighest ? 'amountHighest'
      : option == InvoiceSortOption.amountLowest ? 'amountLowest'
      : 'dateNewest';
    UserPreferencesService.savePurchaseSort(s);
    _applyFiltersAndSort();
  }

  void _setDateFilter(DateRangeOption option) {
    setState(() => _dateRangeOption = option);
    final s = option == DateRangeOption.thisMonth ? 'thisMonth'
      : option == DateRangeOption.all ? 'all'
      : option == DateRangeOption.custom ? 'custom'
      : 'today';
    UserPreferencesService.savePurchaseDateFilter(s);
    _applyFiltersAndSort();
  }

  void _applyFiltersAndSort() {
    final query = _searchController.text.toLowerCase();
    
    // 1. Filter by Search Query
    List<PurchaseInvoice> filtered = _invoices;
    if (query.isNotEmpty) {
      final dateFormat = DateFormat('dd MMM yyyy');
      final monthFormat = DateFormat('MMMM');

      filtered = _invoices.where((inv) {
        final matchesName = inv.supplierName.toLowerCase().contains(query);
        final matchesInvoice = inv.invoiceNumber.toLowerCase().contains(query);
        final matchesAmount = inv.netAmount.toString().contains(query) || 
                              inv.totalAmount.toString().contains(query);
        
        bool matchesDate = false;
        if (inv.invoiceDate != null) {
          final dateStr = dateFormat.format(inv.invoiceDate!).toLowerCase();
          final monthStr = monthFormat.format(inv.invoiceDate!).toLowerCase();
          matchesDate = dateStr.contains(query) || monthStr.contains(query);
        }

        return matchesName || matchesInvoice || matchesAmount || matchesDate;
      }).toList();
    }

    // 2. Filter by Date Range Preset
    final now = DateTime.now();
    DateTime? filterStart;
    DateTime? filterEnd;

    if (_dateRangeOption == DateRangeOption.today) {
      filterStart = DateTime(now.year, now.month, now.day);
      filterEnd = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
    } else if (_dateRangeOption == DateRangeOption.thisMonth) {
      filterStart = DateTime(now.year, now.month, 1);
      filterEnd = DateTime(now.year, now.month + 1, 1).subtract(const Duration(milliseconds: 1));
    } else if (_dateRangeOption == DateRangeOption.custom && _selectedDateRange != null) {
      filterStart = DateTime(_selectedDateRange!.start.year, _selectedDateRange!.start.month, _selectedDateRange!.start.day);
      filterEnd = DateTime(_selectedDateRange!.end.year, _selectedDateRange!.end.month, _selectedDateRange!.end.day, 23, 59, 59, 999);
    }

    if (filterStart != null && filterEnd != null) {
      filtered = filtered.where((inv) {
        if (inv.invoiceDate == null) return false;
        return inv.invoiceDate!.isAfter(filterStart!.subtract(const Duration(milliseconds: 1))) &&
               inv.invoiceDate!.isBefore(filterEnd!.add(const Duration(milliseconds: 1)));
      }).toList();
    }

    // 3. Sort
    filtered.sort((a, b) {
      switch (_currentSort) {
        case InvoiceSortOption.dateNewest:
        case InvoiceSortOption.dateOldest:
          if (a.invoiceDate == null) return 1;
          if (b.invoiceDate == null) return -1;

          // Compare strictly by date (ignoring time)
          final dateA = DateTime(a.invoiceDate!.year, a.invoiceDate!.month, a.invoiceDate!.day);
          final dateB = DateTime(b.invoiceDate!.year, b.invoiceDate!.month, b.invoiceDate!.day);
          
          int dateComp = _currentSort == InvoiceSortOption.dateNewest 
              ? dateB.compareTo(dateA) 
              : dateA.compareTo(dateB);
              
          if (dateComp != 0) return dateComp;

          // If same date, group by Voucher Type (ascending alphabetical)
          final typeA = a.type ?? '';
          final typeB = b.type ?? '';
          int typeComp = typeA.compareTo(typeB);
          
          if (typeComp != 0) return typeComp;

          // If same date and same type, sort sequentially by Invoice Number (ascending)
          return a.invoiceNumber.compareTo(b.invoiceNumber);

        case InvoiceSortOption.amountHighest:
          return b.netAmount.compareTo(a.netAmount);
        case InvoiceSortOption.amountLowest:
          return a.netAmount.compareTo(b.netAmount);
      }
    });

    setState(() {
      _filteredInvoices = filtered;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      _loadPreferencesAndData();
    }
  }

  Future<void> _loadPreferencesAndData() async {
    final savedSort = await UserPreferencesService.loadPurchaseSort();
    final savedDate = await UserPreferencesService.loadPurchaseDateFilter();
    if (mounted) {
      setState(() {
        _currentSort = _sortFromString(savedSort);
        _dateRangeOption = _dateFromString(savedDate);
      });
    }
    _loadData();
  }

  InvoiceSortOption _sortFromString(String s) {
    switch (s) {
      case 'dateOldest': return InvoiceSortOption.dateOldest;
      case 'amountHighest': return InvoiceSortOption.amountHighest;
      case 'amountLowest': return InvoiceSortOption.amountLowest;
      default: return InvoiceSortOption.dateNewest;
    }
  }

  DateRangeOption _dateFromString(String s) {
    switch (s) {
      case 'thisMonth': return DateRangeOption.thisMonth;
      case 'all': return DateRangeOption.all;
      default: return DateRangeOption.today;
    }
  }

  Future<void> _loadData() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final company = CompanyProvider.of(context).selectedCompany;
      final items = await _service.getPurchaseInvoices(companyName: company);
      if (mounted) {
        setState(() { 
          _invoices = items; 
          _isLoading = false; 
        });
        _applyFiltersAndSort();
      }
    } catch (e) {
      if (mounted) setState(() { _error = AppErrorHandler.getFriendlyError(e); _isLoading = false; });
    }
  }

  double get _totalPurchases => _filteredInvoices.fold(0, (sum, inv) => sum + inv.netAmount);

  double get _todaysPurchases {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    double total = 0;
    for (var inv in _invoices) {
      if (inv.invoiceDate != null) {
        final d = DateTime(inv.invoiceDate!.year, inv.invoiceDate!.month, inv.invoiceDate!.day);
        if (d.isAtSameMomentAs(today)) {
          total += inv.netAmount;
        }
      }
    }
    return total;
  }

  int get _todaysPurchasesCount {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    int count = 0;
    for (var inv in _invoices) {
      if (inv.invoiceDate != null) {
        final d = DateTime(inv.invoiceDate!.year, inv.invoiceDate!.month, inv.invoiceDate!.day);
        if (d.isAtSameMomentAs(today)) {
          count++;
        }
      }
    }
    return count;
  }

  @override
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
        title: const Text('Purchase Invoices'),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        actions: [
          IconButton(
            onPressed: _showFilterSortDialog,
            icon: const Icon(Icons.tune_rounded, color: AppTheme.purchaseColor),
            tooltip: 'Filter & Sort',
          ),
          IconButton(onPressed: _loadData, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      body: Column(
        children: [
          SearchBarWidget(
            hintText: 'Search by name, invoice, date...',
            controller: _searchController,
            onChanged: (_) {}, // Handled by listener
          ),
          _buildDateFilterPills(),
          // Scrollable content area: Header cards scroll away, list scrolls underneath
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadData,
              color: AppTheme.primaryColor,
              child: NestedScrollView(
                headerSliverBuilder: (context, innerBoxIsScrolled) => [
                  SliverToBoxAdapter(child: _buildHeader()),
                ],
                body: _buildBody(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderCard(String title, double amount, String subtitle, List<Color> colors, {VoidCallback? onActionTap}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: const TextStyle(color: Colors.white70, fontSize: 12)),
              if (onActionTap != null)
                GestureDetector(
                  onTap: onActionTap,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.bar_chart_rounded,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            formatCurrency(amount),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(subtitle, style: const TextStyle(color: Colors.white70, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    if (_isLoading) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: _buildHeaderCard(
              "Today's Purchases",
              _todaysPurchases,
              "$_todaysPurchasesCount invoice${_todaysPurchasesCount == 1 ? '' : 's'} today",
              [const Color(0xFFBA68C8), const Color(0xFF8E24AA)],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildHeaderCard(
              "Total Purchases",
              _totalPurchases,
              "${_filteredInvoices.length} invoice${_filteredInvoices.length == 1 ? '' : 's'} total",
              [const Color(0xFF8E24AA), const Color(0xFF5E35B1)],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const ShimmerLoading(height: 120);
    if (_error != null) return ErrorState(message: _error!, onRetry: _loadData);
    if (_filteredInvoices.isEmpty) {
      return EmptyState(
        icon: Icons.receipt_long_outlined,
        title: 'No Purchase Invoices Found',
        subtitle: _searchController.text.isNotEmpty ? 'Try a different search term or check filters' : 'Purchases invoice data will appear here once synced from Tally',
        onRetry: _loadData,
      );
    }
    return AnimationLimiter(
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        itemCount: _filteredInvoices.length,
        itemBuilder: (context, index) {
          final invoice = _filteredInvoices[index];
          final showHeader = index == 0 ||
              invoice.invoiceDate == null ||
              _filteredInvoices[index - 1].invoiceDate == null ||
              invoice.invoiceDate!.month != _filteredInvoices[index - 1].invoiceDate!.month ||
              invoice.invoiceDate!.year != _filteredInvoices[index - 1].invoiceDate!.year;

          Widget card = _InvoiceCard(invoice: invoice, onTap: () => _showInvoiceDetail(invoice));
          
          if (showHeader && invoice.invoiceDate != null) {
            final monthStr = DateFormat('MMMM yyyy').format(invoice.invoiceDate!);
            card = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildMonthHeader(monthStr),
                card,
              ],
            );
          }

          return AnimationConfiguration.staggeredList(
            position: index,
            duration: const Duration(milliseconds: 350),
            child: SlideAnimation(verticalOffset: 30, child: FadeInAnimation(child: card)),
          );
        },
      ),
    );
  }

  Widget _buildDialogChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    required Color activeColor,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? activeColor : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? activeColor : Colors.grey.shade300,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.black87,
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  void _showFilterSortDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final activeColor = AppTheme.purchaseColor;
            
            String customRangeLabel = 'Custom...';
            if (_dateRangeOption == DateRangeOption.custom && _selectedDateRange != null) {
              customRangeLabel = '${DateFormat('d MMM').format(_selectedDateRange!.start)} - ${DateFormat('d MMM').format(_selectedDateRange!.end)}';
            }

            Future<void> handleCustomClick() async {
              final DateTimeRange? picked = await showDateRangePicker(
                context: context,
                initialDateRange: _selectedDateRange,
                firstDate: DateTime(2020),
                lastDate: DateTime.now().add(const Duration(days: 365)),
                builder: (context, child) {
                  return Theme(
                    data: Theme.of(context).copyWith(
                      colorScheme: ColorScheme.light(
                        primary: activeColor,
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
                  _dateRangeOption = DateRangeOption.custom;
                });
                _applyFiltersAndSort();
                setDialogState(() {});
              }
            }

            return Dialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 10,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title + Close Icon
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Filter and sort',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: Icon(
                            Icons.close_rounded,
                            color: Colors.grey.shade600,
                            size: 20,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    
                    // SORT BY section
                    const Text(
                      'SORT BY',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textSecondary,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildDialogChip(
                          label: 'Newest',
                          isSelected: _currentSort == InvoiceSortOption.dateNewest,
                          onTap: () {
                            _setSort(InvoiceSortOption.dateNewest);
                            setDialogState(() {});
                          },
                          activeColor: activeColor,
                        ),
                        _buildDialogChip(
                          label: 'Oldest',
                          isSelected: _currentSort == InvoiceSortOption.dateOldest,
                          onTap: () {
                            _setSort(InvoiceSortOption.dateOldest);
                            setDialogState(() {});
                          },
                          activeColor: activeColor,
                        ),
                        _buildDialogChip(
                          label: 'Amount ↓',
                          isSelected: _currentSort == InvoiceSortOption.amountHighest,
                          onTap: () {
                            _setSort(InvoiceSortOption.amountHighest);
                            setDialogState(() {});
                          },
                          activeColor: activeColor,
                        ),
                        _buildDialogChip(
                          label: 'Amount ↑',
                          isSelected: _currentSort == InvoiceSortOption.amountLowest,
                          onTap: () {
                            _setSort(InvoiceSortOption.amountLowest);
                            setDialogState(() {});
                          },
                          activeColor: activeColor,
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    
                    // DATE RANGE section
                    const Text(
                      'DATE RANGE',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textSecondary,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildDialogChip(
                          label: 'All',
                          isSelected: _dateRangeOption == DateRangeOption.all,
                          onTap: () {
                            _setDateFilter(DateRangeOption.all);
                            setDialogState(() {});
                          },
                          activeColor: activeColor,
                        ),
                        _buildDialogChip(
                          label: 'Today',
                          isSelected: _dateRangeOption == DateRangeOption.today,
                          onTap: () {
                            _setDateFilter(DateRangeOption.today);
                            setDialogState(() {});
                          },
                          activeColor: activeColor,
                        ),
                        _buildDialogChip(
                          label: 'This month',
                          isSelected: _dateRangeOption == DateRangeOption.thisMonth,
                          onTap: () {
                            _setDateFilter(DateRangeOption.thisMonth);
                            setDialogState(() {});
                          },
                          activeColor: activeColor,
                        ),
                        _buildDialogChip(
                          label: customRangeLabel,
                          isSelected: _dateRangeOption == DateRangeOption.custom,
                          onTap: handleCustomClick,
                          activeColor: activeColor,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          );
        },
        );
      },
    );
  }

  Widget _buildMonthHeader(String monthStr) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Row(
        children: [
          const Expanded(
            child: Divider(
              color: Color(0xFFE2E8F0),
              thickness: 1,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppTheme.purchaseColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              monthStr,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppTheme.purchaseColor,
              ),
            ),
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Divider(
              color: Color(0xFFE2E8F0),
              thickness: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateFilterPills() {
    String customLabel = 'Custom Range';
    if (_dateRangeOption == DateRangeOption.custom && _selectedDateRange != null) {
      customLabel = '${DateFormat('d MMM').format(_selectedDateRange!.start)} - ${DateFormat('d MMM').format(_selectedDateRange!.end)}';
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
      child: Row(
        children: [
          _buildPill('Today', DateRangeOption.today),
          _buildPill('This Month', DateRangeOption.thisMonth),
          _buildPill('All Time', DateRangeOption.all),
          if (_dateRangeOption == DateRangeOption.custom)
            _buildPill(customLabel, DateRangeOption.custom),
        ],
      ),
    );
  }

  Widget _buildPill(String label, DateRangeOption option) {
    final isSelected = _dateRangeOption == option;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label, style: TextStyle(fontSize: 13, color: isSelected ? Colors.white : Colors.black87)),
        selected: isSelected,
        selectedColor: AppTheme.purchaseColor,
        checkmarkColor: Colors.white,
        onSelected: (selected) {
          if (selected) {
            _setDateFilter(option);
          }
        },
      ),
    );
  }

  void _showInvoiceDetail(PurchaseInvoice invoice) {
    final dateFormat = DateFormat('dd MMM yyyy');
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.90,
          maxChildSize: 0.95,
          minChildSize: 0.5,
          builder: (context, scrollController) {
            return Container(
              margin: const EdgeInsets.only(bottom: 36, left: 16, right: 16),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  Container(margin: const EdgeInsets.only(top: 12), width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.all(20),
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(color: AppTheme.purchaseColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                              child: const Icon(Icons.receipt_long_rounded, color: AppTheme.purchaseColor, size: 24),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Invoice #${invoice.invoiceNumber}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF1A1F36))),
                                  if (invoice.invoiceDate != null)
                                    Text(dateFormat.format(invoice.invoiceDate!), style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.share_rounded),
                              color: AppTheme.purchaseColor,
                              onPressed: () async {
                                try {
                                  final items = invoice.id != null ? await _service.getPurchaseInvoiceItems(invoice.id!) : <PurchaseInvoiceItem>[];
                                  await PdfService.sharePurchaseInvoice(invoice, items);
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                                  }
                                }
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        _detailSection('Supplier Details', [
                          _detailItem('Supplier', invoice.supplierName),
                          if (invoice.shippingAddress != null && invoice.shippingAddress!.isNotEmpty)
                            _detailItem('Ship To', invoice.shippingAddress!),
                          if (invoice.supplierCategoryName != null && invoice.supplierCategoryName!.isNotEmpty)
                            _detailItem('Category', invoice.supplierCategoryName!),
                          if (invoice.type != null && invoice.type!.isNotEmpty)
                            _detailItem('Type', invoice.type!),
                        ]),
                        if (invoice.id != null) ...[
                          const SizedBox(height: 16),
                          FutureBuilder<List<PurchaseInvoiceItem>>(
                            future: _service.getPurchaseInvoiceItems(invoice.id!),
                            builder: (context, snapshot) {
                              if (snapshot.connectionState == ConnectionState.waiting) {
                                return const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator(strokeWidth: 2)));
                              }
                              if (!snapshot.hasData || snapshot.data!.isEmpty) return const SizedBox.shrink();
                              return _buildItemsTable(snapshot.data!);
                            },
                          ),
                        ],
                        const SizedBox(height: 16),
                        _detailSection('Amount Details', [
                          if (invoice.subtotalBeforeDiscount > 0)
                            _detailItem('Subtotal', formatCurrency(invoice.subtotalBeforeDiscount)),
                          if (invoice.discountAmount > 0)
                            _detailItem('Discount (${invoice.discountPercentage.toStringAsFixed(1)}%)', formatCurrency(invoice.discountAmount)),
                          _detailItem('Net Amount', formatCurrency(invoice.netAmount)),
                          _detailItem('GST Amount', formatCurrency(invoice.gstAmount)),
                          if (invoice.roundOff != null && invoice.roundOff! != 0)
                            _detailItem('Round Off', formatCurrency(invoice.roundOff!)),
                          _detailItem('Total Amount', formatCurrency(invoice.totalAmount)),
                        ]),
                        const SizedBox(height: 16),
                        _detailSection('Status', [
                          if (invoice.status != null) _detailItem('Status', invoice.status!),
                          _detailItem('Tally Synced', invoice.syncedToTally ? 'Yes' : 'No'),
                          if (invoice.remarks != null && invoice.remarks!.isNotEmpty)
                            _detailItem('Remarks', invoice.remarks!),
                        ]),
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

  Widget _detailSection(String title, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: const Color(0xFFF8F9FE), borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1A1F36))),
        const SizedBox(height: 10),
        ...children,
      ]),
    );
  }

  Widget _detailItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 120, child: Text(label, style: TextStyle(fontSize: 13, color: Colors.grey.shade500))),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1A1F36)))),
      ]),
    );
  }

  Widget _buildItemsTable(List<PurchaseInvoiceItem> items) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: const Color(0xFFF8F9FE), borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Items', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1A1F36))),
        const SizedBox(height: 10),
        ...items.map((item) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade200)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(
                  children: [
                    Expanded(child: Text(item.productName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1A1F36)))),
                    Text(formatCurrency(item.totalAmount), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.purchaseColor)),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(spacing: 8, runSpacing: 4, children: [
                  _miniChip('Qty: ${item.quantity}'),
                  _miniChip('Rate: \u20B9${item.unitPrice.toStringAsFixed(2)}'),
                  _miniChip('GST: ${item.gstRate.toStringAsFixed(0)}%'),
                  if (item.freeQuantity > 0) _miniChip('Free: ${item.freeQuantity}'),
                  if (item.discountAmount > 0) _miniChip('Disc: \u20B9${item.discountAmount.toStringAsFixed(2)}'),
                ]),
              ]),
            )),
      ]),
    );
  }

  Widget _miniChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(6)),
      child: Text(text, style: TextStyle(fontSize: 11, color: Colors.grey.shade700, fontWeight: FontWeight.w500)),
    );
  }
}

class _InvoiceCard extends StatelessWidget {
  final PurchaseInvoice invoice;
  final VoidCallback? onTap;
  const _InvoiceCard({required this.invoice, this.onTap});

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd MMM yyyy');
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.grey.shade200)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: AppTheme.purchaseColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.receipt_long_rounded, color: AppTheme.purchaseColor, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(invoice.supplierName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF1A1F36))),
                    const SizedBox(height: 2),
                    Text('#${invoice.invoiceNumber}', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                  ]),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(formatCurrency(invoice.totalAmount), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.purchaseColor)),
                    if (invoice.invoiceDate != null)
                      Padding(padding: const EdgeInsets.only(top: 2), child: Text(dateFormat.format(invoice.invoiceDate!), style: TextStyle(fontSize: 11, color: Colors.grey.shade500))),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (invoice.status != null) _statusChip(invoice.status!),
                const SizedBox(width: 8),
                if (invoice.type != null && invoice.type!.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: AppTheme.purchaseColor.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(6)),
                    child: Text(invoice.type!, style: const TextStyle(fontSize: 11, color: AppTheme.purchaseColor, fontWeight: FontWeight.w600)),
                  ),
                const Spacer(),
                Icon(invoice.syncedToTally ? Icons.cloud_done_rounded : Icons.cloud_off_rounded, size: 16, color: invoice.syncedToTally ? Colors.green : Colors.grey.shade400),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusChip(String status) {
    Color color;
    switch (status.toLowerCase()) {
      case 'paid': color = Colors.green; break;
      case 'pending': color = Colors.orange; break;
      case 'cancelled': color = Colors.red; break;
      default: color = Colors.grey;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
      child: Text(status, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
    );
  }
}


