import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import '../providers/company_provider.dart';
import '../services/supabase_service.dart';
import 'company_selection_screen.dart';
import 'main_shell.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final SupabaseService _service = SupabaseService();
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final rawPhone = _phoneController.text.trim();

      final authResponse = await _service.signInWithPhone(
        phone: rawPhone,
        password: _passwordController.text.trim(),
      );

      if (!mounted) return;

      final user = authResponse.user;
      if (user != null) {
        final profile = await _service.getUserProfile(user.id);
        final companyName = profile != null ? profile['company_name']?.toString() : null;

        if (!mounted) return;

        if (companyName != null && companyName.isNotEmpty) {
          CompanyProvider.of(context).selectCompany(companyName);
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const MainShell()),
          );
        } else {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const CompanySelectionScreen()),
          );
        }
      } else {
        _showError('Authentication failed. Please check your credentials.');
      }
    } catch (e) {
      if (mounted) {
        final errStr = e.toString().toLowerCase();
        if (errStr.contains('socketexception') ||
            errStr.contains('failed host lookup') ||
            errStr.contains('network') ||
            errStr.contains('clientexception') ||
            errStr.contains('connection refused') ||
            errStr.contains('timeout')) {
          _showError(
            'No internet connection. Please check your network or Wi-Fi settings and try again.',
            icon: Icons.wifi_off_rounded,
          );
        } else if (errStr.contains('invalid login credentials') ||
            errStr.contains('invalid_credentials') ||
            errStr.contains('invalid credentials') ||
            errStr.contains('400')) {
          _showError(
            'Invalid phone number or password. Please check your credentials and try again.',
            icon: Icons.lock_outline_rounded,
          );
        } else {
          _showError('Login failed: ${e.toString().replaceAll('Exception:', '').trim()}');
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showError(String message, {IconData icon = Icons.error_outline_rounded}) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              icon,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
        backgroundColor: AppTheme.errorColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _showForgotPasswordDialog() {
    final resetPhoneCtrl = TextEditingController(text: _phoneController.text.trim());
    final formKey = GlobalKey<FormState>();
    bool isSending = false;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Row(
                children: [
                  Icon(Icons.lock_reset_rounded, color: AppTheme.primaryColor),
                  SizedBox(width: 8),
                  Text('Reset Password', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
              content: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Enter your registered 10-digit mobile number to receive password reset instructions.',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: resetPhoneCtrl,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Registered Mobile Number',
                        hintText: '9876543210',
                        prefixIcon: Icon(Icons.phone_rounded),
                      ),
                      validator: (val) {
                        if (val == null || val.trim().isEmpty) {
                          return 'Please enter mobile number';
                        }
                        if (val.trim().replaceAll(RegExp(r'[^0-9]'), '').length < 10) {
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
                  onPressed: isSending ? null : () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isSending
                      ? null
                      : () async {
                          if (!formKey.currentState!.validate()) return;
                          setDialogState(() => isSending = true);
                          await Future.delayed(const Duration(milliseconds: 600));
                          if (!mounted) return;
                          Navigator.of(ctx).pop();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Password reset request sent! Check your SMS or contact system admin.'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                  ),
                  child: isSending
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Send Reset Request'),
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
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= 768;

    return Scaffold(
      backgroundColor: isDesktop ? Colors.white : AppTheme.surfaceColor,
      body: SafeArea(
        child: isDesktop ? _buildDesktopLayout() : _buildMobileLayout(),
      ),
    );
  }

  Widget _buildDesktopLayout() {
    return Row(
      children: [
        // Left Hero Panel
        Expanded(
          flex: 5,
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF0D47A1), Color(0xFF1976D2), Color(0xFF1A73E8)],
              ),
            ),
            padding: const EdgeInsets.all(48),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(Icons.analytics_rounded, color: Colors.white, size: 36),
                    ),
                    const SizedBox(width: 16),
                    const Text(
                      'TallyLive',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 36),
                const Text(
                  'Real-Time Business Analytics\n& Live Tally Portal',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Access instant sales insights, stock valuation, cashflow, and outstanding balances across all your business branches.',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withValues(alpha: 0.85),
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 40),

                // Feature Highlights
                _buildFeatureBullet(Icons.bolt_rounded, 'Live Tally Synchronization'),
                const SizedBox(height: 16),
                _buildFeatureBullet(Icons.bar_chart_rounded, 'Instant Sales & Profit Reports'),
                const SizedBox(height: 16),
                _buildFeatureBullet(Icons.verified_user_rounded, 'Secure Multi-Tenant Owner Portal'),
              ],
            ),
          ),
        ),

        // Right Form Panel
        Expanded(
          flex: 5,
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(40),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: _buildLoginForm(),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMobileLayout() {
    return SingleChildScrollView(
      child: Column(
        children: [
          // Mobile Brand Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(24, 40, 24, 32),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF0D47A1), Color(0xFF1A73E8)],
              ),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(24),
                bottomRight: Radius.circular(24),
              ),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.analytics_rounded, color: Colors.white, size: 36),
                ),
                const SizedBox(height: 12),
                const Text(
                  'TallyLive',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Colors.white),
                ),
              ],
            ),
          ),

          // Form Container
          Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: _buildLoginForm(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureBullet(IconData icon, String text) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
        const SizedBox(width: 14),
        Text(
          text,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _buildLoginForm() {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Sign In',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1A1F36),
              ),
            ),
            const SizedBox(height: 24),

            // Phone Number Input
            const Text(
              'Phone Number',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1A1F36),
              ),
            ),
            const SizedBox(height: 6),
            TextFormField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                hintText: '9876543210',
                prefixIcon: Icon(Icons.phone_rounded, size: 20),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter your phone number';
                }
                if (value.trim().replaceAll(RegExp(r'[^0-9]'), '').length < 10) {
                  return 'Enter a valid 10-digit phone number';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Password Input
            const Text(
              'Password',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1A1F36),
              ),
            ),
            const SizedBox(height: 6),
            TextFormField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              decoration: InputDecoration(
                hintText: '••••••••',
                prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    size: 20,
                    color: Colors.grey.shade500,
                  ),
                  onPressed: () {
                    setState(() => _obscurePassword = !_obscurePassword);
                  },
                ),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter your password';
                }
                if (value.length < 6) {
                  return 'Password must be at least 6 characters';
                }
                return null;
              },
            ),
            const SizedBox(height: 20),

            // Submit Button
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _handleLogin,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white,
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Sign In',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          SizedBox(width: 8),
                          Icon(Icons.arrow_forward_rounded, size: 18),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 16),

            // Register Link
            Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    "Don't have an account? ",
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                  ),
                  GestureDetector(
                    onTap: _showRegisterDialog,
                    child: const Text(
                      'Register Now',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryColor,
                      ),
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

  void _showRegisterDialog() {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool isRegistering = false;
    bool obscure = true;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Row(
                children: [
                  Icon(Icons.person_add_rounded, color: AppTheme.primaryColor),
                  SizedBox(width: 8),
                  Text('Create Account', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
              content: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Register your business owner profile to access TallyLive analytics.',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: nameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Full Name *',
                          hintText: 'John Doe',
                          prefixIcon: Icon(Icons.person_outline_rounded),
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return 'Please enter your full name';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: phoneCtrl,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: '10-Digit Mobile Number *',
                          hintText: '9876543210',
                          prefixIcon: Icon(Icons.phone_rounded),
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return 'Please enter mobile number';
                          }
                          if (val.trim().replaceAll(RegExp(r'[^0-9]'), '').length < 10) {
                            return 'Enter a valid 10-digit phone number';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: passwordCtrl,
                        obscureText: obscure,
                        decoration: InputDecoration(
                          labelText: 'Create Password *',
                          hintText: '••••••••',
                          prefixIcon: const Icon(Icons.lock_outline_rounded),
                          suffixIcon: IconButton(
                            icon: Icon(obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                            onPressed: () => setDialogState(() => obscure = !obscure),
                          ),
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return 'Please create a password';
                          }
                          if (val.length < 6) {
                            return 'Password must be at least 6 characters';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isRegistering ? null : () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isRegistering
                      ? null
                      : () async {
                          if (!formKey.currentState!.validate()) return;
                          setDialogState(() => isRegistering = true);
                          try {
                            await _service.registerUser(
                              fullName: nameCtrl.text.trim(),
                              phone: phoneCtrl.text.trim(),
                              password: passwordCtrl.text.trim(),
                            );
                            if (!mounted) return;
                            Navigator.of(ctx).pop();
                            
                            Navigator.of(context).pushReplacement(
                              MaterialPageRoute(builder: (_) => const CompanySelectionScreen()),
                            );
                          } catch (e) {
                            setDialogState(() => isRegistering = false);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Registration failed: ${e.toString().replaceAll('Exception:', '').trim()}'),
                                backgroundColor: AppTheme.errorColor,
                              ),
                            );
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                  ),
                  child: isRegistering
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Register Account'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
