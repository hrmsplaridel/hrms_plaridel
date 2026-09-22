import 'package:flutter/material.dart';

import 'package:hrms_plaridel/core/theme/app_theme.dart';

/// Presentation helpers for L&D Admin → Training Requirements Monitoring only.
class LdTrainingReqUi {
  LdTrainingReqUi._();

  static const Color orange = Color(0xFFEA580C);
  static const Color bg = Color(0xFFF8FAFC);
  static const Color cardBg = Color(0xFFFFFFFF);
  static const Color textPrimary = Color(0xFF1F2937);
  static const Color textSecondary = Color(0xFF64748B);
  static const Color border = Color(0xFFE5E7EB);
  static const Color success = Color(0xFF16A34A);
  static const Color reviewBlue = Color(0xFF2563EB);
  static const Color lockedGray = Color(0xFF64748B);

  static const double cardRadius = 12;
  static const double controlHeight = 42;

  static Color accentOf(BuildContext context) => AppTheme.dashIsDark(context)
      ? AppTheme.primaryNavyLight
      : AppTheme.primaryNavy;

  static Color panelOf(BuildContext context) => AppTheme.dashIsDark(context)
      ? AppTheme.dashPanelOf(context)
      : cardBg;

  static Color hairlineOf(BuildContext context) => AppTheme.dashIsDark(context)
      ? AppTheme.dashHairlineOf(context)
      : border;

  static Color primaryTextOf(BuildContext context) =>
      AppTheme.dashIsDark(context)
      ? AppTheme.dashTextPrimaryOf(context)
      : textPrimary;

  static Color secondaryTextOf(BuildContext context) =>
      AppTheme.dashIsDark(context)
      ? AppTheme.dashTextSecondaryOf(context)
      : textSecondary;

  static BoxDecoration cardDecoration(BuildContext context) {
    return BoxDecoration(
      color: panelOf(context),
      borderRadius: BorderRadius.circular(cardRadius),
      border: Border.all(color: hairlineOf(context)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.04),
          blurRadius: 10,
          offset: const Offset(0, 3),
        ),
      ],
    );
  }

  static BoxDecoration toolbarDecoration(BuildContext context) {
    return BoxDecoration(
      color: panelOf(context),
      borderRadius: BorderRadius.circular(cardRadius),
      border: Border.all(color: hairlineOf(context)),
    );
  }

  static InputDecoration searchDecoration(BuildContext context) {
    return InputDecoration(
      hintText: 'Search employee or training title…',
      prefixIcon: Icon(
        Icons.search_rounded,
        color: secondaryTextOf(context),
      ),
      isDense: true,
      filled: true,
      fillColor: AppTheme.dashMutedSurfaceOf(context),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: hairlineOf(context)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: hairlineOf(context)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: accentOf(context), width: 1.4),
      ),
    );
  }

  static String formatShortDate(DateTime? at) {
    if (at == null) return '—';
    final local = at.toLocal();
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    final h = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    return '${local.year}-$m-$d $h:$min';
  }

  static String initials(String? name) {
    final parts = (name ?? '')
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      final s = parts.first;
      return s.substring(0, s.length >= 2 ? 2 : 1).toUpperCase();
    }
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }
}
