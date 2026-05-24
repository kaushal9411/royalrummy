import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // Dark theme (primary)
  static const Color darkBg        = Color(0xFF0D1117);
  static const Color darkSurface   = Color(0xFF161B22);
  static const Color darkCard      = Color(0xFF21262D);
  static const Color darkBorder    = Color(0xFF30363D);
  static const Color primary       = Color(0xFF238636);
  static const Color primaryLight  = Color(0xFF2EA043);
  static const Color accent        = Color(0xFFE3B341);
  static const Color accentLight   = Color(0xFFF0C84B);
  static const Color danger        = Color(0xFFDA3633);
  static const Color textPrimary   = Color(0xFFF0F6FC);
  static const Color textSecondary = Color(0xFF8B949E);
  static const Color textMuted     = Color(0xFF484F58);
  static const Color trump         = Color(0xFF1F6FEB);
  static const Color trumpLight    = Color(0xFF388BFD);

  // Card suits
  static const Color suitRed   = Color(0xFFFF4757);
  static const Color suitBlack = Color(0xFFF0F6FC);

  // Light theme
  static const Color lightBg      = Color(0xFFF6F8FA);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightCard    = Color(0xFFF0F4F8);
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
    fontFamily: 'GameFont',
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.darkSurface,
      foregroundColor: AppColors.textPrimary,
      elevation: 0,
    ),
    cardTheme: const CardTheme(
      color:        AppColors.darkCard,
      surfaceTintColor: Colors.transparent,
      elevation:    2,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor:  AppColors.primary,
        foregroundColor:  Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.darkCard,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.darkBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.darkBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primary, width: 2),
      ),
      labelStyle: const TextStyle(color: AppColors.textSecondary),
      hintStyle:  const TextStyle(color: AppColors.textMuted),
    ),
    textTheme: const TextTheme(
      displayLarge:  TextStyle(color: AppColors.textPrimary,   fontWeight: FontWeight.bold),
      titleLarge:    TextStyle(color: AppColors.textPrimary,   fontWeight: FontWeight.bold),
      titleMedium:   TextStyle(color: AppColors.textPrimary),
      bodyLarge:     TextStyle(color: AppColors.textPrimary),
      bodyMedium:    TextStyle(color: AppColors.textSecondary),
      labelLarge:    TextStyle(color: AppColors.textPrimary,   fontWeight: FontWeight.bold),
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
    fontFamily: 'GameFont',
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.lightSurface,
      foregroundColor: Colors.black87,
      elevation: 0,
    ),
  );
}
