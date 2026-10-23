import 'dart:async';
import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import '../providers/company_provider.dart';
import '../utils/company_scope.dart';
import '../utils/combined_company_selection.dart';
import '../services/supabase_service.dart';
import '../utils/active_session_guard.dart';
import 'company_selection_screen.dart';
import 'combined_company_picker_screen.dart';
import 'combined_outstanding_report_screen.dart';
import 'combined_purchases_report_screen.dart';
import 'combined_sales_report_screen.dart';
import 'dashboard_screen.dart';
import 'login_screen.dart';
import 'settings_screen.dart';
import 'stock_screen.dart';
import 'ledger_screen.dart';
import 'receivables_payables_screen.dart';
import 'sales_invoice_screen.dart';
import 'purchase_invoices_screen.dart';

/// Feature keys that must never appear as tabs/QA in Combined mode.
const _kCombinedHiddenFeatures = {
  'balance_sheet',
  'profit_loss',
  'cash_flow',
  'tally_cash_flow',
  'db_qa_balance_sheet',
  'db_qa_profit_loss',
  'db_qa_tally_cash_flow',
};

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell>
    with ActiveSessionGuard, WidgetsBindingObserver {
  int _currentIndex = 0;
  final Set<int> _activatedTabs = {0};
  bool _stockScreenShowSales = false;
  int _receivablesPayablesTab = 0;
  String _receivablesPayablesFilter = 'all';
  String? _lastScopeKey;
  Object? _featureError;
  /// Dedupes sync-log stream re-emits so screens only soft-refresh on a new sync.
  String? _lastNotifiedSyncKey;
  final List<StreamSubscription<Map<String, bool>>> _featureSubscriptions = [];
  final List<StreamSubscription<Map<String, dynamic>>> _syncSubscriptions = [];
  final Map<String, Map<String, bool>> _featuresByCompany = {};
  StreamSubscription<Map<String, dynamic>>? _userProfileSubscription;
  bool _exitingForRevokedFlag = false;

  DateTime? _subscriptionExpiresAt;
  bool _subscriptionExpired = false;
  int? _subscriptionDaysLeft;
  String? _subscriptionWarnedCompany;
  /// Hidden until the app process starts again. Not written to disk.
  bool _subscriptionBannerDismissed = false;

  static const _warnDialogDays = 15;
  static const _warnBannerDays = 3;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _listenToUserProfile();
    startActiveSessionGuard();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !mounted) return;
    final companyState = CompanyProvider.maybeOf(context);
    final company = companyState?.selectedCompany;
    if (companyState == null ||
        companyState.isCombinedMode ||
        !CompanyScope.isValid(company)) {
      return;
    }
    _checkSubscriptionExpiry(company!);
  }

  void _listenToUserProfile() {
    final user = SupabaseService().currentUser;
    if (user != null) {
      _userProfileSubscription = SupabaseService().streamUserProfile(user.id).listen((profile) {
        if (!mounted || profile.isEmpty) return;
        final companyState = CompanyProvider.of(context);
        final wasCombined = companyState.isCombinedMode;
        companyState.setUserCombinedReportsEnabled(
          profile['is_combined_reports_enabled'] == true,
        );
        final isActive = profile['is_active'] == true;
        if (!isActive) {
          _forceLogout();
          return;
        }
        if (wasCombined &&
            !companyState.userCombinedReportsEnabled &&
            !_exitingForRevokedFlag) {
          _exitCombinedRevoked();
        }
      });
    }
  }

  Future<void> _exitCombinedRevoked() async {
    _exitingForRevokedFlag = true;
    if (!mounted) return;
    CompanyProvider.of(context).clearCompany();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Combined mode was disabled for your account.'),
      ),
    );
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const CompanySelectionScreen()),
      (route) => false,
    );
  }

  Future<void> _forceLogout() async {
    if (mounted) {
      final state = CompanyProvider.of(context);
      state.clearCompany();
      state.clearUserCapabilities();
    }
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
    final scopeKey = companyState.scopeKey;
    if (scopeKey != _lastScopeKey) {
      _lastScopeKey = scopeKey;
      _lastNotifiedSyncKey = null;
      _currentIndex = 0;
      _stockScreenShowSales = false;
      _receivablesPayablesTab = 0;
      _receivablesPayablesFilter = 'all';
      _activatedTabs
        ..clear()
        ..add(0);
      _featuresByCompany.clear();

      if (companyState.isCombinedMode &&
          CombinedCompanySelection.isReady(companyState.selectedCompanies)) {
        _listenToCombinedFeatures(companyState.selectedCompanies, companyState);
        _listenToCombinedSyncLogs(companyState.selectedCompanies, companyState);
        _clearSubscriptionState();
      } else if (CompanyScope.isValid(companyState.selectedCompany)) {
        final company = companyState.selectedCompany!;
        _listenToCompanyFeatures(company, companyState);
        _listenToSyncLogs(company, companyState);
        _checkSubscriptionExpiry(company);
      } else {
        _cancelFeatureAndSync();
        _clearSubscriptionState();
      }
    }
  }

  void _cancelFeatureAndSync() {
    for (final s in _featureSubscriptions) {
      s.cancel();
    }
    _featureSubscriptions.clear();
    for (final s in _syncSubscriptions) {
      s.cancel();
    }
    _syncSubscriptions.clear();
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
    if (!mounted) return;
    final state = CompanyProvider.of(context);
    if (state.isCombinedMode || state.selectedCompany != companyName) {
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
    if (_subscriptionBannerDismissed) return false;
    final state = CompanyProvider.maybeOf(context);
    if (state != null && state.isCombinedMode) return false;
    if (_subscriptionExpiresAt == null || _subscriptionDaysLeft == null) {
      return false;
    }
    if (_subscriptionExpired) return true;
    return _subscriptionDaysLeft! <= _warnBannerDays;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    stopActiveSessionGuard();
    _cancelFeatureAndSync();
    _userProfileSubscription?.cancel();
    super.dispose();
  }

  void _applyUnionFeatures(CompanyState companyState) {
    if (!companyState.isCombinedMode) return;
    final maps = companyState.selectedCompanies
        .map((c) => _featuresByCompany[c])
        .whereType<Map<String, bool>>()
        .toList();
    if (maps.isEmpty) return;
    final merged = <String, bool>{};
    for (final map in maps) {
      map.forEach((key, value) {
        if (_kCombinedHiddenFeatures.contains(key)) {
          merged[key] = false;
          return;
        }
        merged[key] = (merged[key] ?? false) || value;
      });
    }
    for (final key in _kCombinedHiddenFeatures) {
      merged[key] = false;
    }
    _featureError = null;
    companyState.setFeatures(merged);
  }

  void _listenToCombinedFeatures(
    List<String> companies,
    CompanyState companyState,
  ) {
    _featureError = null;
    _cancelFeatureAndSync();
    // Keep sync separate — re-setup sync after features.
    for (final company in companies) {
      final sub = SupabaseService().streamCompanyFeatures(company).listen(
        (features) {
          if (!mounted || !companyState.isCombinedMode) return;
          if (!companyState.selectedCompanies.contains(company)) return;
          _featuresByCompany[company] = features;
          _applyUnionFeatures(companyState);
        },
        onError: (Object error) {
          if (!mounted || !companyState.isCombinedMode) return;
          setState(() => _featureError = error);
        },
      );
      _featureSubscriptions.add(sub);
    }
    // Seed with one-shot fetch so UI is not stuck waiting for stream.
    Future.wait(companies.map((c) async {
      try {
        final features = await SupabaseService().getCompanyFeatures(c);
        if (!mounted || !companyState.isCombinedMode) return;
        _featuresByCompany[c] = features;
      } catch (_) {}
    })).then((_) {
      if (mounted) _applyUnionFeatures(companyState);
    });
  }

  void _listenToCompanyFeatures(String companyName, CompanyState companyState) {
    _featureError = null;
    _cancelFeatureAndSync();
    final sub = SupabaseService().streamCompanyFeatures(companyName).listen(
      (features) {
        if (mounted && companyState.selectedCompany == companyName) {
          _featureError = null;
          companyState.setFeatures(features);
        }
      },
      onError: (Object error) {
        if (mounted && companyState.selectedCompany == companyName) {
          setState(() => _featureError = error);
        }
      },
    );
    _featureSubscriptions.add(sub);
  }

  String _syncEventKey(String company, Map<String, dynamic> event) {
    final id = event['id']?.toString() ?? '';
    final finished =
        event['finished_at']?.toString() ?? event['updated_at']?.toString() ?? '';
    return '$company|$id|$finished';
  }

  void _notifyIfNewCompletedSync(
    String company,
    Map<String, dynamic> event,
    CompanyState companyState,
  ) {
    if (!mounted || event.isEmpty) return;
    final key = _syncEventKey(company, event);
    if (key == _lastNotifiedSyncKey) return;
    _lastNotifiedSyncKey = key;
    companyState.notifySyncCompleted();
  }

  void _listenToCombinedSyncLogs(
    List<String> companies,
    CompanyState companyState,
  ) {
    for (final s in _syncSubscriptions) {
      s.cancel();
    }
    _syncSubscriptions.clear();
    for (final company in companies) {
      final sub = SupabaseService().streamSyncLogUpdates(company).listen(
        (event) {
          if (!companyState.isCombinedMode) return;
          _notifyIfNewCompletedSync(company, event, companyState);
        },
        onError: (_) {},
      );
      _syncSubscriptions.add(sub);
    }
  }

  void _listenToSyncLogs(String companyName, CompanyState companyState) {
    for (final s in _syncSubscriptions) {
      s.cancel();
    }
    _syncSubscriptions.clear();
    final sub = SupabaseService().streamSyncLogUpdates(companyName).listen(
      (event) {
        _notifyIfNewCompletedSync(companyName, event, companyState);
      },
      onError: (_) {},
    );
    _syncSubscriptions.add(sub);
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

  Future<void> _changeCombinedCompanies() async {
    final state = CompanyProvider.of(context);
    final result = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute(
        builder: (_) => CombinedCompanyPickerScreen(
          enterAppOnConfirm: false,
          initialSelected: state.selectedCompanies,
        ),
      ),
    );
    if (!mounted) return;
    if (result != null && CombinedCompanySelection.isReady(result)) {
      CompanyProvider.of(context).enterCombinedMode(result);
    }
  }

  Future<void> _logout() async {
    await SupabaseService().signOut();
    if (!mounted) return;
    final state = CompanyProvider.of(context);
    state.clearCompany();
    state.clearUserCapabilities();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final companyState = CompanyProvider.of(context);
    final scopeKey = companyState.scopeKey;
    final companyName = companyState.selectedCompany ?? '';
    final isCombined = companyState.isCombinedMode;

    if (_featureError != null || !companyState.featuresLoaded) {
      return Scaffold(
        backgroundColor: AppTheme.surfaceColor,
        body: Center(
          child: _featureError == null
              ? CircularProgressIndicator(color: AppTheme.primaryColor)
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Unable to verify company access.',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          if (isCombined) {
                            _listenToCombinedFeatures(
                              companyState.selectedCompanies,
                              companyState,
                            );
                            _listenToCombinedSyncLogs(
                              companyState.selectedCompanies,
                              companyState,
                            );
                          } else {
                            _listenToCompanyFeatures(companyName, companyState);
                            _listenToSyncLogs(companyName, companyState);
                          }
                        });
                      },
                      child: const Text('Retry'),
                    ),
                  ],
                ),
        ),
      );
    }
    if (![
      'dashboard',
      'stock',
      'ledgers',
      'outstanding',
      'sales',
      'purchases',
      'analytics',
      'cash_flow',
    ].any(companyState.isFeatureEnabled)) {
      return Scaffold(
        appBar: AppBar(title: const Text('TallyLive')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Company access is unavailable. Contact your administrator.'),
              TextButton(onPressed: _switchCompany, child: const Text('Switch company')),
              TextButton(onPressed: _logout, child: const Text('Log out')),
            ],
          ),
        ),
      );
    }

    final showRec = companyState.isFeatureEnabled('out_receivables');
    final showPay = companyState.isFeatureEnabled('out_payables');
    final outstandingIcon = (showRec && showPay)
        ? Icons.swap_horiz_rounded
        : (showRec ? Icons.trending_up_rounded : Icons.trending_down_rounded);

    final companies = companyState.selectedCompanies;

    final screens = [
      DashboardScreen(
        key: CompanyScope.screenKeyForScope('dash', scopeKey),
        onNavigate: _onNavigate,
      ),
      _activatedTabs.contains(1)
          ? StockScreen(
              key: CompanyScope.screenKeyForScope('stock', scopeKey),
              onBack: () => _onNavigate(0),
              showSalesValue: _stockScreenShowSales,
            )
          : const SizedBox.shrink(),
      _activatedTabs.contains(2)
          ? LedgerScreen(
              key: CompanyScope.screenKeyForScope('ledger', scopeKey),
              onBack: () => _onNavigate(0),
            )
          : const SizedBox.shrink(),
      _activatedTabs.contains(3)
          ? (isCombined
              ? CombinedOutstandingReportScreen(
                  key: CompanyScope.screenKeyForScope('outstanding', scopeKey),
                  companyNames: companies,
                  embedded: true,
                )
              : ReceivablesPayablesScreen(
                  key: CompanyScope.screenKeyForScope('outstanding', scopeKey),
                  onBack: () => _onNavigate(0),
                  initialTabIndex: _receivablesPayablesTab,
                  initialFilter: _receivablesPayablesFilter,
                  isActive: _currentIndex == 3,
                ))
          : const SizedBox.shrink(),
      _activatedTabs.contains(4)
          ? (isCombined
              ? CombinedSalesReportScreen(
                  key: CompanyScope.screenKeyForScope('sales', scopeKey),
                  companyNames: companies,
                  embedded: true,
                )
              : SalesInvoiceScreen(
                  key: CompanyScope.screenKeyForScope('sales', scopeKey),
                  onBack: () => _onNavigate(0),
                ))
          : const SizedBox.shrink(),
      _activatedTabs.contains(5)
          ? (isCombined
              ? CombinedPurchasesReportScreen(
                  key: CompanyScope.screenKeyForScope('purchase', scopeKey),
                  companyNames: companies,
                  embedded: true,
                )
              : PurchaseInvoiceScreen(
                  key: CompanyScope.screenKeyForScope('purchase', scopeKey),
                  onBack: () => _onNavigate(0),
                ))
          : const SizedBox.shrink(),
    ];

    return Scaffold(
      body: Column(
        children: [
          _CompanyBanner(
            companyName: companyName,
            isCombined: isCombined,
            combinedCompanies: companies,
            onSwitch: _switchCompany,
            onChangeCombined: isCombined ? _changeCombinedCompanies : null,
          ),
          if (_showSubscriptionBanner)
            _SubscriptionBanner(
              expired: _subscriptionExpired,
              daysLeft: _subscriptionDaysLeft ?? 0,
              expiryDate: _formatExpiryDate(_subscriptionExpiresAt!),
              onTap: _showSubscriptionDialog,
              onClose: () => setState(() => _subscriptionBannerDismissed = true),
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
      bottomNavigationBar: Builder(
        builder: (context) {
          final screenWidth = MediaQuery.sizeOf(context).width;
          final compact = screenWidth < 400;
          final dashLabel = compact ? 'Home' : 'Dashboard';
          final stockLabel = 'Stock';
          final ledgerLabel = compact ? 'Ledger' : 'Ledgers';
          final outLabel = (showRec && showPay)
              ? 'Recv/Pay'
              : (showRec
                  ? (compact ? 'Recv' : 'Receivables')
                  : (compact ? 'Pay' : 'Payables'));
          final salesLabel = 'Sales';
          final purchaseLabel = compact ? 'Purchase' : 'Purchases';

          return Container(
            decoration: BoxDecoration(
              color: AppTheme.cardColor,
              border: Border(
                top: BorderSide(color: AppTheme.dividerColor, width: 1),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: AppTheme.isDark ? 0.35 : 0.06),
                  blurRadius: 12,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? 2 : 8,
                  vertical: 6,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _NavItem(
                      icon: Icons.dashboard_rounded,
                      label: dashLabel,
                      isSelected: _currentIndex == 0,
                      onTap: () => _onNavigate(0),
                      color: AppTheme.primaryColor,
                      compact: compact,
                    ),
                    if (companyState.isFeatureEnabled('stock'))
                      _NavItem(
                        icon: Icons.inventory_2_rounded,
                        label: stockLabel,
                        isSelected: _currentIndex == 1,
                        onTap: () => _onNavigate(1),
                        color: AppTheme.stockColor,
                        compact: compact,
                      ),
                    if (companyState.isFeatureEnabled('ledgers'))
                      _NavItem(
                        icon: Icons.people_alt_rounded,
                        label: ledgerLabel,
                        isSelected: _currentIndex == 2,
                        onTap: () => _onNavigate(2),
                        color: AppTheme.primaryColor,
                        compact: compact,
                      ),
                    if (companyState.isFeatureEnabled('outstanding'))
                      _NavItem(
                        icon: outstandingIcon,
                        label: outLabel,
                        isSelected: _currentIndex == 3,
                        onTap: () => _onNavigate(3),
                        color: AppTheme.receivableColor,
                        compact: compact,
                      ),
                    if (companyState.isFeatureEnabled('sales'))
                      _NavItem(
                        icon: Icons.receipt_long_rounded,
                        label: salesLabel,
                        isSelected: _currentIndex == 4,
                        onTap: () => _onNavigate(4),
                        color: AppTheme.salesColor,
                        compact: compact,
                      ),
                    if (companyState.isFeatureEnabled('purchases'))
                      _NavItem(
                        icon: Icons.shopping_cart_rounded,
                        label: purchaseLabel,
                        isSelected: _currentIndex == 5,
                        onTap: () => _onNavigate(5),
                        color: AppTheme.purchaseColor,
                        compact: compact,
                      ),
                  ],
                ),
              ),
            ),
          );
        },
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
  final bool compact;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
    required this.color,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 2 : 6,
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
                color: isSelected ? color : AppTheme.textSecondary,
              ),
              const SizedBox(height: 3),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: compact ? 9 : 10,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected ? color : AppTheme.textSecondary,
                  ),
                  maxLines: 1,
                  softWrap: false,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SubscriptionBanner extends StatelessWidget {
  final bool expired;
  final int daysLeft;
  final String expiryDate;
  final VoidCallback onTap;
  final VoidCallback onClose;

  const _SubscriptionBanner({
    required this.expired,
    required this.daysLeft,
    required this.expiryDate,
    required this.onTap,
    required this.onClose,
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
      child: Padding(
        padding: const EdgeInsets.only(left: 14, right: 4, top: 2, bottom: 2),
        child: Row(
          children: [
            Icon(
              expired ? Icons.error_outline_rounded : Icons.timelapse_rounded,
              color: Colors.white,
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: InkWell(
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    message,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
            IconButton(
              onPressed: onClose,
              tooltip: 'Hide until next open',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              icon: const Icon(Icons.close_rounded, color: Colors.white, size: 18),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompanyBanner extends StatelessWidget {
  final String companyName;
  final bool isCombined;
  final List<String> combinedCompanies;
  final VoidCallback onSwitch;
  final VoidCallback? onChangeCombined;

  const _CompanyBanner({
    required this.companyName,
    required this.isCombined,
    required this.combinedCompanies,
    required this.onSwitch,
    this.onChangeCombined,
  });

  @override
  Widget build(BuildContext context) {
    final title = isCombined
        ? 'Combined (${combinedCompanies.length})'
        : companyName;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          color: const Color(0xFF0D47A1),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: isCombined
                        ? Align(
                            alignment: Alignment.centerLeft,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                title,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                        : Text(
                            title,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                  ),
                  if (onChangeCombined != null) ...[
                    GestureDetector(
                      onTap: onChangeCombined,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.edit_rounded, color: Colors.white70, size: 14),
                            SizedBox(width: 4),
                            Text(
                              'Change',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
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
                          Text(
                            'Switch',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const SettingsScreen()),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.settings_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (isCombined && combinedCompanies.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 2),
            child: Text(
              combinedCompanies.join('  ·  '),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                height: 1.25,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
      ],
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

class _FadeIndexedStackState extends State<FadeIndexedStack>
    with SingleTickerProviderStateMixin {
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
