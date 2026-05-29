import 'package:flutter/material.dart';

/// DocuTracker layout and brand tokens (warm cream + orange accent).
abstract final class DocuTrackerTokens {
  DocuTrackerTokens._();

  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  // ── Light palette ─────────────────────────────────────────────────────────

  /// App canvas behind cards (soft warm off-white).
  static const Color canvas = Color(0xFFFFF6F4);

  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceCream = Color(0xFFFFF5EB);

  /// Peach highlight panels (action banners, upload zones, metadata chips).
  static const Color highlightPeach = Color(0xFFFFF5F0);
  static const Color highlightPeachBorder = Color(0xFFFFD4B8);

  /// Primary brand orange (sidebar DocuTracker + active section pills).
  static const Color brand = Color(0xFFE65100);
  static const Color brandDark = Color(0xFFBF360C);
  static const Color brandSoft = Color(0xFFFFE8D6);
  static const Color brandMuted = Color(0xFFFFCC80);

  /// Legacy aliases — use [brand] in new code.
  static const Color terracotta = brand;
  static const Color terracottaDark = brandDark;

  static const Color borderSubtle = Color(0xFFF0E4DC);
  static const Color borderStrong = Color(0xFFE8D5C8);

  static const Color textPrimary = Color(0xFF3D2C24);
  static const Color textMuted = Color(0xFF7A6B63);
  static const Color textSecondary = Color(0xFF5C4F48);

  // ── Dark palette ──────────────────────────────────────────────────────────

  static const Color canvasDark = Color(0xFF111827);
  static const Color surfaceDark = Color(0xFF1F2937);
  static const Color borderSubtleDark = Color(0xFF374151);
  static const Color textPrimaryDark = Color(0xFFF3F4F6);
  static const Color textSecondaryDark = Color(0xFFD1D5DB);
  static const Color textMutedDark = Color(0xFF9CA3AF);

  static const Color overduePink = Color(0xFFFFE8E8);
  static const Color overdueAccent = Color(0xFFD64545);
  static const Color alertOrange = brand;
  static const Color escalatedBlue = Color(0xFF3B82F6);

  static const double radiusSm = 10;
  static const double radiusMd = 12;
  static const double radiusLg = 16;

  static const double maxContentWidth = 1680;

  // ── Theme-aware colors ────────────────────────────────────────────────────

  static Color canvasOf(BuildContext context) =>
      isDark(context) ? canvasDark : canvas;

  static Color surfaceOf(BuildContext context) =>
      isDark(context) ? surfaceDark : surface;

  static Color borderSubtleOf(BuildContext context) =>
      isDark(context) ? borderSubtleDark : borderSubtle;

  static Color textPrimaryOf(BuildContext context) =>
      isDark(context) ? textPrimaryDark : textPrimary;

  static Color textSecondaryOf(BuildContext context) =>
      isDark(context) ? textSecondaryDark : textSecondary;

  static Color textMutedOf(BuildContext context) =>
      isDark(context) ? textMutedDark : textMuted;

  static TextStyle titleStyle(BuildContext context) => TextStyle(
        fontSize: 15,
        height: 1.25,
        fontWeight: FontWeight.w700,
        color: textPrimaryOf(context),
      );

  static TextStyle subtitleStyle(BuildContext context) => TextStyle(
        fontSize: 13,
        height: 1.35,
        fontWeight: FontWeight.w400,
        color: textSecondaryOf(context),
      );

  static TextStyle metaStyle(BuildContext context) => TextStyle(
        fontSize: 12,
        height: 1.3,
        fontWeight: FontWeight.w500,
        color: textMutedOf(context),
      );

  static ButtonStyle sectionNavStyle(BuildContext context) {
    final dark = isDark(context);
    return ButtonStyle(
      visualDensity: VisualDensity.compact,
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      ),
      foregroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return Colors.white;
        }
        return dark ? textSecondaryDark : textSecondary;
      }),
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return brand;
        return dark ? surfaceDark : surface;
      }),
      side: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return BorderSide(color: brand.withValues(alpha: 0.5));
        }
        return BorderSide(color: borderSubtleOf(context));
      }),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSm),
        ),
      ),
    );
  }

  static BoxDecoration cardDecoration({
    BuildContext? context,
    Color? borderColor,
    Color? fill,
  }) {
    final dark = context != null && isDark(context);
    return BoxDecoration(
      color: fill ?? (dark ? surfaceDark : surface),
      borderRadius: BorderRadius.circular(radiusLg),
      border: Border.all(
        color: borderColor ?? (dark ? borderSubtleDark : borderSubtle),
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: dark ? 0.25 : 0.04),
          blurRadius: 10,
          offset: const Offset(0, 2),
        ),
      ],
    );
  }

  static ButtonStyle brandFilledStyle() => FilledButton.styleFrom(
        backgroundColor: brand,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSm),
        ),
      );

  /// @deprecated Use [brandFilledStyle].
  static ButtonStyle terracottaFilledStyle() => brandFilledStyle();

  static InputDecoration warmSearchDecoration(
    BuildContext context,
    String hint,
  ) {
    final dark = isDark(context);
    final muted = textMutedOf(context);
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(fontSize: 12, color: muted),
      prefixIcon: Icon(
        Icons.search_rounded,
        color: muted.withValues(alpha: 0.85),
        size: 20,
      ),
      filled: true,
      fillColor: dark ? surfaceDark : surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusSm),
        borderSide: BorderSide(color: borderSubtleOf(context)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusSm),
        borderSide: BorderSide(color: borderSubtleOf(context)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusSm),
        borderSide: const BorderSide(color: brand, width: 1.5),
      ),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(vertical: 12),
    );
  }

  static BoxDecoration warmDropdownDecoration(BuildContext context) {
    return BoxDecoration(
      color: surfaceOf(context),
      borderRadius: BorderRadius.circular(radiusSm),
      border: Border.all(color: borderSubtleOf(context)),
    );
  }

  static ButtonStyle brandOutlinedStyle({BuildContext? context}) {
    final fg = context != null && isDark(context)
        ? brandMuted
        : brand;
    return OutlinedButton.styleFrom(
      foregroundColor: fg,
      side: BorderSide(color: fg),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusSm),
      ),
    );
  }

  /// @deprecated Use [brandOutlinedStyle].
  static ButtonStyle terracottaOutlinedStyle() => brandOutlinedStyle();

  static BoxDecoration errorBannerDecoration(BuildContext context) {
    final dark = isDark(context);
    return BoxDecoration(
      color: dark ? const Color(0xFF3F1D1D) : const Color(0xFFFFF1F2),
      borderRadius: BorderRadius.circular(radiusMd),
      border: Border.all(
        color: dark ? const Color(0xFF7F1D1D) : const Color(0xFFFECACA),
      ),
    );
  }

  static Color errorBannerForeground(BuildContext context) =>
      isDark(context) ? const Color(0xFFFECACA) : const Color(0xFFB91C1C);

  static Color errorBannerIcon(BuildContext context) =>
      isDark(context) ? const Color(0xFFF87171) : const Color(0xFFDC2626);
}
