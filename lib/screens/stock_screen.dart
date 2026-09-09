import 'package:flutter/material.dart';
import '../utils/error_handler.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import '../config/app_theme.dart';
import '../models/stock_item.dart';
import '../providers/company_provider.dart';
import '../services/supabase_service.dart';
import '../services/user_preferences_service.dart';
import '../widgets/search_bar_widget.dart';
import '../widgets/summary_card.dart';
import '../widgets/shimmer_loading.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_state_widget.dart';

class StockScreen extends StatefulWidget {
  final VoidCallback? onBack;
  final bool showSalesValue;
  const StockScreen({super.key, this.onBack, this.showSalesValue = false});

  @override
  State<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends State<StockScreen> {
  final SupabaseService _service = SupabaseService();
  Map<String, double> _productSales = {};
  List<StockItem>? _pendingProducts;
  Map<String, double>? _pendingSalesMap;
  List<StockItem> _products = [];
  List<StockItem> _filteredProducts = [];
  bool _isLoading = true;
  String? _error;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  String _sortBy = 'qty_desc'; // 'qty_desc', 'qty_asc'
  String _stockFilter = 'All'; // 'All', 'Low Stock', 'Zero Stock'

  bool _initialized = false;
  late bool _showSalesValue;

  @override
  void initState() {
    super.initState();
    _showSalesValue = widget.showSalesValue;
    _searchController.addListener(_onSearchChanged);
    _scrollController.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(StockScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.showSalesValue != oldWidget.showSalesValue) {
      setState(() {
        _showSalesValue = widget.showSalesValue;
      });
      _loadData();
    }
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _pendingProducts = null;
    super.dispose();
  }

  void _onScroll() {
    if (_pendingProducts == null) return;
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.pixels <= 0 || pos.pixels >= pos.maxScrollExtent) {
      _applyPendingData();
    }
  }

  void _applyPendingData() {
    if (_pendingProducts == null) return;
    _products = _pendingProducts!;
    _productSales = _pendingSalesMap ?? {};
    _pendingProducts = null;
    _pendingSalesMap = null;
    _onSearchChanged();
  }

  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase();

    final filtered = _products.where((item) {
      bool matchesSearch = true;
      if (query.isNotEmpty) {
        final matchesName = item.name.toLowerCase().contains(query);
        final matchesPart = item.partNumber?.toLowerCase().contains(query) ?? false;
        final matchesRate = item.rate.toString().contains(query);
        final matchesQty = item.quantity.toString().contains(query);
        matchesSearch = matchesName || matchesPart || matchesRate || matchesQty;
      }

      bool matchesFilter = true;
      if (_stockFilter == 'Zero Stock') {
        matchesFilter = item.quantity <= 0;
      } else if (_stockFilter == 'Low Stock') {
        matchesFilter = item.quantity > 0 && item.quantity <= 10;
      }

      return matchesSearch && matchesFilter;
    }).toList();

    // Sort products based on user choice
    if (_sortBy == 'qty_asc') {
      filtered.sort((a, b) => a.quantity.compareTo(b.quantity));
    } else {
      filtered.sort((a, b) => b.quantity.compareTo(a.quantity));
    }

    setState(() {
      _filteredProducts = filtered;
    });
  }

  int? _lastSyncTrigger;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final syncTrigger = CompanyProvider.of(context).syncTrigger;
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
    final savedSort = await UserPreferencesService.loadStockSort();
    final savedFilter = await UserPreferencesService.loadStockStatusFilter();
    if (mounted) {
      setState(() {
        _sortBy = savedSort;
        _stockFilter = savedFilter;
      });
    }
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final company = CompanyProvider.of(context).selectedCompany;
      final items = await _service.getProducts(companyName: company);
      Map<String, double> salesMap = {};
      if (company != null) {
        salesMap = await _service.getProductSalesTotals(companyName: company);
      }
      if (mounted) {
        setState(() {
          _products = items;
          _filteredProducts = items;
          _productSales = salesMap;
          _pendingProducts = null;
          _isLoading = false;
        });
        _onSearchChanged();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = AppErrorHandler.getFriendlyError(e);
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _silentRefresh() async {
    if (!mounted) return;
    try {
      final company = CompanyProvider.of(context).selectedCompany;
      final items = await _service.getProducts(companyName: company);
      Map<String, double> salesMap = {};
      if (company != null) {
        salesMap = await _service.getProductSalesTotals(companyName: company);
      }
      if (!mounted) return;
      _pendingProducts = items;
      _pendingSalesMap = salesMap;
      if (!_scrollController.hasClients) {
        _applyPendingData();
      } else {
        final pos = _scrollController.position;
        if (pos.pixels <= 0 || pos.pixels >= pos.maxScrollExtent) {
          _applyPendingData();
        }
      }
    } catch (_) {
      // Fail silently
    }
  }

  double get _totalValue {
    try {
      if (_showSalesValue) {
        return _filteredProducts.fold(0.0, (sum, item) => sum + (_productSales[item.name] ?? 0.0));
      }
      return _filteredProducts.fold(0.0, (sum, item) => sum + item.stockValue);
    } catch (_) {
      return 0.0;
    }
  }
  int get _totalItems => _filteredProducts.length;

  @override
  Widget build(BuildContext context) {
    final companyState = CompanyProvider.of(context);
    final showCostPrice = companyState.isFeatureEnabled('stock_cost');

    return Scaffold(
      primary: false,
      backgroundColor: AppTheme.surfaceColor,
      appBar: AppBar(
        toolbarHeight: 46.0,
        leading: widget.onBack != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: widget.onBack,
              )
            : null,
        title: Text(_showSalesValue ? 'Products Sales Value' : 'Products'),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        actions: [
          IconButton(
            onPressed: _loadData,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        color: AppTheme.primaryColor,
        child: CustomScrollView(
          controller: _scrollController,
          slivers: [
            if (showCostPrice) SliverToBoxAdapter(child: _buildModeToggle()),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                child: Row(
                  children: [
                    Expanded(
                      child: SearchBarWidget(
                        margin: EdgeInsets.zero,
                        hintText: 'Search by name, part no, rate...',
                        controller: _searchController,
                        onChanged: (_) {}, // Handled by listener
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
                            _sortBy = value;
                          });
                          UserPreferencesService.saveStockSort(value);
                          _onSearchChanged();
                        },
                        itemBuilder: (context) => [
                          PopupMenuItem(
                            value: 'qty_desc',
                            child: Row(
                              children: [
                                Icon(
                                  Icons.arrow_downward_rounded,
                                  size: 18,
                                  color: _sortBy == 'qty_desc' ? AppTheme.primaryColor : Colors.grey,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Quantity: High to Low',
                                  style: TextStyle(
                                    fontWeight: _sortBy == 'qty_desc' ? FontWeight.bold : FontWeight.normal,
                                    color: _sortBy == 'qty_desc' ? AppTheme.primaryColor : Colors.black,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'qty_asc',
                            child: Row(
                              children: [
                                Icon(
                                  Icons.arrow_upward_rounded,
                                  size: 18,
                                  color: _sortBy == 'qty_asc' ? AppTheme.primaryColor : Colors.grey,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Quantity: Low to High',
                                  style: TextStyle(
                                    fontWeight: _sortBy == 'qty_asc' ? FontWeight.bold : FontWeight.normal,
                                    color: _sortBy == 'qty_asc' ? AppTheme.primaryColor : Colors.black,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(child: _buildStockFilter()),
            if (showCostPrice) SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: _buildHeader())),
            _buildSliverBody(showCostPrice: showCostPrice),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    if (_isLoading) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: _showSalesValue
              ? [const Color(0xFF00BCD4), const Color(0xFF00838F)]
              : [const Color(0xFF9C27B0), const Color(0xFF7B1FA2)],
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _showSalesValue ? 'Total Sales Value' : 'Total Stock Value',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 4),
                Text(
                  formatCurrency(_totalValue),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$_totalItems products',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStockFilter() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 2),
      child: Row(
        children: ['All', 'Low Stock', 'Zero Stock'].map((filter) {
          final isSelected = _stockFilter == filter;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(filter, style: TextStyle(fontSize: 13, color: isSelected ? Colors.white : Colors.black87)),
              selected: isSelected,
              selectedColor: AppTheme.primaryColor,
              checkmarkColor: Colors.white,
              onSelected: (selected) {
                if (selected) {
                  setState(() => _stockFilter = filter);
                  UserPreferencesService.saveStockStatusFilter(filter);
                  _onSearchChanged();
                }
              },
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSliverBody({bool showCostPrice = true}) {
    if (_isLoading) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: ShimmerLoading(),
      );
    }
    if (_error != null) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: ErrorStateWidget(error: _error, onRetry: _loadData),
      );
    }
    if (_filteredProducts.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: EmptyState(
          icon: Icons.inventory_2_outlined,
          title: 'No Products Found',
          subtitle: _searchController.text.isNotEmpty
              ? 'Try a different search term or check filters'
              : 'Product data will appear here once synced from Tally',
          onRetry: _loadData,
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final item = _filteredProducts[index];
            return AnimationConfiguration.staggeredList(
              position: index,
              duration: const Duration(milliseconds: 350),
              child: SlideAnimation(
                verticalOffset: 30,
                child: FadeInAnimation(
                  child: _ProductCard(
                    item: item,
                    salesValue: _productSales[item.name] ?? 0.0,
                    showSalesValue: _showSalesValue,
                    showCostPrice: showCostPrice,
                  ),
                ),
              ),
            );
          },
          childCount: _filteredProducts.length,
        ),
      ),
    );
  }

  void _toggleViewMode(bool showSales) {
    if (showSales == _showSalesValue) return;
    setState(() {
      _showSalesValue = showSales;
    });
  }

  Widget _buildModeToggle() {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 320),
        margin: const EdgeInsets.fromLTRB(16, 2, 16, 2),
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(30),
        ),
        child: Row(
          children: [
            Expanded(
              child: _buildToggleTab(
                label: 'Stock Value',
                icon: Icons.inventory_2_rounded,
                isSelected: !_showSalesValue,
                selectedColor: AppTheme.stockColor,
                onTap: () => _toggleViewMode(false),
              ),
            ),
            Expanded(
              child: _buildToggleTab(
                label: 'Sales Value',
                icon: Icons.trending_up_rounded,
                isSelected: _showSalesValue,
                selectedColor: AppTheme.salesColor,
                onTap: () => _toggleViewMode(true),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToggleTab({
    required String label,
    required IconData icon,
    required bool isSelected,
    required Color selectedColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(26),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  )
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? selectedColor : const Color(0xFF64748B),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: isSelected ? const Color(0xFF1E293B) : const Color(0xFF64748B),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  final StockItem item;
  final double salesValue;
  final bool showSalesValue;
  final bool showCostPrice;
  const _ProductCard({
    required this.item,
    this.salesValue = 0.0,
    this.showSalesValue = false,
    this.showCostPrice = true,
  });

  @override
  Widget build(BuildContext context) {
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: (showSalesValue ? AppTheme.salesColor : AppTheme.stockColor).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  showSalesValue ? Icons.trending_up_rounded : Icons.medication_rounded,
                  color: showSalesValue ? AppTheme.salesColor : AppTheme.stockColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1A1F36),
                      ),
                    ),
                    if (item.parent != null && item.parent!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          item.parent!,
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                        ),
                      ),
                  ],
                ),
              ),
              Text(
              formatCurrency(showSalesValue ? salesValue : item.stockValue),
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: showSalesValue ? AppTheme.salesColor : const Color(0xFF1A1F36),
              ),
            ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F9FE),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                _DetailChip(label: 'Qty', value: '${item.quantity}'),
                _divider(),
                if (showCostPrice) ...[
                  _DetailChip(label: 'Rate', value: '\u20B9${item.rate.toStringAsFixed(2)}'),
                  _divider(),
                ],
                _DetailChip(label: 'MRP', value: '\u20B9${item.mrp.toStringAsFixed(2)}'),
                _divider(),
                _DetailChip(label: 'Unit', value: item.unit ?? '-'),
              ],
            ),
          ),
          if (item.hsn != null && item.hsn!.isNotEmpty || item.gstRate > 0) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                if (item.hsn != null && item.hsn!.isNotEmpty)
                  _TagChip(label: 'HSN: ${item.hsn}'),
                if (item.gstRate > 0) ...[
                  const SizedBox(width: 8),
                  _TagChip(label: 'GST: ${item.gstRate.toStringAsFixed(0)}%'),
                ],
                if (item.category != null && item.category!.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  _TagChip(label: item.category!),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _divider() {
    return Container(
      width: 1,
      height: 24,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: Colors.grey.shade300,
    );
  }
}

class _DetailChip extends StatelessWidget {
  final String label;
  final String value;
  const _DetailChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(label, style: TextStyle(fontSize: 10, color: Colors.grey.shade500, fontWeight: FontWeight.w500)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1A1F36)), maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  final String label;
  const _TagChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppTheme.stockColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label, style: const TextStyle(fontSize: 11, color: AppTheme.stockColor, fontWeight: FontWeight.w600)),
    );
  }
}
