import 'dart:async';
import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import '../providers/company_provider.dart';
import '../services/supabase_service.dart';
import 'company_selection_screen.dart';
import 'dashboard_screen.dart';
import 'login_screen.dart';
import 'profile_screen.dart';
import 'stock_screen.dart';
import 'ledger_screen.dart';
import 'receivables_payables_screen.dart';
import 'sales_invoice_screen.dart';
import 'purchase_invoices_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;
  bool _stockScreenShowSales = false;
  int _receivablesPayablesTab = 0;
  String? _lastCompany;
  StreamSubscription<Map<String, bool>>? _featureSubscription;
  StreamSubscription<Map<String, dynamic>>? _syncSubscription;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final companyState = CompanyProvider.of(context);
    final currentCompany = companyState.selectedCompany;
    if (currentCompany != _lastCompany) {
      _lastCompany = currentCompany;
      if (currentCompany != null) {
        _listenToCompanyFeatures(currentCompany, companyState);
        _listenToSyncLogs(currentCompany, companyState);
      } else {
        _featureSubscription?.cancel();
        _featureSubscription = null;
        _syncSubscription?.cancel();
        _syncSubscription = null;
      }
    }
  }

  @override
  void dispose() {
    _featureSubscription?.cancel();
    _syncSubscription?.cancel();
    super.dispose();
  }

  void _listenToCompanyFeatures(String companyName, CompanyState companyState) {
    _featureSubscription?.cancel();
    _featureSubscription = SupabaseService().streamCompanyFeatures(companyName).listen((features) {
      if (mounted) {
        companyState.setFeatures(features);
      }
    }, onError: (_) {
      // Keep existing features on error
    });
  }

  void _listenToSyncLogs(String companyName, CompanyState companyState) {
    _syncSubscription?.cancel();
    _syncSubscription = SupabaseService().streamSyncLogUpdates(companyName).listen((event) {
      if (mounted && event.isNotEmpty) {
        companyState.notifySyncCompleted();
      }
    }, onError: (_) {
      // Ignore errors
    });
  }

  void _onNavigate(
    int index, {
    bool showSalesInStock = false,
    int receivablesPayablesTab = 0,
  }) {
    setState(() {
      _currentIndex = index;
      _stockScreenShowSales = showSalesInStock;
      _receivablesPayablesTab = receivablesPayablesTab;
    });
  }

  void _switchCompany() {
    CompanyProvider.of(context).clearCompany();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const CompanySelectionScreen(isSwitching: true)),
    );
  }

  Future<void> _logout() async {
    await SupabaseService().signOut();
    if (!mounted) return;
    CompanyProvider.of(context).clearCompany();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final companyState = CompanyProvider.of(context);
    final companyName = companyState.selectedCompany ?? '';

    // Calculate outstanding tab label and icon dynamically
    final showRec = companyState.isFeatureEnabled('out_receivables');
    final showPay = companyState.isFeatureEnabled('out_payables');
    final outstandingLabel = (showRec && showPay)
        ? 'Recv/Pay'
        : (showRec ? 'Receivables' : 'Payables');
    final outstandingIcon = (showRec && showPay)
        ? Icons.swap_horiz_rounded
        : (showRec ? Icons.trending_up_rounded : Icons.trending_down_rounded);

    final screens = [
      DashboardScreen(onNavigate: _onNavigate),
      StockScreen(
        onBack: () => _onNavigate(0),
        showSalesValue: _stockScreenShowSales,
      ),
      LedgerScreen(onBack: () => _onNavigate(0)),
      ReceivablesPayablesScreen(
        onBack: () => _onNavigate(0),
        initialTabIndex: _receivablesPayablesTab,
      ),
      SalesInvoiceScreen(onBack: () => _onNavigate(0)),
      PurchaseInvoiceScreen(onBack: () => _onNavigate(0)),
    ];

    return Scaffold(
      body: Column(
        children: [
          _CompanyBanner(companyName: companyName, onSwitch: _switchCompany),
          Expanded(
            child: MediaQuery.removePadding(
              context: context,
              removeTop: true,
              child: FadeIndexedStack(
                index: _currentIndex,
                children: screens,
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _NavItem(
                  icon: Icons.dashboard_rounded,
                  label: 'Dashboard',
                  isSelected: _currentIndex == 0,
                  onTap: () => _onNavigate(0),
                  color: AppTheme.primaryColor,
                ),
                if (companyState.isFeatureEnabled('stock'))
                  _NavItem(
                    icon: Icons.inventory_2_rounded,
                    label: 'Stock',
                    isSelected: _currentIndex == 1,
                    onTap: () => _onNavigate(1),
                    color: AppTheme.stockColor,
                  ),
                if (companyState.isFeatureEnabled('ledgers'))
                  _NavItem(
                    icon: Icons.people_alt_rounded,
                    label: 'Ledgers',
                    isSelected: _currentIndex == 2,
                    onTap: () => _onNavigate(2),
                    color: AppTheme.primaryColor,
                  ),
                if (companyState.isFeatureEnabled('outstanding'))
                  _NavItem(
                    icon: outstandingIcon,
                    label: outstandingLabel,
                    isSelected: _currentIndex == 3,
                    onTap: () => _onNavigate(3),
                    color: AppTheme.receivableColor,
                  ),
                if (companyState.isFeatureEnabled('sales'))
                  _NavItem(
                    icon: Icons.receipt_long_rounded,
                    label: 'Sales',
                    isSelected: _currentIndex == 4,
                    onTap: () => _onNavigate(4),
                    color: AppTheme.salesColor,
                  ),
                if (companyState.isFeatureEnabled('purchases'))
                  _NavItem(
                    icon: Icons.shopping_cart_rounded,
                    label: 'Purchases',
                    isSelected: _currentIndex == 5,
                    onTap: () => _onNavigate(5),
                    color: AppTheme.purchaseColor,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final Color color;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(
          horizontal: 6,
          vertical: 6,
        ),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 20,
              color: isSelected ? color : Colors.grey.shade400,
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 9,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? color : Colors.grey.shade400,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    ));
  }
}

class _CompanyBanner extends StatelessWidget {
  final String companyName;
  final VoidCallback onSwitch;

  const _CompanyBanner({
    required this.companyName,
    required this.onSwitch,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0D47A1),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  companyName,
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              GestureDetector(
                onTap: onSwitch,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.swap_horiz_rounded, color: Colors.white70, size: 16),
                      SizedBox(width: 4),
                      Text('Switch', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ProfileScreen()),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.person_rounded, color: Colors.white, size: 18),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


class FadeIndexedStack extends StatefulWidget {
  final int index;
  final List<Widget> children;
  final Duration duration;

  const FadeIndexedStack({
    super.key,
    required this.index,
    required this.children,
    this.duration = const Duration(milliseconds: 200),
  });

  @override
  State<FadeIndexedStack> createState() => _FadeIndexedStackState();
}

class _FadeIndexedStackState extends State<FadeIndexedStack> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _controller.forward();
    super.initState();
  }

  @override
  void didUpdateWidget(FadeIndexedStack oldWidget) {
    if (widget.index != oldWidget.index) {
      _controller.forward(from: 0.0);
    }
    super.didUpdateWidget(oldWidget);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller,
      child: IndexedStack(
        index: widget.index,
        children: widget.children,
      ),
    );
  }
}
