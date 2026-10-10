import 'dart:async';
import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import '../providers/company_provider.dart';
import '../utils/company_scope.dart';
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
  final Set<int> _activatedTabs = {0};
  bool _stockScreenShowSales = false;
  int _receivablesPayablesTab = 0;
  String _receivablesPayablesFilter = 'all';
  String? _lastCompany;
  Object? _featureError;
  StreamSubscription<Map<String, bool>>? _featureSubscription;
  StreamSubscription<Map<String, dynamic>>? _syncSubscription;
  StreamSubscription<Map<String, dynamic>>? _userProfileSubscription;

  DateTime? _subscriptionExpiresAt;
  bool _subscriptionExpired = false;
  int? _subscriptionDaysLeft;
  String? _subscriptionWarnedCompany;

  static const _warnDialogDays = 15;
  static const _warnBannerDays = 30;

  @override
  void initState() {
    super.initState();
    _listenToUserProfile();
  }

  void _listenToUserProfile() {
    final user = SupabaseService().currentUser;
    if (user != null) {
      _userProfileSubscription = SupabaseService().streamUserProfile(user.id).listen((profile) {
        if (mounted && profile.isNotEmpty) {
          final isActive = profile['is_active'] == true;
          if (!isActive) {
            _forceLogout();
          }
        }
      });
    }
  }

  Future<void> _forceLogout() async {
    await SupabaseService().signOut();
    if (!mounted) return;
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Access Suspended'),
        content: const Text('Your session was terminated because your account was suspended. Please contact the administrator.'),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (route) => false,
              );
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final companyState = CompanyProvider.of(context);
    final currentCompany = companyState.selectedCompany;
    if (currentCompany != _lastCompany) {
      _lastCompany = currentCompany;
      _currentIndex = 0;
      _stockScreenShowSales = false;
      _receivablesPayablesTab = 0;
      _receivablesPayablesFilter = 'all';
      if (currentCompany != null) {
        _activatedTabs.removeWhere((idx) => idx != 0);
        _listenToCompanyFeatures(currentCompany, companyState);
        _listenToSyncLogs(currentCompany, companyState);
        _checkSubscriptionExpiry(currentCompany);
      } else {
        _featureSubscription?.cancel();
        _featureSubscription = null;
        _syncSubscription?.cancel();
        _syncSubscription = null;
        _clearSubscriptionState();
      }
    }
  }

  void _clearSubscriptionState() {
    _subscriptionExpiresAt = null;
    _subscriptionExpired = false;
    _subscriptionDaysLeft = null;
    _subscriptionWarnedCompany = null;
  }

  Future<void> _checkSubscriptionExpiry(String companyName) async {
    final result =
        await SupabaseService().getCompanySubscriptionExpiry(companyName);
    if (!mounted || CompanyProvider.of(context).selectedCompany != companyName) {
      return;
    }

    final expiresAt = result.expiresAt;
    if (expiresAt == null) {
      setState(_clearSubscriptionState);
      return;
    }

    final now = DateTime.now();
    final expired = now.isAfter(expiresAt);
    final daysLeft = expiresAt.difference(now).inDays;

    setState(() {
      _subscriptionExpiresAt = expiresAt;
      _subscriptionExpired = expired;
      _subscriptionDaysLeft = daysLeft;
    });

    final shouldDialog =
        expired || (!expired && daysLeft <= _warnDialogDays);
    if (shouldDialog && _subscriptionWarnedCompany != companyName) {
      _subscriptionWarnedCompany = companyName;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showSubscriptionDialog();
      });
    }
  }

  String _formatExpiryDate(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final local = dt.toLocal();
    return '${local.day.toString().padLeft(2, '0')} ${months[local.month - 1]} ${local.year}';
  }

  void _showSubscriptionDialog() {
    final expired = _subscriptionExpired;
    final days = _subscriptionDaysLeft ?? 0;
    final dateStr = _subscriptionExpiresAt != null
        ? _formatExpiryDate(_subscriptionExpiresAt!)
        : '';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(expired ? 'Subscription Expired' : 'Subscription Reminder'),
        content: Text(
          expired
              ? 'Your subscription expired on $dateStr. Please contact the administrator to renew.'
              : days <= 0
                  ? 'Your subscription expires today ($dateStr). Please renew soon.'
                  : 'Your subscription expires in $days day${days == 1 ? '' : 's'} ($dateStr).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  bool get _showSubscriptionBanner {
    if (_subscriptionExpiresAt == null || _subscriptionDaysLeft == null) {
      return false;
    }
    if (_subscriptionExpired) return true;
    return _subscriptionDaysLeft! <= _warnBannerDays;
  }

  @override
  void dispose() {
    _featureSubscription?.cancel();
    _syncSubscription?.cancel();
    _userProfileSubscription?.cancel();
    super.dispose();
  }

  void _listenToCompanyFeatures(String companyName, CompanyState companyState) {
    _featureError = null;
    _featureSubscription?.cancel();
    _featureSubscription = SupabaseService().streamCompanyFeatures(companyName).listen((features) {
      if (mounted && companyState.selectedCompany == companyName) {
        _featureError = null;
        companyState.setFeatures(features);
      }
    }, onError: (Object error) {
      if (mounted && companyState.selectedCompany == companyName) {
        setState(() => _featureError = error);
      }
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
    String? receivablesPayablesFilter,
  }) {
    setState(() {
      _currentIndex = index;
      _activatedTabs.add(index);
      _stockScreenShowSales = showSalesInStock;
      _receivablesPayablesTab = receivablesPayablesTab;
      _receivablesPayablesFilter = receivablesPayablesFilter ?? 'all';
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
    if (_featureError != null || !companyState.featuresLoaded) {
      return Scaffold(
        backgroundColor: AppTheme.surfaceColor,
        body: Center(
          child: _featureError == null
              ? const CircularProgressIndicator(color: AppTheme.primaryColor)
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Unable to verify company access.', style: TextStyle(color: Color(0xFF1A1F36), fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _listenToCompanyFeatures(companyName, companyState);
                        });
                      },
                      child: const Text('Retry'),
                    ),
                  ],
                ),
        ),
      );
    }
    if (!['dashboard','stock','ledgers','outstanding','sales','purchases','analytics','cash_flow'].any(companyState.isFeatureEnabled)) {
      return Scaffold(appBar: AppBar(title: const Text('TallyLive')), body: Center(child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [const Text('Company access is unavailable. Contact your administrator.'),
          TextButton(onPressed: _switchCompany, child: const Text('Switch company')),
          TextButton(onPressed: _logout, child: const Text('Log out'))],
      )));
    }

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
      DashboardScreen(
        key: CompanyScope.screenKey('dash', companyName),
        onNavigate: _onNavigate,
      ),
      _activatedTabs.contains(1)
          ? StockScreen(
              key: CompanyScope.screenKey('stock', companyName),
              onBack: () => _onNavigate(0),
              showSalesValue: _stockScreenShowSales,
            )
          : const SizedBox.shrink(),
      _activatedTabs.contains(2)
          ? LedgerScreen(
              key: CompanyScope.screenKey('ledger', companyName),
              onBack: () => _onNavigate(0),
            )
          : const SizedBox.shrink(),
      _activatedTabs.contains(3)
          ? ReceivablesPayablesScreen(
              key: CompanyScope.screenKey('outstanding', companyName),
              onBack: () => _onNavigate(0),
              initialTabIndex: _receivablesPayablesTab,
              initialFilter: _receivablesPayablesFilter,
              isActive: _currentIndex == 3,
            )
          : const SizedBox.shrink(),
      _activatedTabs.contains(4)
          ? SalesInvoiceScreen(
              key: CompanyScope.screenKey('sales', companyName),
              onBack: () => _onNavigate(0),
            )
          : const SizedBox.shrink(),
      _activatedTabs.contains(5)
          ? PurchaseInvoiceScreen(
              key: CompanyScope.screenKey('purchase', companyName),
              onBack: () => _onNavigate(0),
            )
          : const SizedBox.shrink(),
    ];

    return Scaffold(
      body: Column(
        children: [
          _CompanyBanner(companyName: companyName, onSwitch: _switchCompany),
          if (_showSubscriptionBanner)
            _SubscriptionBanner(
              expired: _subscriptionExpired,
              daysLeft: _subscriptionDaysLeft ?? 0,
              expiryDate: _formatExpiryDate(_subscriptionExpiresAt!),
              onTap: _showSubscriptionDialog,
            ),
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

class _SubscriptionBanner extends StatelessWidget {
  final bool expired;
  final int daysLeft;
  final String expiryDate;
  final VoidCallback onTap;

  const _SubscriptionBanner({
    required this.expired,
    required this.daysLeft,
    required this.expiryDate,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = expired ? const Color(0xFFB91C1C) : const Color(0xFFB45309);
    final message = expired
        ? 'Subscription expired on $expiryDate. Contact admin to renew.'
        : daysLeft <= 0
            ? 'Subscription expires today ($expiryDate).'
            : 'Subscription expires in $daysLeft day${daysLeft == 1 ? '' : 's'} ($expiryDate).';

    return Material(
      color: bg,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            children: [
              Icon(
                expired ? Icons.error_outline_rounded : Icons.timelapse_rounded,
                color: Colors.white,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Colors.white70, size: 18),
            ],
          ),
        ),
      ),
    );
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
