import 'package:flutter/material.dart';

/// Government-standard HRMS theme constants.
/// Orange and white color scheme, professional typography.
class AppTheme {
  AppTheme._();

  // Primary colors - Orange theme
  static const Color primaryNavy = Color(0xFFE85D04);
  static const Color primaryNavyDark = Color(0xFFBF360C);
  static const Color primaryNavyLight = Color(0xFFFF9800);
  static const Color white = Color(0xFFFFFFFF);

  // Letterhead (government header) - navy for Republic/Province/Municipality text
  static const Color letterheadNavy = Color(0xFF1A237E);
  static const Color letterheadOrange = Color(0xFFE85D04);
  static const Color offWhite = Color(0xFFF8F9FA);
  static const Color lightGray = Color(0xFFE9ECEF);
  static const Color textPrimary = Color(0xFF212529);
  static const Color textSecondary = Color(0xFF495057);

  // Section background alternation
  static const Color sectionAlt = Color(0xFFF1F3F5);

  // Typography
  static const String fontFamily = 'Roboto';
  static const double heroTitleSize = 32.0;
  static const double sectionTitleSize = 24.0;
  static const double cardTitleSize = 18.0;
  static const double bodySize = 16.0;
  static const double smallSize = 14.0;

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryNavy,
        primary: primaryNavy,
        secondary: primaryNavyLight,
        surface: white,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: white,
      appBarTheme: const AppBarTheme(
        backgroundColor: primaryNavy,
        foregroundColor: white,
        elevation: 0,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryNavy,
          foregroundColor: white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
          ),
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryNavy,
          side: const BorderSide(color: primaryNavy),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ),
      cardTheme: CardThemeData(
        color: white,
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
        ),
        margin: EdgeInsets.zero,
      ),
    );
  }
}
