import 'package:flutter/material.dart';

/// Theme and colors for the login screen.
/// Blue/white scheme for branding panel and form accents.
class LoginTheme {
  LoginTheme._();

  // Blue palette (branding & primary actions)
  static const Color bluePrimary = Color(0xFF1E88E5);
  static const Color blueDark = Color(0xFF1565C0);
  static const Color blueLight = Color(0xFF42A5F5);
  static const Color brandingGradientStart = Color(0xFF0D47A1);
  static const Color brandingGradientEnd = Color(0xFF1976D2);

  // Form
  static const Color formBackground = Color(0xFFFFFFFF);
  static const Color borderLight = Color(0xFFE0E0E0);
  static const Color textDark = Color(0xFF212121);
  static const Color textSecondary = Color(0xFF757575);

  // Legacy (for any remaining orange accents)
  static const Color orange = Color(0xFFE85D04);
  static const Color orangeLight = Color(0xFFF57C00);
}
