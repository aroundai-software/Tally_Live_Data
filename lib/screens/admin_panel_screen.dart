import 'dart:async';
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
    if (!_verified) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final tabs = [
      const AdminCompaniesTab(),
      const AdminSyncLicensesTab(),
      const AdminUsersTab(),
      const AdminProfileTab(),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: tabs,
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
                _AdminNavItem(
                  icon: Icons.business_rounded,
                  label: 'Companies',
                  isSelected: _currentIndex == 0,
                  onTap: () => setState(() => _currentIndex = 0),
                ),
                _AdminNavItem(
                  icon: Icons.sync_lock_rounded,
                  label: 'Licenses',
                  isSelected: _currentIndex == 1,
                  onTap: () => setState(() => _currentIndex = 1),
                ),
                _AdminNavItem(
                  icon: Icons.people_alt_rounded,
                  label: 'Users',
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
    final color = isSelected ? const Color(0xFF2453FF) : const Color(0xFF6B7A94);
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
              Icon(icon, color: color, size: 24),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
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
      appBar: AppBar(
        title: Text(
          'TallyLive',
          style: AppTheme.brandTitle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: AppTheme.textPrimary,
          ),
        ),
        elevation: 0,
        backgroundColor: Colors.white,
        automaticallyImplyLeading: false,
        actions: [
          _adminRefreshButton(
            onPressed: _isLoading ? null : _loadCompanies,
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            color: Colors.white,
            child: TextField(
              controller: _searchController,
              onChanged: (val) => setState(() => _searchQuery = val),
              decoration: InputDecoration(
                hintText: 'Search companies...',
                prefixIcon: const Icon(Icons.search, color: AppTheme.textSecondary),
                filled: true,
                fillColor: AppTheme.surfaceColor,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadCompanies,
              child: _isLoading
                  ? const ShimmerLoading()
                  : filtered.isEmpty
                      ? Center(
                          child: Text(
                            _searchQuery.isEmpty ? 'No companies synced yet.' : 'No companies match "$_searchQuery"',
                            style: const TextStyle(color: AppTheme.textSecondary),
                          ),
                        )
                      : AnimationLimiter(
                          child: ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: filtered.length,
                            itemBuilder: (context, index) {
                              final comp = filtered[index];
                              final companyName = comp['company_name'] as String;
                              final features = comp['features'] as Map<String, bool>;

                              return AnimationConfiguration.staggeredList(
                                position: index,
                                duration: const Duration(milliseconds: 350),
                                child: SlideAnimation(
                                  verticalOffset: 50.0,
                                  child: FadeInAnimation(
                                    child: Container(
                                      margin: const EdgeInsets.only(bottom: 12),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(16),
                                        boxShadow: [
                                          BoxShadow(
                                            color: AppTheme.primaryColor.withOpacity(0.05),
                                            blurRadius: 20,
                                            offset: const Offset(0, 4),
                                          ),
                                        ],
                                      ),
                                      child: Material(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(16),
                                        clipBehavior: Clip.antiAlias,
                                        child: ListTile(
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                          leading: Container(
                                            padding: const EdgeInsets.all(10),
                                            decoration: BoxDecoration(
                                              gradient: LinearGradient(
                                                colors: [AppTheme.primaryColor.withOpacity(0.15), AppTheme.primaryColor.withOpacity(0.05)],
                                              ),
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                            child: const Icon(Icons.business_rounded, color: AppTheme.primaryColor),
                                          ),
                                          title: Text(companyName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
                                        trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: AppTheme.textSecondary),
                                        onTap: () async {
                                          final updatedFeatures = await Navigator.of(context).push<Map<String, bool>>(
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
                                      ), // closes ListTile
                                    ), // closes Material
                                  ), // closes Container
                                ), // closes FadeInAnimation
                              ), // closes SlideAnimation
                            ); // closes AnimationConfiguration.staggeredList
                            },
                          ),
                        ),
            ),
          ),
        ],
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

class _AdminSyncLicensesTabState extends State<AdminSyncLicensesTab> {
  final SupabaseService _service = SupabaseService();
  final TextEditingController _searchController = TextEditingController();
  bool _isLoading = true;
  bool _isRefreshing = false;
  List<Map<String, dynamic>> _machines = [];
  final Map<String, List<String>> _machineCompanies = {};
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadMachines();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
    setState(() {
      _searchQuery = '';
      _searchController.clear();
    });
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
                      color: const Color(0xFF2453FF).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.sync_lock_rounded, color: Color(0xFF2453FF), size: 24),
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
                  final initial = currentExpiry != null && currentExpiry.isAfter(DateTime.now())
                      ? currentExpiry
                      : DateTime.now();
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: initial.add(const Duration(days: 30)),
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
                  );
                  if (picked != null) {
                    Navigator.pop(sheetCtx);
                    _applyNewExpiry(machineId, picked);
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
                const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: Color(0xFF2453FF)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _applyNewExpiry(String machineId, DateTime newExpiry) async {
    final success = await _service.updateSyncMachineControl(
      machineId,
      expiresAt: newExpiry,
      syncShouldRun: true,
    );
    if (!mounted) return;
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.green.shade700,
          content: Text('✅ License extended until ${_formatDate(newExpiry)}'),
        ),
      );
      _loadMachines();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.red,
          content: Text('Failed to update license. Make sure expires_at column exists in Supabase.'),
        ),
      );
    }
  }

  Future<void> _toggleSyncRun(String machineId, bool currentValue) async {
    final newValue = !currentValue;
    final success = await _service.updateSyncMachineControl(
      machineId,
      syncShouldRun: newValue,
    );
    if (!mounted) return;
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(newValue ? '🟢 Sync enabled' : '⏸️ Sync paused remotely'),
        ),
      );
      _loadMachines();
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _machines.where((m) {
      final machineKey = m['machine_name']?.toString() ?? '';
      final linked = (_machineCompanies[machineKey] ?? const <String>[])
          .join(' ')
          .toLowerCase();
      final comp = m['current_company']?.toString().toLowerCase() ?? '';
      final mach = m['machine_name']?.toString().toLowerCase() ?? '';
      final q = _searchQuery.toLowerCase();
      return comp.contains(q) || mach.contains(q) || linked.contains(q);
    }).toList();

    return Scaffold(
      backgroundColor: AppTheme.surfaceColor,
      appBar: AppBar(
        title: Text(
          'Sync Licenses',
          style: AppTheme.brandTitle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: AppTheme.textPrimary,
          ),
        ),
        elevation: 0,
        backgroundColor: Colors.white,
        automaticallyImplyLeading: false,
        actions: [
          if (_isRefreshing)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            _adminRefreshButton(
              onPressed: _isLoading ? null : _refreshMachines,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refreshMachines,
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                children: [
                  // Search Box
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppTheme.dividerColor),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: TextField(
                      controller: _searchController,
                      decoration: const InputDecoration(
                        icon: Icon(Icons.search, color: Color(0xFF6B7A94)),
                        hintText: 'Search by company or machine...',
                        border: InputBorder.none,
                      ),
                      onChanged: (val) => setState(() => _searchQuery = val),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Machine Cards
                  if (filtered.isEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32.0),
                        child: Text(
                          'No sync machines found',
                          style: TextStyle(color: AppTheme.textSecondary),
                        ),
                      ),
                    )
                  else
                    ...filtered.map((m) {
                      final companyName = m['current_company']?.toString() ?? 'Unknown Company';
                      final machineName = m['machine_name']?.toString() ?? 'Unknown Machine';
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
                          DateTime.now().toUtc().difference(lastSeen.toUtc()).inHours < 3;
                      final isExpired = expiresAt != null && DateTime.now().isAfter(expiresAt);
                      final daysRemaining = expiresAt != null
                          ? expiresAt.difference(DateTime.now()).inDays
                          : null;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isExpired ? Colors.red.shade200 : AppTheme.dividerColor,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.03),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Company & Machine
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF2453FF).withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Icon(
                                      Icons.business_rounded,
                                      color: Color(0xFF2453FF),
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          companyName,
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w700,
                                            color: AppTheme.textPrimary,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Row(
                                          children: [
                                            Icon(Icons.computer_rounded, size: 14, color: AppTheme.textSecondary),
                                            const SizedBox(width: 4),
                                            Text(
                                              machineName,
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: AppTheme.textSecondary,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  // Online Status dot
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: isOnline
                                          ? Colors.green.shade50
                                          : Colors.grey.shade100,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          width: 6,
                                          height: 6,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: isOnline ? Colors.green : Colors.grey,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          isOnline ? 'Online' : 'Offline',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: isOnline ? Colors.green.shade700 : Colors.grey.shade600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              Builder(
                                builder: (_) {
                                  final linked =
                                      _machineCompanies[machineName] ?? const <String>[];
                                  if (linked.isEmpty) return const SizedBox(height: 12);
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 10, bottom: 4),
                                    child: Text(
                                      'Linked companies: ${linked.join(', ')}',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        color: AppTheme.textSecondary,
                                        height: 1.35,
                                      ),
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(height: 8),

                              // Expiry & Heartbeat Info
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: isExpired
                                      ? Colors.red.shade50
                                      : const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          isExpired ? Icons.error_outline : Icons.timelapse_rounded,
                                          size: 16,
                                          color: isExpired ? Colors.red.shade700 : const Color(0xFF2453FF),
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          expiresAt != null
                                              ? (isExpired
                                                  ? 'Expired on ${_formatDate(expiresAt)}'
                                                  : 'Expires ${_formatDate(expiresAt)} ($daysRemaining d left)')
                                              : 'Active (No Expiry)',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: isExpired ? Colors.red.shade800 : AppTheme.textPrimary,
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (lastSeen != null)
                                      Text(
                                        'Seen ${_timeAgo(lastSeen)}',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: AppTheme.textSecondary,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),

                              // Controls: Switch & Extend Button
                              Row(
                                children: [
                                  Row(
                                    children: [
                                      Switch.adaptive(
                                        value: shouldRun,
                                        activeColor: const Color(0xFF2453FF),
                                        onChanged: (_) => _toggleSyncRun(machineId, shouldRun),
                                      ),
                                      Text(
                                        shouldRun ? 'Sync On' : 'Paused',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                          color: shouldRun ? Colors.green.shade700 : Colors.red.shade700,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const Spacer(),
                                  ElevatedButton.icon(
                                    onPressed: () => _showExtendLicenseSheet(context, m),
                                    icon: const Icon(Icons.add_circle_outline, size: 16),
                                    label: const Text('Extend Plan'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF2453FF),
                                      foregroundColor: Colors.white,
                                      elevation: 0,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
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
    try {
      await _service.updateUserAccess(userId, newValue);
      await _loadUsers();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update access: $e'), backgroundColor: AppTheme.errorColor),
        );
      }
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
              backgroundColor: const Color(0xFFC2372A),
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
                    backgroundColor: const Color(0xFFC2372A),
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
                          Icon(Icons.person_add_rounded, color: Color(0xFF2453FF)),
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
                              backgroundColor: const Color(0xFF2453FF),
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
      appBar: AppBar(
        title: const Text(
          'Users Management',
          style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
        ),
        elevation: 0,
        backgroundColor: Colors.white,
        automaticallyImplyLeading: false,
        actions: [
          if (_isRefreshing)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            _adminRefreshButton(
              onPressed: _isLoading ? null : _refreshUsers,
            ),
        ],
      ),
      floatingActionButton: _isLoading
          ? null
          : FloatingActionButton.extended(
              onPressed: _showCreateUserDialog,
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.person_add_rounded),
              label: const Text('Create User'),
            ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryColor))
          : Column(
              children: [
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search by name or phone...',
                      hintStyle: const TextStyle(color: AppTheme.textSecondary),
                      prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.textSecondary),
                      filled: true,
                      fillColor: AppTheme.surfaceColor,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                    onChanged: (val) {
                      setState(() {
                        _searchQuery = val;
                      });
                    },
                  ),
                ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _refreshUsers,
                    color: AppTheme.primaryColor,
                    child: displayedUsers.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              SizedBox(
                                height: MediaQuery.of(context).size.height * 0.4,
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
                        : ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: displayedUsers.length,
                            itemBuilder: (context, index) {
                              final user = displayedUsers[index];
                              final userId = user['id']?.toString() ?? '';
                              final isActive = user['is_active'] == true;
                              final role = user['role'] ?? 'user';
                              final isExpanded = _expandedUserIds.contains(userId);
                              final isLoadingCompanies = _loadingCompaniesUserIds.contains(userId);
                              final companies = _userCompaniesMap[userId] ?? [];

                              return Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.04),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  children: [
                                    InkWell(
                                      onTap: () => _toggleExpandUser(userId),
                                      borderRadius: BorderRadius.circular(12),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                        child: Row(
                                          children: [
                                            CircleAvatar(
                                              backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.1),
                                              child: Text(
                                                ((user['full_name']?.toString().trim().isNotEmpty ?? false) ? user['full_name'].toString().trim().characters.first.toUpperCase() : 'U'),
                                                style: const TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.bold),
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    user['full_name']?.toString() ?? 'Unknown User',
                                                    style: const TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(user['phone_number']?.toString() ?? '', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                                                  const SizedBox(height: 4),
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                    decoration: BoxDecoration(
                                                      color: role == 'super_admin' ? Colors.red.withValues(alpha: 0.1) : Colors.blue.withValues(alpha: 0.1),
                                                      borderRadius: BorderRadius.circular(12),
                                                    ),
                                                    child: Text(
                                                      role.toString().toUpperCase(),
                                                      style: TextStyle(
                                                        fontSize: 10,
                                                        fontWeight: FontWeight.w700,
                                                        color: role == 'super_admin' ? Colors.red : Colors.blue,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            Icon(
                                              isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                                              color: AppTheme.textSecondary,
                                            ),
                                            const SizedBox(width: 8),
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
                                      const Divider(height: 1, indent: 16, endIndent: 16),
                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.all(16),
                                        decoration: BoxDecoration(
                                          color: AppTheme.surfaceColor.withValues(alpha: 0.5),
                                          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
                                        ),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                const Icon(Icons.business_rounded, size: 16, color: AppTheme.primaryColor),
                                                const SizedBox(width: 6),
                                                Expanded(
                                                  child: Text(
                                                    'Linked Companies (${companies.length})',
                                                    style: const TextStyle(
                                                      fontWeight: FontWeight.w700,
                                                      fontSize: 13,
                                                      color: AppTheme.textPrimary,
                                                    ),
                                                  ),
                                                ),
                                                TextButton.icon(
                                                  onPressed: () => _showAdminLinkCompanyDialog(
                                                    userId: userId,
                                                    userName: user['full_name']?.toString() ?? 'User',
                                                  ),
                                                  icon: const Icon(Icons.add_rounded, size: 16),
                                                  label: const Text('Link'),
                                                  style: TextButton.styleFrom(
                                                    foregroundColor: AppTheme.primaryColor,
                                                    padding: const EdgeInsets.symmetric(horizontal: 8),
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
                                                    child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryColor),
                                                  ),
                                                ),
                                              )
                                            else if (companies.isEmpty)
                                              const Text(
                                                'No companies linked. Tap Link to assign companies.',
                                                style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontStyle: FontStyle.italic),
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
                                                          final features = await _service.getCompanyFeatures(comp);
                                                          if (!context.mounted) return;
                                                          Navigator.of(context).push(
                                                            MaterialPageRoute(
                                                              builder: (_) => CompanyFeaturesScreen(
                                                                companyName: comp,
                                                                initialFeatures: features,
                                                              ),
                                                            ),
                                                          );
                                                        } catch (e) {
                                                          if (context.mounted) {
                                                            ScaffoldMessenger.of(context).showSnackBar(
                                                              SnackBar(content: Text('Error loading features: $e')),
                                                            );
                                                          }
                                                        }
                                                      },
                                                      borderRadius: BorderRadius.circular(8),
                                                      child: Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                                        decoration: BoxDecoration(
                                                          borderRadius: BorderRadius.circular(8),
                                                          border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
                                                        ),
                                                        child: Row(
                                                          mainAxisSize: MainAxisSize.min,
                                                          children: [
                                                            const Icon(Icons.domain_rounded, size: 14, color: AppTheme.primaryColor),
                                                            const SizedBox(width: 6),
                                                            Flexible(
                                                              child: Text(
                                                                comp,
                                                                maxLines: 1,
                                                                overflow: TextOverflow.ellipsis,
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
                                                              borderRadius: BorderRadius.circular(10),
                                                              child: const Padding(
                                                                padding: EdgeInsets.all(2),
                                                                child: Icon(
                                                                  Icons.close_rounded,
                                                                  size: 14,
                                                                  color: AppTheme.textSecondary,
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
                              );
                            },
                          ),
                  ),
                ),
              ],
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
              backgroundColor: const Color(0xFFC2372A),
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
      appBar: AppBar(
        title: const Text(
          'Admin Profile',
          style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
        ),
        elevation: 0,
        backgroundColor: Colors.white,
        automaticallyImplyLeading: false,
        actions: [
          _adminRefreshButton(
            onPressed: _isLoading ? null : _loadProfile,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryColor))
          : Center(
              child: SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      children: [
                      // Profile Details Card
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.primaryColor.withOpacity(0.05),
                              blurRadius: 20,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.all(20.0),
                        child: Row(
                          children: [
                            Container(
                              height: 60,
                              width: 60,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [AppTheme.primaryColor.withOpacity(0.15), AppTheme.primaryColor.withOpacity(0.05)],
                                ),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.admin_panel_settings_rounded, size: 32, color: AppTheme.primaryColor),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'System Administrator',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                      color: AppTheme.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Phone: $_adminPhone',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: AppTheme.textSecondary,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),
                      
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'ACCOUNT',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.textSecondary,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      
                      _buildActionItem(
                        icon: Icons.admin_panel_settings_rounded,
                        title: 'Create New Admin Account',
                        subtitle: 'Add a new super administrator',
                        color: const Color(0xFF2453FF),
                        onTap: _showCreateAdminDialog,
                      ),
                      const SizedBox(height: 12),
                      
                      _buildActionItem(
                        icon: Icons.password_rounded,
                        title: 'Change Password',
                        subtitle: 'Update your administrator password',
                        color: AppTheme.primaryColor,
                        onTap: _showChangePasswordDialog,
                      ),
                      const SizedBox(height: 24),
                      
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.textSecondary.withOpacity(0.05),
                              blurRadius: 20,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AppTheme.textSecondary.withOpacity(0.05),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(Icons.info_outline_rounded, color: AppTheme.textSecondary.withOpacity(0.7), size: 22),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'App Version',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '$_appVersion (Latest)',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppTheme.textSecondary,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
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
    );
  }

  Widget _buildActionItem({
    required IconData icon,
    required String title,
    String? subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [color.withOpacity(0.15), color.withOpacity(0.05)],
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: color == AppTheme.errorColor ? color : AppTheme.textPrimary,
          ),
        ),
        subtitle: subtitle != null ? Text(subtitle, style: const TextStyle(color: AppTheme.textSecondary)) : null,
        trailing: Icon(Icons.arrow_forward_ios_rounded, size: 16, color: color == AppTheme.errorColor ? color : AppTheme.textSecondary),
        onTap: onTap,
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
                    backgroundColor: const Color(0xFFC2372A),
                  ),
                );
              }
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.white,
              title: const Text('Change Password', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F1A2B))),
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
                  child: const Text('Cancel', style: TextStyle(color: Color(0xFF6B7A94))),
                ),
                ElevatedButton(
                  onPressed: isUpdating ? null : submitPasswordChange,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2453FF),
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
                    backgroundColor: const Color(0xFFC2372A),
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
                          Icon(Icons.admin_panel_settings_rounded, color: Color(0xFF2453FF)),
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
                              backgroundColor: const Color(0xFF2453FF),
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
        backgroundColor: const Color(0xFFF5F7FB),
        appBar: AppBar(
          title: Text(
            widget.companyName,
            style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF0F1A2B), fontSize: 16),
          ),
          elevation: 0,
          backgroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF0F1A2B)),
            onPressed: _savingFeature ? null : () => Navigator.of(context).pop(_features),
          ),
          actions: [
            _adminRefreshButton(
              color: const Color(0xFF0F1A2B),
              onPressed: _savingFeature ? null : _refreshFeatures,
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
          children: [
            const Text(
              'FEATURE CONFIGURATIONS',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: Color(0xFF6B7A94),
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 12),
            
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 0,
              color: Colors.white,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8),
                child: Column(
                  children: [
                    // Nested Sub-settings Categories
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
                    const Divider(color: Color(0xFFE4E9F1), height: 1, indent: 36),
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
                    const Divider(color: Color(0xFFE4E9F1), height: 1, indent: 36),
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
                    const Divider(color: Color(0xFFE4E9F1), height: 1, indent: 36),
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
                    const Divider(color: Color(0xFFE4E9F1), height: 1, indent: 36),
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
                    const Divider(color: Color(0xFFE4E9F1), height: 1, indent: 36),
                    _buildFinancialStatementsNavItem(),
                    
                    // Simple Toggles for other screens
                    const Divider(color: Color(0xFFE4E9F1), height: 1, indent: 36),
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
                    const Divider(color: Color(0xFFE4E9F1), height: 1, indent: 36),
                    _buildToggleItem('Sales Invoices', 'sales', Icons.description_outlined),
                    const Divider(color: Color(0xFFE4E9F1), height: 1, indent: 36),
                    _buildToggleItem('Purchase Invoices', 'purchases', Icons.shopping_bag_outlined),
                  ],
                ),
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
      leading: const Icon(Icons.account_balance_outlined, size: 20, color: Color(0xFF6B7A94)),
      title: const Text(
        'Financial Statements',
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Color(0xFF3A4A63),
        ),
      ),
      subtitle: Text(
        isEnabled ? 'Enabled • $detail' : 'Disabled',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: isEnabled ? const Color(0xFF2453FF) : const Color(0xFF6B7A94),
        ),
      ),
      trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Color(0xFF6B7A94)),
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
      leading: Icon(icon, size: 20, color: const Color(0xFF6B7A94)),
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Color(0xFF3A4A63),
        ),
      ),
      subtitle: Text(
        isEnabled ? 'Enabled • $subtitleText' : 'Disabled',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: isEnabled ? const Color(0xFF2453FF) : const Color(0xFF6B7A94),
        ),
      ),
      trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Color(0xFF6B7A94)),
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
          Icon(icon, size: 20, color: const Color(0xFF6B7A94)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF3A4A63),
              ),
            ),
          ),
          Switch.adaptive(
            value: isEnabled,
            activeColor: const Color(0xFF2453FF),
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
        backgroundColor: const Color(0xFFF5F7FB),
        appBar: AppBar(
          title: const Text(
            'Dashboard Settings',
            style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF0F1A2B), fontSize: 16),
          ),
          elevation: 0,
          backgroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF0F1A2B)),
            onPressed: _savingFeature ? null : () => Navigator.of(context).pop(_features),
          ),
          actions: [
            _adminRefreshButton(
              color: const Color(0xFF0F1A2B),
              onPressed: _savingFeature ? null : _refreshFeatures,
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 16),
          children: [
            // Main Dashboard Toggle
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 0,
              color: Colors.white,
              child: ListTile(
                title: const Text('Dashboard Screen', style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF0F1A2B))),
                subtitle: const Text('Enable or disable the entire dashboard tab'),
                trailing: Switch.adaptive(
                  value: isDashboardEnabled,
                  activeColor: const Color(0xFF2453FF),
                  onChanged: (_) => _toggleFeature('dashboard', isDashboardEnabled),
                ),
              ),
            ),
            const SizedBox(height: 24),
            
            const Text(
              'DASHBOARD COMPONENTS',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: Color(0xFF6B7A94),
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 12),
            
            IgnorePointer(
              ignoring: !isDashboardEnabled,
              child: Opacity(
                opacity: isDashboardEnabled ? 1.0 : 0.5,
                child: Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                        const Divider(color: Color(0xFFE4E9F1), height: 1, indent: 36),
                        _buildSubToggleItem('6 Grid Summary Cards', 'db_summary_cards', Icons.grid_view_rounded),
                        if (_features['db_summary_cards'] ?? true) ...[
                          const SizedBox(height: 8),
                          _buildVisualCardGrid(),
                          const SizedBox(height: 8),
                        ],
                        const Divider(color: Color(0xFFE4E9F1), height: 1, indent: 36),
                        _buildSubToggleItem('Daybook Section', 'db_daybook', Icons.today_rounded),
                        const Divider(color: Color(0xFFE4E9F1), height: 1, indent: 36),
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
        'color': const Color(0xFF2453FF),
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
        'color': const Color(0xFFC2372A),
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
        color: const Color(0xFFF8F9FE),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE4E9F1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'ACTIVE SUMMARY CARDS (TAP TO TOGGLE)',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: Color(0xFF6B7A94),
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
                                  color: isItemEnabled ? color : const Color(0xFFE4E9F1),
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
                                            color: isItemEnabled ? const Color(0xFF0F1A2B) : Colors.grey.shade500,
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
        'color': const Color(0xFF2453FF),
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
        color: const Color(0xFFF8F9FE),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE4E9F1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'ACTIVE QUICK ACTIONS (TAP TO TOGGLE)',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: Color(0xFF6B7A94),
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
                                  color: isItemEnabled ? color : const Color(0xFFE4E9F1),
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
                                          ? const Color(0xFF0F1A2B)
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
        'color': const Color(0xFFC2372A),
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
        color: const Color(0xFFF8F9FE),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE4E9F1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'NET POSITION DETAILS (TAP TO TOGGLE ROWS)',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: Color(0xFF6B7A94),
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
                                  color: isItemEnabled ? color : const Color(0xFFE4E9F1),
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
                                            color: isItemEnabled ? const Color(0xFF0F1A2B) : Colors.grey.shade500,
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
          Icon(icon, size: 20, color: const Color(0xFF6B7A94)),
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
                        color: Color(0xFF3A4A63),
                      ),
                    ),
                  ),
                  if (isEnabled && isExpanded != null) ...[
                    const SizedBox(width: 6),
                    Icon(
                      isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                      size: 18,
                      color: const Color(0xFF2453FF),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Switch.adaptive(
            value: isEnabled,
            activeColor: const Color(0xFF2453FF),
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
        backgroundColor: const Color(0xFFF5F7FB),
        appBar: AppBar(
          title: const Text(
            'Stock Settings',
            style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF0F1A2B), fontSize: 16),
          ),
          elevation: 0,
          backgroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF0F1A2B)),
            onPressed: _savingFeature ? null : () => Navigator.of(context).pop(_features),
          ),
          actions: [
            _adminRefreshButton(
              color: const Color(0xFF0F1A2B),
              onPressed: _savingFeature ? null : _refreshFeatures,
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
          children: [
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 0,
              color: Colors.white,
              child: ListTile(
                title: const Text('Stock Screen', style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF0F1A2B))),
                subtitle: const Text('Enable or disable the entire stock tab'),
                trailing: Switch.adaptive(
                  value: isStockEnabled,
                  activeColor: const Color(0xFF2453FF),
                  onChanged: (_) => _toggleFeature('stock', isStockEnabled),
                ),
              ),
            ),
            const SizedBox(height: 24),
            
            const Text(
              'STOCK PRIVACY & CONTROLS',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: Color(0xFF6B7A94),
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 12),
            
            IgnorePointer(
              ignoring: !isStockEnabled,
              child: Opacity(
                opacity: isStockEnabled ? 1.0 : 0.5,
                child: Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                        const Divider(color: Color(0xFFE4E9F1), height: 1, indent: 36),
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
          Icon(icon, size: 20, color: const Color(0xFF6B7A94)),
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
                    color: Color(0xFF3A4A63),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF6B7A94),
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: isEnabled,
            activeColor: const Color(0xFF2453FF),
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
        backgroundColor: const Color(0xFFF5F7FB),
        appBar: AppBar(
          title: const Text(
            'Outstanding Settings',
            style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF0F1A2B), fontSize: 16),
          ),
          elevation: 0,
          backgroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF0F1A2B)),
            onPressed: _savingFeature ? null : () => Navigator.of(context).pop(_features),
          ),
          actions: [
            _adminRefreshButton(
              color: const Color(0xFF0F1A2B),
              onPressed: _savingFeature ? null : _refreshFeatures,
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
          children: [
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 0,
              color: Colors.white,
              child: ListTile(
                title: const Text('Outstanding Screen', style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF0F1A2B))),
                subtitle: const Text('Enable or disable the entire Recv/Pay tab'),
                trailing: Switch.adaptive(
                  value: isOutstandingEnabled,
                  activeColor: const Color(0xFF2453FF),
                  onChanged: (_) => _toggleFeature('outstanding', isOutstandingEnabled),
                ),
              ),
            ),
            const SizedBox(height: 24),
            
            const Text(
              'OUTSTANDING TAB VISIBILITY',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: Color(0xFF6B7A94),
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 12),
            
            IgnorePointer(
              ignoring: !isOutstandingEnabled,
              child: Opacity(
                opacity: isOutstandingEnabled ? 1.0 : 0.5,
                child: Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                  color: Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8),
                    child: Column(
                      children: [
                        _buildSubToggleItem('Receivables Tab', 'out_receivables', Icons.call_received_rounded),
                        const Divider(color: Color(0xFFE4E9F1), height: 1, indent: 36),
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
          Icon(icon, size: 20, color: const Color(0xFF6B7A94)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF3A4A63),
              ),
            ),
          ),
          Switch.adaptive(
            value: isEnabled,
            activeColor: const Color(0xFF2453FF),
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
        backgroundColor: const Color(0xFFF5F7FB),
        appBar: AppBar(
          title: const Text(
            'Reports Settings',
            style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF0F1A2B), fontSize: 16),
          ),
          elevation: 0,
          backgroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF0F1A2B)),
            onPressed: _savingFeature ? null : () => Navigator.of(context).pop(_features),
          ),
          actions: [
            _adminRefreshButton(
              color: const Color(0xFF0F1A2B),
              onPressed: _savingFeature ? null : _refreshFeatures,
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
          children: [
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 0,
              color: Colors.white,
              child: ListTile(
                title: const Text('Analytics & Reports Screen', style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF0F1A2B))),
                subtitle: const Text('Enable or disable the entire reports screen'),
                trailing: Switch.adaptive(
                  value: isReportsEnabled,
                  activeColor: const Color(0xFF2453FF),
                  onChanged: (_) => _toggleFeature('analytics', isReportsEnabled),
                ),
              ),
            ),
            const SizedBox(height: 24),
            
            const Text(
              'REPORT TYPE VISIBILITY',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: Color(0xFF6B7A94),
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 12),
            
            IgnorePointer(
              ignoring: !isReportsEnabled,
              child: Opacity(
                opacity: isReportsEnabled ? 1.0 : 0.5,
                child: Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                  color: Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8),
                    child: Column(
                      children: [
                        _buildSubToggleItem('Sales Reports', 'rep_sales', Icons.trending_up_rounded),
                        const Divider(color: Color(0xFFE4E9F1), height: 1, indent: 36),
                        _buildSubToggleItem('Purchase Reports', 'rep_purchases', Icons.trending_down_rounded),
                        const Divider(color: Color(0xFFE4E9F1), height: 1, indent: 36),
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
          Icon(icon, size: 20, color: const Color(0xFF6B7A94)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF3A4A63),
              ),
            ),
          ),
          Switch.adaptive(
            value: isEnabled,
            activeColor: const Color(0xFF2453FF),
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
      leading: Icon(icon, size: 20, color: const Color(0xFF6B7A94)),
      title: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF3A4A63))),
      subtitle: Text(
        isEnabled ? 'Enabled • $subtitleText' : 'Disabled',
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: isEnabled ? const Color(0xFF2453FF) : const Color(0xFF6B7A94)),
      ),
      trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Color(0xFF6B7A94)),
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
        backgroundColor: const Color(0xFFF5F7FB),
        appBar: AppBar(
          title: const Text('Cash Flow Settings',
              style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF0F1A2B), fontSize: 16)),
          elevation: 0,
          backgroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF0F1A2B)),
            onPressed: _savingFeature ? null : () => Navigator.of(context).pop(_features),
          ),
          actions: [
            _adminRefreshButton(
              color: const Color(0xFF0F1A2B),
              onPressed: _savingFeature ? null : _refreshFeatures,
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
          children: [
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 0,
              color: Colors.white,
              child: ListTile(
                title: const Text('Cash Flow Insights Screen',
                    style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF0F1A2B))),
                subtitle: const Text('Enable or disable the entire Cash Flow screen'),
                trailing: Switch.adaptive(
                  value: isCashFlowEnabled,
                  activeColor: const Color(0xFF2453FF),
                  onChanged: (_) => _toggleFeature('cash_flow', isCashFlowEnabled),
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'SECTION VISIBILITY',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF6B7A94), letterSpacing: 1.0),
            ),
            const SizedBox(height: 12),
            IgnorePointer(
              ignoring: !isCashFlowEnabled,
              child: Opacity(
                opacity: isCashFlowEnabled ? 1.0 : 0.5,
                child: Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                  color: Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8),
                    child: Column(
                      children: [
                        _buildSubToggleItem('Summary Cards (Total Bills & Amount)', 'cf_summary', Icons.grid_view_rounded),
                        const Divider(color: Color(0xFFE4E9F1), height: 1, indent: 36),
                        _buildSubToggleItem('Global Overview Banner', 'cf_overview', Icons.bar_chart_rounded),
                        const Divider(color: Color(0xFFE4E9F1), height: 1, indent: 36),
                        _buildSubToggleItem('Speed Distribution Chart', 'cf_pie_chart', Icons.pie_chart_rounded),
                        const Divider(color: Color(0xFFE4E9F1), height: 1, indent: 36),
                        _buildSubToggleItem('Monthly Trend Chart', 'cf_trend', Icons.show_chart_rounded),
                        const Divider(color: Color(0xFFE4E9F1), height: 1, indent: 36),
                        _buildSubToggleItem('Fastest Paying Customers', 'cf_fastest', Icons.emoji_events_rounded),
                        const Divider(color: Color(0xFFE4E9F1), height: 1, indent: 36),
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
          Icon(icon, size: 20, color: const Color(0xFF6B7A94)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF3A4A63))),
          ),
          Switch.adaptive(
            value: isEnabled,
            activeColor: const Color(0xFF2453FF),
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
        backgroundColor: const Color(0xFFF5F7FB),
        appBar: AppBar(
          title: const Text('Ledger Settings',
              style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF0F1A2B), fontSize: 16)),
          elevation: 0,
          backgroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF0F1A2B)),
            onPressed: _savingFeature ? null : () => Navigator.of(context).pop(_features),
          ),
          actions: [
            _adminRefreshButton(
              color: const Color(0xFF0F1A2B),
              onPressed: _savingFeature ? null : _refreshFeatures,
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
          children: [
            // Master switch
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 0,
              color: Colors.white,
              child: ListTile(
                title: const Text('Ledgers & Transactions Screen',
                    style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF0F1A2B))),
                subtitle: const Text('Enable or disable the entire Ledgers section'),
                trailing: Switch.adaptive(
                  value: isLedgersEnabled,
                  activeColor: const Color(0xFF2453FF),
                  onChanged: (_) => _toggleFeature('ledgers', isLedgersEnabled),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Tabs section
            const Text('TAB VISIBILITY', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF6B7A94), letterSpacing: 1.0)),
            const SizedBox(height: 12),
            IgnorePointer(
              ignoring: !isLedgersEnabled,
              child: Opacity(
                opacity: isLedgersEnabled ? 1.0 : 0.5,
                child: Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                  color: Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8),
                    child: Column(
                      children: [
                        _buildSubToggleItem('Transactions Tab', 'ls_transactions', Icons.receipt_long_rounded),
                        const Divider(color: Color(0xFFE4E9F1), height: 1, indent: 36),
                        _buildSubToggleItem('Performance Tab', 'ls_performance', Icons.insights_rounded),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Performance sub-sections
            const Text('PERFORMANCE TAB SECTIONS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF6B7A94), letterSpacing: 1.0)),
            const SizedBox(height: 12),
            IgnorePointer(
              ignoring: !isPerfEnabled,
              child: Opacity(
                opacity: isPerfEnabled ? 1.0 : 0.5,
                child: Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                  color: Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8),
                    child: Column(
                      children: [
                        _buildSubToggleItem('Avg Collection Speed Card', 'ls_perf_speed', Icons.speed_rounded),
                        const Divider(color: Color(0xFFE4E9F1), height: 1, indent: 36),
                        _buildSubToggleItem('Enable Tally Formula Toggle', 'ls_perf_tally_formula', Icons.calculate_rounded),
                        const Divider(color: Color(0xFFE4E9F1), height: 1, indent: 36),
                        _buildSubToggleItem('Avg Payment Delay Card', 'ls_perf_delay', Icons.timer_rounded),
                        const Divider(color: Color(0xFFE4E9F1), height: 1, indent: 36),
                        _buildSubToggleItem('Payment Delay Trend Chart', 'ls_perf_trend', Icons.show_chart_rounded),
                        const Divider(color: Color(0xFFE4E9F1), height: 1, indent: 36),
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
          Icon(icon, size: 20, color: const Color(0xFF6B7A94)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF3A4A63))),
          ),
          Switch.adaptive(
            value: isEnabled,
            activeColor: const Color(0xFF2453FF),
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
        backgroundColor: const Color(0xFFF5F7FB),
        appBar: AppBar(
          title: const Text(
            'Financial Statements',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: Color(0xFF0F1A2B),
              fontSize: 16,
            ),
          ),
          elevation: 0,
          backgroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF0F1A2B)),
            onPressed:
                _savingFeature ? null : () => Navigator.of(context).pop(_features),
          ),
          actions: [
            _adminRefreshButton(
              color: const Color(0xFF0F1A2B),
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
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: Color(0xFF6B7A94),
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 12),
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 0,
              color: Colors.white,
              child: ListTile(
                title: const Text(
                  'Balance Sheet Screen',
                  style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF0F1A2B)),
                ),
                subtitle: const Text('Enable or disable the Balance Sheet report'),
                trailing: Switch.adaptive(
                  value: isBsEnabled,
                  activeColor: const Color(0xFF2453FF),
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
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: Color(0xFF6B7A94),
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 12),
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 0,
              color: Colors.white,
              child: ListTile(
                title: const Text(
                  'Profit & Loss Screen',
                  style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF0F1A2B)),
                ),
                subtitle: const Text('Enable or disable the Profit & Loss report'),
                trailing: Switch.adaptive(
                  value: isPlEnabled,
                  activeColor: const Color(0xFF2453FF),
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
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
          Icon(icon, size: 20, color: const Color(0xFF6B7A94)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF3A4A63),
              ),
            ),
          ),
          Switch.adaptive(
            value: isEnabled,
            activeColor: const Color(0xFF2453FF),
            onChanged: (_) => _toggleFeature(featureKey, isEnabled),
          ),
        ],
      ),
    );
  }
}