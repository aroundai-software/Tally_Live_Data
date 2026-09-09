import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../services/supabase_service.dart';
import '../config/app_theme.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import '../widgets/shimmer_loading.dart';
import 'login_screen.dart';

// ─── Main Admin Shell (Tabs) ──────────────────────────────────
class AdminPanelScreen extends StatefulWidget {
  final bool isRootAdmin;
  const AdminPanelScreen({super.key, this.isRootAdmin = false});

  @override
  State<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends State<AdminPanelScreen> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final tabs = [
      const AdminCompaniesTab(),
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
                  icon: Icons.person_rounded,
                  label: 'Profile',
                  isSelected: _currentIndex == 1,
                  onTap: () => setState(() => _currentIndex = 1),
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
  bool _isLoading = true;
  List<Map<String, dynamic>> _companiesFeatures = [];
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadCompanies();
  }

  Future<void> _loadCompanies() async {
    setState(() => _isLoading = true);
    try {
      final data = await _service.getAllCompaniesFeatures();
      setState(() {
        _companiesFeatures = data;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading companies: $e')),
        );
      }
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
        title: const Text('TallyLive', style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
        elevation: 0,
        backgroundColor: Colors.white,
        automaticallyImplyLeading: false,
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            color: Colors.white,
            child: TextField(
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

// ─── Tab 2: Profile & Logout ──────────────────────────────────
class AdminProfileTab extends StatefulWidget {
  const AdminProfileTab({super.key});

  @override
  State<AdminProfileTab> createState() => _AdminProfileTabState();
}

class _AdminProfileTabState extends State<AdminProfileTab> {
  final SupabaseService _service = SupabaseService();
  String _adminPhone = '';
  String _appVersion = 'v2.0.2';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final user = _service.currentUser;
      if (user != null) {
        final profile = await _service.getUserProfile(user.id);
        
        final info = await PackageInfo.fromPlatform();

        setState(() {
          _adminPhone = profile?['phone_number']?.toString() ?? user.phone ?? '97000000';
          _appVersion = 'v${info.version}';
          _isLoading = false;
        });
      }
    } catch (_) {
      setState(() => _isLoading = false);
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
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryColor))
          : Center(
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
                      
                      // User Management Section
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'USER MANAGEMENT',
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
                        icon: Icons.person_add_rounded,
                        title: 'Create New User Account',
                        subtitle: 'Add an owner account & link a company',
                        color: AppTheme.primaryColor,
                        onTap: _showCreateUserDialog,
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

  void _showCreateUserDialog() {
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
                await _service.adminRegisterUser(
                  fullName: nameCtrl.text.trim(),
                  phone: phoneCtrl.text.trim(),
                  password: passwordCtrl.text.trim(),
                );
                if (!mounted) return;
                Navigator.of(ctx).pop();
                
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('User account created successfully!'),
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
                          Icon(Icons.person_add_rounded, color: Color(0xFF2453FF)),
                          SizedBox(width: 8),
                          Text('Create New User', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Register a new business owner profile to let them access TallyLive analytics.',
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
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
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

  @override
  void initState() {
    super.initState();
    _features = Map<String, bool>.from(widget.initialFeatures);
  }

  Future<void> _toggleFeature(String featureKey, bool currentValue) async {
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
          _features[featureKey] = currentValue;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update setting: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (didPop) return;
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
            onPressed: () => Navigator.of(context).pop(_features),
          ),
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
  bool _isNetPositionConfigExpanded = true;

  @override
  void initState() {
    super.initState();
    _features = Map<String, bool>.from(widget.initialFeatures);
  }

  Future<void> _toggleFeature(String featureKey, bool currentValue) async {
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
          _features[featureKey] = currentValue;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update setting: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDashboardEnabled = _features['dashboard'] ?? true;

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (didPop) return;
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
            onPressed: () => Navigator.of(context).pop(_features),
          ),
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
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: cardItems.map((item) {
              final key = item['key'] as String;
              final isItemEnabled = _features[key] ?? true;
              final color = item['color'] as Color;

              return GestureDetector(
                onTap: () => _toggleFeature(key, isItemEnabled),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 140,
                  height: 90,
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
                              size: 16,
                              color: isItemEnabled ? color : Colors.grey.shade400,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              item['title'] as String,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: isItemEnabled ? const Color(0xFF0F1A2B) : Colors.grey.shade500),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: quickActionItems.map((item) {
              final key = item['key'] as String;
              final isItemEnabled = _features[key] ?? true;
              final color = item['color'] as Color;

              return Expanded(
                child: GestureDetector(
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
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: isItemEnabled ? const Color(0xFF0F1A2B) : Colors.grey.shade500,
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
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: netPositionItems.map((item) {
              final key = item['key'] as String;
              final isItemEnabled = _features[key] ?? true;
              final color = item['color'] as Color;

              return GestureDetector(
                onTap: () => _toggleFeature(key, isItemEnabled),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 140,
                  height: 90,
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
                              size: 16,
                              color: isItemEnabled ? color : Colors.grey.shade400,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              item['title'] as String,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: isItemEnabled ? const Color(0xFF0F1A2B) : Colors.grey.shade500),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
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

  @override
  void initState() {
    super.initState();
    _features = Map<String, bool>.from(widget.initialFeatures);
  }

  Future<void> _toggleFeature(String featureKey, bool currentValue) async {
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
          _features[featureKey] = currentValue;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update setting: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isStockEnabled = _features['stock'] ?? true;

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (didPop) return;
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
            onPressed: () => Navigator.of(context).pop(_features),
          ),
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

  @override
  void initState() {
    super.initState();
    _features = Map<String, bool>.from(widget.initialFeatures);
  }

  Future<void> _toggleFeature(String featureKey, bool currentValue) async {
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
          _features[featureKey] = currentValue;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update setting: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isOutstandingEnabled = _features['outstanding'] ?? true;

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (didPop) return;
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
            onPressed: () => Navigator.of(context).pop(_features),
          ),
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

  @override
  void initState() {
    super.initState();
    _features = Map<String, bool>.from(widget.initialFeatures);
  }

  Future<void> _toggleFeature(String featureKey, bool currentValue) async {
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
          _features[featureKey] = currentValue;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update setting: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isReportsEnabled = _features['analytics'] ?? true;

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (didPop) return;
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
            onPressed: () => Navigator.of(context).pop(_features),
          ),
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

  @override
  void initState() {
    super.initState();
    _features = Map<String, bool>.from(widget.initialFeatures);
  }

  Future<void> _toggleFeature(String featureKey, bool currentValue) async {
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
        setState(() { _features[featureKey] = currentValue; });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update setting: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isCashFlowEnabled = _features['cash_flow'] ?? true;

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (didPop) return;
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
            onPressed: () => Navigator.of(context).pop(_features),
          ),
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

  @override
  void initState() {
    super.initState();
    _features = Map<String, bool>.from(widget.initialFeatures);
  }

  Future<void> _toggleFeature(String featureKey, bool currentValue) async {
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
      }
      if (featureKey == 'ledgers' && updatedValue) {
        _features['ls_transactions'] = true;
        _features['ls_performance'] = true;
        _features['ls_perf_speed'] = true;
        _features['ls_perf_delay'] = true;
        _features['ls_perf_trend'] = true;
        _features['ls_perf_history'] = true;
      }
      // Performance tab toggle cascades its sub-sections
      if (featureKey == 'ls_performance' && !updatedValue) {
        _features['ls_perf_speed'] = false;
        _features['ls_perf_delay'] = false;
        _features['ls_perf_trend'] = false;
        _features['ls_perf_history'] = false;
      }
      if (featureKey == 'ls_performance' && updatedValue) {
        _features['ls_perf_speed'] = true;
        _features['ls_perf_delay'] = true;
        _features['ls_perf_trend'] = true;
        _features['ls_perf_history'] = true;
      }

      // Auto-toggle main features based on sub-features
      if (featureKey != 'ledgers') {
        // Auto-toggle performance tab based on its sections
        if (featureKey.startsWith('ls_perf_')) {
          final anyPerfSubEnabled = (_features['ls_perf_speed'] ?? false) ||
              (_features['ls_perf_delay'] ?? false) ||
              (_features['ls_perf_trend'] ?? false) ||
              (_features['ls_perf_history'] ?? false);
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
        setState(() { _features[featureKey] = currentValue; });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update setting: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLedgersEnabled = _features['ledgers'] ?? true;
    final isPerfEnabled = (_features['ls_performance'] ?? true) && isLedgersEnabled;

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (didPop) return;
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
            onPressed: () => Navigator.of(context).pop(_features),
          ),
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
