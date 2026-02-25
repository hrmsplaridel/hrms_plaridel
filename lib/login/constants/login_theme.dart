import 'package:flutter/material.dart';

/// Theme and colors for the login screen.
/// Orange/white scheme for branding panel and form accents.
class LoginTheme {
  LoginTheme._();

  // Orange palette (branding & primary actions)
  static const Color bluePrimary = Color(0xFFE85D04);
  static const Color blueDark = Color(0xFFBF360C);
  static const Color blueLight = Color(0xFFFF9800);
  static const Color brandingGradientStart = Color(0xFFBF360C);
  static const Color brandingGradientEnd = Color(0xFFE85D04);

  // Form
  static const Color formBackground = Color(0xFFFFFFFF);
  static const Color borderLight = Color(0xFFE0E0E0);
  static const Color textDark = Color(0xFF212121);
  static const Color textSecondary = Color(0xFF757575);

  // Orange accents
  static const Color orange = Color(0xFFE85D04);
  static const Color orangeLight = Color(0xFFFF9800);
}
