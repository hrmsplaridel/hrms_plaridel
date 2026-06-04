import 'package:flutter/material.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/docutracker/theme/docutracker_tokens.dart';

/// Shared DocuTracker design tokens matching admin/DTR patterns.
class DocuTrackerStyles {
  DocuTrackerStyles._();

  static const Color primaryGreen = Color(0xFF4CAF50);
  static const Color destructiveRed = Color(0xFFE53935);
  static const Color warningOrange = Color(0xFFF59E0B);
  static const Color secondaryBlue = Color(0xFF3B82F6);
  static const EdgeInsets panelPadding = EdgeInsets.all(16);

  static TextStyle cardLabelStyle({Color? color}) => TextStyle(
    color: color ?? AppTheme.textSecondary,
    fontSize: 11.5,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.2,
  );

  static TextStyle cardValueStyle({Color? color}) => TextStyle(
    color: color ?? AppTheme.textPrimary,
    fontSize: 22,
    fontWeight: FontWeight.w800,
    height: 1.15,
  );

  static TextStyle cardMetaStyle({Color? color}) => TextStyle(
    color: (color ?? AppTheme.textSecondary).withValues(alpha: 0.92),
    fontSize: 11.5,
    height: 1.3,
    fontWeight: FontWeight.w500,
  );

  static InputDecoration inputDecoration(
    BuildContext context,
    String hint, [
    IconData? icon,
  ]) {
    return AppTheme.dashInputDecoration(
      context,
      hintText: hint,
      prefixIcon: icon != null
          ? Icon(icon, color: DocuTrackerTokens.brand, size: 22)
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

  /// Green primary (approve / success actions).
  static ButtonStyle primaryButtonStyle() => FilledButton.styleFrom(
    backgroundColor: primaryGreen,
    foregroundColor: Colors.white,
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    elevation: 0,
  );

  /// Orange brand primary (module chrome, create, open, links).
  static ButtonStyle primaryBrandButtonStyle() =>
      DocuTrackerTokens.brandFilledStyle();

  /// @deprecated Use [primaryBrandButtonStyle].
  static ButtonStyle primaryButtonStyleNavy() => primaryBrandButtonStyle();

  static ButtonStyle outlinedButtonStyle() => OutlinedButton.styleFrom(
    foregroundColor: AppTheme.textPrimary,
    side: BorderSide(color: DocuTrackerTokens.brand.withValues(alpha: 0.6)),
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
  );

  static ButtonStyle outlinedGreenStyle() => OutlinedButton.styleFrom(
    foregroundColor: primaryGreen,
    side: const BorderSide(color: primaryGreen),
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
  );

  static ButtonStyle outlinedRedStyle() => OutlinedButton.styleFrom(
    foregroundColor: destructiveRed,
    side: const BorderSide(color: destructiveRed),
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
  );

  static ButtonStyle destructiveButtonStyle() => FilledButton.styleFrom(
    backgroundColor: destructiveRed,
    foregroundColor: Colors.white,
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    elevation: 0,
  );

  static ButtonStyle warningButtonStyle() => OutlinedButton.styleFrom(
    foregroundColor: warningOrange,
    side: const BorderSide(color: warningOrange),
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
  );

  static ButtonStyle secondaryButtonStyle() => OutlinedButton.styleFrom(
    foregroundColor: secondaryBlue,
    side: BorderSide(color: secondaryBlue.withValues(alpha: 0.8)),
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
    backgroundColor: secondaryBlue,
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

  static ButtonStyle iconButtonStyle() =>
      IconButton.styleFrom(foregroundColor: DocuTrackerTokens.brand);

  static Widget filterDropdownWrapper(Widget child) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    decoration: BoxDecoration(
      color: DocuTrackerTokens.surfaceCream,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: DocuTrackerTokens.borderSubtle),
    ),
    child: child,
  );

  static BoxDecoration cardDecoration() => DocuTrackerTokens.cardDecoration();

  static BoxDecoration listCardDecoration() =>
      DocuTrackerTokens.cardDecoration();

  static Widget stateMessage({
    required IconData icon,
    required Color color,
    required String message,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: color.withValues(alpha: 0.95),
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
