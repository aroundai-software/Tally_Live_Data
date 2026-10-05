import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config/supabase_config.dart';
import 'config/app_theme.dart';
import 'providers/company_provider.dart';
import 'screens/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: SupabaseConfig.supabaseUrl,
    anonKey: SupabaseConfig.supabaseAnonKey,
  );

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );

  runApp(TallyLiveApp());
}

/// Provides premium, glass-like smooth scrolling across the entire app
/// on all devices (touch, trackpad, mouse, and stylus).
class GlassSmoothScrollBehavior extends MaterialScrollBehavior {
  const GlassSmoothScrollBehavior();

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

  @override
  Widget buildOverscrollIndicator(BuildContext context, Widget child, ScrollableDetails details) {
    // Avoid harsh edge stretch / glow, preserving clean glass bounce
    return child;
  }
}

class TallyLiveApp extends StatelessWidget {
  TallyLiveApp({super.key});

  final CompanyState _companyState = CompanyState();

  @override
  Widget build(BuildContext context) {
    return CompanyProvider(
      state: _companyState,
      child: MaterialApp(
        title: 'TallyLive',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        scrollBehavior: const GlassSmoothScrollBehavior(),
        home: const SplashScreen(),
      ),
    );
  }
}
