import 'package:flutter/material.dart';
import '../utils/error_handler.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:intl/intl.dart';
import '../config/app_theme.dart';
import '../models/daybook_entry.dart';
import '../providers/company_provider.dart';
import '../services/supabase_service.dart';
import '../widgets/search_bar_widget.dart';
import '../widgets/shimmer_loading.dart';
import '../widgets/empty_state.dart';

class DaybookScreen extends StatefulWidget {
  final VoidCallback? onBack;
  const DaybookScreen({super.key, this.onBack});

  @override
  State<DaybookScreen> createState() => _DaybookScreenState();
}

class _DaybookScreenState extends State<DaybookScreen> {
  final SupabaseService _service = SupabaseService();
  List<DaybookEntry> _allEntries = [];
  List<DaybookEntry> _entries = [];
  List<DaybookEntry>? _pendingAllEntries; // Holds data fetched silently
  bool _isLoading = true;
  String? _error;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  DateTime _selectedDate = DateTime.now();

  String _selectedCategory = 'All';
  final List<String> _categories = [
    'All',
    'Sales',
    'Purchases',
    'Receipts',
    'Payments',
    'Journals & Contras'
  ];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _pendingAllEntries = null;
    super.dispose();
  }

  void _onScroll() {
    if (_pendingAllEntries == null) return;
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    final atTop = pos.pixels <= 0;
    final atBottom = pos.pixels >= pos.maxScrollExtent;
    if (atTop || atBottom) {
      _applyPendingData();
    }
  }

  void _applyPendingData() {
    if (_pendingAllEntries == null) return;
    _allEntries = _pendingAllEntries!;
    _pendingAllEntries = null;
    _applyFilter();
  }

  void _onSearchChanged() {
    // Basic debounce logic can go here, but for now just reload
    _loadData();
  }

  bool _initialized = false;
  int? _lastSyncTrigger;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final syncTrigger = CompanyProvider.of(context).syncTrigger;
    if (!_initialized) {
      _initialized = true;
      _lastSyncTrigger = syncTrigger;
      _loadData();
    } else if (_lastSyncTrigger != syncTrigger) {
      _lastSyncTrigger = syncTrigger;
      _silentRefresh();
    }
  }

  void _applyFilter() {
    if (_selectedCategory == 'All') {
      setState(() => _entries = List.from(_allEntries));
      return;
    }
    
    setState(() {
      _entries = _allEntries.where((entry) {
        final type = entry.voucherType.toLowerCase();
        switch (_selectedCategory) {
          case 'Sales':
            return type.contains('sales') || type.contains('invoice');
          case 'Purchases':
            return type.contains('purchase') || type.contains('bill');
          case 'Receipts':
            return type.contains('receipt');
          case 'Payments':
            return type.contains('payment');
          case 'Journals & Contras':
            return type.contains('journal') || type.contains('contra');
          default:
            return true;
        }
      }).toList();
    });
  }

  List<DaybookEntry> _sortItems(List<DaybookEntry> items) {
    items.sort((a, b) {
      if (a.date == null) return 1;
      if (b.date == null) return -1;
      final dateA = DateTime(a.date!.year, a.date!.month, a.date!.day);
      final dateB = DateTime(b.date!.year, b.date!.month, b.date!.day);
      int dateComp = dateB.compareTo(dateA);
      if (dateComp != 0) return dateComp;
      int typeComp = a.voucherType.compareTo(b.voucherType);
      if (typeComp != 0) return typeComp;
      return (a.voucherNumber ?? '').compareTo(b.voucherNumber ?? '');
    });
    return items;
  }

  Future<void> _loadData() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final company = CompanyProvider.of(context).selectedCompany;
      final query = _searchController.text.toLowerCase();
      final items = await _service.getDaybookEntries(
        companyName: company,
        date: _selectedDate,
        searchQuery: query.isNotEmpty ? query : null,
      );
      if (mounted) {
        _allEntries = _sortItems(items);
        _pendingAllEntries = null;
        _applyFilter();
        setState(() { _isLoading = false; });
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
      final query = _searchController.text.toLowerCase();
      final items = await _service.getDaybookEntries(
        companyName: company,
        date: _selectedDate,
        searchQuery: query.isNotEmpty ? query : null,
      );
      if (!mounted) return;
      _pendingAllEntries = _sortItems(items);
      // Apply immediately if at top or bottom of list
      if (!_scrollController.hasClients) {
        _applyPendingData();
      } else {
        final pos = _scrollController.position;
        if (pos.pixels <= 0 || pos.pixels >= pos.maxScrollExtent) {
          _applyPendingData();
        }
      }
    } catch (_) {
      // Fail silently — user can pull-to-refresh if needed
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppTheme.primaryColor,
              onPrimary: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
      _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surfaceColor,
      appBar: AppBar(
        leading: widget.onBack != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: widget.onBack,
              )
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).pop(),
              ),
        title: const Text('Daybook'),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        actions: [
          IconButton(
            onPressed: () => _selectDate(context),
            icon: const Icon(Icons.calendar_month_rounded),
          ),
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
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: Colors.white,
              child: Row(
                children: [
                  const Icon(Icons.today_rounded, color: AppTheme.primaryColor, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    DateFormat('EEEE, MMM d, yyyy').format(_selectedDate),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF1A1F36)),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () {
                      setState(() => _selectedDate = DateTime.now());
                      _loadData();
                    },
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('Today'),
                  ),
                ],
              ),
            ),
            SearchBarWidget(
              hintText: 'Search voucher, ledger, type...',
              controller: _searchController,
              onChanged: (_) {}, 
            ),
            const SizedBox(height: 8),
            _buildCategoryFilter(),
            const SizedBox(height: 4),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryFilter() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: _categories.map((c) {
          final selected = _selectedCategory == c;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(c),
              selected: selected,
              onSelected: (_) {
                setState(() { _selectedCategory = c; });
                _applyFilter();
              },
              selectedColor: AppTheme.primaryColor,
              labelStyle: TextStyle(
                color: selected ? Colors.white : Colors.grey.shade700,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                fontSize: 13,
              ),
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const ShimmerLoading();
    if (_error != null) return ErrorState(message: _error!, onRetry: _loadData);
    if (_entries.isEmpty) {
      return EmptyState(
        icon: Icons.menu_book_rounded,
        title: 'No Transactions',
        subtitle: 'No daybook entries found for this date',
        onRetry: _loadData,
      );
    }

    return AnimationLimiter(
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: _entries.length,
        itemBuilder: (context, index) {
          final entry = _entries[index];
          return AnimationConfiguration.staggeredList(
            position: index,
            duration: const Duration(milliseconds: 350),
            child: SlideAnimation(
              verticalOffset: 30,
              child: FadeInAnimation(
                child: _DaybookCard(entry: entry),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _DaybookCard extends StatelessWidget {
  final DaybookEntry entry;
  const _DaybookCard({required this.entry});

  void _showEntryDetails(BuildContext context, Color color, IconData icon) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _DetailsBottomSheet(entry: entry, color: color, icon: icon),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDebit = entry.isDebit;
    final Color color = isDebit ? Colors.green.shade600 : Colors.red.shade600;
    final IconData icon = isDebit ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _showEntryDetails(context, color, icon),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.ledgerName,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF1A1F36)),
                      ),
                      const SizedBox(height: 2),
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: Text(
                              entry.voucherType,
                              style: TextStyle(fontSize: 10, color: Colors.grey.shade700, fontWeight: FontWeight.w600),
                            ),
                          ),
                          if (entry.voucherNumber != null && entry.voucherNumber!.isNotEmpty)
                            Text('#${entry.voucherNumber}', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                        ],
                      ),
                      if (entry.narration != null && entry.narration!.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(entry.narration!, style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontStyle: FontStyle.italic)),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      NumberFormat.currency(locale: 'en_IN', symbol: '\u20B9').format(entry.amount),
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: color),
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
}

class _DetailsBottomSheet extends StatelessWidget {
  final DaybookEntry entry;
  final Color color;
  final IconData icon;

  const _DetailsBottomSheet({
    required this.entry,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.only(top: 12, bottom: 24, left: 24, right: 24),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle for the bottom sheet
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 24),
            // Header: Icon + Ledger Name
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: color, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.ledgerName,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1A1F36),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        entry.date != null ? DateFormat('EEEE, MMM d, yyyy').format(entry.date!) : 'N/A',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),
            // Details Row: Amount, Voucher Type, Voucher Number
            _buildDetailRow('Amount', NumberFormat.currency(locale: 'en_IN', symbol: '\u20B9').format(entry.amount), valueColor: color),
            const SizedBox(height: 16),
            _buildDetailRow('Voucher Type', entry.voucherType),
            if (entry.voucherNumber != null && entry.voucherNumber!.isNotEmpty) ...[
              const SizedBox(height: 16),
              _buildDetailRow('Voucher Number', entry.voucherNumber!),
            ],
            if (entry.narration != null && entry.narration!.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 16),
              const Text(
                'Narration',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                entry.narration!,
                style: const TextStyle(
                  fontSize: 15,
                  color: Color(0xFF1A1F36),
                  height: 1.4,
                ),
              ),
            ],
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: Colors.grey,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: valueColor ?? const Color(0xFF1A1F36),
          ),
        ),
      ],
    );
  }
}
