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
  int? _lastSyncTrigger;
  bool _isNetPositionExpanded = false;
  bool _isCashBankDetailsOpen = false;
  final Set<String> _cashBankExpandedSections = {'cash', 'bank', 'bank_od'};

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final syncTrigger = CompanyProvider.of(context).syncTrigger;
    if (!_initialized) {
      _initialized = true;
      _lastSyncTrigger = syncTrigger;
      _loadDashboardData();
    } else if (_lastSyncTrigger != syncTrigger) {
      _lastSyncTrigger = syncTrigger;
      _loadDashboardData(silent: true);
    }
  }

  String? get _company => CompanyProvider.of(context).selectedCompany;

  Future<void> _loadDashboardData({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }
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

          _cashBankLedgers = List<Ledger>.from(results[17] as List);
          double cTot = 0, bTot = 0;
          for (var l in _cashBankLedgers) {
            final type = l.ledgerType?.toLowerCase().trim() ?? '';
            final name = l.name.toLowerCase().trim();
            if (type.contains('charge') || type.contains('expense') || name.contains('charges') || name.contains('vetting')) continue;
            if (type.contains('cash') || name.startsWith('cash') || name.startsWith('petty cash')) {
              cTot += l.closingBalance;
            } else {
              bTot += l.closingBalance;
            }
          }
          _totalCash = cTot;
          _totalBank = bTot;
          _lastSyncedTime = results[18] as DateTime?;

          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted && !silent) {
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
      resizeToAvoidBottomInset: false,
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
          'action': () => widget.onNavigate(1),
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
      // Temporarily hidden - will add later
      /*
      if (companyState.isFeatureEnabled('db_card_total_receivables'))
        {
          'title': 'Total Receivables',
          'value': formatCompactCurrency(_totalReceivables),
          'icon': Icons.trending_up_rounded,
          'color': const Color(0xFF0DA6A0),
          'subtitle': 'Total outstanding to collect',
          'action': () => widget.onNavigate(3, receivablesPayablesTab: 0),
        },
      if (companyState.isFeatureEnabled('db_card_total_payables'))
        {
          'title': 'Total Payables',
          'value': formatCompactCurrency(_totalPayables),
          'icon': Icons.trending_down_rounded,
          'color': const Color(0xFF7C3AED),
          'subtitle': 'Total outstanding to pay',
          'action': () => widget.onNavigate(3, receivablesPayablesTab: 1),
        },
      */
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
        child: Row(
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
      if (companyState.isFeatureEnabled('cash_flow'))
        {'icon': Icons.account_balance_wallet_rounded, 'label': 'Cash Flow', 'color': Colors.green.shade600, 'index': 98},
      if (companyState.isFeatureEnabled('analytics') && companyState.isFeatureEnabled('db_qa_reports'))
        {'icon': Icons.analytics_rounded, 'label': 'Reports', 'color': Colors.purple.shade500, 'index': 99},
    ];

    if (actions.isEmpty) return const SizedBox.shrink();

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: actions.map((action) {
        final label = action['label']?.toString().toLowerCase() ?? '';
        final featureKey = label == 'cash flow' ? 'cash_flow' : (label == 'reports' ? 'analytics' : label);

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
    final cashLedgers = <Ledger>[];
    final bankLedgers = <Ledger>[];
    final bankOdLedgers = <Ledger>[];

    for (var l in _cashBankLedgers) {
      final type = l.ledgerType?.toLowerCase().trim() ?? '';
      final name = l.name.toLowerCase().trim();

      // Exclude charges and expenses
      if (type.contains('charge') || type.contains('expense') || name.contains('charges') || name.contains('vetting')) {
        continue;
      }

      if (type.contains('cash') || name.startsWith('cash') || name.startsWith('petty cash')) {
        cashLedgers.add(l);
      } else if (type.contains('od') || type.contains('occ') || name.contains('(od)') || name.contains(' od') || name.endsWith('od')) {
        bankOdLedgers.add(l);
      } else {
        bankLedgers.add(l);
      }
    }

    double cashDebit = 0, cashCredit = 0;
    for (var l in cashLedgers) {
      if (l.closingBalance >= 0) {
        cashDebit += l.closingBalance;
      } else {
        cashCredit += l.closingBalance.abs();
      }
    }

    double bankDebit = 0, bankCredit = 0;
    for (var l in bankLedgers) {
      if (l.closingBalance >= 0) {
        bankDebit += l.closingBalance;
      } else {
        bankCredit += l.closingBalance.abs();
      }
    }

    double odDebit = 0, odCredit = 0;
    for (var l in bankOdLedgers) {
      if (l.closingBalance >= 0) {
        odDebit += l.closingBalance;
      } else {
        odCredit += l.closingBalance.abs();
      }
    }

    final grandTotalDebit = cashDebit + bankDebit + odDebit;
    final grandTotalCredit = cashCredit + bankCredit + odCredit;
    final netTotal = grandTotalDebit - grandTotalCredit;

    return _buildModalOverlay(
      onClose: () => setState(() { _isCashBankDetailsOpen = false; }),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Cash & Bank Summary',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF1A1F36)),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => setState(() { _isCashBankDetailsOpen = false; }),
                    ),
                  ],
                ),
                const Divider(height: 20, color: Color(0xFFE2E8F0)),
                
                // Summary Banner
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF0F766E), Color(0xFF115E59)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Expanded(
                            child: Text(
                              'Net Cash & Bank Balance',
                              style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerRight,
                              child: Text(
                                netTotal >= 0
                                    ? '${formatCurrency(netTotal)} Dr'
                                    : '${formatCurrency(netTotal.abs())} Cr',
                                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          runAlignment: WrapAlignment.center,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 12,
                          runSpacing: 4,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text('Total Debit: ', style: TextStyle(color: Colors.white70, fontSize: 11)),
                                Text(
                                  formatCurrency(grandTotalDebit),
                                  style: const TextStyle(color: Color(0xFF6EE7B7), fontSize: 12, fontWeight: FontWeight.w700),
                                ),
                              ],
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text('Total Credit: ', style: TextStyle(color: Colors.white70, fontSize: 11)),
                                Text(
                                  formatCurrency(grandTotalCredit),
                                  style: const TextStyle(color: Color(0xFFFCA5A5), fontSize: 12, fontWeight: FontWeight.w700),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // 1. Cash-in-Hand
                _buildTallyGroupCard(
                  sectionKey: 'cash',
                  title: 'Cash-in-Hand',
                  icon: Icons.payments_rounded,
                  iconColor: const Color(0xFF0D9488),
                  debitTotal: cashDebit,
                  creditTotal: cashCredit,
                  ledgers: cashLedgers,
                ),

                // 2. Bank Accounts
                _buildTallyGroupCard(
                  sectionKey: 'bank',
                  title: 'Bank Accounts',
                  icon: Icons.account_balance_rounded,
                  iconColor: const Color(0xFF2563EB),
                  debitTotal: bankDebit,
                  creditTotal: bankCredit,
                  ledgers: bankLedgers,
                ),

                // 3. Bank OD A/c
                _buildTallyGroupCard(
                  sectionKey: 'bank_od',
                  title: 'Bank OD A/c',
                  icon: Icons.credit_card_rounded,
                  iconColor: const Color(0xFFE11D48),
                  debitTotal: odDebit,
                  creditTotal: odCredit,
                  ledgers: bankOdLedgers,
                ),
                const SizedBox(height: 6),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTallyGroupCard({
    required String sectionKey,
    required String title,
    required IconData icon,
    required Color iconColor,
    required double debitTotal,
    required double creditTotal,
    required List<Ledger> ledgers,
  }) {
    final isExpanded = _cashBankExpandedSections.contains(sectionKey);
    final netBalance = debitTotal - creditTotal;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE2E8F0)),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header (Click to expand/collapse)
          InkWell(
            onTap: () {
              setState(() {
                if (_cashBankExpandedSections.contains(sectionKey)) {
                  _cashBankExpandedSections.remove(sectionKey);
                } else {
                  _cashBankExpandedSections.add(sectionKey);
                }
              });
            },
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: iconColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, color: iconColor, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${ledgers.length} account${ledgers.length == 1 ? '' : 's'}',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Totals summary & chevron
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            netBalance >= 0
                                ? '${formatCurrency(netBalance)} Dr'
                                : '${formatCurrency(netBalance.abs())} Cr',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: netBalance >= 0 ? const Color(0xFF0F766E) : const Color(0xFFDC2626),
                            ),
                          ),
                          const SizedBox(width: 6),
                          AnimatedRotation(
                            turns: isExpanded ? 0.5 : 0.0,
                            duration: const Duration(milliseconds: 200),
                            child: const Icon(
                              Icons.keyboard_arrow_down_rounded,
                              size: 20,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                      if (debitTotal > 0 && creditTotal > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 2, right: 26),
                          child: Text(
                            'Dr: ${formatCurrency(debitTotal)} | Cr: ${formatCurrency(creditTotal)}',
                            style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Expanded Content (Tally Debit & Credit Table)
          if (isExpanded) ...[
            const Divider(height: 1, color: Color(0xFFF1F5F9)),
            // Table Header: PARTICULARS | DEBIT | CREDIT
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              color: const Color(0xFFF8FAFC),
              child: Row(
                children: const [
                  Expanded(
                    flex: 5,
                    child: Text(
                      'PARTICULARS',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF64748B),
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      'DEBIT',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0D9488),
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      'CREDIT',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFE11D48),
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFF1F5F9)),

            // Account Rows
            if (ledgers.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'No accounts in this category',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              )
            else
              ...ledgers.map((l) {
                final isDebit = l.closingBalance >= 0;
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: Color(0xFFF8FAFC))),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 5,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Text(
                            l.name,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF1E293B),
                              height: 1.25,
                            ),
                          ),
                        ),
                      ),
                      // Debit Column
                      Expanded(
                        flex: 3,
                        child: Text(
                          isDebit ? formatCurrency(l.closingBalance) : '-',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: isDebit ? FontWeight.w600 : FontWeight.w400,
                            color: isDebit ? const Color(0xFF0F766E) : Colors.grey.shade400,
                          ),
                        ),
                      ),
                      // Credit Column
                      Expanded(
                        flex: 3,
                        child: Text(
                          !isDebit ? formatCurrency(l.closingBalance.abs()) : '-',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: !isDebit ? FontWeight.w600 : FontWeight.w400,
                            color: !isDebit ? const Color(0xFFDC2626) : Colors.grey.shade400,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),

            // Subtotal Footer for this category
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: const BoxDecoration(
                color: Color(0xFFF1F5F9),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(12),
                  bottomRight: Radius.circular(12),
                ),
              ),
              child: Row(
                children: [
                  const Expanded(
                    flex: 5,
                    child: Text(
                      'Category Total',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF334155),
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      debitTotal > 0 ? formatCurrency(debitTotal) : '-',
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0F766E),
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      creditTotal > 0 ? formatCurrency(creditTotal) : '-',
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFDC2626),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
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
