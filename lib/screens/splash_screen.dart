import 'dart:async';

import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../providers/company_provider.dart';
import '../services/supabase_service.dart';
import 'company_selection_screen.dart';
import 'login_screen.dart';
import 'main_shell.dart';
import 'admin_panel_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  final SupabaseService _service = SupabaseService();
  bool _animate = false;

  @override
  void initState() {
    super.initState();
    _animate = true;
    _runStartupSequence();
  }

  Future<void> _runStartupSequence() async {
    final results = await Future.wait<dynamic>([
      Future.delayed(const Duration(milliseconds: 400)),
      _resolveDestination(),
    ]);
    if (!mounted) return;
    final destination = results[1] as Widget;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => destination),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    precacheImage(const AssetImage('assets/icon/app_logo.png'), context);
  }

  Future<Widget> _resolveDestination() async {
    final session = _service.currentSession;
    if (session == null) {
      return const LoginScreen();
    }

    try {
      final user = session.user;
      final profile = await _service.getUserProfile(user.id);
      
      if (profile?['is_active'] != true) {
        await _service.signOut();
        return const LoginScreen();
      }
      // Admin Redirection check
      final role = profile != null ? profile['role']?.toString() : null;
      final email = user.email;
      final phone = profile != null ? profile['phone_number']?.toString() : user.phone;
      final cleanPhone = phone?.replaceAll(RegExp(r'[^0-9]'), '') ?? '';
      final isSuperAdmin = role == 'super_admin' || email == 'admin@tallylive.com' || cleanPhone == '97000000';

      if (isSuperAdmin) {
        return const AdminPanelScreen(isRootAdmin: true);
      }

      final companyName = profile != null ? profile['company_name']?.toString() : null;
      if (companyName != null && companyName.isNotEmpty) {
        if (mounted) {
          CompanyProvider.of(context).selectCompany(companyName);
        }
        return const MainShell();
      } else {
        return const CompanySelectionScreen();
      }
    } catch (_) {
      return const LoginScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surfaceColor,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFE8F2FF), Colors.white],
          ),
        ),
        child: Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.85, end: _animate ? 1.0 : 0.85),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutBack,
            builder: (context, scale, child) {
              return AnimatedOpacity(
                opacity: _animate ? 1 : 0,
                duration: const Duration(milliseconds: 600),
                child: Transform.scale(scale: scale, child: child),
              );
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Image.asset(
                        'assets/icon/app_logo.png',
                        width: 110,
                        height: 110,
                        fit: BoxFit.contain,
                        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                          if (wasSynchronouslyLoaded || frame != null) {
                            return child;
                          }
                          return const SizedBox(width: 110, height: 110);
                        },
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'TallyLive',
                        style: AppTheme.brandTitle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                          color: const Color(0xFF1A1F36),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Live Tally Data Portal',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                const SizedBox(
                  height: 4,
                  width: 120,
                  child: ClipRRect(
                    borderRadius: BorderRadius.all(Radius.circular(4)),
                    child: LinearProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryColor),
                      backgroundColor: Color(0xFFDFE8F4),
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
