import 'package:flutter/material.dart';

/// DocuTracker layout and brand tokens (warm cream + orange accent).
abstract final class DocuTrackerTokens {
  DocuTrackerTokens._();

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

  static const Color overduePink = Color(0xFFFFE8E8);
  static const Color overdueAccent = Color(0xFFD64545);
  static const Color alertOrange = brand;
  static const Color escalatedBlue = Color(0xFF3B82F6);

  static const double radiusSm = 10;
  static const double radiusMd = 12;
  static const double radiusLg = 16;

  static const double maxContentWidth = 1680;

  static TextStyle titleStyle(BuildContext context) => const TextStyle(
    fontSize: 15,
    height: 1.25,
    fontWeight: FontWeight.w700,
    color: textPrimary,
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

  static BoxDecoration cardDecoration({Color? borderColor, Color? fill}) {
    return BoxDecoration(
      color: fill ?? surface,
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

  static InputDecoration warmSearchDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: metaStyle(),
      prefixIcon: Icon(
        Icons.search_rounded,
        color: textMuted.withValues(alpha: 0.85),
        size: 20,
      ),
      filled: true,
      fillColor: surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusSm),
        borderSide: const BorderSide(color: borderSubtle),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusSm),
        borderSide: const BorderSide(color: borderSubtle),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusSm),
        borderSide: const BorderSide(color: brand, width: 1.5),
      ),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(vertical: 12),
    );
  }

  static BoxDecoration warmDropdownDecoration() {
    return BoxDecoration(
      color: surface,
      borderRadius: BorderRadius.circular(radiusSm),
      border: Border.all(color: borderSubtle),
    );
  }

  static ButtonStyle brandOutlinedStyle() => OutlinedButton.styleFrom(
    foregroundColor: brand,
    side: const BorderSide(color: brand),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radiusSm),
    ),
  );

  /// @deprecated Use [brandOutlinedStyle].
  static ButtonStyle terracottaOutlinedStyle() => brandOutlinedStyle();
}
