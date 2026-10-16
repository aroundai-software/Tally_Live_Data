import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../config/app_theme.dart';
import '../providers/company_provider.dart';
import '../services/supabase_service.dart';
import '../utils/admin_access.dart';
import 'admin_panel_screen.dart';
import 'login_screen.dart';
import '../providers/theme_provider.dart';
import 'profile_screen.dart';
import 'security_settings_screen.dart';
import 'theme_settings_screen.dart';

/// Clean settings hub — drill into Account Info, Password, Devices, etc.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final SupabaseService _service = SupabaseService();
  String _appVersion = '';
  String _displayName = '';
  String _role = 'owner';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final user = _service.currentUser;
      final info = await PackageInfo.fromPlatform();
      String name = 'Account';
      String role = 'owner';
      if (user != null) {
        final profile = await _service.getUserProfile(user.id);
        name = profile?['full_name']?.toString().trim().isNotEmpty == true
            ? profile!['full_name'].toString()
            : 'Business Owner';
        role = profile?['role']?.toString() ?? 'owner';
      }
      if (!mounted) return;
      setState(() {
        _appVersion = 'v${info.version}';
        _displayName = name;
        _role = role;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _handleLogout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Logout'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.errorColor,
              foregroundColor: Colors.white,
            ),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _service.signOut();
      if (!mounted) return;
      final state = CompanyProvider.of(context);
      state.clearCompany();
      state.clearUserCapabilities();
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  void _showChangePasswordDialog() {
    final newPassCtrl = TextEditingController();
    final confirmPassCtrl = TextEditingController();
    final confirmPassFocus = FocusNode();
    final formKey = GlobalKey<FormState>();
    var isSaving = false;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> submit() async {
              if (!formKey.currentState!.validate() || isSaving) return;
              setDialogState(() => isSaving = true);
              try {
                await _service.updatePassword(newPassCtrl.text.trim());
                if (!mounted) return;
                Navigator.of(ctx).pop();
                ScaffoldMessenger.of(this.context).showSnackBar(
                  const SnackBar(
                    content: Text('Password updated successfully!'),
                    backgroundColor: Colors.green,
                  ),
                );
              } catch (e) {
                setDialogState(() => isSaving = false);
                ScaffoldMessenger.of(this.context).showSnackBar(
                  SnackBar(
                    content: Text('Failed to update password: $e'),
                    backgroundColor: AppTheme.errorColor,
                  ),
                );
              }
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Row(
                children: [
                  Icon(Icons.lock_reset_rounded, color: AppTheme.primaryColor),
                  SizedBox(width: 8),
                  Text(
                    'Change Password',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              content: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: newPassCtrl,
                      obscureText: true,
                      textInputAction: TextInputAction.next,
                      onFieldSubmitted: (_) {
                        FocusScope.of(context).requestFocus(confirmPassFocus);
                      },
                      decoration: const InputDecoration(
                        labelText: 'New Password',
                        hintText: 'Enter new password',
                        prefixIcon: Icon(Icons.lock_outline),
                      ),
                      validator: (val) {
                        if (val == null || val.length < 6) {
                          return 'Password must be at least 6 characters';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: confirmPassCtrl,
                      focusNode: confirmPassFocus,
                      obscureText: true,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => submit(),
                      decoration: const InputDecoration(
                        labelText: 'Confirm New Password',
                        hintText: 'Re-enter new password',
                        prefixIcon: Icon(Icons.lock_outline),
                      ),
                      validator: (val) {
                        if (val != newPassCtrl.text) {
                          return 'Passwords do not match';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isSaving ? null : submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                  ),
                  child: isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text('Update Password'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surfaceColor,
      appBar: AppBar(
        title: Text('Settings', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: AppTheme.cardColor,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryColor))
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  children: [
                    _buildHeroCard(),
                    const SizedBox(height: 20),
                    _sectionLabel('ACCOUNT'),
                    const SizedBox(height: 8),
                    _menuCard([
                      _menuTile(
                        icon: Icons.person_outline_rounded,
                        title: 'Account Info',
                        subtitle: 'Name and phone',
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const ProfileScreen()),
                          );
                        },
                      ),
                      _menuTile(
                        icon: Icons.lock_outline_rounded,
                        title: 'Change Password',
                        subtitle: 'Update your login password',
                        onTap: _showChangePasswordDialog,
                      ),
                      _menuTile(
                        icon: Icons.devices_rounded,
                        title: 'Devices & Login',
                        subtitle: 'Current device and recent login history',
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const SecuritySettingsScreen(),
                            ),
                          );
                        },
                        showDivider: false,
                      ),
                    ]),
                    if (isSuperAdminRole(_role)) ...[
                      const SizedBox(height: 20),
                      _sectionLabel('ADMIN'),
                      const SizedBox(height: 8),
                      _menuCard([
                        _menuTile(
                          icon: Icons.admin_panel_settings_rounded,
                          title: 'Admin Control Panel',
                          subtitle: 'Manage subscriptions and users',
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const AdminPanelScreen(),
                              ),
                            );
                          },
                          showDivider: false,
                        ),
                      ]),
                    ],
                    const SizedBox(height: 20),
                    _sectionLabel('APP'),
                    const SizedBox(height: 8),
                    _menuCard([
                      _menuTile(
                        icon: Icons.brightness_6_rounded,
                        title: 'Theme',
                        subtitle: ThemeController.of(context).label,
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ThemeSettingsScreen(),
                            ),
                          ).then((_) {
                            if (mounted) setState(() {});
                          });
                        },
                      ),
                      _menuTile(
                        icon: Icons.info_outline_rounded,
                        title: 'App Version',
                        subtitle: _appVersion.isEmpty
                            ? '—'
                            : '$_appVersion (Latest)',
                        onTap: null,
                        showDivider: false,
                      ),
                    ]),
                    const SizedBox(height: 28),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: OutlinedButton.icon(
                        onPressed: _handleLogout,
                        icon: const Icon(
                          Icons.logout_rounded,
                          color: AppTheme.errorColor,
                          size: 20,
                        ),
                        label: const Text(
                          'Sign Out',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.errorColor,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                            color: AppTheme.errorColor,
                            width: 1.5,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          backgroundColor: Colors.red.withValues(alpha: 0.04),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildHeroCard() {
    final initials = _displayName.trim().isNotEmpty
        ? _displayName
            .trim()
            .split(RegExp(r'\s+'))
            .map((e) => e.isNotEmpty ? e.characters.first : '')
            .where((c) => c.isNotEmpty)
            .take(2)
            .join()
            .toUpperCase()
        : 'TL';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1A73E8), Color(0xFF0D47A1)],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryColor.withValues(alpha: 0.25),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: AppTheme.cardColor.withValues(alpha: 0.2),
            child: CircleAvatar(
              radius: 24,
              backgroundColor: AppTheme.cardColor,
              child: Text(
                initials,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.primaryColor,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _displayName,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Manage your account and security',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: AppTheme.textSecondary,
        letterSpacing: 0.8,
      ),
    );
  }

  Widget _menuCard(List<Widget> children) {
    return Material(color: AppTheme.cardColor,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.dividerColor),
        ),
        child: Column(children: children),
      ),
    );
  }

  Widget _menuTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
    bool showDivider = true,
  }) {
    return Column(
      children: [
        ListTile(
          onTap: onTap,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: AppTheme.primaryColor, size: 20),
          ),
          title: Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          subtitle: Text(
            subtitle,
            style: TextStyle(
              fontSize: 12,
              color: AppTheme.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
          trailing: onTap == null
              ? null
              : Icon(Icons.chevron_right_rounded, color: AppTheme.textSecondary),
        ),
        if (showDivider)
          Divider(height: 1, indent: 68, color: AppTheme.dividerColor),
      ],
    );
  }
}
