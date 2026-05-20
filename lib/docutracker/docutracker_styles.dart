import 'package:flutter/material.dart';
import '../landingpage/constants/app_theme.dart';

/// Shared DocuTracker design tokens matching admin/DTR patterns.
class DocuTrackerStyles {
  DocuTrackerStyles._();

  static const Color primaryGreen = Color(0xFF4CAF50);
  static const Color destructiveRed = Color(0xFFE53935);

  static InputDecoration inputDecoration(
    BuildContext context,
    String hint, [
    IconData? icon,
  ]) {
    return AppTheme.dashInputDecoration(
      context,
      hintText: hint,
      prefixIcon: icon != null
          ? Icon(icon, color: AppTheme.primaryNavy, size: 22)
          : null,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      radius: 12,
    );
  }

  static InputDecoration dropdownDecoration(BuildContext context, String hint) {
    return AppTheme.dashInputDecoration(
      context,
      hintText: hint,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      radius: 12,
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
        side: BorderSide(color: AppTheme.primaryNavy.withOpacity(0.6)),
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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        elevation: 0,
      );

  static ButtonStyle iconButtonStyle() => IconButton.styleFrom(
        foregroundColor: AppTheme.primaryNavy,
      );

  static Widget filterDropdownWrapper(Widget child) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: AppTheme.lightGray.withOpacity(0.5),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.transparent),
        ),
        child: child,
      );

  static BoxDecoration cardDecoration(BuildContext context) =>
      AppTheme.dashSurfaceCard(context, radius: 20);

  static BoxDecoration listCardDecoration(BuildContext context) =>
      AppTheme.dashSurfaceCard(context, radius: 16);
}
