import 'package:flutter/material.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import '../config/app_theme.dart';
import '../models/ledger.dart';
import '../providers/company_provider.dart';
import '../services/supabase_service.dart';
import '../widgets/search_bar_widget.dart';
import '../widgets/summary_card.dart';
import '../widgets/shimmer_loading.dart';
import '../widgets/empty_state.dart';

class LedgerScreen extends StatefulWidget {
  final VoidCallback? onBack;
  const LedgerScreen({super.key, this.onBack});

  @override
  State<LedgerScreen> createState() => _LedgerScreenState();
}

class _LedgerScreenState extends State<LedgerScreen> {
  final SupabaseService _service = SupabaseService();
  List<Ledger> _customers = [];
  List<Ledger> _filteredCustomers = [];
  bool _isLoading = true;
  String? _error;
  final TextEditingController _searchController = TextEditingController();

  // Search filter flags
  bool _searchInName = true;
  bool _searchInCategory = true;
  bool _searchInPlace = true;

  String _typeFilter = 'All';

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
      _filteredCustomers = _customers.where((customer) {
        bool matchesSearch = true;
        if (query.isNotEmpty) {
          final matchesName = _searchInName && customer.name.toLowerCase().contains(query);
          final matchesCategory = _searchInCategory && (customer.categoryName?.toLowerCase().contains(query) ?? false);
          final matchesPlace = _searchInPlace && (
            (customer.city?.toLowerCase().contains(query) ?? false) || 
            (customer.fullAddress.toLowerCase().contains(query))
          );
          matchesSearch = matchesName || matchesCategory || matchesPlace;
        }

        bool matchesType = true;
        if (_typeFilter == 'Debtors') {
          matchesType = customer.ledgerType?.toLowerCase().contains('debtor') ?? false;
        } else if (_typeFilter == 'Creditors') {
          matchesType = customer.ledgerType?.toLowerCase().contains('creditor') ?? false;
        }

        return matchesSearch && matchesType;
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
    setState(() { _isLoading = true; _error = null; });
    try {
      final company = CompanyProvider.of(context).selectedCompany;
      final items = await _service.getCustomers(companyName: company);
      if (mounted) {
        setState(() { 
          _customers = items; 
          _filteredCustomers = items;
          _isLoading = false; 
        });
        _onSearchChanged();
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _isLoading = false; });
    }
  }

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
        title: const Text('Customers / Ledgers'),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        actions: [
          IconButton(onPressed: _loadData, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        color: AppTheme.primaryColor,
        child: Column(
          children: [
            _buildHeader(),
            SearchBarWidget(
              hintText: 'Search customers...',
              controller: _searchController,
              onChanged: (_) {}, // Handled by listener
              trailing: PopupMenuButton<String>(
                icon: const Icon(Icons.tune_rounded, color: AppTheme.primaryColor),
                onSelected: (value) {
                  setState(() {
                    if (value == 'name') _searchInName = !_searchInName;
                    if (value == 'category') _searchInCategory = !_searchInCategory;
                    if (value == 'place') _searchInPlace = !_searchInPlace;
                  });
                  _onSearchChanged();
                },
                itemBuilder: (context) => [
                  _buildFilterItem('Customer Name', _searchInName, 'name'),
                  _buildFilterItem('Category Name', _searchInCategory, 'category'),
                  _buildFilterItem('Place / City', _searchInPlace, 'place'),
                ],
              ),
            ),
            _buildTypeFilter(),
            const SizedBox(height: 4),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    if (_isLoading) return const SizedBox.shrink();
    final activeCount = _filteredCustomers.where((c) => c.isActive).length;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF1A73E8), Color(0xFF0D47A1)]),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Total Customers', style: TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 4),
                Text('${_filteredCustomers.length}', style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w700)),
                Text('$activeCount active', style: const TextStyle(color: Colors.white60, fontSize: 12)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.people_rounded, color: Colors.white, size: 24),
          ),
        ],
      ),
    );
  }

  Widget _buildTypeFilter() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: ['All', 'Debtors', 'Creditors'].map((type) {
          final isSelected = _typeFilter == type;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(type, style: TextStyle(fontSize: 13, color: isSelected ? Colors.white : Colors.black87)),
              selected: isSelected,
              selectedColor: AppTheme.primaryColor,
              checkmarkColor: Colors.white,
              onSelected: (selected) {
                if (selected) {
                  setState(() => _typeFilter = type);
                  _onSearchChanged();
                }
              },
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const ShimmerLoading();
    if (_error != null) return ErrorState(message: _error!, onRetry: _loadData);
    if (_filteredCustomers.isEmpty) {
      return EmptyState(
        icon: Icons.people_outlined,
        title: 'No Customers Found',
        subtitle: _searchController.text.isNotEmpty ? 'Try a different search term or check filters' : 'Customer data will appear here once synced from Tally',
        onRetry: _loadData,
      );
    }
    return AnimationLimiter(
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        itemCount: _filteredCustomers.length,
        itemBuilder: (context, index) {
          final customer = _filteredCustomers[index];
          return AnimationConfiguration.staggeredList(
            position: index,
            duration: const Duration(milliseconds: 350),
            child: SlideAnimation(
              verticalOffset: 30,
              child: FadeInAnimation(child: _CustomerCard(customer: customer)),
            ),
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

class _CustomerCard extends StatelessWidget {
  final Ledger customer;
  const _CustomerCard({required this.customer});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        shape: const Border(),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppTheme.primaryColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.person_rounded, color: AppTheme.primaryColor, size: 18),
        ),
        title: Text(
          customer.name,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF1A1F36)),
        ),
        subtitle: Text(
          customer.categoryName ?? customer.city ?? '',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (customer.openingBalance != 0)
              Text(
                formatCurrency(customer.openingBalance.abs()),
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1A1F36)),
              ),
            if (!customer.isActive)
              Container(
                margin: const EdgeInsets.only(top: 2),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(4)),
                child: Text('Inactive', style: TextStyle(fontSize: 10, color: Colors.red.shade700, fontWeight: FontWeight.w600)),
              ),
          ],
        ),
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F9FE),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              children: [
                if (customer.openingBalance != 0)
                  _detailRow('Opening Bal', formatCurrency(customer.openingBalance.abs())),
                if (customer.gstNumber != null && customer.gstNumber!.isNotEmpty)
                  _detailRow('GSTIN', customer.gstNumber!),
                if (customer.panNumber != null && customer.panNumber!.isNotEmpty)
                  _detailRow('PAN', customer.panNumber!),
                if (customer.phone != null && customer.phone!.isNotEmpty)
                  _detailRow('Mobile', customer.phone!),
                if (customer.email != null && customer.email!.isNotEmpty)
                  _detailRow('Email', customer.email!),
                if (customer.contactPerson != null && customer.contactPerson!.isNotEmpty)
                  _detailRow('Contact', customer.contactPerson!),
                if (customer.fullAddress.isNotEmpty)
                  _detailRow('Address', customer.fullAddress),
                if (customer.creditPeriod != null && customer.creditPeriod!.isNotEmpty)
                  _detailRow('Credit Period', customer.creditPeriod!),
                if (customer.creditLimit != null && customer.creditLimit! > 0)
                  _detailRow('Credit Limit', formatCurrency(customer.creditLimit!)),
                if (customer.discountPercentage > 0)
                  _detailRow('Discount', '${customer.discountPercentage.toStringAsFixed(1)}%'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade500, fontWeight: FontWeight.w500)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1A1F36))),
          ),
        ],
      ),
    );
  }
}
