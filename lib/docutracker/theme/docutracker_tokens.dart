import 'package:flutter/material.dart';

/// DocuTracker SaaS-style layout and surface tokens (Notion/Linear-like).
/// Use for spacing, canvas, and card chrome — brand colors stay on [AppTheme].
abstract final class DocuTrackerTokens {
  DocuTrackerTokens._();

  /// App canvas behind cards (quiet gray).
  static const Color canvas = Color(0xFFF5F6F8);

  static const Color surface = Color(0xFFFFFFFF);
  static const Color borderSubtle = Color(0xFFE8EAED);
  static const Color borderStrong = Color(0xFFDDE1E6);

  static const Color textMuted = Color(0xFF5C6370);
  static const Color textSecondary = Color(0xFF495057);

  static const double radiusSm = 10;
  static const double radiusMd = 12;
  static const double radiusLg = 16;

  static const double maxContentWidth = 1200;

  /// Section title (e.g. "Overdue")
  static TextStyle titleStyle(BuildContext context) => const TextStyle(
        fontSize: 15,
        height: 1.25,
        fontWeight: FontWeight.w700,
        color: Color(0xFF212529),
      );

  static TextStyle subtitleStyle() => const TextStyle(
        fontSize: 13,
        height: 1.35,
        fontWeight: FontWeight.w400,
        color: textSecondary,
      );

  static TextStyle metaStyle() => const TextStyle(
        fontSize: 12,
        height: 1.3,
        fontWeight: FontWeight.w500,
        color: textMuted,
      );

  static BoxDecoration cardDecoration({Color? borderColor}) {
    return BoxDecoration(
      color: surface,
      borderRadius: BorderRadius.circular(radiusLg),
      border: Border.all(color: borderColor ?? borderSubtle),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.04),
          blurRadius: 10,
          offset: const Offset(0, 2),
        ),
      ],
    );
  }
}
