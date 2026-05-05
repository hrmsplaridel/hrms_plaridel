import 'package:flutter/material.dart';
import '../landingpage/constants/app_theme.dart';
import 'theme/docutracker_tokens.dart';

/// Shared DocuTracker design tokens matching admin/DTR patterns.
class DocuTrackerStyles {
  DocuTrackerStyles._();

  static const Color primaryGreen = Color(0xFF4CAF50);
  static const Color destructiveRed = Color(0xFFE53935);

  static InputDecoration inputDecoration(String hint, [IconData? icon]) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: icon != null
          ? Icon(icon, color: AppTheme.primaryNavy, size: 22)
          : null,
      filled: true,
      fillColor: AppTheme.offWhite,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.08)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppTheme.primaryNavy, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }

  static InputDecoration dropdownDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: AppTheme.offWhite,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.08)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppTheme.primaryNavy, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }

  static ButtonStyle primaryButtonStyle() => FilledButton.styleFrom(
        backgroundColor: primaryGreen,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        elevation: 0,
      );

  static ButtonStyle primaryButtonStyleNavy() => FilledButton.styleFrom(
        backgroundColor: AppTheme.primaryNavy,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        elevation: 0,
      );

  static ButtonStyle outlinedButtonStyle() => OutlinedButton.styleFrom(
        foregroundColor: AppTheme.textPrimary,
        side: BorderSide(color: AppTheme.primaryNavy.withValues(alpha: 0.6)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      );

  static ButtonStyle outlinedGreenStyle() => OutlinedButton.styleFrom(
        foregroundColor: primaryGreen,
        side: const BorderSide(color: primaryGreen),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      );

  static ButtonStyle outlinedRedStyle() => OutlinedButton.styleFrom(
        foregroundColor: destructiveRed,
        side: const BorderSide(color: destructiveRed),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      );

  static ButtonStyle destructiveButtonStyle() => FilledButton.styleFrom(
        backgroundColor: destructiveRed,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        elevation: 0,
      );

  static ButtonStyle approveButtonStyle() => FilledButton.styleFrom(
        backgroundColor: primaryGreen,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        elevation: 0,
      );

  // Blue filled — Forward action
  static ButtonStyle forwardButtonStyle() => FilledButton.styleFrom(
        backgroundColor: const Color(0xFF3B5BDB),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        elevation: 0,
      );

  // Subtle text — Return action (least destructive)
  static ButtonStyle returnButtonStyle() => TextButton.styleFrom(
        foregroundColor: const Color(0xFF6B7280),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      );

  static ButtonStyle iconButtonStyle() => IconButton.styleFrom(
        foregroundColor: AppTheme.primaryNavy,
      );

  static Widget filterDropdownWrapper(Widget child) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFF8F9FB),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE4E7ED)),
        ),
        child: child,
      );

  static BoxDecoration cardDecoration() => DocuTrackerTokens.cardDecoration();

  static BoxDecoration listCardDecoration() => DocuTrackerTokens.cardDecoration();
}
