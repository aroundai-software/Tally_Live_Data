import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static bool _isDark = false;
  static int _revision = 0;

  /// Bumps whenever [bindBrightness] changes light/dark. Used to force UI rebuilds.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// Call from [MaterialApp.builder] so static palette getters match the active theme.
  /// Returns true when the active palette flipped.
  static bool bindBrightness(Brightness brightness) {
    final next = brightness == Brightness.dark;
    if (_isDark == next) return false;
    _isDark = next;
    _revision++;
    revision.value = _revision;
    return true;
  }

  static bool get isDark => _isDark;
  static int get revisionValue => _revision;

  static const Color primaryColor = Color(0xFF1A73E8);
  static const Color secondaryColor = Color(0xFF4CAF50);
  static const Color accentColor = Color(0xFFFF6D00);
  static const Color errorColor = Color(0xFFE53935);
  static const Color receivableColor = Color(0xFF2196F3);
  static const Color payableColor = Color(0xFFFF5722);
  static const Color stockColor = Color(0xFF9C27B0);
  static const Color salesColor = Color(0xFF00BCD4);
  static const Color purchaseColor = Color(0xFF8E24AA);

  // Light palette
  static const Color lightSurface = Color(0xFFF8F9FE);
  static const Color lightCard = Colors.white;
  static const Color lightTextPrimary = Color(0xFF1A1F36);
  static const Color lightTextSecondary = Color(0xFF6B7280);
  static const Color lightDivider = Color(0xFFE5E7EB);

  // Dark palette
  static const Color darkSurface = Color(0xFF0F1419);
  static const Color darkCard = Color(0xFF1A2332);
  static const Color darkTextPrimary = Color(0xFFF1F5F9);
  static const Color darkTextSecondary = Color(0xFF94A3B8);
  static const Color darkDivider = Color(0xFF2A3544);

  /// Adaptive — switches with [bindBrightness].
  static Color get surfaceColor => _isDark ? darkSurface : lightSurface;
  static Color get cardColor => _isDark ? darkCard : lightCard;
  static Color get textPrimary => _isDark ? darkTextPrimary : lightTextPrimary;
  static Color get textSecondary =>
      _isDark ? darkTextSecondary : lightTextSecondary;
  static Color get dividerColor => _isDark ? darkDivider : lightDivider;

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryColor,
        primary: primaryColor,
        secondary: secondaryColor,
        error: errorColor,
        surface: lightSurface,
      ),
      scaffoldBackgroundColor: lightSurface,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: ZoomPageTransitionsBuilder(),
          TargetPlatform.iOS: ZoomPageTransitionsBuilder(),
          TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
        },
      ),
      textTheme: GoogleFonts.interTextTheme().copyWith(
        headlineLarge: GoogleFonts.inter(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          color: lightTextPrimary,
        ),
        headlineMedium: GoogleFonts.inter(
          fontSize: 22,
          fontWeight: FontWeight.w600,
          color: lightTextPrimary,
        ),
        headlineSmall: GoogleFonts.inter(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: lightTextPrimary,
        ),
        titleLarge: GoogleFonts.inter(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: lightTextPrimary,
        ),
        titleMedium: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: lightTextPrimary,
        ),
        bodyLarge: GoogleFonts.inter(
          fontSize: 16,
          fontWeight: FontWeight.w400,
          color: lightTextPrimary,
        ),
        bodyMedium: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: lightTextSecondary,
        ),
        bodySmall: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w400,
          color: lightTextSecondary,
        ),
        labelLarge: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: primaryColor,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: lightCard,
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: false,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: lightTextPrimary,
        ),
        iconTheme: IconThemeData(color: lightTextPrimary),
      ),
      cardTheme: CardThemeData(
        color: lightCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: lightDivider, width: 1),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: lightCard,
        selectedItemColor: primaryColor,
        unselectedItemColor: lightTextSecondary,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w400,
        ),
      ),
      dividerColor: lightDivider,
      dialogTheme: DialogThemeData(
        backgroundColor: lightCard,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: lightCard,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: lightDivider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: lightDivider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: primaryColor, width: 2),
        ),
        hintStyle: GoogleFonts.inter(
          fontSize: 14,
          color: lightTextSecondary,
        ),
      ),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryColor,
        brightness: Brightness.dark,
        primary: primaryColor,
        secondary: secondaryColor,
        error: errorColor,
        surface: darkSurface,
      ),
      scaffoldBackgroundColor: darkSurface,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: ZoomPageTransitionsBuilder(),
          TargetPlatform.iOS: ZoomPageTransitionsBuilder(),
          TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
        },
      ),
      textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme).copyWith(
        headlineLarge: GoogleFonts.inter(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          color: darkTextPrimary,
        ),
        headlineMedium: GoogleFonts.inter(
          fontSize: 22,
          fontWeight: FontWeight.w600,
          color: darkTextPrimary,
        ),
        headlineSmall: GoogleFonts.inter(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: darkTextPrimary,
        ),
        titleLarge: GoogleFonts.inter(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: darkTextPrimary,
        ),
        titleMedium: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: darkTextPrimary,
        ),
        bodyLarge: GoogleFonts.inter(
          fontSize: 16,
          fontWeight: FontWeight.w400,
          color: darkTextPrimary,
        ),
        bodyMedium: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: darkTextSecondary,
        ),
        bodySmall: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w400,
          color: darkTextSecondary,
        ),
        labelLarge: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: primaryColor,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: darkCard,
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: false,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: darkTextPrimary,
        ),
        iconTheme: IconThemeData(color: darkTextPrimary),
      ),
      cardTheme: CardThemeData(
        color: darkCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: darkDivider, width: 1),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: darkCard,
        selectedItemColor: primaryColor,
        unselectedItemColor: darkTextSecondary,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w400,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: darkCard,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: darkTextPrimary,
        ),
        contentTextStyle: GoogleFonts.inter(
          fontSize: 14,
          color: darkTextSecondary,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: darkCard,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: darkDivider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: darkDivider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: primaryColor, width: 2),
        ),
        hintStyle: GoogleFonts.inter(
          fontSize: 14,
          color: darkTextSecondary,
        ),
      ),
      dividerColor: darkDivider,
      listTileTheme: const ListTileThemeData(
        textColor: darkTextPrimary,
        iconColor: darkTextSecondary,
      ),
    );
  }

  static TextStyle brandTitle({
    double fontSize = 28,
    Color? color,
    FontWeight fontWeight = FontWeight.w800,
    double letterSpacing = 0.5,
  }) {
    return GoogleFonts.playfairDisplay(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color ?? textPrimary,
      letterSpacing: letterSpacing,
    );
  }

  /// Theme for [showDateRangePicker] / date dialogs — keeps light & dark readable.
  static ThemeData datePickerOverlayTheme(
    BuildContext context, {
    Color? primary,
  }) {
    final base = Theme.of(context);
    final dark = base.brightness == Brightness.dark;
    final accent = primary ?? primaryColor;
    return base.copyWith(
      colorScheme: base.colorScheme.copyWith(
        primary: accent,
        onPrimary: Colors.white,
        surface: dark ? darkCard : lightCard,
        onSurface: dark ? darkTextPrimary : lightTextPrimary,
        onSurfaceVariant: dark ? darkTextSecondary : lightTextSecondary,
      ),
      textTheme: base.textTheme.apply(
        bodyColor: dark ? darkTextPrimary : lightTextPrimary,
        displayColor: dark ? darkTextPrimary : lightTextPrimary,
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: dark ? darkCard : lightCard,
        headerBackgroundColor: accent,
        headerForegroundColor: Colors.white,
        rangeSelectionBackgroundColor: accent.withValues(alpha: dark ? 0.35 : 0.2),
        dayForegroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return Colors.white;
          if (states.contains(WidgetState.disabled)) {
            return (dark ? darkTextSecondary : lightTextSecondary)
                .withValues(alpha: 0.4);
          }
          return dark ? darkTextPrimary : lightTextPrimary;
        }),
        rangePickerHeaderForegroundColor: Colors.white,
        todayForegroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return Colors.white;
          return accent;
        }),
        weekdayStyle: TextStyle(
          color: dark ? darkTextSecondary : lightTextSecondary,
          fontWeight: FontWeight.w600,
        ),
        yearStyle: TextStyle(
          color: dark ? darkTextPrimary : lightTextPrimary,
        ),
      ),
    );
  }
}
