import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../services/supabase_service.dart';
import '../config/app_theme.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import '../widgets/shimmer_loading.dart';
import 'login_screen.dart';

/// Shared AppBar refresh control for admin screens.
Widget _adminRefreshButton({
  required VoidCallback? onPressed,
  Color color = AppTheme.textPrimary,
}) {
  return IconButton(
    tooltip: 'Refresh',
    icon: Icon(Icons.refresh_rounded, color: color),
    onPressed: onPressed,
  );
}

/// Smooth wheel / trackpad scrolling on web + desktop for admin lists.
class _AdminScrollBehavior extends MaterialScrollBehavior {
  const _AdminScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const BouncingScrollPhysics(
      parent: AlwaysScrollableScrollPhysics(),
    );
  }
}

const _adminListPhysics = BouncingScrollPhysics(
  parent: AlwaysScrollableScrollPhysics(),
);

/// Page title + subtitle row used across admin tabs.
class _AdminPageHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<Widget>? actions;

  const _AdminPageHeader({
    required this.title,
    required this.subtitle,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 12, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: AppTheme.textSecondary,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          if (actions != null) ...actions!,
        ],
      ),
    );
  }
}

/// Compact status chip (Online / Offline / Active / Expired).
class _AdminStatusPill extends StatelessWidget {
  final String label;
  final bool isPositive;

  const _AdminStatusPill({
    required this.label,
    required this.isPositive,
  });

  @override
  Widget build(BuildContext context) {
    final fg = isPositive ? const Color(0xFF15803D) : AppTheme.textSecondary;
    final bg = isPositive ? const Color(0xFFDCFCE7) : const Color(0xFFF3F4F6);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
      ),
    );
  }
}

/// Sidebar nav row for wide admin shell.
class _AdminSidebarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _AdminSidebarItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppTheme.primaryColor.withValues(alpha: 0.08)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 3,
                  height: 20,
                  decoration: BoxDecoration(
                    color: isSelected ? AppTheme.primaryColor : Colors.transparent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 10),
                Icon(
                  icon,
                  size: 20,
                  color: isSelected ? AppTheme.primaryColor : AppTheme.textSecondary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                      color: isSelected ? AppTheme.primaryColor : AppTheme.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AdminSidebar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onSelect;

  const _AdminSidebar({
    required this.currentIndex,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 240,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          right: BorderSide(color: AppTheme.dividerColor, width: 1),
        ),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.asset(
                      'assets/icon/app_logo.png',
                      width: 36,
                      height: 36,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.analytics_rounded,
                          color: AppTheme.primaryColor,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'TallyLive',
                      style: AppTheme.brandTitle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            _AdminSidebarItem(
              icon: Icons.business_rounded,
              label: 'Companies',
              isSelected: currentIndex == 0,
              onTap: () => onSelect(0),
            ),
            _AdminSidebarItem(
              icon: Icons.people_alt_rounded,
              label: 'Users',
              isSelected: currentIndex == 1,
              onTap: () => onSelect(1),
            ),
            _AdminSidebarItem(
              icon: Icons.sync_lock_rounded,
              label: 'Subscriptions',
              isSelected: currentIndex == 2,
              onTap: () => onSelect(2),
            ),
            _AdminSidebarItem(
              icon: Icons.person_rounded,
              label: 'Profile',
              isSelected: currentIndex == 3,
              onTap: () => onSelect(3),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Main Admin Shell (Tabs) ──────────────────────────────────
class AdminPanelScreen extends StatefulWidget {
  final bool isRootAdmin;
  const AdminPanelScreen({super.key, this.isRootAdmin = false});

  @override
  State<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends State<AdminPanelScreen> {
  int _currentIndex = 0;
  bool _verified = false;
  bool _closing = false;
  StreamSubscription<Map<String, dynamic>>? _profileSubscription;

  bool _allowed(Map<String, dynamic>? profile) {
    final user = SupabaseService().currentUser;
    final phone = profile?['phone_number']?.toString().replaceAll(RegExp(r'[^0-9]'), '') ?? '';
    return user != null && profile?['is_active'] == true &&
      (profile?['role'] == 'super_admin' || user.email == 'admin@tallylive.com' || phone == '97000000');
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _verifyAccess(); });
  }

  Future<void> _denyAccess() async {
    if (_closing || !mounted) return;
    _closing = true;
    setState(() => _verified = false);
    if (SupabaseService().currentUser != null) await SupabaseService().signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
  }

  Future<void> _verifyAccess() async {
    final service = SupabaseService();
    final user = service.currentUser;
    final profile = user == null ? null : await service.getUserProfile(user.id);
    if (!mounted) return;
    if (!_allowed(profile)) { await _denyAccess(); return; }
    setState(() => _verified = true);
    _profileSubscription = service.streamUserProfile(user!.id).listen((profile) {
      // Realtime can emit empty maps while reconnecting — ignore those.
      // Only force logout when we receive a real profile that fails the check.
      if (!mounted || profile.isEmpty) return;
      if (!_allowed(profile)) _denyAccess();
    }, onError: (Object _) {
      // Stream glitches must not wipe the admin session on hot restart / reconnect.
    });
  }

  @override
  void dispose() {
    _profileSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_verified) {
      return const Scaffold(
        backgroundColor: AppTheme.surfaceColor,
        body: Center(child: CircularProgressIndicator(color: AppTheme.primaryColor)),
      );
    }
    final tabs = [
      const AdminCompaniesTab(),
      const AdminUsersTab(),
      const AdminSyncLicensesTab(),
      const AdminProfileTab(),
    ];
    final isWide = MediaQuery.of(context).size.width >= 900;
    final stack = IndexedStack(
      index: _currentIndex,
      children: tabs,
    );

    if (isWide) {
      return ScrollConfiguration(
        behavior: const _AdminScrollBehavior(),
        child: Scaffold(
          backgroundColor: AppTheme.surfaceColor,
          body: Row(
            children: [
              _AdminSidebar(
                currentIndex: _currentIndex,
                onSelect: (i) => setState(() => _currentIndex = i),
              ),
              Expanded(child: stack),
            ],
          ),
        ),
      );
    }

    return ScrollConfiguration(
      behavior: const _AdminScrollBehavior(),
      child: Scaffold(
        backgroundColor: AppTheme.surfaceColor,
        body: stack,
        bottomNavigationBar: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            border: const Border(
              top: BorderSide(color: AppTheme.dividerColor, width: 1),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
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
                  _AdminNavItem(
                    icon: Icons.business_rounded,
                    label: 'Companies',
                    isSelected: _currentIndex == 0,
                    onTap: () => setState(() => _currentIndex = 0),
                  ),
                  _AdminNavItem(
                    icon: Icons.people_alt_rounded,
                    label: 'Users',
                    isSelected: _currentIndex == 1,
                    onTap: () => setState(() => _currentIndex = 1),
                  ),
                  _AdminNavItem(
                    icon: Icons.sync_lock_rounded,
                    label: 'Subscriptions',
                    isSelected: _currentIndex == 2,
                    onTap: () => setState(() => _currentIndex = 2),
                  ),
                  _AdminNavItem(
                    icon: Icons.person_rounded,
                    label: 'Profile',
                    isSelected: _currentIndex == 3,
                    onTap: () => setState(() => _currentIndex = 3),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AdminNavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _AdminNavItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = isSelected ? AppTheme.primaryColor : AppTheme.textSecondary;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Tab 1: Companies List ────────────────────────────────────
class AdminCompaniesTab extends StatefulWidget {
  const AdminCompaniesTab({super.key});

  @override
  State<AdminCompaniesTab> createState() => _AdminCompaniesTabState();
}

class _AdminCompaniesTabState extends State<AdminCompaniesTab> {
  final SupabaseService _service = SupabaseService();
  final TextEditingController _searchController = TextEditingController();
  bool _isLoading = true;
  List<Map<String, dynamic>> _companiesFeatures = [];
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadCompanies();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCompanies() async {
    setState(() {
      _isLoading = true;
      _searchQuery = '';
      _searchController.clear();
    });
    try {
      final data = await _service.getAllCompaniesFeatures();
      if (!mounted) return;
      setState(() {
        _companiesFeatures = data;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading companies: $e')),
      );
    }
  }

  Widget _buildAnalyticsHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      color: Colors.white,
      child: Row(
        children: [
          Expanded(child: _buildStatCard('Total Companies', _companiesFeatures.length.toString(), Icons.business)),
          const SizedBox(width: 12),
          Expanded(child: _buildStatCard('Active Now', _companiesFeatures.length.toString(), Icons.check_circle_outline)),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, String count, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.dividerColor),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.primaryColor, size: 20),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(fontSize: 11, color: AppTheme.textSecondary, fontWeight: FontWeight.w500)),
              Text(count, style: TextStyle(fontSize: 18, color: AppTheme.textPrimary, fontWeight: FontWeight.w700)),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _companiesFeatures.where((c) {
      final name = c['company_name']?.toString().toLowerCase() ?? '';
      return name.contains(_searchQuery.toLowerCase());
    }).toList();

    return Scaffold(
      backgroundColor: AppTheme.surfaceColor,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _AdminPageHeader(
              title: 'Companies',
              subtitle: 'Manage company access and features',
              actions: [
                _adminRefreshButton(
                  onPressed: _isLoading ? null : _loadCompanies,
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: TextField(
                controller: _searchController,
                onChanged: (val) => setState(() => _searchQuery = val),
                decoration: InputDecoration(
                  hintText: 'Search companies...',
                  hintStyle: const TextStyle(color: AppTheme.textSecondary, fontSize: 14),
                  prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.textSecondary, size: 20),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppTheme.dividerColor),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppTheme.dividerColor),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppTheme.primaryColor, width: 1.5),
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                color: AppTheme.primaryColor,
                onRefresh: _loadCompanies,
                child: _isLoading
                    ? const ShimmerLoading()
                    : filtered.isEmpty
                        ? ListView(
                            physics: _adminListPhysics,
                            children: [
                              SizedBox(
                                height: MediaQuery.of(context).size.height * 0.35,
                                child: Center(
                                  child: Text(
                                    _searchQuery.isEmpty
                                        ? 'No companies synced yet.'
                                        : 'No companies match "$_searchQuery"',
                                    style: const TextStyle(color: AppTheme.textSecondary),
                                  ),
                                ),
                              ),
                            ],
                          )
                        : AnimationLimiter(
                            child: ListView.separated(
                              physics: _adminListPhysics,
                              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                              itemCount: filtered.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 8),
                              itemBuilder: (context, index) {
                                final comp = filtered[index];
                                final companyName = comp['company_name'] as String;
                                final features = comp['features'] as Map<String, bool>;

                                return AnimationConfiguration.staggeredList(
                                  position: index,
                                  duration: const Duration(milliseconds: 280),
                                  child: SlideAnimation(
                                    verticalOffset: 24.0,
                                    child: FadeInAnimation(
                                      child: Material(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(12),
                                        clipBehavior: Clip.antiAlias,
                                        child: InkWell(
                                          borderRadius: BorderRadius.circular(12),
                                          onTap: () async {
                                            final updatedFeatures =
                                                await Navigator.of(context).push<Map<String, bool>>(
                                              MaterialPageRoute(
                                                builder: (_) => CompanyFeaturesScreen(
                                                  companyName: companyName,
                                                  initialFeatures: features,
                                                ),
                                              ),
                                            );
                                            if (updatedFeatures != null && mounted) {
                                              setState(() {
                                                comp['features'] = updatedFeatures;
                                              });
                                            }
                                          },
                                          child: Container(
                                            decoration: BoxDecoration(
                                              borderRadius: BorderRadius.circular(12),
                                              border: Border.all(color: AppTheme.dividerColor),
                                            ),
                                            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                                            child: Row(
                                              children: [
                                                Container(
                                                  width: 40,
                                                  height: 40,
                                                  decoration: BoxDecoration(
                                                    color: AppTheme.primaryColor.withValues(alpha: 0.1),
                                                    borderRadius: BorderRadius.circular(8),
                                                  ),
                                                  child: const Icon(
                                                    Icons.business_rounded,
                                                    color: AppTheme.primaryColor,
                                                    size: 20,
                                                  ),
                                                ),
                                                const SizedBox(width: 14),
                                                Expanded(
                                                  child: Text(
                                                    companyName,
                                                    style: const TextStyle(
                                                      fontSize: 15,
                                                      fontWeight: FontWeight.w600,
                                                      color: AppTheme.textPrimary,
                                                    ),
                                                  ),
                                                ),
                                                const Text(
                                                  'Features',
                                                  style: TextStyle(
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w500,
                                                    color: AppTheme.textSecondary,
                                                  ),
                                                ),
                                                const SizedBox(width: 4),
                                                const Icon(
                                                  Icons.chevron_right_rounded,
                                                  size: 20,
                                                  color: AppTheme.textSecondary,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Tab 2: Users Management ──────────────────────────────────
// ─── Tab 1.5: Sync Licenses & Machine Control ──────────────────
class AdminSyncLicensesTab extends StatefulWidget {
  const AdminSyncLicensesTab({super.key});

  @override
  State<AdminSyncLicensesTab> createState() => _AdminSyncLicensesTabState();
}

enum _LicenseSort {
  recentlySeen,
  companyAz,
  machineAz,
  expirySoonest,
  expiryLatest,
}

enum _LicenseFilter {
  all,
  expiringSoon,
  expired,
  noExpiry,
  syncPaused,
}

class _AdminSyncLicensesTabState extends State<AdminSyncLicensesTab> {
  final SupabaseService _service = SupabaseService();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _listScrollController = ScrollController();
  bool _isLoading = true;
  bool _isRefreshing = false;
  List<Map<String, dynamic>> _machines = [];
  final Map<String, List<String>> _machineCompanies = {};
  String _searchQuery = '';
  _LicenseSort _sort = _LicenseSort.recentlySeen;
  _LicenseFilter _filter = _LicenseFilter.all;

  @override
  void initState() {
    super.initState();
    _loadMachines();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _listScrollController.dispose();
    super.dispose();
  }

  DateTime? _parseMachineDate(dynamic raw) {
    if (raw == null) return null;
    return DateTime.tryParse(raw.toString());
  }

  /// Update one machine in memory so the list does not reload / jump to top.
  void _patchMachineLocally(
    String machineId, {
    bool? syncShouldRun,
    DateTime? expiresAt,
  }) {
    final i = _machines.indexWhere((m) => m['id']?.toString() == machineId);
    if (i < 0) return;
    setState(() {
      final copy = Map<String, dynamic>.from(_machines[i]);
      if (syncShouldRun != null) copy['sync_should_run'] = syncShouldRun;
      if (expiresAt != null) {
        copy['expires_at'] = expiresAt.toUtc().toIso8601String();
      }
      _machines[i] = copy;
    });
  }

  List<Map<String, dynamic>> _visibleMachines() {
    final q = _searchQuery.toLowerCase();
    final now = DateTime.now();

    var list = _machines.where((m) {
      final machineKey = m['machine_name']?.toString() ?? '';
      final linked = (_machineCompanies[machineKey] ?? const <String>[])
          .join(' ')
          .toLowerCase();
      final comp = m['current_company']?.toString().toLowerCase() ?? '';
      final mach = machineKey.toLowerCase();
      if (q.isNotEmpty &&
          !comp.contains(q) &&
          !mach.contains(q) &&
          !linked.contains(q)) {
        return false;
      }

      final expiresAt = _parseMachineDate(m['expires_at']);
      final isExpired = expiresAt != null && now.isAfter(expiresAt);
      final daysLeft =
          expiresAt == null ? null : expiresAt.difference(now).inDays;
      final paused = m['sync_should_run'] != true;

      switch (_filter) {
        case _LicenseFilter.all:
          return true;
        case _LicenseFilter.expiringSoon:
          return expiresAt != null &&
              !isExpired &&
              daysLeft != null &&
              daysLeft <= 7;
        case _LicenseFilter.expired:
          return isExpired;
        case _LicenseFilter.noExpiry:
          return expiresAt == null;
        case _LicenseFilter.syncPaused:
          return paused;
      }
    }).toList();

    int cmpStr(String? a, String? b) =>
        (a ?? '').toLowerCase().compareTo((b ?? '').toLowerCase());

    list.sort((a, b) {
      switch (_sort) {
        case _LicenseSort.recentlySeen:
          final aSeen = _parseMachineDate(a['last_seen_at']);
          final bSeen = _parseMachineDate(b['last_seen_at']);
          if (aSeen == null && bSeen == null) return 0;
          if (aSeen == null) return 1;
          if (bSeen == null) return -1;
          return bSeen.compareTo(aSeen);
        case _LicenseSort.companyAz:
          return cmpStr(
            a['current_company']?.toString(),
            b['current_company']?.toString(),
          );
        case _LicenseSort.machineAz:
          return cmpStr(
            a['machine_name']?.toString(),
            b['machine_name']?.toString(),
          );
        case _LicenseSort.expirySoonest:
        case _LicenseSort.expiryLatest:
          final aExp = _parseMachineDate(a['expires_at']);
          final bExp = _parseMachineDate(b['expires_at']);
          if (aExp == null && bExp == null) return 0;
          if (aExp == null) return 1;
          if (bExp == null) return -1;
          final c = aExp.compareTo(bExp);
          return _sort == _LicenseSort.expirySoonest ? c : -c;
      }
    });

    return list;
  }

  Future<void> _loadMachines({bool fullScreenLoader = true}) async {
    if (fullScreenLoader) {
      setState(() => _isLoading = true);
    } else {
      setState(() => _isRefreshing = true);
    }
    try {
      final data = await _service.getAllSyncMachines();
      final links = <String, List<String>>{};
      await Future.wait(data.map((m) async {
        final name = m['machine_name']?.toString() ?? '';
        if (name.isEmpty) return;
        links[name] = await _service.getCompaniesForMachine(name);
      }));
      if (mounted) {
        setState(() {
          _machines = data;
          _machineCompanies
            ..clear()
            ..addAll(links);
          _isLoading = false;
          _isRefreshing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isRefreshing = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading sync machines: $e')),
        );
      }
    }
  }

  Future<void> _refreshMachines() async {
    if (_isRefreshing || _isLoading) return;
    await _loadMachines(fullScreenLoader: false);
  }

  String _formatDate(DateTime dt) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${dt.day.toString().padLeft(2, '0')} ${months[dt.month - 1]} ${dt.year}';
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().toUtc().difference(dt.toUtc());
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 30) return '${diff.inDays}d ago';
    return _formatDate(dt);
  }

  void _showExtendLicenseSheet(BuildContext context, Map<String, dynamic> machine) {
    final machineName = machine['machine_name']?.toString() ?? 'Machine';
    final companyName = machine['current_company']?.toString() ?? 'Company';
    final machineId = machine['id']?.toString() ?? '';

    DateTime? currentExpiry;
    final expRaw = machine['expires_at'];
    if (expRaw != null) {
      try {
        currentExpiry = DateTime.parse(expRaw.toString());
      } catch (_) {}
    }

    final isExpired = currentExpiry != null && DateTime.now().isAfter(currentExpiry);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetCtx) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.sync_lock_rounded, color: AppTheme.primaryColor, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Extend License',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        Text(
                          '$companyName ($machineName)',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.dividerColor),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Current Expiry:',
                      style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                    ),
                    Text(
                      currentExpiry != null
                          ? '${_formatDate(currentExpiry)}${isExpired ? ' (Expired)' : ''}'
                          : 'No expiry set',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isExpired ? Colors.red.shade700 : AppTheme.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Select Extension Plan:',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              _buildPlanOption(
                sheetCtx,
                label: '+ 1 Month (30 Days)',
                subtitle: 'Add 30 days to subscription',
                days: 30,
                currentExpiry: currentExpiry,
                machineId: machineId,
              ),
              _buildPlanOption(
                sheetCtx,
                label: '+ 3 Months (90 Days)',
                subtitle: 'Add 90 days to subscription',
                days: 90,
                currentExpiry: currentExpiry,
                machineId: machineId,
              ),
              _buildPlanOption(
                sheetCtx,
                label: '+ 6 Months (180 Days)',
                subtitle: 'Add 180 days to subscription',
                days: 180,
                currentExpiry: currentExpiry,
                machineId: machineId,
              ),
              _buildPlanOption(
                sheetCtx,
                label: '+ 1 Year (365 Days)',
                subtitle: 'Add 365 days to subscription',
                days: 365,
                currentExpiry: currentExpiry,
                machineId: machineId,
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () async {
                  final now = DateTime.now();
                  final today = DateTime(now.year, now.month, now.day);
                  final initial = currentExpiry != null && currentExpiry.isAfter(now)
                      ? currentExpiry
                      : today;
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: initial.isBefore(today) ? today : initial,
                    firstDate: today,
                    lastDate: today.add(const Duration(days: 365 * 5)),
                  );
                  if (picked != null) {
                    Navigator.pop(sheetCtx);
                    // End of selected local day (date picker returns midnight).
                    final endOfDay = DateTime(
                      picked.year,
                      picked.month,
                      picked.day,
                      23,
                      59,
                      59,
                    );
                    _applyNewExpiry(machineId, endOfDay);
                  }
                },
                icon: const Icon(Icons.calendar_today_rounded, size: 18),
                label: const Text('Pick Exact Date...'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPlanOption(
    BuildContext sheetCtx, {
    required String label,
    required String subtitle,
    required int days,
    required DateTime? currentExpiry,
    required String machineId,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            Navigator.pop(sheetCtx);
            final base = (currentExpiry != null && currentExpiry.isAfter(DateTime.now()))
                ? currentExpiry
                : DateTime.now();
            final newExpiry = base.add(Duration(days: days));
            _applyNewExpiry(machineId, newExpiry);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              border: Border.all(color: AppTheme.dividerColor),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                    ),
                  ],
                ),
                const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: AppTheme.primaryColor),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _applyNewExpiry(String machineId, DateTime newExpiry) async {
    final alreadyPast = DateTime.now().isAfter(newExpiry);
    final success = await _service.updateSyncMachineControl(
      machineId,
      expiresAt: newExpiry,
      // Only turn sync on when the new expiry is still in the future.
      syncShouldRun: !alreadyPast,
    );
    if (!mounted) return;
    if (success) {
      _patchMachineLocally(
        machineId,
        expiresAt: newExpiry,
        syncShouldRun: !alreadyPast,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor:
              alreadyPast ? Colors.orange.shade800 : Colors.green.shade700,
          content: Text(
            alreadyPast
                ? 'License set to ${_formatDate(newExpiry)} — sync paused (date already passed).'
                : 'License updated until ${_formatDate(newExpiry)}',
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.red,
          content: Text('Failed to update license. Check your connection and try again.'),
        ),
      );
    }
  }

  Future<void> _toggleSyncRun(String machineId, bool currentValue) async {
    final newValue = !currentValue;
    // Optimistic UI — keep scroll position; revert on failure.
    _patchMachineLocally(machineId, syncShouldRun: newValue);
    final success = await _service.updateSyncMachineControl(
      machineId,
      syncShouldRun: newValue,
    );
    if (!mounted) return;
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(newValue ? 'Sync enabled' : 'Sync paused remotely'),
        ),
      );
    } else {
      _patchMachineLocally(machineId, syncShouldRun: currentValue);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Text(
            newValue
                ? 'Cannot enable sync — subscription has expired. Extend the license first.'
                : 'Failed to pause sync. Try again.',
          ),
        ),
      );
    }
  }

  String _sortLabel(_LicenseSort s) {
    switch (s) {
      case _LicenseSort.recentlySeen:
        return 'Recently seen';
      case _LicenseSort.companyAz:
        return 'Company A–Z';
      case _LicenseSort.machineAz:
        return 'Machine A–Z';
      case _LicenseSort.expirySoonest:
        return 'Expiry soonest';
      case _LicenseSort.expiryLatest:
        return 'Expiry latest';
    }
  }

  String _filterLabel(_LicenseFilter f) {
    switch (f) {
      case _LicenseFilter.all:
        return 'All';
      case _LicenseFilter.expiringSoon:
        return 'Expiring ≤7d';
      case _LicenseFilter.expired:
        return 'Expired';
      case _LicenseFilter.noExpiry:
        return 'No expiry';
      case _LicenseFilter.syncPaused:
        return 'Paused';
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _visibleMachines();

    return Scaffold(
      backgroundColor: AppTheme.surfaceColor,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _AdminPageHeader(
              title: 'Subscriptions',
              subtitle: 'Manage sync machines and subscription expiry',
              actions: [
                if (_isRefreshing)
                  const Padding(
                    padding: EdgeInsets.only(right: 12, top: 8),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryColor),
                    ),
                  )
                else
                  _adminRefreshButton(
                    onPressed: _isLoading ? null : _refreshMachines,
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: TextField(
                controller: _searchController,
                onChanged: (val) => setState(() => _searchQuery = val),
                decoration: InputDecoration(
                  hintText: 'Search by company or machine...',
                  hintStyle: const TextStyle(color: AppTheme.textSecondary, fontSize: 14),
                  prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.textSecondary, size: 20),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppTheme.dividerColor),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppTheme.dividerColor),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppTheme.primaryColor, width: 1.5),
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<_LicenseSort>(
                      value: _sort,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: 'Sort',
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: AppTheme.dividerColor),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: AppTheme.dividerColor),
                        ),
                      ),
                      items: _LicenseSort.values
                          .map(
                            (s) => DropdownMenuItem(
                              value: s,
                              child: Text(_sortLabel(s), overflow: TextOverflow.ellipsis),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setState(() => _sort = v);
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<_LicenseFilter>(
                      value: _filter,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: 'Filter',
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: AppTheme.dividerColor),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: AppTheme.dividerColor),
                        ),
                      ),
                      items: _LicenseFilter.values
                          .map(
                            (f) => DropdownMenuItem(
                              value: f,
                              child: Text(_filterLabel(f), overflow: TextOverflow.ellipsis),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setState(() => _filter = v);
                      },
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryColor))
                  : RefreshIndicator(
                      color: AppTheme.primaryColor,
                      onRefresh: _refreshMachines,
                      child: filtered.isEmpty
                          ? ListView(
                              controller: _listScrollController,
                              physics: _adminListPhysics,
                              children: [
                                const SizedBox(height: 120),
                                Center(
                                  child: Text(
                                    _searchQuery.isEmpty && _filter == _LicenseFilter.all
                                        ? 'No sync machines found'
                                        : 'No machines match your search/filter',
                                    style: const TextStyle(color: AppTheme.textSecondary),
                                  ),
                                ),
                              ],
                            )
                          : ListView.separated(
                              controller: _listScrollController,
                              physics: _adminListPhysics,
                              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                              itemCount: filtered.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 6),
                              itemBuilder: (context, index) {
                                final m = filtered[index];
                                final companyName =
                                    m['current_company']?.toString() ?? 'Unknown Company';
                                final machineName =
                                    m['machine_name']?.toString() ?? 'Unknown Machine';
                                final shouldRun = m['sync_should_run'] == true;
                                final machineId = m['id']?.toString() ?? '';

                                DateTime? lastSeen;
                                final lsRaw = m['last_seen_at'];
                                if (lsRaw != null) {
                                  try {
                                    lastSeen = DateTime.parse(lsRaw.toString());
                                  } catch (_) {}
                                }

                                DateTime? expiresAt;
                                final expRaw = m['expires_at'];
                                if (expRaw != null) {
                                  try {
                                    expiresAt = DateTime.parse(expRaw.toString());
                                  } catch (_) {}
                                }

                                final isOnline = lastSeen != null &&
                                    DateTime.now()
                                            .toUtc()
                                            .difference(lastSeen.toUtc())
                                            .inHours <
                                        3;
                                final isExpired =
                                    expiresAt != null && DateTime.now().isAfter(expiresAt);
                                final daysRemaining = expiresAt != null
                                    ? expiresAt.difference(DateTime.now()).inDays
                                    : null;
                                final linked =
                                    _machineCompanies[machineName] ?? const <String>[];

                                final expiryLabel = expiresAt != null
                                    ? (isExpired
                                        ? 'Expired ${_formatDate(expiresAt)}'
                                        : 'Expires ${_formatDate(expiresAt)}'
                                            '${daysRemaining != null ? ' ($daysRemaining d)' : ''}')
                                    : 'No expiry';
                                final seenLabel =
                                    lastSeen != null ? 'Seen ${_timeAgo(lastSeen)}' : null;

                                return Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: isExpired
                                          ? AppTheme.errorColor.withValues(alpha: 0.35)
                                          : AppTheme.dividerColor,
                                    ),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 8,
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      Container(
                                        width: 32,
                                        height: 32,
                                        decoration: BoxDecoration(
                                          color: AppTheme.primaryColor.withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(7),
                                        ),
                                        child: const Icon(
                                          Icons.computer_rounded,
                                          color: AppTheme.primaryColor,
                                          size: 17,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              machineName,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 13.5,
                                                fontWeight: FontWeight.w600,
                                                color: AppTheme.textPrimary,
                                                height: 1.2,
                                              ),
                                            ),
                                            const SizedBox(height: 1),
                                            Text(
                                              companyName,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: AppTheme.textSecondary,
                                                height: 1.2,
                                              ),
                                            ),
                                            if (linked.isNotEmpty) ...[
                                              const SizedBox(height: 1),
                                              Text(
                                                'Linked: ${linked.join(', ')}',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontSize: 10.5,
                                                  color: AppTheme.textSecondary,
                                                  height: 1.2,
                                                ),
                                              ),
                                            ],
                                            const SizedBox(height: 3),
                                            Row(
                                              children: [
                                                Container(
                                                  padding: const EdgeInsets.symmetric(
                                                    horizontal: 5,
                                                    vertical: 1,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: isOnline
                                                        ? const Color(0xFFDCFCE7)
                                                        : const Color(0xFFF3F4F6),
                                                    borderRadius: BorderRadius.circular(4),
                                                  ),
                                                  child: Text(
                                                    isOnline ? 'Online' : 'Offline',
                                                    style: TextStyle(
                                                      fontSize: 9.5,
                                                      fontWeight: FontWeight.w600,
                                                      height: 1.2,
                                                      color: isOnline
                                                          ? const Color(0xFF15803D)
                                                          : AppTheme.textSecondary,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 6),
                                                Expanded(
                                                  child: Tooltip(
                                                    message:
                                                        'Last sync PC heartbeat. Online = within 3 hours.',
                                                    child: Text(
                                                      seenLabel == null
                                                          ? expiryLabel
                                                          : '$expiryLabel · $seenLabel',
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        fontWeight: FontWeight.w500,
                                                        height: 1.2,
                                                        color: isExpired
                                                            ? AppTheme.errorColor
                                                            : AppTheme.textSecondary,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Column(
                                            mainAxisSize: MainAxisSize.min,
                                            crossAxisAlignment: CrossAxisAlignment.center,
                                            children: [
                                              const Text(
                                                'Sync',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w600,
                                                  color: AppTheme.textSecondary,
                                                  height: 1,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Transform.scale(
                                                    scale: 0.82,
                                                    child: Switch.adaptive(
                                                      value: shouldRun,
                                                      materialTapTargetSize:
                                                          MaterialTapTargetSize.shrinkWrap,
                                                      activeColor: AppTheme.primaryColor,
                                                      onChanged: (_) => _toggleSyncRun(
                                                        machineId,
                                                        shouldRun,
                                                      ),
                                                    ),
                                                  ),
                                                  Text(
                                                    shouldRun ? 'On' : 'Off',
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.w600,
                                                      color: shouldRun
                                                          ? const Color(0xFF15803D)
                                                          : AppTheme.errorColor,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                          const SizedBox(width: 8),
                                          OutlinedButton(
                                            onPressed: () =>
                                                _showExtendLicenseSheet(context, m),
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor: AppTheme.primaryColor,
                                              side: const BorderSide(
                                                color: AppTheme.primaryColor,
                                              ),
                                              visualDensity: VisualDensity.compact,
                                              tapTargetSize:
                                                  MaterialTapTargetSize.shrinkWrap,
                                              minimumSize: const Size(0, 30),
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 10,
                                                vertical: 4,
                                              ),
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(7),
                                              ),
                                            ),
                                            child: const Text(
                                              'Extend',
                                              style: TextStyle(fontSize: 12),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Tab 2: Users Management ──────────────────────────────────

class AdminUsersTab extends StatefulWidget {
  const AdminUsersTab({super.key});

  @override
  State<AdminUsersTab> createState() => _AdminUsersTabState();
}

class _AdminUsersTabState extends State<AdminUsersTab> {
  final SupabaseService _service = SupabaseService();
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _users = [];
  String _searchQuery = '';
  bool _isLoading = true;
  bool _isRefreshing = false;

  final Set<String> _expandedUserIds = {};
  final Set<String> _loadingCompaniesUserIds = {};
  final Map<String, List<String>> _userCompaniesMap = {};

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadUsers({bool fullScreenLoader = false}) async {
    if (fullScreenLoader && mounted) {
      setState(() => _isLoading = true);
    }
    try {
      final users = await _service.getAllUsers();
      if (!mounted) return;
      setState(() {
        _users = users;
        _isLoading = false;
        _isRefreshing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isRefreshing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load users: $e'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
    }
  }

  Future<void> _refreshUsers() async {
    if (_isRefreshing || _isLoading) return;
    setState(() {
      _isRefreshing = true;
      _userCompaniesMap.clear();
      _expandedUserIds.clear();
      _loadingCompaniesUserIds.clear();
      _searchQuery = '';
      _searchController.clear();
    });
    // Keep current list visible — full-screen loader was wiping users on error/filter.
    await _loadUsers(fullScreenLoader: false);
  }

  Future<void> _toggleExpandUser(String userId) async {
    final isExpanded = _expandedUserIds.contains(userId);
    setState(() {
      if (isExpanded) {
        _expandedUserIds.remove(userId);
      } else {
        _expandedUserIds.add(userId);
      }
    });

    if (!isExpanded && !_userCompaniesMap.containsKey(userId)) {
      setState(() {
        _loadingCompaniesUserIds.add(userId);
      });
      try {
        final companies = await _service.getUserCompanies(userId);
        if (mounted) {
          setState(() {
            _userCompaniesMap[userId] = companies;
            _loadingCompaniesUserIds.remove(userId);
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _userCompaniesMap[userId] = [];
            _loadingCompaniesUserIds.remove(userId);
          });
        }
      }
    }
  }

  Future<void> _toggleAccess(String userId, bool newValue) async {
    final idx = _users.indexWhere((u) => u['id']?.toString() == userId);
    final previous = idx >= 0 ? _users[idx]['is_active'] == true : !newValue;
    if (idx >= 0) {
      setState(() {
        _users[idx] = Map<String, dynamic>.from(_users[idx])
          ..['is_active'] = newValue;
      });
    }
    try {
      await _service.updateUserAccess(userId, newValue);
    } catch (e) {
      if (!mounted) return;
      if (idx >= 0) {
        setState(() {
          _users[idx] = Map<String, dynamic>.from(_users[idx])
            ..['is_active'] = previous;
        });
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update access: $e'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
    }
  }

  Future<void> _refreshUserCompanies(String userId) async {
    // Merged list: user_companies + profile primary (additive link model).
    final companies = await _service.getUserCompanies(userId);
    if (!mounted) return;
    setState(() => _userCompaniesMap[userId] = companies);
  }

  Future<void> _showAdminLinkCompanyDialog({
    required String userId,
    required String userName,
  }) async {
    final already = _userCompaniesMap[userId] ?? const <String>[];
    List<String> allCompanies = [];
    try {
      allCompanies = await _service.getCompanies();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load companies: $e')),
      );
      return;
    }
    if (!mounted) return;

    final available = allCompanies
        .where((c) => !already.any((a) => a.toLowerCase() == c.toLowerCase()))
        .toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    if (available.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No more companies available to link.')),
      );
      return;
    }

    String query = '';
    String? selected;

    final linked = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final filtered = query.trim().isEmpty
                ? available
                : available
                    .where((c) =>
                        c.toLowerCase().contains(query.trim().toLowerCase()))
                    .toList();
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              insetPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              child: SizedBox(
                width: 420,
                height: 480,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Link company to $userName',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Select a Tally company. No mobile verification required.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        decoration: InputDecoration(
                          hintText: 'Search companies…',
                          prefixIcon: const Icon(Icons.search_rounded),
                          filled: true,
                          fillColor: AppTheme.surfaceColor,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        onChanged: (v) => setDialogState(() => query = v),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: filtered.isEmpty
                            ? const Center(
                                child: Text(
                                  'No matching companies',
                                  style: TextStyle(color: AppTheme.textSecondary),
                                ),
                              )
                            : ListView.builder(
                                itemCount: filtered.length,
                                itemBuilder: (_, i) {
                                  final name = filtered[i];
                                  final isSel = selected == name;
                                  return ListTile(
                                    dense: true,
                                    selected: isSel,
                                    selectedTileColor: AppTheme.primaryColor
                                        .withValues(alpha: 0.08),
                                    title: Text(
                                      name,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: isSel
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                      ),
                                    ),
                                    trailing: isSel
                                        ? const Icon(
                                            Icons.check_circle_rounded,
                                            color: AppTheme.primaryColor,
                                            size: 20,
                                          )
                                        : null,
                                    onTap: () =>
                                        setDialogState(() => selected = name),
                                  );
                                },
                              ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(),
                            child: const Text('Cancel'),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: selected == null
                                ? null
                                : () => Navigator.of(ctx).pop(selected),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primaryColor,
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('Link'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (linked == null || linked.isEmpty || !mounted) return;

    try {
      final name = await _service.adminLinkCompanyToUser(
        userId: userId,
        companyName: linked,
      );
      await _refreshUserCompanies(userId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Linked “$name”'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll('Exception:', '').trim()),
          backgroundColor: AppTheme.errorColor,
        ),
      );
    }
  }

  Future<void> _unlinkCompany({
    required String userId,
    required String companyName,
  }) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unlink company?'),
        content: Text(
          'Remove “$companyName” from this user’s access?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.errorColor,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Unlink'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    try {
      await _service.adminUnlinkCompanyFromUser(
        userId: userId,
        companyName: companyName,
      );
      if (!mounted) return;
      // Immediate UI update, then reconcile from DB.
      setState(() {
        final current = List<String>.from(_userCompaniesMap[userId] ?? const []);
        current.removeWhere(
          (c) => c.trim().toLowerCase() == companyName.trim().toLowerCase(),
        );
        _userCompaniesMap[userId] = current;
      });
      await _refreshUserCompanies(userId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unlinked “$companyName”')),
      );
    } catch (e) {
      if (!mounted) return;
      await _refreshUserCompanies(userId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll('Exception:', '').trim()),
          backgroundColor: AppTheme.errorColor,
        ),
      );
    }
  }

  void _showCreateUserDialog() {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();

    final nameFocus = FocusNode();
    final phoneFocus = FocusNode();
    final passwordFocus = FocusNode();

    final formKey = GlobalKey<FormState>();
    var isRegistering = false;
    var obscure = true;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> submitRegistration() async {
              if (!formKey.currentState!.validate() || isRegistering) return;
              setDialogState(() => isRegistering = true);
              try {
                await _service.adminRegisterUser(
                  fullName: nameCtrl.text.trim(),
                  phone: phoneCtrl.text.trim(),
                  password: passwordCtrl.text.trim(),
                );
                if (!mounted) return;
                Navigator.of(ctx).pop();
                ScaffoldMessenger.of(this.context).showSnackBar(
                  const SnackBar(
                    content: Text('User account created successfully!'),
                    backgroundColor: Colors.green,
                  ),
                );
                await _refreshUsers();
              } catch (e) {
                setDialogState(() => isRegistering = false);
                ScaffoldMessenger.of(this.context).showSnackBar(
                  SnackBar(
                    content: Text(e.toString().replaceAll('Exception:', '').trim()),
                    backgroundColor: AppTheme.errorColor,
                  ),
                );
              }
            }

            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.person_add_rounded, color: AppTheme.primaryColor),
                          SizedBox(width: 8),
                          Text('Create New User', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Register a new business owner. Link companies after creating the account.',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: nameCtrl,
                        focusNode: nameFocus,
                        textInputAction: TextInputAction.next,
                        onFieldSubmitted: (_) {
                          FocusScope.of(context).requestFocus(phoneFocus);
                        },
                        decoration: const InputDecoration(
                          labelText: 'Full Name *',
                          hintText: 'John Doe',
                          prefixIcon: Icon(Icons.person_outline_rounded),
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return 'Please enter user\'s full name';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: phoneCtrl,
                        focusNode: phoneFocus,
                        keyboardType: TextInputType.phone,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(10),
                        ],
                        textInputAction: TextInputAction.next,
                        onFieldSubmitted: (_) {
                          FocusScope.of(context).requestFocus(passwordFocus);
                        },
                        decoration: const InputDecoration(
                          labelText: '10-Digit Mobile Number *',
                          hintText: '9876543210',
                          prefixIcon: Icon(Icons.phone_rounded),
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return 'Please enter mobile number';
                          }
                          if (val.trim().length != 10) {
                            return 'Enter a valid 10-digit phone number';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: passwordCtrl,
                        focusNode: passwordFocus,
                        obscureText: obscure,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => submitRegistration(),
                        decoration: InputDecoration(
                          labelText: 'Temporary Password *',
                          hintText: '••••••••',
                          prefixIcon: const Icon(Icons.lock_outline_rounded),
                          suffixIcon: IconButton(
                            icon: Icon(obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                            onPressed: () => setDialogState(() => obscure = !obscure),
                          ),
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return 'Please create a temporary password';
                          }
                          if (val.length < 6) {
                            return 'Password must be at least 6 characters';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: isRegistering ? null : () => Navigator.of(ctx).pop(),
                            child: const Text('Cancel'),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: isRegistering ? null : submitRegistration,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primaryColor,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            child: isRegistering
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : const Text('Create User'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final displayedUsers = _users.where((user) {
      final name = (user['full_name'] ?? '').toString().toLowerCase();
      final phone = (user['phone_number'] ?? '').toString().toLowerCase();
      final query = _searchQuery.toLowerCase();
      return name.contains(query) || phone.contains(query);
    }).toList();

    return Scaffold(
      backgroundColor: AppTheme.surfaceColor,
      floatingActionButton: _isLoading
          ? null
          : FloatingActionButton.extended(
              onPressed: _showCreateUserDialog,
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
              elevation: 2,
              icon: const Icon(Icons.person_add_rounded),
              label: const Text('Create User'),
            ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _AdminPageHeader(
              title: 'Users',
              subtitle: 'Manage accounts, access, and company links',
              actions: [
                if (_isRefreshing)
                  const Padding(
                    padding: EdgeInsets.only(right: 12, top: 8),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryColor),
                    ),
                  )
                else
                  _adminRefreshButton(
                    onPressed: _isLoading ? null : _refreshUsers,
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search by name or phone...',
                  hintStyle: const TextStyle(color: AppTheme.textSecondary, fontSize: 14),
                  prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.textSecondary, size: 20),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppTheme.dividerColor),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppTheme.dividerColor),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppTheme.primaryColor, width: 1.5),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                onChanged: (val) {
                  setState(() {
                    _searchQuery = val;
                  });
                },
              ),
            ),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryColor))
                  : RefreshIndicator(
                      onRefresh: _refreshUsers,
                      color: AppTheme.primaryColor,
                      child: displayedUsers.isEmpty
                          ? ListView(
                              physics: _adminListPhysics,
                              children: [
                                SizedBox(
                                  height: MediaQuery.of(context).size.height * 0.35,
                                  child: Center(
                                    child: Text(
                                      _users.isEmpty
                                          ? 'No users found'
                                          : 'No users match your search',
                                      style: const TextStyle(color: AppTheme.textSecondary),
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : ListView.separated(
                              physics: _adminListPhysics,
                              padding: const EdgeInsets.fromLTRB(20, 8, 20, 88),
                              itemCount: displayedUsers.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 8),
                              itemBuilder: (context, index) {
                                final user = displayedUsers[index];
                                final userId = user['id']?.toString() ?? '';
                                final isActive = user['is_active'] == true;
                                final role = user['role'] ?? 'user';
                                final isExpanded = _expandedUserIds.contains(userId);
                                final isLoadingCompanies =
                                    _loadingCompaniesUserIds.contains(userId);
                                final companies = _userCompaniesMap[userId] ?? [];

                                return Material(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  clipBehavior: Clip.antiAlias,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: AppTheme.dividerColor),
                                    ),
                                    child: Column(
                                    children: [
                                      InkWell(
                                        onTap: () => _toggleExpandUser(userId),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 12,
                                          ),
                                          child: Row(
                                            children: [
                                              CircleAvatar(
                                                radius: 18,
                                                backgroundColor:
                                                    AppTheme.primaryColor.withValues(alpha: 0.1),
                                                child: Text(
                                                  ((user['full_name']
                                                              ?.toString()
                                                              .trim()
                                                              .isNotEmpty ??
                                                          false)
                                                      ? user['full_name']
                                                          .toString()
                                                          .trim()
                                                          .characters
                                                          .first
                                                          .toUpperCase()
                                                      : 'U'),
                                                  style: const TextStyle(
                                                    color: AppTheme.primaryColor,
                                                    fontWeight: FontWeight.w700,
                                                    fontSize: 13,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      user['full_name']?.toString() ??
                                                          'Unknown User',
                                                      style: const TextStyle(
                                                        fontWeight: FontWeight.w600,
                                                        color: AppTheme.textPrimary,
                                                        fontSize: 14,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 2),
                                                    Text(
                                                      user['phone_number']?.toString() ?? '',
                                                      style: const TextStyle(
                                                        color: AppTheme.textSecondary,
                                                        fontSize: 12,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      role.toString().toUpperCase(),
                                                      style: TextStyle(
                                                        fontSize: 10,
                                                        fontWeight: FontWeight.w700,
                                                        letterSpacing: 0.4,
                                                        color: role == 'super_admin'
                                                            ? AppTheme.errorColor
                                                            : AppTheme.primaryColor,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              Icon(
                                                isExpanded
                                                    ? Icons.keyboard_arrow_up_rounded
                                                    : Icons.keyboard_arrow_down_rounded,
                                                color: AppTheme.textSecondary,
                                              ),
                                              Switch(
                                                value: isActive,
                                                activeColor: AppTheme.primaryColor,
                                                onChanged: (val) => _toggleAccess(userId, val),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      if (isExpanded) ...[
                                        const Divider(
                                          height: 1,
                                          color: AppTheme.dividerColor,
                                        ),
                                        Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
                                          color: AppTheme.surfaceColor,
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  const Icon(
                                                    Icons.business_rounded,
                                                    size: 16,
                                                    color: AppTheme.primaryColor,
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Expanded(
                                                    child: Text(
                                                      'Linked Companies (${companies.length})',
                                                      style: const TextStyle(
                                                        fontWeight: FontWeight.w600,
                                                        fontSize: 13,
                                                        color: AppTheme.textPrimary,
                                                      ),
                                                    ),
                                                  ),
                                                  TextButton.icon(
                                                    onPressed: () =>
                                                        _showAdminLinkCompanyDialog(
                                                      userId: userId,
                                                      userName: user['full_name']?.toString() ??
                                                          'User',
                                                    ),
                                                    icon: const Icon(Icons.add_rounded, size: 16),
                                                    label: const Text('Link'),
                                                    style: TextButton.styleFrom(
                                                      foregroundColor: AppTheme.primaryColor,
                                                      padding: const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                      ),
                                                      visualDensity: VisualDensity.compact,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 10),
                                              if (isLoadingCompanies)
                                                const Padding(
                                                  padding: EdgeInsets.symmetric(vertical: 8.0),
                                                  child: Center(
                                                    child: SizedBox(
                                                      width: 20,
                                                      height: 20,
                                                      child: CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                        color: AppTheme.primaryColor,
                                                      ),
                                                    ),
                                                  ),
                                                )
                                              else if (companies.isEmpty)
                                                const Text(
                                                  'No companies linked. Tap Link to assign companies.',
                                                  style: TextStyle(
                                                    color: AppTheme.textSecondary,
                                                    fontSize: 12,
                                                    fontStyle: FontStyle.italic,
                                                  ),
                                                )
                                              else
                                                Wrap(
                                                  spacing: 8,
                                                  runSpacing: 8,
                                                  children: companies.map((comp) {
                                                    return Material(
                                                      color: Colors.white,
                                                      borderRadius: BorderRadius.circular(8),
                                                      child: InkWell(
                                                        onTap: () async {
                                                          try {
                                                            final features = await _service
                                                                .getCompanyFeatures(comp);
                                                            if (!context.mounted) return;
                                                            Navigator.of(context).push(
                                                              MaterialPageRoute(
                                                                builder: (_) =>
                                                                    CompanyFeaturesScreen(
                                                                  companyName: comp,
                                                                  initialFeatures: features,
                                                                ),
                                                              ),
                                                            );
                                                          } catch (e) {
                                                            if (context.mounted) {
                                                              ScaffoldMessenger.of(context)
                                                                  .showSnackBar(
                                                                SnackBar(
                                                                  content: Text(
                                                                    'Error loading features: $e',
                                                                  ),
                                                                ),
                                                              );
                                                            }
                                                          }
                                                        },
                                                        borderRadius: BorderRadius.circular(8),
                                                        child: Container(
                                                          padding: const EdgeInsets.symmetric(
                                                            horizontal: 10,
                                                            vertical: 6,
                                                          ),
                                                          decoration: BoxDecoration(
                                                            borderRadius:
                                                                BorderRadius.circular(8),
                                                            border: Border.all(
                                                              color: AppTheme.dividerColor,
                                                            ),
                                                          ),
                                                          child: Row(
                                                            mainAxisSize: MainAxisSize.min,
                                                            children: [
                                                              const Icon(
                                                                Icons.domain_rounded,
                                                                size: 14,
                                                                color: AppTheme.primaryColor,
                                                              ),
                                                              const SizedBox(width: 6),
                                                              Flexible(
                                                                child: Text(
                                                                  comp,
                                                                  maxLines: 1,
                                                                  overflow:
                                                                      TextOverflow.ellipsis,
                                                                  style: const TextStyle(
                                                                    fontSize: 12,
                                                                    fontWeight: FontWeight.w500,
                                                                    color: AppTheme.textPrimary,
                                                                  ),
                                                                ),
                                                              ),
                                                              const SizedBox(width: 2),
                                                              InkWell(
                                                                onTap: () => _unlinkCompany(
                                                                  userId: userId,
                                                                  companyName: comp,
                                                                ),
                                                                borderRadius:
                                                                    BorderRadius.circular(10),
                                                                child: const Padding(
                                                                  padding: EdgeInsets.all(2),
                                                                  child: Icon(
                                                                    Icons.close_rounded,
                                                                    size: 14,
                                                                    color:
                                                                        AppTheme.textSecondary,
                                                                  ),
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                      ),
                                                    );
                                                  }).toList(),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  ),
                                );
                              },
                            ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}


// ─── Tab 3: Profile & Logout ──────────────────────────────────
class AdminProfileTab extends StatefulWidget {
  const AdminProfileTab({super.key});

  @override
  State<AdminProfileTab> createState() => _AdminProfileTabState();
}

class _AdminProfileTabState extends State<AdminProfileTab> {
  final SupabaseService _service = SupabaseService();
  String _adminPhone = '';
  String _appVersion = 'v3.0.0';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    setState(() => _isLoading = true);
    try {
      final user = _service.currentUser;
      if (user != null) {
        final profile = await _service.getUserProfile(user.id);
        
        final info = await PackageInfo.fromPlatform();

        if (!mounted) return;
        setState(() {
          _adminPhone = profile?['phone_number']?.toString() ?? user.phone ?? '97000000';
          _appVersion = 'v${info.version}';
          _isLoading = false;
        });
      } else if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleLogout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Confirm Logout', style: TextStyle(fontWeight: FontWeight.w700)),
        content: const Text('Are you sure you want to log out of the admin panel?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.errorColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Logout', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _service.signOut();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surfaceColor,
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryColor))
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _AdminPageHeader(
                    title: 'Profile',
                    subtitle: 'Account settings and admin tools',
                    actions: [
                      _adminRefreshButton(
                        onPressed: _isLoading ? null : _loadProfile,
                      ),
                    ],
                  ),
                  Expanded(
                    child: Center(
                      child: SingleChildScrollView(
                        physics: _adminListPhysics,
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 560),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: AppTheme.dividerColor),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      height: 48,
                                      width: 48,
                                      decoration: BoxDecoration(
                                        color: AppTheme.primaryColor.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: const Icon(
                                        Icons.admin_panel_settings_rounded,
                                        size: 26,
                                        color: AppTheme.primaryColor,
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'System Administrator',
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w700,
                                              color: AppTheme.textPrimary,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'Phone: $_adminPhone',
                                            style: const TextStyle(
                                              fontSize: 13,
                                              color: AppTheme.textSecondary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 28),
                              const Text(
                                'ACCOUNT',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.textSecondary,
                                  letterSpacing: 0.8,
                                ),
                              ),
                              const SizedBox(height: 10),
                              _buildActionItem(
                                icon: Icons.password_rounded,
                                title: 'Change Password',
                                subtitle: 'Update your administrator password',
                                color: AppTheme.primaryColor,
                                onTap: _showChangePasswordDialog,
                              ),
                              const SizedBox(height: 24),
                              const Text(
                                'ADMINS',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.textSecondary,
                                  letterSpacing: 0.8,
                                ),
                              ),
                              const SizedBox(height: 10),
                              _buildActionItem(
                                icon: Icons.admin_panel_settings_rounded,
                                title: 'Create New Admin Account',
                                subtitle: 'Add a new super administrator',
                                color: AppTheme.primaryColor,
                                onTap: _showCreateAdminDialog,
                              ),
                              const SizedBox(height: 24),
                              const Text(
                                'APP',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.textSecondary,
                                  letterSpacing: 0.8,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 14,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: AppTheme.dividerColor),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.info_outline_rounded,
                                      color: AppTheme.textSecondary.withValues(alpha: 0.8),
                                      size: 22,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'App Version',
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                              color: AppTheme.textPrimary,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            '$_appVersion (Latest)',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: AppTheme.textSecondary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 24),
                              const Text(
                                'LOGOUT',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.textSecondary,
                                  letterSpacing: 0.8,
                                ),
                              ),
                              const SizedBox(height: 10),
                              _buildActionItem(
                                icon: Icons.logout_rounded,
                                title: 'Logout Account',
                                subtitle: null,
                                color: AppTheme.errorColor,
                                onTap: _handleLogout,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildActionItem({
    required IconData icon,
    required String title,
    String? subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.dividerColor),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: color == AppTheme.errorColor
                            ? color
                            : AppTheme.textPrimary,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: color == AppTheme.errorColor
                    ? color
                    : AppTheme.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showChangePasswordDialog() {
    final passwordCtrl = TextEditingController();
    final confirmPasswordCtrl = TextEditingController();

    final formKey = GlobalKey<FormState>();
    bool isUpdating = false;
    bool obscurePassword = true;
    bool obscureConfirm = true;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> submitPasswordChange() async {
              if (!formKey.currentState!.validate() || isUpdating) return;
              setDialogState(() => isUpdating = true);
              try {
                await _service.updatePassword(passwordCtrl.text.trim());
                if (!mounted) return;
                Navigator.of(ctx).pop();
                
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Password updated successfully!'),
                    backgroundColor: Colors.green,
                  ),
                );
              } catch (e) {
                setDialogState(() => isUpdating = false);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(e.toString().replaceAll('Exception:', '').trim()),
                    backgroundColor: AppTheme.errorColor,
                  ),
                );
              }
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.white,
              title: const Text('Change Password', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
              content: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: passwordCtrl,
                        obscureText: obscurePassword,
                        style: const TextStyle(fontSize: 14),
                        decoration: InputDecoration(
                          labelText: 'New Password',
                          prefixIcon: const Icon(Icons.lock_rounded, size: 20),
                          suffixIcon: IconButton(
                            icon: Icon(obscurePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded, size: 20),
                            onPressed: () => setDialogState(() => obscurePassword = !obscurePassword),
                          ),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        validator: (v) => v!.trim().length < 6 ? 'Minimum 6 characters' : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: confirmPasswordCtrl,
                        obscureText: obscureConfirm,
                        style: const TextStyle(fontSize: 14),
                        decoration: InputDecoration(
                          labelText: 'Confirm Password',
                          prefixIcon: const Icon(Icons.lock_rounded, size: 20),
                          suffixIcon: IconButton(
                            icon: Icon(obscureConfirm ? Icons.visibility_off_rounded : Icons.visibility_rounded, size: 20),
                            onPressed: () => setDialogState(() => obscureConfirm = !obscureConfirm),
                          ),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        validator: (v) {
                          if (v!.trim().length < 6) return 'Minimum 6 characters';
                          if (v!.trim() != passwordCtrl.text.trim()) return 'Passwords do not match';
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isUpdating ? null : () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel', style: TextStyle(color: AppTheme.textSecondary)),
                ),
                ElevatedButton(
                  onPressed: isUpdating ? null : submitPasswordChange,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    elevation: 0,
                  ),
                  child: isUpdating
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('Update Password', style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showCreateAdminDialog() {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();

    final nameFocus = FocusNode();
    final phoneFocus = FocusNode();
    final passwordFocus = FocusNode();

    final formKey = GlobalKey<FormState>();
    bool isRegistering = false;
    bool obscure = true;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> submitRegistration() async {
              if (!formKey.currentState!.validate() || isRegistering) return;
              setDialogState(() => isRegistering = true);
              try {
                await _service.adminRegisterAdminAccount(
                  fullName: nameCtrl.text.trim(),
                  phone: phoneCtrl.text.trim(),
                  password: passwordCtrl.text.trim(),
                );
                if (!mounted) return;
                Navigator.of(ctx).pop();
                
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Admin account created successfully!'),
                    backgroundColor: Colors.green,
                  ),
                );
              } catch (e) {
                setDialogState(() => isRegistering = false);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(e.toString().replaceAll('Exception:', '').trim()),
                    backgroundColor: AppTheme.errorColor,
                  ),
                );
              }
            }

            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.admin_panel_settings_rounded, color: AppTheme.primaryColor),
                          SizedBox(width: 8),
                          Text('Create New Admin', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Register a new Super Administrator with full system access.',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: nameCtrl,
                        focusNode: nameFocus,
                        textInputAction: TextInputAction.next,
                        onFieldSubmitted: (_) {
                          FocusScope.of(context).requestFocus(phoneFocus);
                        },
                        decoration: const InputDecoration(
                          labelText: 'Full Name *',
                          hintText: 'Admin Name',
                          prefixIcon: Icon(Icons.person_outline_rounded),
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return 'Please enter admin\'s full name';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: phoneCtrl,
                        focusNode: phoneFocus,
                        keyboardType: TextInputType.phone,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(10),
                        ],
                        textInputAction: TextInputAction.next,
                        onFieldSubmitted: (_) {
                          FocusScope.of(context).requestFocus(passwordFocus);
                        },
                        decoration: const InputDecoration(
                          labelText: '10-Digit Mobile Number *',
                          hintText: '9876543210',
                          prefixIcon: Icon(Icons.phone_rounded),
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return 'Please enter mobile number';
                          }
                          if (val.trim().length != 10) {
                            return 'Enter a valid 10-digit phone number';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: passwordCtrl,
                        focusNode: passwordFocus,
                        obscureText: obscure,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => submitRegistration(),
                        decoration: InputDecoration(
                          labelText: 'Temporary Password *',
                          hintText: '••••••••',
                          prefixIcon: const Icon(Icons.lock_outline_rounded),
                          suffixIcon: IconButton(
                            icon: Icon(obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                            onPressed: () => setDialogState(() => obscure = !obscure),
                          ),
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return 'Please create a temporary password';
                          }
                          if (val.length < 6) {
                            return 'Password must be at least 6 characters';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: isRegistering ? null : () => Navigator.of(ctx).pop(),
                            child: const Text('Cancel'),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: isRegistering ? null : submitRegistration,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primaryColor,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            child: isRegistering
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Text('Create Admin'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// ─── Feature Details Gating Page ──────────────────────────────
class CompanyFeaturesScreen extends StatefulWidget {
  final String companyName;
  final Map<String, bool> initialFeatures;

  const CompanyFeaturesScreen({
    super.key,
    required this.companyName,
    required this.initialFeatures,
  });

  @override
  State<CompanyFeaturesScreen> createState() => _CompanyFeaturesScreenState();
}

class _CompanyFeaturesScreenState extends State<CompanyFeaturesScreen> {
  final SupabaseService _service = SupabaseService();
  late Map<String, bool> _features;
  bool _savingFeature = false;

  @override
  void initState() {
    super.initState();
    _features = Map<String, bool>.from(widget.initialFeatures);
  }

  Future<void> _refreshFeatures() async {
    if (_savingFeature) return;
    try {
      final features = await _service.getCompanyFeatures(widget.companyName);
      if (!mounted) return;
      setState(() => _features = Map<String, bool>.from(features));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to refresh: $e')),
        );
      }
    }
  }

  Future<void> _toggleFeature(String featureKey, bool currentValue) async {
    if (_savingFeature) return;
    _savingFeature = true;
    final previousFeatures = Map<String, bool>.from(_features);
    final updatedValue = !currentValue;
    
    // 1. Optimistic Update - flip the switch instantly!
    setState(() {
      _features[featureKey] = updatedValue;
      if (!updatedValue) {
        if (featureKey == 'sales') {
          _features['db_card_today_sales'] = false;
          _features['db_qa_sales'] = false;
        } else if (featureKey == 'purchases') {
          _features['db_card_today_purchases'] = false;
        } else if (featureKey == 'ledgers') {
          _features['db_card_cash_bank'] = false;
          _features['db_np_cash'] = false;
          _features['db_np_bank'] = false;
          _features['db_qa_ledgers'] = false;
          _features['ls_transactions'] = false;
          _features['ls_performance'] = false;
          _features['ls_perf_speed'] = false;
          _features['ls_perf_delay'] = false;
          _features['ls_perf_trend'] = false;
          _features['ls_perf_history'] = false;
          _features['ls_perf_tally_formula'] = false;
        } else if (featureKey == 'stock') {
          _features['db_card_stock_value'] = false;
          _features['db_np_stock'] = false;
          _features['db_qa_stock'] = false;
        } else if (featureKey == 'outstanding') {
          _features['db_card_overdue_receivables'] = false;
          _features['db_card_overdue_payables'] = false;
          _features['db_np_receivables'] = false;
          _features['db_np_payables'] = false;
        } else if (featureKey == 'analytics') {
          _features['db_qa_reports'] = false;
        } else if (featureKey == 'balance_sheet') {
          _features['db_qa_balance_sheet'] = false;
        } else if (featureKey == 'profit_loss') {
          _features['db_qa_profit_loss'] = false;
        } else if (featureKey == 'dashboard') {
          _features['db_net_position'] = false;
          _features['db_summary_cards'] = false;
          _features['db_daybook'] = false;
          _features['db_quick_actions'] = false;
        }
      } else {
        if (featureKey == 'sales') {
          _features['db_card_today_sales'] = true;
          _features['db_qa_sales'] = true;
        } else if (featureKey == 'purchases') {
          _features['db_card_today_purchases'] = true;
        } else if (featureKey == 'ledgers') {
          _features['db_card_cash_bank'] = true;
          _features['db_np_cash'] = true;
          _features['db_np_bank'] = true;
          _features['db_qa_ledgers'] = true;
          _features['ls_transactions'] = true;
          _features['ls_performance'] = true;
          _features['ls_perf_speed'] = true;
          _features['ls_perf_delay'] = true;
          _features['ls_perf_trend'] = true;
          _features['ls_perf_history'] = true;
          _features['ls_perf_tally_formula'] = true;
        } else if (featureKey == 'stock') {
          _features['db_card_stock_value'] = true;
          _features['db_np_stock'] = true;
          _features['db_qa_stock'] = true;
        } else if (featureKey == 'outstanding') {
          _features['db_card_overdue_receivables'] = true;
          _features['db_card_overdue_payables'] = true;
          _features['db_np_receivables'] = true;
          _features['db_np_payables'] = true;
        } else if (featureKey == 'analytics') {
          _features['db_qa_reports'] = true;
        } else if (featureKey == 'balance_sheet') {
          _features['db_qa_balance_sheet'] = true;
        } else if (featureKey == 'profit_loss') {
          _features['db_qa_profit_loss'] = true;
        } else if (featureKey == 'dashboard') {
          _features['db_net_position'] = true;
          _features['db_summary_cards'] = true;
          _features['db_daybook'] = true;
          _features['db_quick_actions'] = true;
        }
      }
    });

    try {
      final updatedFeatures = Map<String, bool>.from(_features);
      // Update in Supabase in background
      await _service.updateCompanyFeatures(widget.companyName, updatedFeatures);
    } catch (e) {
      // 2. Revert the switch if database update fails
      if (mounted) {
        setState(() {
          _features = previousFeatures;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update setting: $e')),
        );
      }
    } finally {
      if (mounted) { setState(() => _savingFeature = false); } else { _savingFeature = false; }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (didPop || _savingFeature) return;
        Navigator.of(context).pop(_features);
      },
      child: Scaffold(
        backgroundColor: AppTheme.surfaceColor,
        appBar: AppBar(
          title: Text(
            widget.companyName,
            style: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.textPrimary, fontSize: 16),
          ),
          elevation: 0,
          backgroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: AppTheme.textPrimary),
            onPressed: _savingFeature ? null : () => Navigator.of(context).pop(_features),
          ),
          actions: [
            _adminRefreshButton(
              color: AppTheme.textPrimary,
              onPressed: _savingFeature ? null : _refreshFeatures,
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          children: [
            const Text(
              'Feature configurations',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.dividerColor),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Column(
                children: [
                  _buildNavCategoryItem(
                    'Dashboard Overview',
                    'dashboard',
                    '4 Sub-features',
                    Icons.dashboard_outlined,
                    DashboardFeaturesScreen(
                      companyName: widget.companyName,
                      initialFeatures: _features,
                    ),
                  ),
                  const Divider(color: AppTheme.dividerColor, height: 1, indent: 36),
                  _buildNavCategoryItem(
                    'Stock Inventory',
                    'stock',
                    'Cost Price Control',
                    Icons.inventory_2_outlined,
                    StockFeaturesScreen(
                      companyName: widget.companyName,
                      initialFeatures: _features,
                    ),
                  ),
                  const Divider(color: AppTheme.dividerColor, height: 1, indent: 36),
                  _buildNavCategoryItem(
                    'Outstanding Reports',
                    'outstanding',
                    'Recv/Pay Controls',
                    Icons.account_balance_wallet_outlined,
                    OutstandingFeaturesScreen(
                      companyName: widget.companyName,
                      initialFeatures: _features,
                    ),
                  ),
                  const Divider(color: AppTheme.dividerColor, height: 1, indent: 36),
                  _buildNavCategoryItem(
                    'Analytics & Reports',
                    'analytics',
                    '3 Report Types',
                    Icons.trending_up_outlined,
                    ReportsFeaturesScreen(
                      companyName: widget.companyName,
                      initialFeatures: _features,
                    ),
                  ),
                  const Divider(color: AppTheme.dividerColor, height: 1, indent: 36),
                  _buildNavCategoryItem(
                    'Cash Flow Insights',
                    'cash_flow',
                    'Overview & Charts',
                    Icons.waterfall_chart_outlined,
                    CashFlowFeaturesScreen(
                      companyName: widget.companyName,
                      initialFeatures: _features,
                    ),
                  ),
                  const Divider(color: AppTheme.dividerColor, height: 1, indent: 36),
                  _buildFinancialStatementsNavItem(),
                  const Divider(color: AppTheme.dividerColor, height: 1, indent: 36),
                  _buildNavCategoryItem(
                    'Ledgers & Transactions',
                    'ledgers',
                    'Tabs & Performance Sections',
                    Icons.receipt_long_outlined,
                    LedgerFeaturesScreen(
                      companyName: widget.companyName,
                      initialFeatures: _features,
                    ),
                  ),
                  const Divider(color: AppTheme.dividerColor, height: 1, indent: 36),
                  _buildToggleItem('Sales Invoices', 'sales', Icons.description_outlined),
                  const Divider(color: AppTheme.dividerColor, height: 1, indent: 36),
                  _buildToggleItem('Purchase Invoices', 'purchases', Icons.shopping_bag_outlined),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFinancialStatementsNavItem() {
    final bsOn = _features['balance_sheet'] ?? true;
    final plOn = _features['profit_loss'] ?? true;
    final isEnabled = bsOn || plOn;
    final detail = [
      if (bsOn) 'Balance Sheet',
      if (plOn) 'Profit & Loss',
    ].join(' • ');
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.account_balance_outlined, size: 20, color: AppTheme.textSecondary),
      title: const Text(
        'Financial Statements',
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppTheme.textPrimary,
        ),
      ),
      subtitle: Text(
        isEnabled ? 'Enabled • $detail' : 'Disabled',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: isEnabled ? AppTheme.primaryColor : AppTheme.textSecondary,
        ),
      ),
      trailing: const Icon(Icons.chevron_right_rounded, size: 20, color: AppTheme.textSecondary),
      onTap: () async {
        if (_savingFeature) return;
        final updatedFeatures = await Navigator.of(context).push<Map<String, bool>>(
          MaterialPageRoute(
            builder: (_) => FinancialReportsFeaturesScreen(
              companyName: widget.companyName,
              initialFeatures: _features,
            ),
          ),
        );
        if (updatedFeatures != null) {
          setState(() {
            _features = updatedFeatures;
          });
        }
      },
    );
  }

  Widget _buildNavCategoryItem(String title, String featureKey, String subtitleText, IconData icon, Widget targetScreen) {
    final isEnabled = _features[featureKey] ?? true;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, size: 20, color: AppTheme.textSecondary),
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppTheme.textPrimary,
        ),
      ),
      subtitle: Text(
        isEnabled ? 'Enabled • $subtitleText' : 'Disabled',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: isEnabled ? AppTheme.primaryColor : AppTheme.textSecondary,
        ),
      ),
      trailing: const Icon(Icons.chevron_right_rounded, size: 20, color: AppTheme.textSecondary),
      onTap: () async {
        if (_savingFeature) return;
        final updatedFeatures = await Navigator.of(context).push<Map<String, bool>>(
          MaterialPageRoute(builder: (_) => targetScreen),
        );
        if (updatedFeatures != null) {
          setState(() {
            _features = updatedFeatures;
          });
        }
      },
    );
  }

  Widget _buildToggleItem(String label, String featureKey, IconData icon) {
    final isEnabled = _features[featureKey] ?? true;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppTheme.textSecondary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
          Switch.adaptive(
            value: isEnabled,
            activeColor: AppTheme.primaryColor,
            onChanged: (_) => _toggleFeature(featureKey, isEnabled),
          ),
        ],
      ),
    );
  }
}

// ─── Sub-features: Dashboard Overview ─────────────────────────
class DashboardFeaturesScreen extends StatefulWidget {
  final String companyName;
  final Map<String, bool> initialFeatures;

  const DashboardFeaturesScreen({
    super.key,
    required this.companyName,
    required this.initialFeatures,
  });

  @override
  State<DashboardFeaturesScreen> createState() => _DashboardFeaturesScreenState();
}

class _DashboardFeaturesScreenState extends State<DashboardFeaturesScreen> {
  final SupabaseService _service = SupabaseService();
  late Map<String, bool> _features;
  bool _savingFeature = false;
  bool _isNetPositionConfigExpanded = true;

  @override
  void initState() {
    super.initState();
    _features = Map<String, bool>.from(widget.initialFeatures);
  }

  Future<void> _refreshFeatures() async {
    if (_savingFeature) return;
    try {
      final features = await _service.getCompanyFeatures(widget.companyName);
      if (!mounted) return;
      setState(() => _features = Map<String, bool>.from(features));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to refresh: $e')),
        );
      }
    }
  }

  Future<void> _toggleFeature(String featureKey, bool currentValue) async {
    if (_savingFeature) return;
    _savingFeature = true;
    final previousFeatures = Map<String, bool>.from(_features);
    final updatedValue = !currentValue;
    setState(() {
      _features[featureKey] = updatedValue;
      if (featureKey == 'dashboard') {
        if (!updatedValue) {
          _features['db_net_position'] = false;
          _features['db_summary_cards'] = false;
          _features['db_daybook'] = false;
          _features['db_quick_actions'] = false;
        } else {
          _features['db_net_position'] = true;
          _features['db_summary_cards'] = true;
          _features['db_daybook'] = true;
          _features['db_quick_actions'] = true;
        }
      }
    });

    try {
      final updatedFeatures = Map<String, bool>.from(_features);
      await _service.updateCompanyFeatures(widget.companyName, updatedFeatures);
    } catch (e) {
      if (mounted) {
        setState(() {
          _features = previousFeatures;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update setting: $e')),
        );
      }
    } finally {
      if (mounted) { setState(() => _savingFeature = false); } else { _savingFeature = false; }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDashboardEnabled = _features['dashboard'] ?? true;

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (didPop || _savingFeature) return;
        Navigator.of(context).pop(_features);
      },
      child: Scaffold(
        backgroundColor: AppTheme.surfaceColor,
        appBar: AppBar(
          title: const Text(
            'Dashboard Settings',
            style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.textPrimary, fontSize: 16),
          ),
          elevation: 0,
          backgroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: AppTheme.textPrimary),
            onPressed: _savingFeature ? null : () => Navigator.of(context).pop(_features),
          ),
          actions: [
            _adminRefreshButton(
              color: AppTheme.textPrimary,
              onPressed: _savingFeature ? null : _refreshFeatures,
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 16),
          children: [
            // Main Dashboard Toggle
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: AppTheme.dividerColor),
              ),
              elevation: 0,
              color: Colors.white,
              child: ListTile(
                title: const Text('Dashboard Screen', style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
                subtitle: const Text('Enable or disable the entire dashboard tab'),
                trailing: Switch.adaptive(
                  value: isDashboardEnabled,
                  activeColor: AppTheme.primaryColor,
                  onChanged: (_) => _toggleFeature('dashboard', isDashboardEnabled),
                ),
              ),
            ),
            const SizedBox(height: 24),
            
            const Text(
              'DASHBOARD COMPONENTS',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            
            IgnorePointer(
              ignoring: !isDashboardEnabled,
              child: Opacity(
                opacity: isDashboardEnabled ? 1.0 : 0.5,
                child: Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: AppTheme.dividerColor),
                  ),
                  elevation: 0,
                  color: Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 8),
                    child: Column(
                      children: [
                        _buildSubToggleItem(
                          'Net Position Header Card',
                          'db_net_position',
                          Icons.bar_chart_rounded,
                          isExpanded: _isNetPositionConfigExpanded,
                          onExpandToggle: () {
                            setState(() {
                              _isNetPositionConfigExpanded = !_isNetPositionConfigExpanded;
                            });
                          },
                        ),
                        if ((_features['db_net_position'] ?? true) && _isNetPositionConfigExpanded) ...[
                          const SizedBox(height: 8),
                          _buildNetPositionDetailsConfig(),
                          const SizedBox(height: 8),
                        ],
                        const Divider(color: AppTheme.dividerColor, height: 1, indent: 36),
                        _buildSubToggleItem('6 Grid Summary Cards', 'db_summary_cards', Icons.grid_view_rounded),
                        if (_features['db_summary_cards'] ?? true) ...[
                          const SizedBox(height: 8),
                          _buildVisualCardGrid(),
                          const SizedBox(height: 8),
                        ],
                        const Divider(color: AppTheme.dividerColor, height: 1, indent: 36),
                        _buildSubToggleItem('Daybook Section', 'db_daybook', Icons.today_rounded),
                        const Divider(color: AppTheme.dividerColor, height: 1, indent: 36),
                        _buildSubToggleItem('Quick Actions Grid', 'db_quick_actions', Icons.bolt_rounded),
                        if (_features['db_quick_actions'] ?? true) ...[
                          const SizedBox(height: 8),
                          _buildVisualQuickActionsRow(),
                          const SizedBox(height: 8),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVisualCardGrid() {
    final width = MediaQuery.of(context).size.width;

    final cardItems = [
      {
        'key': 'db_card_cash_bank',
        'title': 'Cash & Bank',
        'icon': Icons.account_balance_wallet_rounded,
        'color': Colors.teal,
      },
      {
        'key': 'db_card_stock_value',
        'title': 'Stock Value',
        'icon': Icons.inventory_2_rounded,
        'color': const Color(0xFF9C27B0),
      },
      {
        'key': 'db_card_today_sales',
        'title': "Today's Sales",
        'icon': Icons.point_of_sale_rounded,
        'color': AppTheme.primaryColor,
      },
      {
        'key': 'db_card_today_purchases',
        'title': "Today's Purchases",
        'icon': Icons.shopping_cart_rounded,
        'color': const Color(0xFFB96A00),
      },
      {
        'key': 'db_card_overdue_receivables',
        'title': 'Receivables',
        'icon': Icons.warning_amber_rounded,
        'color': AppTheme.errorColor,
      },
      {
        'key': 'db_card_overdue_payables',
        'title': 'Payables',
        'icon': Icons.warning_amber_rounded,
        'color': const Color(0xFF880E4F),
      },
      {
        'key': 'db_card_total_receivables',
        'title': 'Total Receivables',
        'icon': Icons.trending_up_rounded,
        'color': const Color(0xFF0DA6A0),
      },
      {
        'key': 'db_card_total_payables',
        'title': 'Total Payables',
        'icon': Icons.trending_down_rounded,
        'color': const Color(0xFF7C3AED),
      },
    ];

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'ACTIVE SUMMARY CARDS (TAP TO TOGGLE)',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: AppTheme.textSecondary,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              const crossAxisCount = 2;
              const spacing = 10.0;
              final cardWidth = (constraints.maxWidth - spacing * (crossAxisCount - 1)) / crossAxisCount;
              final rows = <Widget>[];
              for (int i = 0; i < cardItems.length; i += crossAxisCount) {
                final rowItems = cardItems.sublist(i, (i + crossAxisCount).clamp(0, cardItems.length));
                rows.add(
                  Row(
                    children: [
                      for (int j = 0; j < rowItems.length; j++) ...[
                        if (j > 0) const SizedBox(width: spacing),
                        Builder(builder: (_) {
                          final item = rowItems[j];
                          final key = item['key'] as String;
                          final isItemEnabled = _features[key] ?? true;
                          final color = item['color'] as Color;
                          return GestureDetector(
                            onTap: () => _toggleFeature(key, isItemEnabled),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              width: cardWidth,
                              height: 88,
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: isItemEnabled ? color.withOpacity(0.08) : Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isItemEnabled ? color : AppTheme.dividerColor,
                                  width: isItemEnabled ? 2.0 : 1.0,
                                ),
                              ),
                              child: Stack(
                                children: [
                                  Align(
                                    alignment: Alignment.topRight,
                                    child: Icon(
                                      isItemEnabled ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                                      size: 14,
                                      color: isItemEnabled ? color : Colors.grey.shade300,
                                    ),
                                  ),
                                  Center(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          item['icon'] as IconData,
                                          size: 20,
                                          color: isItemEnabled ? color : Colors.grey.shade400,
                                        ),
                                        const SizedBox(height: 5),
                                        Text(
                                          item['title'] as String,
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: isItemEnabled ? AppTheme.textPrimary : Colors.grey.shade500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                      ],
                      // fill remaining space if last row has fewer items
                      if (rowItems.length < crossAxisCount)
                        SizedBox(width: cardWidth + spacing),
                    ],
                  ),
                );
                if (i + crossAxisCount < cardItems.length) {
                  rows.add(const SizedBox(height: spacing));
                }
              }
              return Column(children: rows);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildVisualQuickActionsRow() {
    final quickActionItems = [
      {
        'key': 'db_qa_stock',
        'label': 'Stock',
        'icon': Icons.inventory_2_rounded,
        'color': const Color(0xFF9C27B0),
      },
      {
        'key': 'db_qa_ledgers',
        'label': 'Ledgers',
        'icon': Icons.people_alt_rounded,
        'color': AppTheme.primaryColor,
      },
      {
        'key': 'db_qa_sales',
        'label': 'Sales',
        'icon': Icons.receipt_long_rounded,
        'color': const Color(0xFF0DA6A0),
      },
      {
        'key': 'db_qa_reports',
        'label': 'Reports',
        'icon': Icons.analytics_rounded,
        'color': Colors.purple.shade500,
      },
      {
        'key': 'db_qa_balance_sheet',
        'label': 'Balance Sheet',
        'icon': Icons.account_balance_outlined,
        'color': const Color(0xFF0F766E),
      },
      {
        'key': 'db_qa_profit_loss',
        'label': 'P&L',
        'icon': Icons.trending_up_rounded,
        'color': const Color(0xFFB45309),
      },
    ];

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'ACTIVE QUICK ACTIONS (TAP TO TOGGLE)',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: AppTheme.textSecondary,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 12),
          ...List.generate((quickActionItems.length / 3).ceil(), (rowIndex) {
            final start = rowIndex * 3;
            final rowItems = quickActionItems.sublist(
              start,
              (start + 3).clamp(0, quickActionItems.length),
            );
            return Padding(
              padding: EdgeInsets.only(bottom: rowIndex == 0 ? 8 : 0),
              child: Row(
                children: [
                  for (final item in rowItems)
                    Expanded(
                      child: Builder(
                        builder: (context) {
                          final key = item['key'] as String;
                          final isItemEnabled = _features[key] ?? true;
                          final color = item['color'] as Color;
                          return GestureDetector(
                            onTap: () => _toggleFeature(key, isItemEnabled),
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                color: isItemEnabled ? color.withOpacity(0.06) : Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isItemEnabled ? color : AppTheme.dividerColor,
                                  width: isItemEnabled ? 1.5 : 1.0,
                                ),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    item['icon'] as IconData,
                                    size: 18,
                                    color: isItemEnabled ? color : Colors.grey.shade400,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    item['label'] as String,
                                    textAlign: TextAlign.center,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: isItemEnabled
                                          ? AppTheme.textPrimary
                                          : Colors.grey.shade500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  if (rowItems.length < 3)
                    for (var i = rowItems.length; i < 3; i++)
                      const Expanded(child: SizedBox()),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildNetPositionDetailsConfig() {
    final width = MediaQuery.of(context).size.width;

    final netPositionItems = [
      {
        'key': 'db_np_cash',
        'title': 'Cash in Hand',
        'icon': Icons.money_rounded,
        'color': Colors.teal,
      },
      {
        'key': 'db_np_bank',
        'title': 'Bank Accounts',
        'icon': Icons.account_balance_rounded,
        'color': Colors.blue,
      },
      {
        'key': 'db_np_stock',
        'title': 'Stock in Hand',
        'icon': Icons.inventory_2_rounded,
        'color': const Color(0xFF9C27B0),
      },
      {
        'key': 'db_np_receivables',
        'title': 'Receivables',
        'icon': Icons.trending_up_rounded,
        'color': AppTheme.errorColor,
      },
      {
        'key': 'db_np_payables',
        'title': 'Payables',
        'icon': Icons.trending_down_rounded,
        'color': const Color(0xFF880E4F),
      },
    ];

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'NET POSITION DETAILS (TAP TO TOGGLE ROWS)',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: AppTheme.textSecondary,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              const crossAxisCount = 2;
              const spacing = 10.0;
              final cardWidth = (constraints.maxWidth - spacing * (crossAxisCount - 1)) / crossAxisCount;
              final rows = <Widget>[];
              for (int i = 0; i < netPositionItems.length; i += crossAxisCount) {
                final rowItems = netPositionItems.sublist(i, (i + crossAxisCount).clamp(0, netPositionItems.length));
                rows.add(
                  Row(
                    children: [
                      for (int j = 0; j < rowItems.length; j++) ...[
                        if (j > 0) const SizedBox(width: spacing),
                        Builder(builder: (_) {
                          final item = rowItems[j];
                          final key = item['key'] as String;
                          final isItemEnabled = _features[key] ?? true;
                          final color = item['color'] as Color;
                          return GestureDetector(
                            onTap: () => _toggleFeature(key, isItemEnabled),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              width: cardWidth,
                              height: 88,
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: isItemEnabled ? color.withOpacity(0.08) : Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isItemEnabled ? color : AppTheme.dividerColor,
                                  width: isItemEnabled ? 2.0 : 1.0,
                                ),
                              ),
                              child: Stack(
                                children: [
                                  Align(
                                    alignment: Alignment.topRight,
                                    child: Icon(
                                      isItemEnabled ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                                      size: 14,
                                      color: isItemEnabled ? color : Colors.grey.shade300,
                                    ),
                                  ),
                                  Center(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          item['icon'] as IconData,
                                          size: 20,
                                          color: isItemEnabled ? color : Colors.grey.shade400,
                                        ),
                                        const SizedBox(height: 5),
                                        Text(
                                          item['title'] as String,
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: isItemEnabled ? AppTheme.textPrimary : Colors.grey.shade500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                      ],
                      if (rowItems.length < crossAxisCount)
                        SizedBox(width: cardWidth + spacing),
                    ],
                  ),
                );
                if (i + crossAxisCount < netPositionItems.length) {
                  rows.add(const SizedBox(height: spacing));
                }
              }
              return Column(children: rows);
            },
          ),
        ],
      ),
    );
  }



  Widget _buildSubToggleItem(
    String label, 
    String featureKey, 
    IconData icon, {
    bool? isExpanded, 
    VoidCallback? onExpandToggle,
  }) {
    final isEnabled = _features[featureKey] ?? true;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppTheme.textSecondary),
          const SizedBox(width: 12),
          Expanded(
            child: InkWell(
              onTap: isEnabled ? onExpandToggle : null,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ),
                  if (isEnabled && isExpanded != null) ...[
                    const SizedBox(width: 6),
                    Icon(
                      isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                      size: 18,
                      color: AppTheme.primaryColor,
                    ),
                  ],
                ],
              ),
            ),
          ),
          Switch.adaptive(
            value: isEnabled,
            activeColor: AppTheme.primaryColor,
            onChanged: (_) => _toggleFeature(featureKey, isEnabled),
          ),
        ],
      ),
    );
  }
}

// ─── Sub-features: Stock Inventory ────────────────────────────
class StockFeaturesScreen extends StatefulWidget {
  final String companyName;
  final Map<String, bool> initialFeatures;

  const StockFeaturesScreen({
    super.key,
    required this.companyName,
    required this.initialFeatures,
  });

  @override
  State<StockFeaturesScreen> createState() => _StockFeaturesScreenState();
}

class _StockFeaturesScreenState extends State<StockFeaturesScreen> {
  final SupabaseService _service = SupabaseService();
  late Map<String, bool> _features;
  bool _savingFeature = false;

  @override
  void initState() {
    super.initState();
    _features = Map<String, bool>.from(widget.initialFeatures);
  }

  Future<void> _refreshFeatures() async {
    if (_savingFeature) return;
    try {
      final features = await _service.getCompanyFeatures(widget.companyName);
      if (!mounted) return;
      setState(() => _features = Map<String, bool>.from(features));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to refresh: $e')),
        );
      }
    }
  }

  Future<void> _toggleFeature(String featureKey, bool currentValue) async {
    if (_savingFeature) return;
    _savingFeature = true;
    final previousFeatures = Map<String, bool>.from(_features);
    final updatedValue = !currentValue;
    setState(() {
      _features[featureKey] = updatedValue;
      if (featureKey == 'stock') {
        if (!updatedValue) {
          _features['db_card_stock_value'] = false;
          _features['db_np_stock'] = false;
          _features['db_qa_stock'] = false;
        } else {
          _features['db_card_stock_value'] = true;
          _features['db_np_stock'] = true;
          _features['db_qa_stock'] = true;
        }
      }
    });

    try {
      final updatedFeatures = Map<String, bool>.from(_features);
      await _service.updateCompanyFeatures(widget.companyName, updatedFeatures);
    } catch (e) {
      if (mounted) {
        setState(() {
          _features = previousFeatures;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update setting: $e')),
        );
      }
    } finally {
      if (mounted) { setState(() => _savingFeature = false); } else { _savingFeature = false; }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isStockEnabled = _features['stock'] ?? true;

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (didPop || _savingFeature) return;
        Navigator.of(context).pop(_features);
      },
      child: Scaffold(
        backgroundColor: AppTheme.surfaceColor,
        appBar: AppBar(
          title: const Text(
            'Stock Settings',
            style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.textPrimary, fontSize: 16),
          ),
          elevation: 0,
          backgroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: AppTheme.textPrimary),
            onPressed: _savingFeature ? null : () => Navigator.of(context).pop(_features),
          ),
          actions: [
            _adminRefreshButton(
              color: AppTheme.textPrimary,
              onPressed: _savingFeature ? null : _refreshFeatures,
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
          children: [
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: AppTheme.dividerColor),
              ),
              elevation: 0,
              color: Colors.white,
              child: ListTile(
                title: const Text('Stock Screen', style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
                subtitle: const Text('Enable or disable the entire stock tab'),
                trailing: Switch.adaptive(
                  value: isStockEnabled,
                  activeColor: AppTheme.primaryColor,
                  onChanged: (_) => _toggleFeature('stock', isStockEnabled),
                ),
              ),
            ),
            const SizedBox(height: 24),
            
            const Text(
              'STOCK PRIVACY & CONTROLS',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            
            IgnorePointer(
              ignoring: !isStockEnabled,
              child: Opacity(
                opacity: isStockEnabled ? 1.0 : 0.5,
                child: Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: AppTheme.dividerColor),
                  ),
                  elevation: 0,
                  color: Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8),
                    child: Column(
                      children: [
                        _buildSubToggleItem(
                          'Show Cost / Purchase Price',
                          'stock_cost',
                          'Allows users to see product purchase rates and margins',
                          Icons.attach_money_rounded,
                        ),
                        const Divider(color: AppTheme.dividerColor, height: 1, indent: 36),
                        _buildSubToggleItem(
                          'Item Parents & New Categories',
                          'stock_item_parents',
                          'Shows the Item Parents menu with new product alerts',
                          Icons.category_rounded,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubToggleItem(String label, String featureKey, String description, IconData icon) {
    final isEnabled = _features[featureKey] ?? true;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppTheme.textSecondary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: isEnabled,
            activeColor: AppTheme.primaryColor,
            onChanged: (_) => _toggleFeature(featureKey, isEnabled),
          ),
        ],
      ),
    );
  }
}

// ─── Sub-features: Outstanding Reports ────────────────────────
class OutstandingFeaturesScreen extends StatefulWidget {
  final String companyName;
  final Map<String, bool> initialFeatures;

  const OutstandingFeaturesScreen({
    super.key,
    required this.companyName,
    required this.initialFeatures,
  });

  @override
  State<OutstandingFeaturesScreen> createState() => _OutstandingFeaturesScreenState();
}

class _OutstandingFeaturesScreenState extends State<OutstandingFeaturesScreen> {
  final SupabaseService _service = SupabaseService();
  late Map<String, bool> _features;
  bool _savingFeature = false;

  @override
  void initState() {
    super.initState();
    _features = Map<String, bool>.from(widget.initialFeatures);
  }

  Future<void> _refreshFeatures() async {
    if (_savingFeature) return;
    try {
      final features = await _service.getCompanyFeatures(widget.companyName);
      if (!mounted) return;
      setState(() => _features = Map<String, bool>.from(features));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to refresh: $e')),
        );
      }
    }
  }

  Future<void> _toggleFeature(String featureKey, bool currentValue) async {
    if (_savingFeature) return;
    _savingFeature = true;
    final previousFeatures = Map<String, bool>.from(_features);
    final updatedValue = !currentValue;
    setState(() {
      _features[featureKey] = updatedValue;
      if (featureKey == 'outstanding') {
        if (!updatedValue) {
          _features['db_card_overdue_receivables'] = false;
          _features['db_card_overdue_payables'] = false;
          _features['db_np_receivables'] = false;
          _features['db_np_payables'] = false;
          _features['out_receivables'] = false;
          _features['out_payables'] = false;
        } else {
          _features['db_card_overdue_receivables'] = true;
          _features['db_card_overdue_payables'] = true;
          _features['db_np_receivables'] = true;
          _features['db_np_payables'] = true;
          _features['out_receivables'] = true;
          _features['out_payables'] = true;
        }
      }
    });

    try {
      final updatedFeatures = Map<String, bool>.from(_features);
      await _service.updateCompanyFeatures(widget.companyName, updatedFeatures);
    } catch (e) {
      if (mounted) {
        setState(() {
          _features = previousFeatures;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update setting: $e')),
        );
      }
    } finally {
      if (mounted) { setState(() => _savingFeature = false); } else { _savingFeature = false; }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isOutstandingEnabled = _features['outstanding'] ?? true;

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (didPop || _savingFeature) return;
        Navigator.of(context).pop(_features);
      },
      child: Scaffold(
        backgroundColor: AppTheme.surfaceColor,
        appBar: AppBar(
          title: const Text(
            'Outstanding Settings',
            style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.textPrimary, fontSize: 16),
          ),
          elevation: 0,
          backgroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: AppTheme.textPrimary),
            onPressed: _savingFeature ? null : () => Navigator.of(context).pop(_features),
          ),
          actions: [
            _adminRefreshButton(
              color: AppTheme.textPrimary,
              onPressed: _savingFeature ? null : _refreshFeatures,
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
          children: [
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: AppTheme.dividerColor),
              ),
              elevation: 0,
              color: Colors.white,
              child: ListTile(
                title: const Text('Outstanding Screen', style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
                subtitle: const Text('Enable or disable the entire Recv/Pay tab'),
                trailing: Switch.adaptive(
                  value: isOutstandingEnabled,
                  activeColor: AppTheme.primaryColor,
                  onChanged: (_) => _toggleFeature('outstanding', isOutstandingEnabled),
                ),
              ),
            ),
            const SizedBox(height: 24),
            
            const Text(
              'OUTSTANDING TAB VISIBILITY',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            
            IgnorePointer(
              ignoring: !isOutstandingEnabled,
              child: Opacity(
                opacity: isOutstandingEnabled ? 1.0 : 0.5,
                child: Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: AppTheme.dividerColor),
                  ),
                  elevation: 0,
                  color: Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8),
                    child: Column(
                      children: [
                        _buildSubToggleItem('Receivables Tab', 'out_receivables', Icons.call_received_rounded),
                        const Divider(color: AppTheme.dividerColor, height: 1, indent: 36),
                        _buildSubToggleItem('Payables Tab', 'out_payables', Icons.call_made_rounded),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubToggleItem(String label, String featureKey, IconData icon) {
    final isEnabled = _features[featureKey] ?? true;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppTheme.textSecondary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
          Switch.adaptive(
            value: isEnabled,
            activeColor: AppTheme.primaryColor,
            onChanged: (_) => _toggleFeature(featureKey, isEnabled),
          ),
        ],
      ),
    );
  }
}

// ─── Sub-features: Analytics & Reports ────────────────────────
class ReportsFeaturesScreen extends StatefulWidget {
  final String companyName;
  final Map<String, bool> initialFeatures;

  const ReportsFeaturesScreen({
    super.key,
    required this.companyName,
    required this.initialFeatures,
  });

  @override
  State<ReportsFeaturesScreen> createState() => _ReportsFeaturesScreenState();
}

class _ReportsFeaturesScreenState extends State<ReportsFeaturesScreen> {
  final SupabaseService _service = SupabaseService();
  late Map<String, bool> _features;
  bool _savingFeature = false;

  @override
  void initState() {
    super.initState();
    _features = Map<String, bool>.from(widget.initialFeatures);
  }

  Future<void> _refreshFeatures() async {
    if (_savingFeature) return;
    try {
      final features = await _service.getCompanyFeatures(widget.companyName);
      if (!mounted) return;
      setState(() => _features = Map<String, bool>.from(features));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to refresh: $e')),
        );
      }
    }
  }

  Future<void> _toggleFeature(String featureKey, bool currentValue) async {
    if (_savingFeature) return;
    _savingFeature = true;
    final previousFeatures = Map<String, bool>.from(_features);
    final updatedValue = !currentValue;
    setState(() {
      _features[featureKey] = updatedValue;
      if (featureKey == 'analytics') {
        if (!updatedValue) {
          _features['db_qa_reports'] = false;
          _features['rep_sales'] = false;
          _features['rep_purchases'] = false;
          _features['rep_ledgers'] = false;
        } else {
          _features['db_qa_reports'] = true;
          _features['rep_sales'] = true;
          _features['rep_purchases'] = true;
          _features['rep_ledgers'] = true;
        }
      }
      
      if (featureKey != 'analytics') {
        final anySubEnabled = (_features['rep_sales'] ?? false) ||
            (_features['rep_purchases'] ?? false) ||
            (_features['rep_ledgers'] ?? false);
        _features['analytics'] = anySubEnabled;
      }
    });

    try {
      final updatedFeatures = Map<String, bool>.from(_features);
      await _service.updateCompanyFeatures(widget.companyName, updatedFeatures);
    } catch (e) {
      if (mounted) {
        setState(() {
          _features = previousFeatures;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update setting: $e')),
        );
      }
    } finally {
      if (mounted) { setState(() => _savingFeature = false); } else { _savingFeature = false; }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isReportsEnabled = _features['analytics'] ?? true;

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (didPop || _savingFeature) return;
        Navigator.of(context).pop(_features);
      },
      child: Scaffold(
        backgroundColor: AppTheme.surfaceColor,
        appBar: AppBar(
          title: const Text(
            'Reports Settings',
            style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.textPrimary, fontSize: 16),
          ),
          elevation: 0,
          backgroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: AppTheme.textPrimary),
            onPressed: _savingFeature ? null : () => Navigator.of(context).pop(_features),
          ),
          actions: [
            _adminRefreshButton(
              color: AppTheme.textPrimary,
              onPressed: _savingFeature ? null : _refreshFeatures,
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
          children: [
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: AppTheme.dividerColor),
              ),
              elevation: 0,
              color: Colors.white,
              child: ListTile(
                title: const Text('Analytics & Reports Screen', style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
                subtitle: const Text('Enable or disable the entire reports screen'),
                trailing: Switch.adaptive(
                  value: isReportsEnabled,
                  activeColor: AppTheme.primaryColor,
                  onChanged: (_) => _toggleFeature('analytics', isReportsEnabled),
                ),
              ),
            ),
            const SizedBox(height: 24),
            
            const Text(
              'REPORT TYPE VISIBILITY',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            
            IgnorePointer(
              ignoring: !isReportsEnabled,
              child: Opacity(
                opacity: isReportsEnabled ? 1.0 : 0.5,
                child: Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: AppTheme.dividerColor),
                  ),
                  elevation: 0,
                  color: Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8),
                    child: Column(
                      children: [
                        _buildSubToggleItem('Sales Reports', 'rep_sales', Icons.trending_up_rounded),
                        const Divider(color: AppTheme.dividerColor, height: 1, indent: 36),
                        _buildSubToggleItem('Purchase Reports', 'rep_purchases', Icons.trending_down_rounded),
                        const Divider(color: AppTheme.dividerColor, height: 1, indent: 36),
                        _buildSubToggleItem('Ledger Reports & Analysis', 'rep_ledgers', Icons.people_alt_rounded),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubToggleItem(String label, String featureKey, IconData icon) {
    final isEnabled = _features[featureKey] ?? true;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppTheme.textSecondary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
          Switch.adaptive(
            value: isEnabled,
            activeColor: AppTheme.primaryColor,
            onChanged: (_) => _toggleFeature(featureKey, isEnabled),
          ),
        ],
      ),
    );
  }

  Widget _buildNavSubItem(String title, String featureKey, String subtitleText, IconData icon, Widget targetScreen) {
    final isEnabled = _features[featureKey] ?? true;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, size: 20, color: AppTheme.textSecondary),
      title: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
      subtitle: Text(
        isEnabled ? 'Enabled • $subtitleText' : 'Disabled',
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: isEnabled ? AppTheme.primaryColor : AppTheme.textSecondary),
      ),
      trailing: const Icon(Icons.chevron_right_rounded, size: 20, color: AppTheme.textSecondary),
      onTap: () async {
        if (_savingFeature) return;
        final updatedFeatures = await Navigator.of(context).push<Map<String, bool>>(
          MaterialPageRoute(builder: (_) => targetScreen),
        );
        if (updatedFeatures != null) {
          setState(() { _features = updatedFeatures; });
        }
      },
    );
  }
}

// ─── Sub-features: Cash Flow Insights ─────────────────────────
class CashFlowFeaturesScreen extends StatefulWidget {
  final String companyName;
  final Map<String, bool> initialFeatures;

  const CashFlowFeaturesScreen({
    super.key,
    required this.companyName,
    required this.initialFeatures,
  });

  @override
  State<CashFlowFeaturesScreen> createState() => _CashFlowFeaturesScreenState();
}

class _CashFlowFeaturesScreenState extends State<CashFlowFeaturesScreen> {
  final SupabaseService _service = SupabaseService();
  late Map<String, bool> _features;
  bool _savingFeature = false;

  @override
  void initState() {
    super.initState();
    _features = Map<String, bool>.from(widget.initialFeatures);
  }

  Future<void> _refreshFeatures() async {
    if (_savingFeature) return;
    try {
      final features = await _service.getCompanyFeatures(widget.companyName);
      if (!mounted) return;
      setState(() => _features = Map<String, bool>.from(features));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to refresh: $e')),
        );
      }
    }
  }

  Future<void> _toggleFeature(String featureKey, bool currentValue) async {
    if (_savingFeature) return;
    _savingFeature = true;
    final previousFeatures = Map<String, bool>.from(_features);
    final updatedValue = !currentValue;
    setState(() {
      _features[featureKey] = updatedValue;
      // If main cash_flow is toggled off, disable all sub-features
      if (featureKey == 'cash_flow' && !updatedValue) {
        _features['cf_summary'] = false;
        _features['cf_overview'] = false;
        _features['cf_pie_chart'] = false;
        _features['cf_trend'] = false;
        _features['cf_fastest'] = false;
        _features['cf_slowest'] = false;
      }
      // If main cash_flow is toggled on, enable all sub-features
      if (featureKey == 'cash_flow' && updatedValue) {
        _features['cf_summary'] = true;
        _features['cf_overview'] = true;
        _features['cf_pie_chart'] = true;
        _features['cf_trend'] = true;
        _features['cf_fastest'] = true;
        _features['cf_slowest'] = true;
      }
      
      // Auto-toggle main feature based on sub-features
      if (featureKey != 'cash_flow') {
        final anySubEnabled = (_features['cf_summary'] ?? false) ||
            (_features['cf_overview'] ?? false) ||
            (_features['cf_pie_chart'] ?? false) ||
            (_features['cf_trend'] ?? false) ||
            (_features['cf_fastest'] ?? false) ||
            (_features['cf_slowest'] ?? false);
        _features['cash_flow'] = anySubEnabled;
      }
    });

    try {
      await _service.updateCompanyFeatures(widget.companyName, Map<String, bool>.from(_features));
    } catch (e) {
      if (mounted) {
        setState(() { _features = previousFeatures; });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update setting: $e')),
        );
      }
    } finally {
      if (mounted) { setState(() => _savingFeature = false); } else { _savingFeature = false; }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isCashFlowEnabled = _features['cash_flow'] ?? true;

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (didPop || _savingFeature) return;
        Navigator.of(context).pop(_features);
      },
      child: Scaffold(
        backgroundColor: AppTheme.surfaceColor,
        appBar: AppBar(
          title: const Text('Cash Flow Settings',
              style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.textPrimary, fontSize: 16)),
          elevation: 0,
          backgroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: AppTheme.textPrimary),
            onPressed: _savingFeature ? null : () => Navigator.of(context).pop(_features),
          ),
          actions: [
            _adminRefreshButton(
              color: AppTheme.textPrimary,
              onPressed: _savingFeature ? null : _refreshFeatures,
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
          children: [
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: AppTheme.dividerColor),
              ),
              elevation: 0,
              color: Colors.white,
              child: ListTile(
                title: const Text('Cash Flow Insights Screen',
                    style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
                subtitle: const Text('Enable or disable the entire Cash Flow screen'),
                trailing: Switch.adaptive(
                  value: isCashFlowEnabled,
                  activeColor: AppTheme.primaryColor,
                  onChanged: (_) => _toggleFeature('cash_flow', isCashFlowEnabled),
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'SECTION VISIBILITY',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppTheme.textSecondary, letterSpacing: 1.0),
            ),
            const SizedBox(height: 12),
            IgnorePointer(
              ignoring: !isCashFlowEnabled,
              child: Opacity(
                opacity: isCashFlowEnabled ? 1.0 : 0.5,
                child: Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: AppTheme.dividerColor),
                  ),
                  elevation: 0,
                  color: Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8),
                    child: Column(
                      children: [
                        _buildSubToggleItem('Summary Cards (Total Bills & Amount)', 'cf_summary', Icons.grid_view_rounded),
                        const Divider(color: AppTheme.dividerColor, height: 1, indent: 36),
                        _buildSubToggleItem('Global Overview Banner', 'cf_overview', Icons.bar_chart_rounded),
                        const Divider(color: AppTheme.dividerColor, height: 1, indent: 36),
                        _buildSubToggleItem('Speed Distribution Chart', 'cf_pie_chart', Icons.pie_chart_rounded),
                        const Divider(color: AppTheme.dividerColor, height: 1, indent: 36),
                        _buildSubToggleItem('Monthly Trend Chart', 'cf_trend', Icons.show_chart_rounded),
                        const Divider(color: AppTheme.dividerColor, height: 1, indent: 36),
                        _buildSubToggleItem('Fastest Paying Customers', 'cf_fastest', Icons.emoji_events_rounded),
                        const Divider(color: AppTheme.dividerColor, height: 1, indent: 36),
                        _buildSubToggleItem('Slowest Paying Customers', 'cf_slowest', Icons.warning_amber_rounded),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubToggleItem(String label, String featureKey, IconData icon) {
    final isEnabled = _features[featureKey] ?? true;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppTheme.textSecondary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
          ),
          Switch.adaptive(
            value: isEnabled,
            activeColor: AppTheme.primaryColor,
            onChanged: (_) => _toggleFeature(featureKey, isEnabled),
          ),
        ],
      ),
    );
  }
}

// ─── Sub-features: Ledger Statement Screen ─────────────────────
class LedgerFeaturesScreen extends StatefulWidget {
  final String companyName;
  final Map<String, bool> initialFeatures;

  const LedgerFeaturesScreen({
    super.key,
    required this.companyName,
    required this.initialFeatures,
  });

  @override
  State<LedgerFeaturesScreen> createState() => _LedgerFeaturesScreenState();
}

class _LedgerFeaturesScreenState extends State<LedgerFeaturesScreen> {
  final SupabaseService _service = SupabaseService();
  late Map<String, bool> _features;
  bool _savingFeature = false;

  @override
  void initState() {
    super.initState();
    _features = Map<String, bool>.from(widget.initialFeatures);
  }

  Future<void> _refreshFeatures() async {
    if (_savingFeature) return;
    try {
      final features = await _service.getCompanyFeatures(widget.companyName);
      if (!mounted) return;
      setState(() => _features = Map<String, bool>.from(features));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to refresh: $e')),
        );
      }
    }
  }

  Future<void> _toggleFeature(String featureKey, bool currentValue) async {
    if (_savingFeature) return;
    _savingFeature = true;
    final previousFeatures = Map<String, bool>.from(_features);
    final updatedValue = !currentValue;
    setState(() {
      _features[featureKey] = updatedValue;
      // Master ledgers toggle cascades
      if (featureKey == 'ledgers' && !updatedValue) {
        _features['ls_transactions'] = false;
        _features['ls_performance'] = false;
        _features['ls_perf_speed'] = false;
        _features['ls_perf_delay'] = false;
        _features['ls_perf_trend'] = false;
        _features['ls_perf_history'] = false;
        _features['ls_perf_tally_formula'] = false;
      }
      if (featureKey == 'ledgers' && updatedValue) {
        _features['ls_transactions'] = true;
        _features['ls_performance'] = true;
        _features['ls_perf_speed'] = true;
        _features['ls_perf_delay'] = true;
        _features['ls_perf_trend'] = true;
        _features['ls_perf_history'] = true;
        _features['ls_perf_tally_formula'] = true;
      }
      // Performance tab toggle cascades its sub-sections
      if (featureKey == 'ls_performance' && !updatedValue) {
        _features['ls_perf_speed'] = false;
        _features['ls_perf_delay'] = false;
        _features['ls_perf_trend'] = false;
        _features['ls_perf_history'] = false;
        _features['ls_perf_tally_formula'] = false;
      }
      if (featureKey == 'ls_performance' && updatedValue) {
        _features['ls_perf_speed'] = true;
        _features['ls_perf_delay'] = true;
        _features['ls_perf_trend'] = true;
        _features['ls_perf_history'] = true;
        _features['ls_perf_tally_formula'] = true;
      }

      // Auto-toggle main features based on sub-features
      if (featureKey != 'ledgers') {
        // Auto-toggle performance tab based on its sections
        if (featureKey.startsWith('ls_perf_')) {
          final anyPerfSubEnabled = (_features['ls_perf_speed'] ?? false) ||
              (_features['ls_perf_delay'] ?? false) ||
              (_features['ls_perf_trend'] ?? false) ||
              (_features['ls_perf_history'] ?? false) ||
              (_features['ls_perf_tally_formula'] ?? false);
          _features['ls_performance'] = anyPerfSubEnabled;
        }

        // Auto-toggle master ledgers based on tabs
        final anyLedgerSubEnabled = (_features['ls_transactions'] ?? false) ||
            (_features['ls_performance'] ?? false);
        _features['ledgers'] = anyLedgerSubEnabled;
      }
    });

    try {
      await _service.updateCompanyFeatures(widget.companyName, Map<String, bool>.from(_features));
    } catch (e) {
      if (mounted) {
        setState(() { _features = previousFeatures; });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update setting: $e')),
        );
      }
    } finally {
      if (mounted) { setState(() => _savingFeature = false); } else { _savingFeature = false; }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLedgersEnabled = _features['ledgers'] ?? true;
    final isPerfEnabled = (_features['ls_performance'] ?? true) && isLedgersEnabled;

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (didPop || _savingFeature) return;
        Navigator.of(context).pop(_features);
      },
      child: Scaffold(
        backgroundColor: AppTheme.surfaceColor,
        appBar: AppBar(
          title: const Text('Ledger Settings',
              style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.textPrimary, fontSize: 16)),
          elevation: 0,
          backgroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: AppTheme.textPrimary),
            onPressed: _savingFeature ? null : () => Navigator.of(context).pop(_features),
          ),
          actions: [
            _adminRefreshButton(
              color: AppTheme.textPrimary,
              onPressed: _savingFeature ? null : _refreshFeatures,
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
          children: [
            // Master switch
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: AppTheme.dividerColor),
              ),
              elevation: 0,
              color: Colors.white,
              child: ListTile(
                title: const Text('Ledgers & Transactions Screen',
                    style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
                subtitle: const Text('Enable or disable the entire Ledgers section'),
                trailing: Switch.adaptive(
                  value: isLedgersEnabled,
                  activeColor: AppTheme.primaryColor,
                  onChanged: (_) => _toggleFeature('ledgers', isLedgersEnabled),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Tabs section
            const Text('TAB VISIBILITY', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppTheme.textSecondary, letterSpacing: 1.0)),
            const SizedBox(height: 12),
            IgnorePointer(
              ignoring: !isLedgersEnabled,
              child: Opacity(
                opacity: isLedgersEnabled ? 1.0 : 0.5,
                child: Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: AppTheme.dividerColor),
                  ),
                  elevation: 0,
                  color: Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8),
                    child: Column(
                      children: [
                        _buildSubToggleItem('Transactions Tab', 'ls_transactions', Icons.receipt_long_rounded),
                        const Divider(color: AppTheme.dividerColor, height: 1, indent: 36),
                        _buildSubToggleItem('Performance Tab', 'ls_performance', Icons.insights_rounded),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Performance sub-sections
            const Text('PERFORMANCE TAB SECTIONS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppTheme.textSecondary, letterSpacing: 1.0)),
            const SizedBox(height: 12),
            IgnorePointer(
              ignoring: !isPerfEnabled,
              child: Opacity(
                opacity: isPerfEnabled ? 1.0 : 0.5,
                child: Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: AppTheme.dividerColor),
                  ),
                  elevation: 0,
                  color: Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8),
                    child: Column(
                      children: [
                        _buildSubToggleItem('Avg Collection Speed Card', 'ls_perf_speed', Icons.speed_rounded),
                        const Divider(color: AppTheme.dividerColor, height: 1, indent: 36),
                        _buildSubToggleItem('Enable Tally Formula Toggle', 'ls_perf_tally_formula', Icons.calculate_rounded),
                        const Divider(color: AppTheme.dividerColor, height: 1, indent: 36),
                        _buildSubToggleItem('Avg Payment Delay Card', 'ls_perf_delay', Icons.timer_rounded),
                        const Divider(color: AppTheme.dividerColor, height: 1, indent: 36),
                        _buildSubToggleItem('Payment Delay Trend Chart', 'ls_perf_trend', Icons.show_chart_rounded),
                        const Divider(color: AppTheme.dividerColor, height: 1, indent: 36),
                        _buildSubToggleItem('Settlement History List', 'ls_perf_history', Icons.history_rounded),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubToggleItem(String label, String featureKey, IconData icon) {
    final isEnabled = _features[featureKey] ?? true;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppTheme.textSecondary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
          ),
          Switch.adaptive(
            value: isEnabled,
            activeColor: AppTheme.primaryColor,
            onChanged: (_) => _toggleFeature(featureKey, isEnabled),
          ),
        ],
      ),
    );
  }
}

// ─── Sub-features: Financial Statements (Balance Sheet / P&L) ──
class FinancialReportsFeaturesScreen extends StatefulWidget {
  final String companyName;
  final Map<String, bool> initialFeatures;

  const FinancialReportsFeaturesScreen({
    super.key,
    required this.companyName,
    required this.initialFeatures,
  });

  @override
  State<FinancialReportsFeaturesScreen> createState() =>
      _FinancialReportsFeaturesScreenState();
}

class _FinancialReportsFeaturesScreenState
    extends State<FinancialReportsFeaturesScreen> {
  final SupabaseService _service = SupabaseService();
  late Map<String, bool> _features;
  bool _savingFeature = false;

  @override
  void initState() {
    super.initState();
    _features = Map<String, bool>.from(widget.initialFeatures);
  }

  Future<void> _refreshFeatures() async {
    if (_savingFeature) return;
    try {
      final features = await _service.getCompanyFeatures(widget.companyName);
      if (!mounted) return;
      setState(() => _features = Map<String, bool>.from(features));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to refresh: $e')),
        );
      }
    }
  }

  Future<void> _toggleFeature(String featureKey, bool currentValue) async {
    if (_savingFeature) return;
    _savingFeature = true;
    final previousFeatures = Map<String, bool>.from(_features);
    final updatedValue = !currentValue;
    setState(() {
      _features[featureKey] = updatedValue;
      if (featureKey == 'balance_sheet') {
        _features['db_qa_balance_sheet'] = updatedValue;
      } else if (featureKey == 'profit_loss') {
        _features['db_qa_profit_loss'] = updatedValue;
      } else if (featureKey == 'db_qa_balance_sheet' && updatedValue) {
        _features['balance_sheet'] = true;
      } else if (featureKey == 'db_qa_profit_loss' && updatedValue) {
        _features['profit_loss'] = true;
      }
    });

    try {
      await _service.updateCompanyFeatures(
        widget.companyName,
        Map<String, bool>.from(_features),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _features = previousFeatures;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update setting: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _savingFeature = false);
      } else {
        _savingFeature = false;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isBsEnabled = _features['balance_sheet'] ?? true;
    final isPlEnabled = _features['profit_loss'] ?? true;

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (didPop || _savingFeature) return;
        Navigator.of(context).pop(_features);
      },
      child: Scaffold(
        backgroundColor: AppTheme.surfaceColor,
        appBar: AppBar(
          title: const Text(
            'Financial Statements',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
              fontSize: 16,
            ),
          ),
          elevation: 0,
          backgroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: AppTheme.textPrimary),
            onPressed:
                _savingFeature ? null : () => Navigator.of(context).pop(_features),
          ),
          actions: [
            _adminRefreshButton(
              color: AppTheme.textPrimary,
              onPressed: _savingFeature ? null : _refreshFeatures,
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
          children: [
            const Text(
              'BALANCE SHEET',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: AppTheme.dividerColor),
              ),
              elevation: 0,
              color: Colors.white,
              child: ListTile(
                title: const Text(
                  'Balance Sheet Screen',
                  style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
                ),
                subtitle: const Text('Enable or disable the Balance Sheet report'),
                trailing: Switch.adaptive(
                  value: isBsEnabled,
                  activeColor: AppTheme.primaryColor,
                  onChanged: (_) => _toggleFeature('balance_sheet', isBsEnabled),
                ),
              ),
            ),
            const SizedBox(height: 12),
            IgnorePointer(
              ignoring: !isBsEnabled,
              child: Opacity(
                opacity: isBsEnabled ? 1.0 : 0.5,
                child: Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: AppTheme.dividerColor),
                  ),
                  elevation: 0,
                  color: Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8),
                    child: _buildSubToggleItem(
                      'Dashboard Quick Action',
                      'db_qa_balance_sheet',
                      Icons.flash_on_rounded,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'PROFIT & LOSS',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: AppTheme.dividerColor),
              ),
              elevation: 0,
              color: Colors.white,
              child: ListTile(
                title: const Text(
                  'Profit & Loss Screen',
                  style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
                ),
                subtitle: const Text('Enable or disable the Profit & Loss report'),
                trailing: Switch.adaptive(
                  value: isPlEnabled,
                  activeColor: AppTheme.primaryColor,
                  onChanged: (_) => _toggleFeature('profit_loss', isPlEnabled),
                ),
              ),
            ),
            const SizedBox(height: 12),
            IgnorePointer(
              ignoring: !isPlEnabled,
              child: Opacity(
                opacity: isPlEnabled ? 1.0 : 0.5,
                child: Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: AppTheme.dividerColor),
                  ),
                  elevation: 0,
                  color: Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8),
                    child: _buildSubToggleItem(
                      'Dashboard Quick Action',
                      'db_qa_profit_loss',
                      Icons.flash_on_rounded,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubToggleItem(String label, String featureKey, IconData icon) {
    final isEnabled = _features[featureKey] ?? true;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppTheme.textSecondary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
          Switch.adaptive(
            value: isEnabled,
            activeColor: AppTheme.primaryColor,
            onChanged: (_) => _toggleFeature(featureKey, isEnabled),
          ),
        ],
      ),
    );
  }
}