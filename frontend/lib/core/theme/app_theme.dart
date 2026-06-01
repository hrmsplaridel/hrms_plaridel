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

  /// Neutral main-area background for admin / employee portal content.
  static const Color dashCanvas = Color(0xFFF4F5F7);

  /// Hairline borders for minimal dashboard cards and chrome.
  static const Color dashHairline = Color(0xFFE8EAED);

  static bool dashIsDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color dashCanvasOf(BuildContext context) =>
      dashIsDark(context) ? const Color(0xFF12151C) : dashCanvas;

  static Color dashPanelOf(BuildContext context) =>
      dashIsDark(context) ? const Color(0xFF1A1F2A) : white;

  static Color dashHairlineOf(BuildContext context) =>
      dashIsDark(context) ? const Color(0xFF343B4A) : dashHairline;

  static Color dashMutedSurfaceOf(BuildContext context) =>
      dashIsDark(context) ? const Color(0xFF242A36) : offWhite;

  static Color dashTextPrimaryOf(BuildContext context) =>
      dashIsDark(context) ? const Color(0xFFEEF1F5) : textPrimary;

  static Color dashTextSecondaryOf(BuildContext context) =>
      dashIsDark(context) ? const Color(0xFFB0B8C4) : textSecondary;

  static Color sectionAltOf(BuildContext context) =>
      dashIsDark(context) ? const Color(0xFF12151C) : sectionAlt;

  /// Filled input / dropdown background.
  static Color dashInputFillOf(BuildContext context) =>
      dashIsDark(context) ? const Color(0xFF242A36) : offWhite;

  static Color dashInputBorderOf(BuildContext context) =>
      dashIsDark(context) ? const Color(0xFF3D4451) : dashHairline;

  static TextStyle dashFieldTextStyle(BuildContext context) =>
      TextStyle(color: dashTextPrimaryOf(context), fontSize: 16);

  static TextStyle dashFieldHintStyle(BuildContext context) => TextStyle(
    color: dashTextSecondaryOf(context).withValues(alpha: 0.9),
    fontSize: 14,
  );

  /// Theme-aware filled outline field (profile, settings, forms).
  static InputDecoration dashInputDecoration(
    BuildContext context, {
    String? labelText,
    String? hintText,
    String? helperText,
    Widget? prefixIcon,
    Widget? suffixIcon,
    EdgeInsetsGeometry? contentPadding,
    bool isDense = true,
    double radius = 14,
  }) {
    final borderRadius = BorderRadius.circular(radius);
    final borderColor = dashInputBorderOf(context);
    return InputDecoration(
      labelText: labelText,
      hintText: hintText,
      helperText: helperText,
      labelStyle: TextStyle(color: dashTextSecondaryOf(context)),
      hintStyle: dashFieldHintStyle(context),
      helperStyle: TextStyle(fontSize: 12, color: dashTextSecondaryOf(context)),
      floatingLabelStyle: TextStyle(
        color: dashTextPrimaryOf(context),
        fontWeight: FontWeight.w600,
      ),
      filled: true,
      fillColor: dashInputFillOf(context),
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      border: OutlineInputBorder(
        borderRadius: borderRadius,
        borderSide: BorderSide(color: borderColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: borderRadius,
        borderSide: BorderSide(color: borderColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: borderRadius,
        borderSide: const BorderSide(color: primaryNavy, width: 2),
      ),
      contentPadding: contentPadding,
      isDense: isDense,
    );
  }

  static InputDecorationTheme _inputDecorationTheme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final fill = dark ? const Color(0xFF242A36) : offWhite;
    final border = dark ? const Color(0xFF3D4451) : dashHairline;
    final label = dark ? const Color(0xFFB0B8C4) : textSecondary;
    final hint = dark ? const Color(0xFF8B939E) : textSecondary;
    final floating = dark ? const Color(0xFFEEF1F5) : textPrimary;
    final radius = BorderRadius.circular(14);
    return InputDecorationTheme(
      filled: true,
      fillColor: fill,
      labelStyle: TextStyle(color: label),
      hintStyle: TextStyle(color: hint),
      floatingLabelStyle: TextStyle(
        color: floating,
        fontWeight: FontWeight.w600,
      ),
      border: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: const BorderSide(color: primaryNavy, width: 2),
      ),
    );
  }

  /// White card with light border and subtle depth (dashboard panels).
  static BoxDecoration dashSurfaceCard(
    BuildContext context, {
    double radius = 16,
  }) {
    final dark = dashIsDark(context);
    return BoxDecoration(
      color: dark ? const Color(0xFF1E2430) : white,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: dashHairlineOf(context)),
      boxShadow: [
        BoxShadow(
          color: dark
              ? Colors.black.withValues(alpha: 0.35)
              : Colors.black.withValues(alpha: 0.028),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ],
    );
  }

  static TextStyle dashSectionTitle(BuildContext context) => TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.12,
    color: dashTextSecondaryOf(context),
    height: 1.25,
  );

  // Section background alternation
  static const Color sectionAlt = Color(0xFFF1F3F5);

  /// Standard depth for section strips and large white panels.
  static List<BoxShadow> get panelShadow => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.085),
      blurRadius: 26,
      offset: const Offset(0, 10),
    ),
    BoxShadow(
      color: primaryNavy.withValues(alpha: 0.075),
      blurRadius: 20,
      offset: const Offset(0, 5),
    ),
  ];

  /// Slightly softer shadow for nested cards and dense grids.
  static List<BoxShadow> get cardShadow => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.07),
      blurRadius: 16,
      offset: const Offset(0, 7),
    ),
    BoxShadow(
      color: primaryNavy.withValues(alpha: 0.06),
      blurRadius: 12,
      offset: const Offset(0, 3),
    ),
  ];

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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryNavy,
          side: const BorderSide(color: primaryNavy),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        ),
      ),
      cardTheme: CardThemeData(
        color: white,
        elevation: 2,
        shadowColor: Colors.black.withValues(alpha: 0.1),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: _inputDecorationTheme(Brightness.light),
      dropdownMenuTheme: const DropdownMenuThemeData(
        textStyle: TextStyle(color: textPrimary, fontSize: 16),
      ),
    );
  }

  static ThemeData get darkTheme {
    const surface = Color(0xFF1A1F2A);
    const canvas = Color(0xFF12151C);
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.dark(
        primary: primaryNavyLight,
        onPrimary: Colors.black,
        secondary: primaryNavy,
        onSecondary: white,
        surface: surface,
        onSurface: Color(0xFFE8EAED),
        outline: Color(0xFF3D4451),
        error: Color(0xFFFFB4AB),
      ),
      scaffoldBackgroundColor: canvas,
      appBarTheme: const AppBarTheme(
        backgroundColor: surface,
        foregroundColor: Color(0xFFE8EAED),
        elevation: 0,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryNavy,
          foregroundColor: white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryNavyLight,
          side: const BorderSide(color: primaryNavyLight),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        ),
      ),
      cardTheme: CardThemeData(
        color: const Color(0xFF1E2430),
        elevation: 2,
        shadowColor: Colors.black.withValues(alpha: 0.4),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: _inputDecorationTheme(Brightness.dark),
      dropdownMenuTheme: const DropdownMenuThemeData(
        textStyle: TextStyle(color: Color(0xFFEEF1F5), fontSize: 16),
      ),
      listTileTheme: const ListTileThemeData(
        textColor: Color(0xFFEEF1F5),
        iconColor: primaryNavyLight,
      ),
    );
  }
}
