import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // ── Core palette ────────────────────────────────────────
  static const Color darkBg        = Color(0xFF060A14);
  static const Color darkSurface   = Color(0xFF0E1624);
  static const Color darkCard      = Color(0xFF162032);
  static const Color darkBorder    = Color(0xFF1E3050);

  // Gradient stops
  static const Color gradTop       = Color(0xFF071020);
  static const Color gradMid       = Color(0xFF0B1A30);
  static const Color gradBot       = Color(0xFF060E1A);

  // Primary – emerald green
  static const Color primary       = Color(0xFF00C853);
  static const Color primaryLight  = Color(0xFF69F0AE);
  static const Color primaryDark   = Color(0xFF007E33);

  // Accent – gold
  static const Color accent        = Color(0xFFFFD600);
  static const Color accentLight   = Color(0xFFFFFF52);
  static const Color accentDark    = Color(0xFFC7A600);

  // Trump – electric blue
  static const Color trump         = Color(0xFF2979FF);
  static const Color trumpLight    = Color(0xFF82B1FF);

  // Status
  static const Color danger        = Color(0xFFFF1744);
  static const Color dangerDark    = Color(0xFFB71C1C);

  // Text
  static const Color textPrimary   = Color(0xFFF0F6FC);
  static const Color textSecondary = Color(0xFF7A8FA6);
  static const Color textMuted     = Color(0xFF3D5068);

  // Suit colors
  static const Color suitRed   = Color(0xFFE53935);
  static const Color suitBlack = Color(0xFF1A1A2E);

  // Light theme
  static const Color lightBg      = Color(0xFFF0F4F8);
  static const Color lightSurface = Color(0xFFFFFFFF);

  // Glow helpers
  static Color primaryGlow(double opacity) => primary.withValues(alpha: opacity);
  static Color accentGlow(double opacity)  => accent.withValues(alpha: opacity);
  static Color dangerGlow(double opacity)  => danger.withValues(alpha: opacity);
}

class AppTheme {
  AppTheme._();

  static ThemeData get dark => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.darkBg,
    colorScheme: const ColorScheme.dark(
      primary:   AppColors.primary,
      secondary: AppColors.accent,
      surface:   AppColors.darkSurface,
      error:     AppColors.danger,
      onPrimary: Colors.white,
      onSurface: AppColors.textPrimary,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.darkSurface,
      foregroundColor: AppColors.textPrimary,
      elevation: 0,
      centerTitle: true,
    ),
    cardTheme: const CardThemeData(
      color:            AppColors.darkCard,
      surfaceTintColor: Colors.transparent,
      elevation:        4,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        shadowColor:     AppColors.primaryGlow(0.5),
        elevation:       6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
        textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 0.5),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.textPrimary,
        side: const BorderSide(color: AppColors.darkBorder),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled:    true,
      fillColor: AppColors.darkCard,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.darkBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.darkBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.danger),
      ),
      labelStyle:      const TextStyle(color: AppColors.textSecondary),
      hintStyle:       const TextStyle(color: AppColors.textMuted),
      prefixIconColor: AppColors.textSecondary,
      suffixIconColor: AppColors.textSecondary,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
    ),
    textTheme: const TextTheme(
      displayLarge: TextStyle(color: AppColors.textPrimary,   fontWeight: FontWeight.w800, letterSpacing: -0.5),
      titleLarge:   TextStyle(color: AppColors.textPrimary,   fontWeight: FontWeight.bold),
      titleMedium:  TextStyle(color: AppColors.textPrimary,   fontWeight: FontWeight.w600),
      bodyLarge:    TextStyle(color: AppColors.textPrimary),
      bodyMedium:   TextStyle(color: AppColors.textSecondary),
      labelLarge:   TextStyle(color: AppColors.textPrimary,   fontWeight: FontWeight.bold),
    ),
    tabBarTheme: const TabBarThemeData(
      indicatorColor: AppColors.accent,
      labelColor:     AppColors.textPrimary,
      unselectedLabelColor: AppColors.textSecondary,
    ),
    dividerTheme: const DividerThemeData(color: AppColors.darkBorder, thickness: 1),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.darkCard,
      contentTextStyle: const TextStyle(color: AppColors.textPrimary),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      behavior: SnackBarBehavior.floating,
    ),
  );

  static ThemeData get light => ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: AppColors.lightBg,
    colorScheme: const ColorScheme.light(
      primary:   AppColors.primary,
      secondary: AppColors.accent,
      surface:   AppColors.lightSurface,
    ),
  );
}
