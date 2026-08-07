import 'package:flutter/material.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:intl/intl.dart';
import '../config/app_theme.dart';
import '../providers/company_provider.dart';
import '../services/supabase_service.dart';
import '../widgets/summary_card.dart';
import '../widgets/shimmer_loading.dart';
import '../widgets/error_state_widget.dart';
import 'daybook_screen.dart';
import 'reports_screen.dart';

class DashboardScreen extends StatefulWidget {
  final Function(int) onNavigate;
  const DashboardScreen({super.key, required this.onNavigate});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final SupabaseService _service = SupabaseService();
  bool _isLoading = true;
  Object? _error;

  double _totalStockValue = 0;
  int _stockItemCount = 0;
  double _totalReceivables = 0;
  double _totalPayables = 0;
  double _totalSales = 0;
  int _salesCount = 0;
  double _totalPurchases = 0;
  int _purchaseCount = 0;

  double _daybookInflow = 0;
  double _daybookOutflow = 0;

  bool _initialized = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      _loadDashboardData();
    }
  }

  String? get _company => CompanyProvider.of(context).selectedCompany;

  Future<void> _loadDashboardData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final c = _company;
      final results = await Future.wait([
        _service.getTotalStockValue(companyName: c),
        _service.getProductCount(companyName: c),
        _service.getTotalReceivables(companyName: c),
        _service.getTotalPayables(companyName: c),
        _service.getTotalSales(companyName: c),
        _service.getSalesInvoiceCount(companyName: c),
        _service.getTotalPurchases(companyName: c),
        _service.getPurchaseInvoiceCount(companyName: c),
        _service.getDaybookSummary(date: DateTime.now(), companyName: c),
      ]);

      if (mounted) {
        setState(() {
          _totalStockValue = results[0] as double;
          _stockItemCount = results[1] as int;
          _totalReceivables = results[2] as double;
          _totalPayables = results[3] as double;
          _totalSales = results[4] as double;
          _salesCount = results[5] as int;
          _totalPurchases = results[6] as double;
          _purchaseCount = results[7] as int;
          
          final dbSummary = results[8] as Map<String, double>;
          _daybookInflow = dbSummary['inflow'] ?? 0.0;
          _daybookOutflow = dbSummary['outflow'] ?? 0.0;

          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surfaceColor,
      body: RefreshIndicator(
        onRefresh: _loadDashboardData,
        color: AppTheme.primaryColor,
        child: _isLoading 
          ? const ShimmerGridLoading(itemCount: 4)
          : _error != null
              ? ErrorStateWidget(
                  error: _error,
                  onRetry: _loadDashboardData,
                )
              : SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: _buildBody(),
                ),
      ),
    );
  }

  Widget _buildBody() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: AnimationLimiter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Overview',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF1A1F36)),
                ),
                Row(
                  children: [
                    Text(
                      'Last updated: ${DateFormat('HH:mm').format(DateTime.now())}',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      onPressed: _loadDashboardData,
                      icon: const Icon(Icons.refresh_rounded, size: 20),
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Refresh Dashboard',
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),

            _buildSummaryGrid(),
            const SizedBox(height: 24),
            _buildDaybookCard(),
            const SizedBox(height: 24),
            const Text(
              'Quick Actions',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF1A1F36)),
            ),
            const SizedBox(height: 14),
            _buildQuickActions(),
            const SizedBox(height: 24),
            _buildFinancialHighlight(),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryGrid() {
    final screenWidth = MediaQuery.of(context).size.width;
    int crossAxisCount = 2;
    double childAspectRatio = 1.6;

    if (screenWidth >= 1200) {
      crossAxisCount = 5;
      childAspectRatio = 1.6;
    } else if (screenWidth >= 800) {
      crossAxisCount = 3;
      childAspectRatio = 1.5;
    } else if (screenWidth >= 600) {
      crossAxisCount = 3;
      childAspectRatio = 1.5;
    } else {
      crossAxisCount = 2;
      childAspectRatio = 1.5;
    }

    final items = [
      {
        'title': 'Total Stock Value',
        'value': formatCompactCurrency(_totalStockValue),
        'icon': Icons.inventory_2_rounded,
        'color': AppTheme.stockColor,
        'subtitle': '$_stockItemCount items',
      },
      {
        'title': 'Total Sales',
        'value': formatCompactCurrency(_totalSales),
        'icon': Icons.point_of_sale_rounded,
        'color': AppTheme.salesColor,
        'subtitle': '$_salesCount invoices',
      },
      {
        'title': 'Total Purchases',
        'value': formatCompactCurrency(_totalPurchases),
        'icon': Icons.shopping_cart_rounded,
        'color': AppTheme.purchaseColor,
        'subtitle': '$_purchaseCount invoices',
      },
      {
        'title': 'Receivables',
        'value': formatCompactCurrency(_totalReceivables),
        'icon': Icons.arrow_downward_rounded,
        'color': AppTheme.receivableColor,
        'subtitle': 'Amount to collect',
      },
      {
        'title': 'Payables',
        'value': formatCompactCurrency(_totalPayables),
        'icon': Icons.arrow_upward_rounded,
        'color': AppTheme.payableColor,
        'subtitle': 'Amount to pay',
      },
    ];

    return AnimationLimiter(
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        shrinkWrap: true,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: childAspectRatio,
        ),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          return AnimationConfiguration.staggeredGrid(
            position: index,
            columnCount: crossAxisCount,
            duration: const Duration(milliseconds: 400),
            child: ScaleAnimation(
              child: FadeInAnimation(
                child: SummaryCard(
                  title: item['title'] as String,
                  value: item['value'] as String,
                  icon: item['icon'] as IconData,
                  color: item['color'] as Color,
                  subtitle: item['subtitle'] as String?,
                  onTap: () => widget.onNavigate(index + 1),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDaybookCard() {
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const DaybookScreen()),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.menu_book_rounded, color: Colors.blue, size: 20),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Today\'s Daybook',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF1A1F36)),
                  ),
                ),
                Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.grey.shade400),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Total Inflow', style: TextStyle(fontSize: 12, color: Colors.grey.shade500, fontWeight: FontWeight.w500)),
                      const SizedBox(height: 4),
                      Text(
                        formatCompactCurrency(_daybookInflow),
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.green.shade600),
                      ),
                    ],
                  ),
                ),
                Container(width: 1, height: 30, color: Colors.grey.shade200),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Total Outflow', style: TextStyle(fontSize: 12, color: Colors.grey.shade500, fontWeight: FontWeight.w500)),
                        const SizedBox(height: 4),
                        Text(
                          formatCompactCurrency(_daybookOutflow),
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.red.shade600),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActions() {
    final actions = [
      {'icon': Icons.inventory_2_rounded, 'label': 'Stock', 'color': AppTheme.stockColor, 'index': 1},
      {'icon': Icons.people_alt_rounded, 'label': 'Ledgers', 'color': AppTheme.primaryColor, 'index': 2},
      {'icon': Icons.receipt_long_rounded, 'label': 'Sales', 'color': AppTheme.salesColor, 'index': 4},
      {'icon': Icons.analytics_rounded, 'label': 'Reports', 'color': Colors.purple.shade500, 'index': 99},
    ];

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: actions.map((action) {
        return Expanded(
          child: GestureDetector(
            onTap: () {
              if (action['index'] == 99) {
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ReportsScreen()));
              } else {
                widget.onNavigate(action['index'] as int);
              }
            },
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: (action['color'] as Color).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      action['icon'] as IconData,
                      color: action['color'] as Color,
                      size: 20,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    action['label'] as String,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1A1F36),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildFinancialHighlight() {
    final netBalance = _totalReceivables - _totalPayables;
    final isPositive = netBalance >= 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isPositive
              ? [const Color(0xFF43A047), const Color(0xFF2E7D32)]
              : [const Color(0xFFE53935), const Color(0xFFC62828)],
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: (isPositive ? Colors.green : Colors.red).withValues(alpha: 0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Net Balance',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  formatCompactCurrency(netBalance.abs()),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isPositive ? 'Net Receivable' : 'Net Payable',
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isPositive ? Icons.trending_up_rounded : Icons.trending_down_rounded,
              color: Colors.white,
              size: 24,
            ),
          ),
        ],
      ),
    );
  }
}
