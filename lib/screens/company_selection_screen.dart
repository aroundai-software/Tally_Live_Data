import 'package:flutter/material.dart';
import '../utils/error_handler.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../config/app_theme.dart';
import '../services/supabase_service.dart';
import '../services/user_preferences_service.dart';
import '../providers/company_provider.dart';
import 'main_shell.dart';
import 'login_screen.dart';

class CompanySelectionScreen extends StatefulWidget {
  final bool isSwitching;
  const CompanySelectionScreen({super.key, this.isSwitching = false});

  @override
  State<CompanySelectionScreen> createState() => _CompanySelectionScreenState();
}

class _CompanySelectionScreenState extends State<CompanySelectionScreen> {
  final SupabaseService _service = SupabaseService();
  List<String> _companies = [];
  bool _isLoading = true;
  String? _error;
  String? _appVersion;

  @override
  void initState() {
    super.initState();
    _loadCompanies();
    _loadVersion();
  }

  Future<void> _loadCompanies() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final user = _service.currentUser;
      final companies = user != null ? await _service.getUserCompanies(user.id) : await _service.getCompanies();
      if (mounted) {
        setState(() { _companies = companies; _isLoading = false; });
        // Auto-skip if not switching and exactly one company
        if (!widget.isSwitching && companies.length == 1) {
          _selectCompany(companies.first);
          return;
        }
        // Auto-restore last selected company if not switching
        if (!widget.isSwitching && companies.length > 1) {
          final lastCompany = await UserPreferencesService.loadLastCompany();
          if (lastCompany != null && companies.contains(lastCompany) && mounted) {
            _selectCompany(lastCompany);
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() { _error = AppErrorHandler.getFriendlyError(e); _isLoading = false; });
      }
    }
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        _appVersion = 'v${info.version}';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _appVersion = 'v2.0.2';
      });
    }
  }

  void _selectCompany(String company) {
    UserPreferencesService.saveLastCompany(company);
    CompanyProvider.of(context).selectCompany(company);
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const MainShell()),
    );
  }

  void _showLinkCompanyDialog() {
    final nameCtrl = TextEditingController();
    final mobileCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool isLinking = false;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Row(
                children: [
                  Icon(Icons.add_business_rounded, color: AppTheme.primaryColor),
                  SizedBox(width: 8),
                  Text('Link New Company', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
              content: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Enter the exact Tally company name and registered mobile number to link it to your account.',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Company Name',
                        hintText: '',
                        prefixIcon: Icon(Icons.business_rounded),
                      ),
                      validator: (val) {
                        if (val == null || val.trim().isEmpty) {
                          return 'Please enter exact company name';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: mobileCtrl,
                      keyboardType: TextInputType.phone,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(10),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Registered Mobile Number',
                        hintText: '9447000111',
                        prefixIcon: Icon(Icons.phone_rounded),
                      ),
                      validator: (val) {
                        if (val == null || val.trim().isEmpty) {
                          return 'Please enter registered mobile number';
                        }
                        if (val.trim().length != 10) {
                          return 'Enter a valid 10-digit phone number';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isLinking ? null : () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isLinking
                      ? null
                      : () async {
                          if (!formKey.currentState!.validate()) return;
                          setDialogState(() => isLinking = true);
                          try {
                            final user = _service.currentUser;
                            if (user != null) {
                              final linkedName = await _service.linkCompanyToUser(
                                userId: user.id,
                                companyName: nameCtrl.text.trim(),
                                mobileNumber: mobileCtrl.text.trim(),
                              );
                              if (!mounted) return;
                              Navigator.of(ctx).pop();
                              await _loadCompanies();
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Successfully linked $linkedName!'),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            }
                          } catch (e) {
                            setDialogState(() => isLinking = false);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(e.toString().replaceAll('Exception:', '').trim()),
                                backgroundColor: AppTheme.errorColor,
                              ),
                            );
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                  ),
                  child: isLinking
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Link Company'),
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
    final selectedCompany = CompanyProvider.of(context).selectedCompany;
    final showBackButton = widget.isSwitching || (selectedCompany != null && selectedCompany.isNotEmpty) || _companies.isNotEmpty;

    return Scaffold(
      backgroundColor: AppTheme.surfaceColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: showBackButton
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF1A1F36)),
                tooltip: 'Back to Dashboard',
                onPressed: () {
                  final provider = CompanyProvider.of(context);
                  if ((provider.selectedCompany == null || provider.selectedCompany!.isEmpty) && _companies.isNotEmpty) {
                    provider.selectCompany(_companies.first);
                  }
                  if (Navigator.of(context).canPop()) {
                    Navigator.of(context).pop();
                  } else {
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(builder: (_) => const MainShell()),
                    );
                  }
                },
              )
            : null,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: Color(0xFF1A1F36)),
            tooltip: 'Log Out',
            onPressed: () async {
              await _service.signOut();
              if (!mounted) return;
              CompanyProvider.of(context).clearCompany();
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              );
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            SizedBox(height: showBackButton ? 0 : 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    'assets/icon/app_icon.png',
                    width: 68,
                    height: 68,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(width: 14),
                  const Text(
                    'TallyLive',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                      color: Color(0xFF1A1F36),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Select Company',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Color(0xFF1A1F36)),
            ),
            const SizedBox(height: 6),
            Text(
              'Choose a Tally company to view its data',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 16),
            Expanded(child: _buildBody()),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _showLinkCompanyDialog,
                  icon: const Icon(Icons.add_business_rounded, color: AppTheme.primaryColor),
                  label: const Text(
                    '+ Link New Company',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.primaryColor),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppTheme.primaryColor, width: 1.5),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                '© ${DateTime.now().year} Around AI • ${_appVersion ?? 'v2.0.2'}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded, size: 48, color: Colors.red.shade300),
              const SizedBox(height: 16),
              Text('Failed to load companies', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.red.shade700)),
              const SizedBox(height: 8),
              Text(_error!, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _loadCompanies,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (_companies.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.business_outlined, size: 48, color: Colors.grey.shade300),
              const SizedBox(height: 16),
              const Text('No companies found', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF1A1F36))),
              const SizedBox(height: 8),
              Text('Sync data from Tally to get started', style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _loadCompanies,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Refresh'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      itemCount: _companies.length,
      itemBuilder: (context, index) {
        final company = _companies[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              onTap: () => _selectCompany(company),
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _companyColor(index).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.business_rounded, color: _companyColor(index), size: 24),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        company,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF1A1F36)),
                      ),
                    ),
                    Icon(Icons.arrow_forward_ios_rounded, size: 16, color: Colors.grey.shade400),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Color _companyColor(int index) {
    final colors = [
      AppTheme.primaryColor,
      AppTheme.salesColor,
      AppTheme.stockColor,
      AppTheme.receivableColor,
      const Color(0xFF7C4DFF),
      const Color(0xFFFF6D00),
    ];
    return colors[index % colors.length];
  }
}
