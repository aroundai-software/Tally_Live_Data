import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config/supabase_config.dart';
import 'config/app_theme.dart';
import 'providers/company_provider.dart';
import 'providers/theme_provider.dart';
import 'screens/splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: SupabaseConfig.supabaseUrl,
    anonKey: SupabaseConfig.supabaseAnonKey,
  );

  final themeController = ThemeController();
  await themeController.load();

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );

  runApp(TallyLiveApp(themeController: themeController));
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
  TallyLiveApp({super.key, required this.themeController});

  final ThemeController themeController;
  final CompanyState _companyState = CompanyState();

  @override
  Widget build(BuildContext context) {
    return ThemeControllerScope(
      controller: themeController,
      child: CompanyProvider(
        state: _companyState,
        child: ListenableBuilder(
          listenable: themeController,
          builder: (context, _) {
            return MaterialApp(
              title: 'TallyLive',
              debugShowCheckedModeBanner: false,
              theme: AppTheme.lightTheme,
              darkTheme: AppTheme.darkTheme,
              themeMode: themeController.mode,
              scrollBehavior: const GlassSmoothScrollBehavior(),
              builder: (context, child) {
                final brightness = Theme.of(context).brightness;
                AppTheme.bindBrightness(brightness);
                // AppTheme.* colors are static — screens that don't call Theme.of
                // won't rebuild on themeMode change. Force the navigator subtree
                // to rebuild when brightness flips (without remounting routes).
                return _ThemeRebuildGate(
                  brightness: brightness,
                  revisionListenable: AppTheme.revision,
                  child: child ?? const SizedBox.shrink(),
                );
              },
              home: const SplashScreen(),
            );
          },
        ),
      ),
    );
  }
}

/// Marks the entire app subtree dirty when brightness / AppTheme revision changes
/// so widgets using static [AppTheme] getters pick up the new palette.
class _ThemeRebuildGate extends StatefulWidget {
  const _ThemeRebuildGate({
    required this.brightness,
    required this.revisionListenable,
    required this.child,
  });

  final Brightness brightness;
  final ValueNotifier<int> revisionListenable;
  final Widget child;

  @override
  State<_ThemeRebuildGate> createState() => _ThemeRebuildGateState();
}

class _ThemeRebuildGateState extends State<_ThemeRebuildGate> {
  @override
  void initState() {
    super.initState();
    widget.revisionListenable.addListener(_onRevision);
  }

  @override
  void didUpdateWidget(covariant _ThemeRebuildGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.revisionListenable != widget.revisionListenable) {
      oldWidget.revisionListenable.removeListener(_onRevision);
      widget.revisionListenable.addListener(_onRevision);
    }
    if (oldWidget.brightness != widget.brightness) {
      _scheduleSubtreeRebuild();
    }
  }

  @override
  void dispose() {
    widget.revisionListenable.removeListener(_onRevision);
    super.dispose();
  }

  void _onRevision() => _scheduleSubtreeRebuild();

  void _scheduleSubtreeRebuild() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _dirtySubtree(context as Element);
    });
  }

  void _dirtySubtree(Element element) {
    element.markNeedsBuild();
    element.visitChildren(_dirtySubtree);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
