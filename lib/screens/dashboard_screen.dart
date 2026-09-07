import 'package:flutter/material.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:intl/intl.dart';
import '../config/app_theme.dart';
import '../providers/company_provider.dart';
import '../services/supabase_service.dart';
import '../widgets/summary_card.dart';
import '../widgets/shimmer_loading.dart';
import '../widgets/error_state_widget.dart';
import '../models/ledger.dart';
import 'daybook_screen.dart';
import 'reports_screen.dart';
import 'money_flow_screen.dart';

class DashboardScreen extends StatefulWidget {
  final Function(int, {
    bool showSalesInStock, 
    int receivablesPayablesTab,
  }) onNavigate;

  const DashboardScreen({
    super.key, 
    required this.onNavigate,
  });

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
  double _totalOverdueReceivables = 0;
  double _totalPayables = 0;
  double _totalOverduePayables = 0;
  double _totalSales = 0;
  int _salesCount = 0;
  double _totalPurchases = 0;
  int _purchaseCount = 0;
  double _todaysSales = 0;
  double _todaysPurchases = 0;
  int _todaysSalesCount = 0;
  int _todaysPurchasesCount = 0;

  double _daybookInflow = 0;
  double _daybookOutflow = 0;

  double _totalCash = 0;
  double _totalBank = 0;
  List<Ledger> _cashBankLedgers = [];
  DateTime? _lastSyncedTime;

  bool _initialized = false;
  bool _isNetPositionExpanded = false;
  bool _isCashBankDetailsOpen = false;

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
      final results = await Future.wait<dynamic>([
        _service.getTotalStockValue(companyName: c),
        _service.getProductCount(companyName: c),
        _service.getTotalReceivables(companyName: c),
        _service.getTotalPayables(companyName: c),
        _service.getTotalSales(companyName: c),
        _service.getSalesInvoiceCount(companyName: c),
        _service.getTotalPurchases(companyName: c),
        _service.getPurchaseInvoiceCount(companyName: c),
        _service.getDaybookSummary(date: DateTime.now(), companyName: c),
        _service.getTotalOverdueReceivables(companyName: c),
        _service.getTotalOverduePayables(companyName: c),
        _service.getTodaysSales(companyName: c),
        _service.getTodaysPurchases(companyName: c),
        _service.getTodaysSalesCount(companyName: c),
        _service.getTodaysPurchasesCount(companyName: c),
        _service.getTotalCash(companyName: c),
        _service.getTotalBank(companyName: c),
        _service.getCashBankLedgers(companyName: c),
        _service.getLastSyncTime(companyName: c),
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
          
          _totalOverdueReceivables = results[9] as double;
          _totalOverduePayables = results[10] as double;
          _todaysSales = results[11] as double;
          _todaysPurchases = results[12] as double;
          _todaysSalesCount = results[13] as int;
          _todaysPurchasesCount = results[14] as int;
          final dbSummary = results[8] as Map<String, double>;
          _daybookInflow = dbSummary['inflow'] ?? 0.0;
          _daybookOutflow = dbSummary['outflow'] ?? 0.0;

          _totalCash = results[15] as double;
          _totalBank = results[16] as double;
          _cashBankLedgers = List<Ledger>.from(results[17] as List);
          _lastSyncedTime = results[18] as DateTime?;

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
      body: Stack(
        children: [
          RefreshIndicator(
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
          if (_isCashBankDetailsOpen)
            _buildCashBankDetailsOverlay(),
        ],
      ),
    );
  }

  void _checkFeatureAndRun(String featureKey, VoidCallback onAllowed) {
    final companyState = CompanyProvider.of(context);
    if (companyState.isFeatureEnabled(featureKey)) {
      onAllowed();
    } else {
      _showLockedDialog(featureKey);
    }
  }

  void _showLockedDialog(String featureKey) {
    String featureName = featureKey.toUpperCase();
    if (featureKey == 'ledgers') featureName = 'Ledgers & Cash/Bank';
    if (featureKey == 'outstanding') featureName = 'Outstanding Reports';
    if (featureKey == 'stock') featureName = 'Stock Inventory';
    if (featureKey == 'sales') featureName = 'Sales Invoices';
    if (featureKey == 'purchases') featureName = 'Purchase Invoices';
    if (featureKey == 'analytics') featureName = 'Analytics & Reports';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(Icons.lock_rounded, color: Color(0xFF2453FF)),
            SizedBox(width: 8),
            Text('Feature Locked', style: TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
        content: Text(
          'The "$featureName" feature is currently disabled for this company. Please contact your system administrator to enable it.',
          style: const TextStyle(color: Color(0xFF3A4A63), fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK', style: TextStyle(color: Color(0xFF2453FF), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final companyState = CompanyProvider.of(context);
    final showNetPosition = companyState.isFeatureEnabled('db_net_position');
    final showSummaryGrid = companyState.isFeatureEnabled('db_summary_cards');
    final showDaybook = companyState.isFeatureEnabled('db_daybook');
    final showQuickActions = companyState.isFeatureEnabled('db_quick_actions');

    final showQuickActionsBlock = showQuickActions && (
      (companyState.isFeatureEnabled('stock') && companyState.isFeatureEnabled('db_qa_stock')) ||
      (companyState.isFeatureEnabled('ledgers') && companyState.isFeatureEnabled('db_qa_ledgers')) ||
      (companyState.isFeatureEnabled('sales') && companyState.isFeatureEnabled('db_qa_sales')) ||
      (companyState.isFeatureEnabled('analytics') && companyState.isFeatureEnabled('db_qa_reports'))
    );

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
                Flexible(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          'Last synced: ${_formatLastSyncedText(_lastSyncedTime)}',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                          overflow: TextOverflow.ellipsis,
                        ),
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
                ),
              ],
            ),
            const SizedBox(height: 16),

            if (showNetPosition) ...[
              _buildFinancialHighlight(),
              const SizedBox(height: 24),
            ],
            if (showSummaryGrid) ...[
              _buildSummaryGrid(),
              const SizedBox(height: 24),
            ],
            if (showDaybook) ...[
              _buildDaybookCard(),
              const SizedBox(height: 24),
            ],
            if (showQuickActionsBlock) ...[
              const Text(
                'Quick Actions',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF1A1F36)),
              ),
              const SizedBox(height: 14),
              _buildQuickActions(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryGrid() {
    final companyState = CompanyProvider.of(context);
    final screenWidth = MediaQuery.of(context).size.width;
    int crossAxisCount = 2;
    double childAspectRatio = 1.6;

    if (screenWidth >= 1200) {
      crossAxisCount = 6;
      childAspectRatio = 1.5;
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
      if (companyState.isFeatureEnabled('db_card_cash_bank'))
        {
          'title': 'Cash & Bank Balance',
          'value': formatCompactCurrency(_totalCash + _totalBank),
          'icon': Icons.account_balance_wallet_rounded,
          'color': Colors.teal,
          'subtitle': 'Cash and bank accounts',
          'action': companyState.isFeatureEnabled('ledgers') ? () => _showCashBankDetails() : null,
        },
      if (companyState.isFeatureEnabled('db_card_stock_value'))
        {
          'title': 'Total Stock Value',
          'value': formatCompactCurrency(_totalStockValue),
          'icon': Icons.inventory_2_rounded,
          'color': AppTheme.stockColor,
          'subtitle': '$_stockItemCount items',
          'action': () => widget.onNavigate(1, showSalesInStock: true),
        },
      if (companyState.isFeatureEnabled('db_card_today_sales'))
        {
          'title': 'Today\'s Sales',
          'value': formatCompactCurrency(_todaysSales),
          'icon': Icons.point_of_sale_rounded,
          'color': AppTheme.salesColor,
          'subtitle': '$_todaysSalesCount invoice${_todaysSalesCount == 1 ? '' : 's'} today',
          'action': () => widget.onNavigate(4),
        },
      if (companyState.isFeatureEnabled('db_card_today_purchases'))
        {
          'title': 'Today\'s Purchases',
          'value': formatCompactCurrency(_todaysPurchases),
          'icon': Icons.shopping_cart_rounded,
          'color': AppTheme.purchaseColor,
          'subtitle': '$_todaysPurchasesCount invoice${_todaysPurchasesCount == 1 ? '' : 's'} today',
          'action': () => widget.onNavigate(5),
        },
      if (companyState.isFeatureEnabled('db_card_overdue_receivables'))
        {
          'title': 'Overdue Receivables',
          'value': formatCompactCurrency(_totalOverdueReceivables),
          'icon': Icons.warning_amber_rounded,
          'color': AppTheme.receivableColor,
          'subtitle': 'Overdue bills to collect',
          'action': () => widget.onNavigate(3),
        },
      if (companyState.isFeatureEnabled('db_card_overdue_payables'))
        {
          'title': 'Overdue Payables',
          'value': formatCompactCurrency(_totalOverduePayables),
          'icon': Icons.warning_amber_rounded,
          'color': AppTheme.payableColor,
          'subtitle': 'Overdue bills to pay',
          'action': () => widget.onNavigate(3),
        },
    ];

    if (items.isEmpty) return const SizedBox.shrink();

    // Dynamically adjust crossAxisCount if we have fewer items than columns
    if (items.length < crossAxisCount) {
      crossAxisCount = items.length;
    }

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
                  onTap: item['action'] as VoidCallback?,
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
    final companyState = CompanyProvider.of(context);
    final actions = [
      if (companyState.isFeatureEnabled('stock') && companyState.isFeatureEnabled('db_qa_stock'))
        {'icon': Icons.inventory_2_rounded, 'label': 'Stock', 'color': AppTheme.stockColor, 'index': 1},
      if (companyState.isFeatureEnabled('ledgers') && companyState.isFeatureEnabled('db_qa_ledgers'))
        {'icon': Icons.people_alt_rounded, 'label': 'Ledgers', 'color': AppTheme.primaryColor, 'index': 2},
      if (companyState.isFeatureEnabled('sales') && companyState.isFeatureEnabled('db_qa_sales'))
        {'icon': Icons.receipt_long_rounded, 'label': 'Sales', 'color': AppTheme.salesColor, 'index': 4},
      if (companyState.isFeatureEnabled('analytics') && companyState.isFeatureEnabled('db_qa_reports'))
        {'icon': Icons.account_balance_wallet_rounded, 'label': 'Cash Flow', 'color': Colors.green.shade600, 'index': 98},
      if (companyState.isFeatureEnabled('analytics') && companyState.isFeatureEnabled('db_qa_reports'))
        {'icon': Icons.analytics_rounded, 'label': 'Reports', 'color': Colors.purple.shade500, 'index': 99},
    ];

    if (actions.isEmpty) return const SizedBox.shrink();

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: actions.map((action) {
        final label = action['label']?.toString().toLowerCase() ?? '';
        final featureKey = (label == 'reports' || label == 'cash flow') ? 'analytics' : label;

        return Expanded(
          child: GestureDetector(
            onTap: () {
              _checkFeatureAndRun(featureKey, () {
                if (action['index'] == 99) {
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ReportsScreen()));
                } else if (action['index'] == 98) {
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MoneyFlowScreen()));
                } else {
                  widget.onNavigate(action['index'] as int);
                }
              });
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
    final companyState = CompanyProvider.of(context);
    final netPosition = _totalStockValue + _totalReceivables - _totalPayables + _totalCash + _totalBank;
    final isPositive = netPosition >= 0;

    final cashLedgers = _cashBankLedgers.where((l) => l.ledgerType?.toLowerCase().contains('cash') ?? false).toList();
    final bankLedgers = _cashBankLedgers.where((l) => l.ledgerType?.toLowerCase().contains('bank') ?? false).toList();

    return GestureDetector(
      onTap: () => setState(() {
        _isNetPositionExpanded = !_isNetPositionExpanded;
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
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
        child: Column(
          children: [
            // Header Row (Always Visible)
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Net Position',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        formatCompactCurrency(netPosition.abs()),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isPositive ? 'Net Position (Surplus)' : 'Net Position (Deficit)',
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  _isNetPositionExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                  color: Colors.white70,
                  size: 24,
                ),
                const SizedBox(width: 8),
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

            // Expanded Inline Details
            if (_isNetPositionExpanded) ...[
              const SizedBox(height: 12),
              const Divider(color: Colors.white24, height: 1),
              const SizedBox(height: 12),
              
              // Stock in Hand Row
              if (companyState.isFeatureEnabled('db_np_stock')) ...[
                _buildInlineDetailRow(
                  title: 'Stock in Hand',
                  value: _totalStockValue,
                  icon: Icons.inventory_2_rounded,
                  onTap: companyState.isFeatureEnabled('stock') ? () {
                    widget.onNavigate(1); // Navigates to Stock screen
                  } : null,
                ),
                const SizedBox(height: 8),
              ],

              // Receivables Row
              if (companyState.isFeatureEnabled('db_np_receivables')) ...[
                _buildInlineDetailRow(
                  title: 'Outstanding Receivables',
                  value: _totalReceivables,
                  icon: Icons.trending_up_rounded,
                  onTap: (companyState.isFeatureEnabled('outstanding') && companyState.isFeatureEnabled('out_receivables')) ? () {
                    widget.onNavigate(
                      3,
                      receivablesPayablesTab: 0,
                    ); // Receivables Screen
                  } : null,
                ),
                const SizedBox(height: 8),
              ],

              // Payables Row
              if (companyState.isFeatureEnabled('db_np_payables')) ...[
                _buildInlineDetailRow(
                  title: 'Outstanding Payables',
                  value: -_totalPayables,
                  icon: Icons.trending_down_rounded,
                  onTap: (companyState.isFeatureEnabled('outstanding') && companyState.isFeatureEnabled('out_payables')) ? () {
                    widget.onNavigate(
                      3,
                      receivablesPayablesTab: 1,
                    ); // Payables Screen
                  } : null,
                ),
                const SizedBox(height: 8),
              ],

              // Cash Row (Expandable / List)
              if (companyState.isFeatureEnabled('db_np_cash')) ...[
                _buildInlineExpandableDetailRow(
                  title: 'Cash in Hand',
                  totalValue: _totalCash,
                  icon: Icons.money_rounded,
                  ledgers: cashLedgers,
                ),
                const SizedBox(height: 8),
              ],

              // Bank Row (Expandable / List)
              if (companyState.isFeatureEnabled('db_np_bank')) ...[
                _buildInlineExpandableDetailRow(
                  title: 'Bank Accounts',
                  totalValue: _totalBank,
                  icon: Icons.account_balance_rounded,
                  ledgers: bankLedgers,
                ),
                const SizedBox(height: 4),
              ],
            ],
          ],
        ),
      ),
    );
  }

  void _showCashBankDetails() {
    setState(() {
      _isCashBankDetailsOpen = true;
    });
  }

  Widget _buildInlineDetailRow({
    required String title,
    required double value,
    required IconData icon,
    VoidCallback? onTap,
  }) {
    final isNegative = value < 0;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white24),
          borderRadius: BorderRadius.circular(10),
          color: Colors.white.withValues(alpha: 0.06),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white70, size: 16),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xE6FFFFFF)),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              formatCurrency(value),
              style: TextStyle(
                fontSize: 13, 
                fontWeight: FontWeight.w700, 
                color: isNegative ? const Color(0xFFFFD2D2) : Colors.white,
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 6),
              const Icon(Icons.arrow_forward_ios_rounded, size: 10, color: Colors.white70),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInlineExpandableDetailRow({
    required String title,
    required double totalValue,
    required IconData icon,
    required List<Ledger> ledgers,
  }) {
    return Theme(
      data: Theme.of(context).copyWith(
        dividerColor: Colors.transparent,
        unselectedWidgetColor: Colors.white70,
        colorScheme: const ColorScheme.light(primary: Colors.white),
      ),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white24),
          borderRadius: BorderRadius.circular(10),
          color: Colors.white.withValues(alpha: 0.06),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
            iconColor: Colors.white,
            collapsedIconColor: Colors.white70,
            title: Row(
              children: [
                Icon(icon, color: Colors.white70, size: 16),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xE6FFFFFF)),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  formatCurrency(totalValue),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white),
                ),
              ],
            ),
            trailing: const SizedBox.shrink(),
            children: [
            if (ledgers.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Text(
                  'No accounts synced',
                  style: TextStyle(fontSize: 12, color: Colors.white60),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Column(
                  children: ledgers.map((l) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              l.name,
                              style: const TextStyle(fontSize: 12, color: Colors.white70),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            formatCurrency(l.closingBalance),
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

  Widget _buildModalOverlay({required Widget child, required VoidCallback onClose}) {
    return Positioned.fill(
      child: Stack(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onClose,
            child: Container(
              color: Colors.black.withValues(alpha: 0.5),
            ),
          ),
          Center(
            child: GestureDetector(
              onTap: () {}, // Prevent taps inside the modal from bubbling up and closing it
              child: child,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCashBankDetailsOverlay() {
    final cashLedgers = _cashBankLedgers.where((l) => l.ledgerType?.toLowerCase().contains('cash') ?? false).toList();
    final bankLedgers = _cashBankLedgers.where((l) => l.ledgerType?.toLowerCase().contains('bank') ?? false).toList();

    return _buildModalOverlay(
      onClose: () => setState(() { _isCashBankDetailsOpen = false; }),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Cash & Bank Details',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF1A1F36)),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => setState(() { _isCashBankDetailsOpen = false; }),
                    ),
                  ],
                ),
                const Divider(height: 24, color: Color(0xFFE2E8F0)),
                
                // Summary Banner
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF009688), Color(0xFF004D40)], // Teal gradient
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Total Balance',
                        style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                      Text(
                        formatCurrency(_totalCash + _totalBank),
                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Cash Row (Expandable / List)
                _buildExpandableDetailRow(
                  title: 'Cash in Hand',
                  totalValue: _totalCash,
                  icon: Icons.money_rounded,
                  iconColor: Colors.teal,
                  ledgers: cashLedgers,
                ),
                const SizedBox(height: 8),

                // Bank Row (Expandable / List)
                _buildExpandableDetailRow(
                  title: 'Bank Accounts',
                  totalValue: _totalBank,
                  icon: Icons.account_balance_rounded,
                  iconColor: Colors.blue,
                  ledgers: bankLedgers,
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }





  Widget _buildExpandableDetailRow({
    required String title,
    required double totalValue,
    required IconData icon,
    required Color iconColor,
    required List<Ledger> ledgers,
  }) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFEAECF0)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(icon, color: iconColor, size: 16),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF344054)),
                ),
              ),
            ],
          ),
          trailing: Text(
            formatCurrency(totalValue),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1D2939)),
          ),
          children: [
            if (ledgers.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Text(
                  'No accounts synced',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Column(
                  children: ledgers.map((l) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              l.name,
                              style: const TextStyle(fontSize: 12, color: Color(0xFF475467)),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            formatCurrency(l.closingBalance),
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF475467)),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _formatLastSyncedText(DateTime? dateTime) {
    if (dateTime == null) return 'N/A';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = DateTime(now.year, now.month, now.day - 1);
    final syncDate = DateTime(dateTime.year, dateTime.month, dateTime.day);

    final timeStr = DateFormat('HH:mm').format(dateTime);

    if (syncDate == today) {
      return 'Today, $timeStr';
    } else if (syncDate == yesterday) {
      return 'Yesterday, $timeStr';
    } else {
      return '${DateFormat('dd MMM').format(dateTime)}, $timeStr';
    }
  }
}
