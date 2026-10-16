import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import '../providers/company_provider.dart';
import '../services/supabase_service.dart';
import '../widgets/shimmer_loading.dart';

/// Account info only (name, phone, companies). Opened from Settings.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final SupabaseService _service = SupabaseService();
  bool _isLoading = true;

  String _fullName = '';
  List<String> _assignedCompanies = [];
  String _phone = '';
  String _companyName = '';
  String? _userId;

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
  }

  Future<void> _loadUserProfile() async {
    setState(() => _isLoading = true);
    try {
      final user = _service.currentUser;
      if (user != null) {
        _userId = user.id;
        final profile = await _service.getUserProfile(user.id);
        final assigned = await _service.getUserCompanies(user.id);
        _assignedCompanies = assigned;
        String rawPhone = '';
        if (profile != null) {
          _fullName = profile['full_name']?.toString() ?? 'Business Owner';
          rawPhone = profile['phone_number']?.toString() ??
              user.phone ??
              user.email?.split('@').first ??
              '';
          _companyName = profile['company_name']?.toString() ??
              CompanyProvider.of(context).selectedCompany ??
              '';
        } else {
          rawPhone = user.phone ?? user.email?.split('@').first ?? '';
          _companyName = CompanyProvider.of(context).selectedCompany ?? '';
        }

        if (rawPhone.startsWith('+91')) {
          rawPhone = rawPhone.substring(3);
        } else if (rawPhone.startsWith('+')) {
          rawPhone = rawPhone.substring(1);
        }
        _phone = rawPhone;
      }
    } catch (_) {
      // Offline / transient — keep last known values.
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showEditPhoneDialog() {
    final phoneCtrl = TextEditingController(text: _phone);
    final formKey = GlobalKey<FormState>();
    var isSaving = false;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Row(
                children: [
                  Icon(Icons.phone_android_rounded, color: AppTheme.primaryColor),
                  SizedBox(width: 8),
                  Text(
                    'Update Phone Number',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              content: Form(
                key: formKey,
                child: TextFormField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Phone Number',
                    hintText: '9876543210',
                    prefixIcon: Icon(Icons.phone_rounded),
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Please enter a phone number';
                    }
                    if (val.trim().replaceAll(RegExp(r'[^0-9]'), '').length < 10) {
                      return 'Enter a valid phone number';
                    }
                    return null;
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          if (!formKey.currentState!.validate()) return;
                          setDialogState(() => isSaving = true);
                          try {
                            final newPhone = phoneCtrl.text.trim();
                            final targetUserId =
                                _userId ?? _service.currentUser?.id;
                            if (targetUserId != null) {
                              await _service.updateUserPhone(
                                targetUserId,
                                newPhone,
                              );
                            }
                            if (!mounted) return;
                            Navigator.of(ctx).pop();
                            await _loadUserProfile();
                            if (!mounted) return;
                            ScaffoldMessenger.of(this.context).showSnackBar(
                              const SnackBar(
                                content: Text('Phone number updated successfully!'),
                                backgroundColor: Colors.green,
                              ),
                            );
                          } catch (e) {
                            setDialogState(() => isSaving = false);
                            ScaffoldMessenger.of(this.context).showSnackBar(
                              SnackBar(
                                content: Text('Failed to update phone: $e'),
                                backgroundColor: AppTheme.errorColor,
                              ),
                            );
                          }
                        },
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
                      : const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showEditNameDialog() {
    final nameCtrl = TextEditingController(text: _fullName);
    final formKey = GlobalKey<FormState>();
    var isSaving = false;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Row(
                children: [
                  Icon(Icons.person_outline_rounded, color: AppTheme.primaryColor),
                  SizedBox(width: 8),
                  Text(
                    'Update Full Name',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              content: Form(
                key: formKey,
                child: TextFormField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Full Name',
                    hintText: 'Dr. Rajesh Kumar',
                    prefixIcon: Icon(Icons.person),
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Please enter your name';
                    }
                    return null;
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          if (!formKey.currentState!.validate()) return;
                          setDialogState(() => isSaving = true);
                          try {
                            final newName = nameCtrl.text.trim();
                            final targetUserId =
                                _userId ?? _service.currentUser?.id;
                            if (targetUserId != null) {
                              await _service.updateUserFullName(
                                targetUserId,
                                newName,
                              );
                            }
                            if (!mounted) return;
                            Navigator.of(ctx).pop();
                            await _loadUserProfile();
                            if (!mounted) return;
                            ScaffoldMessenger.of(this.context).showSnackBar(
                              const SnackBar(
                                content: Text('Name updated successfully!'),
                                backgroundColor: Colors.green,
                              ),
                            );
                          } catch (e) {
                            setDialogState(() => isSaving = false);
                            ScaffoldMessenger.of(this.context).showSnackBar(
                              SnackBar(
                                content: Text('Failed to update name: $e'),
                                backgroundColor: AppTheme.errorColor,
                              ),
                            );
                          }
                        },
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
                      : Text('Save'),
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
        title: Text(
          'Account Info',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: AppTheme.cardColor,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadUserProfile,
          ),
        ],
      ),
      body: _isLoading
          ? const ShimmerGridLoading(itemCount: 3)
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      _buildHeaderCard(),
                      const SizedBox(height: 16),
                      _buildInfoSection(),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildHeaderCard() {
    final initials = _fullName.trim().isNotEmpty
        ? _fullName
            .trim()
            .split(RegExp(r'\s+'))
            .map((e) => e.isNotEmpty ? e.characters.first : '')
            .where((c) => c.isNotEmpty)
            .take(2)
            .join()
            .toUpperCase()
        : 'OW';
    final companyState = CompanyProvider.of(context);
    final selectedCompany = companyState.isCombinedMode
        ? 'Combined (${companyState.selectedCompanies.length} companies)'
        : (companyState.selectedCompany ?? _companyName);

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
      child: Column(
        children: [
          CircleAvatar(
            radius: 36,
            backgroundColor: AppTheme.cardColor.withValues(alpha: 0.2),
            child: CircleAvatar(
              radius: 32,
              backgroundColor: AppTheme.cardColor,
              child: Text(
                initials,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.primaryColor,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _fullName,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.business_rounded, color: Colors.white, size: 14),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    selectedCompany,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoSection() {
    return Material(color: AppTheme.cardColor,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.dividerColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'Account Information',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
            Divider(height: 1, color: AppTheme.dividerColor),
            _buildListTile(
              icon: Icons.person_outline_rounded,
              title: 'Full Name',
              subtitle: _fullName,
              onTap: _showEditNameDialog,
            ),
            Divider(height: 1, indent: 54, color: AppTheme.dividerColor),
            _buildListTile(
              icon: Icons.phone_android_rounded,
              title: 'Phone Number',
              subtitle: _phone,
              onTap: _showEditPhoneDialog,
            ),
            Divider(height: 1, indent: 54, color: AppTheme.dividerColor),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.business_rounded,
                      color: AppTheme.primaryColor,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Assigned Companies',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        SizedBox(height: 6),
                        if (_assignedCompanies.isEmpty)
                          Text(
                            _companyName,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textPrimary,
                            ),
                          )
                        else
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: _assignedCompanies.map((comp) {
                              final isSelected = comp ==
                                  CompanyProvider.of(context).selectedCompany;
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? AppTheme.primaryColor
                                          .withValues(alpha: 0.18)
                                      : (AppTheme.isDark
                                          ? const Color(0xFF243044)
                                          : Colors.grey.shade100),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: isSelected
                                        ? AppTheme.primaryColor
                                            .withValues(alpha: 0.45)
                                        : AppTheme.dividerColor,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (isSelected)
                                      const Padding(
                                        padding: EdgeInsets.only(right: 4),
                                        child: Icon(
                                          Icons.check_circle_rounded,
                                          color: AppTheme.primaryColor,
                                          size: 13,
                                        ),
                                      ),
                                    Flexible(
                                      child: Text(
                                        comp,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: isSelected
                                              ? FontWeight.w700
                                              : FontWeight.w500,
                                          color: isSelected
                                              ? AppTheme.primaryColor
                                              : AppTheme.textPrimary,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildListTile({
    required IconData icon,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
  }) {
    return ListTile(
      onTap: onTap,
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
          fontSize: 12,
          color: AppTheme.textSecondary,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppTheme.textPrimary,
        ),
      ),
      trailing: onTap != null
          ? Icon(Icons.edit_outlined, size: 18, color: AppTheme.textSecondary)
          : null,
    );
  }
}
