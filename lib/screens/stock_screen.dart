import 'package:flutter/material.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import '../config/app_theme.dart';
import '../models/stock_item.dart';
import '../providers/company_provider.dart';
import '../services/supabase_service.dart';
import '../widgets/search_bar_widget.dart';
import '../widgets/summary_card.dart';
import '../widgets/shimmer_loading.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_state_widget.dart';

class StockScreen extends StatefulWidget {
  final VoidCallback? onBack;
  const StockScreen({super.key, this.onBack});

  @override
  State<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends State<StockScreen> {
  final SupabaseService _service = SupabaseService();
  List<StockItem> _products = [];
  List<StockItem> _filteredProducts = [];
  bool _isLoading = true;
  String? _error;
  final TextEditingController _searchController = TextEditingController();

  // Search filter flags
  bool _searchInName = true;
  bool _searchInPartNumber = true;
  bool _searchInRate = true;
  bool _searchInQuantity = true;

  String _stockFilter = 'All'; // 'All', 'Low Stock', 'Zero Stock'

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
    final query = _searchController.text.toLowerCase();

    setState(() {
      _filteredProducts = _products.where((item) {
        bool matchesSearch = true;
        if (query.isNotEmpty) {
          final matchesName = _searchInName && item.name.toLowerCase().contains(query);
          final matchesPart = _searchInPartNumber && (item.partNumber?.toLowerCase().contains(query) ?? false);
          final matchesRate = _searchInRate && item.rate.toString().contains(query);
          final matchesQty = _searchInQuantity && item.quantity.toString().contains(query);
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
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final company = CompanyProvider.of(context).selectedCompany;
      final items = await _service.getProducts(companyName: company);
      if (mounted) {
        setState(() {
          _products = items;
          _filteredProducts = items;
          _isLoading = false;
        });
        _onSearchChanged(); // Re-apply current search if any
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  double get _totalValue {
    try {
      return _filteredProducts.fold(0.0, (sum, item) => sum + item.stockValue);
    } catch (_) {
      return 0.0;
    }
  }
  int get _totalItems => _filteredProducts.length;

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
        title: const Text('Products / Stock'),
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
        child: Column(
          children: [
            _buildHeader(),
            SearchBarWidget(
              hintText: 'Search by name, part no, rate...',
              controller: _searchController,
              onChanged: (_) {}, // Handled by listener
              trailing: PopupMenuButton<String>(
                icon: Icon(Icons.tune_rounded, color: AppTheme.primaryColor),
                onSelected: (value) {
                  setState(() {
                    if (value == 'name') _searchInName = !_searchInName;
                    if (value == 'part') _searchInPartNumber = !_searchInPartNumber;
                    if (value == 'rate') _searchInRate = !_searchInRate;
                    if (value == 'qty') _searchInQuantity = !_searchInQuantity;
                  });
                  _onSearchChanged();
                },
                itemBuilder: (context) => [
                  _buildFilterItem('Item Name', _searchInName, 'name'),
                  _buildFilterItem('Part Number', _searchInPartNumber, 'part'),
                  _buildFilterItem('Rate', _searchInRate, 'rate'),
                  _buildFilterItem('Quantity', _searchInQuantity, 'qty'),
                ],
              ),
            ),
            _buildStockFilter(),
            const SizedBox(height: 4),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    if (_isLoading) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF9C27B0), Color(0xFF7B1FA2)],
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Total Stock Value',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                  _onSearchChanged();
                }
              },
            ),
          );
        }).toList(),
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

  Widget _buildBody() {
    if (_isLoading) return const ShimmerLoading();
    if (_error != null) return ErrorStateWidget(error: _error, onRetry: _loadData);
    if (_filteredProducts.isEmpty) {
      return EmptyState(
        icon: Icons.inventory_2_outlined,
        title: 'No Products Found',
        subtitle: _searchController.text.isNotEmpty
            ? 'Try a different search term or check filters'
            : 'Product data will appear here once synced from Tally',
        onRetry: _loadData,
      );
    }

    return AnimationLimiter(
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        itemCount: _filteredProducts.length,
        itemBuilder: (context, index) {
          final item = _filteredProducts[index];
          return AnimationConfiguration.staggeredList(
            position: index,
            duration: const Duration(milliseconds: 350),
            child: SlideAnimation(
              verticalOffset: 30,
              child: FadeInAnimation(
                child: _ProductCard(item: item),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  final StockItem item;
  const _ProductCard({required this.item});

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
                  color: AppTheme.stockColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.medication_rounded, color: AppTheme.stockColor, size: 20),
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
                formatCurrency(item.stockValue),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A1F36),
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
                _DetailChip(label: 'Rate', value: '\u20B9${item.rate.toStringAsFixed(2)}'),
                _divider(),
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
