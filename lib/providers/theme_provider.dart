import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/user_preferences_service.dart';

class ThemeController extends ChangeNotifier {
  ThemeMode _mode = ThemeMode.system;

  ThemeMode get mode => _mode;

  String get label {
    switch (_mode) {
      case ThemeMode.light:
        return 'Light';
      case ThemeMode.dark:
        return 'Dark';
      case ThemeMode.system:
        return 'System default';
    }
  }

  Future<void> load() async {
    final stored = await UserPreferencesService.loadThemeMode();
    _mode = _fromStorage(stored);
    _applySystemUiOverlay();
    notifyListeners();
  }

  Future<void> setMode(ThemeMode mode) async {
    if (_mode == mode) return;
    _mode = mode;
    await UserPreferencesService.saveThemeMode(_toStorage(mode));
    _applySystemUiOverlay();
    notifyListeners();
  }

  void _applySystemUiOverlay() {
    final brightness = switch (_mode) {
      ThemeMode.light => Brightness.dark,
      ThemeMode.dark => Brightness.light,
      ThemeMode.system =>
        WidgetsBinding.instance.platformDispatcher.platformBrightness ==
                Brightness.dark
            ? Brightness.light
            : Brightness.dark,
    };
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: brightness,
        statusBarBrightness:
            brightness == Brightness.light ? Brightness.dark : Brightness.light,
      ),
    );
  }

  static String _toStorage(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }

  static ThemeMode _fromStorage(String? value) {
    switch (value) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  static ThemeController of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<ThemeControllerScope>();
    assert(scope != null, 'ThemeController not found in context');
    return scope!.controller;
  }
}

class ThemeControllerScope extends InheritedNotifier<ThemeController> {
  const ThemeControllerScope({
    super.key,
    required this.controller,
    required super.child,
  }) : super(notifier: controller);

  final ThemeController controller;
}
