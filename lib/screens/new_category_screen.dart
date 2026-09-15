import 'package:flutter/material.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';

import '../config/app_theme.dart';
import '../models/stock_item.dart';
import '../providers/company_provider.dart';
import '../services/supabase_service.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_state_widget.dart';
import '../widgets/shimmer_loading.dart';
import '../widgets/summary_card.dart'; // For formatCurrency
import '../widgets/search_bar_widget.dart';

class NewCategoryScreen extends StatefulWidget {
  final List<String> newCategories;
  final String? screenTitle;

  const NewCategoryScreen({
    super.key,
    required this.newCategories,
    this.screenTitle,
  });

  @override
  State<NewCategoryScreen> createState() => _NewCategoryScreenState();
}

class _NewCategoryScreenState extends State<NewCategoryScreen> {
  final SupabaseService _service = SupabaseService();
  bool _isLoading = true;
  String? _error;
  List<StockItem> _categoryProducts = [];
  List<StockItem> _filteredProducts = [];
  final TextEditingController _searchController = TextEditingController();

  bool _isInit = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_isInit) {
      _loadData();
      _isInit = false;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String? query) {
    setState(() {
      final safeQuery = query ?? '';
      if (safeQuery.isEmpty) {
        _filteredProducts = _categoryProducts;
      } else {
        final lowerQuery = safeQuery.toLowerCase();
        _filteredProducts = _categoryProducts.where((item) {
          final itemName = item.name ?? '';
          return itemName.toLowerCase().contains(lowerQuery) ||
                 (item.parent != null && item.parent!.toLowerCase().contains(lowerQuery));
        }).toList();
      }
    });
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
          _categoryProducts = items.where((i) => widget.newCategories.contains(i.parent)).toList();
          _filteredProducts = _categoryProducts;
          _isLoading = false;
        });
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

  Widget _buildProductCard(StockItem item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF1F5F9)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  item.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    color: Color(0xFF1E293B),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  item.parent ?? 'Unknown',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF64748B),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Current Stock', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                  const SizedBox(height: 4),
                  Text(
                    '${item.quantity} ${item.unit ?? ''}',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: item.quantity <= 0 ? Colors.red : const Color(0xFF334155),
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('Stock Value', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                  const SizedBox(height: 4),
                  Text(
                    formatCurrency(item.stockValue),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: Color(0xFF334155),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surfaceColor,
      appBar: AppBar(
        title: Text(widget.screenTitle ?? 'New Arrivals', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: SearchBarWidget(
              controller: _searchController,
              hintText: 'Search products...',
              onChanged: _onSearchChanged,
              margin: EdgeInsets.zero,
            ),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const ShimmerLoading();
    }
    if (_error != null) {
      return ErrorStateWidget(error: _error, onRetry: _loadData);
    }
    if (_filteredProducts.isEmpty) {
      return const EmptyState(
        icon: Icons.inventory_2_outlined,
        title: 'No Products Found',
        subtitle: 'Could not find any products matching your search.',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _filteredProducts.length,
      itemBuilder: (context, index) {
        return _buildProductCard(_filteredProducts[index]);
      },
    );
  }
}
