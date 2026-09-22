import 'package:flutter/material.dart';

import 'package:hrms_plaridel/core/theme/app_theme.dart';

/// Final Requirements–only presentation helpers (ADMIN → RSP → Final Requirements).
///
/// Scoped to this screen so other RSP modules keep their existing look.
class RspFinalReqUi {
  RspFinalReqUi._();

  static const Color orange = Color(0xFFEA580C);
  static const Color bg = Color(0xFFF8FAFC);
  static const Color cardBg = Color(0xFFFFFFFF);
  static const Color textPrimary = Color(0xFF1F2937);
  static const Color textSecondary = Color(0xFF64748B);
  static const Color border = Color(0xFFE5E7EB);
  static const Color success = Color(0xFF16A34A);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFDC2626);
  static const Color readyBlue = Color(0xFF2563EB);
  static const Color hiredPurple = Color(0xFF7C3AED);

  static const double cardRadius = 12;
  static const double controlHeight = 44;
  static const double inputRadius = 10;

  static Color accentOf(BuildContext context) => AppTheme.dashIsDark(context)
      ? AppTheme.primaryNavyLight
      : AppTheme.primaryNavy;

  static Color pageBgOf(BuildContext context) => AppTheme.dashIsDark(context)
      ? AppTheme.dashMutedSurfaceOf(context)
      : bg;

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

  static BoxDecoration cardDecoration(
    BuildContext context, {
    bool highlighted = false,
  }) {
    final ac = accentOf(context);
    return BoxDecoration(
      color: panelOf(context),
      borderRadius: BorderRadius.circular(cardRadius),
      border: Border.all(
        color: highlighted
            ? ac.withValues(alpha: 0.40)
            : hairlineOf(context),
        width: highlighted ? 1.2 : 1,
      ),
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

  static InputDecoration filterDecoration(
    BuildContext context, {
    String? hint,
    String? label,
    Widget? prefixIcon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      hintText: hint,
      labelText: label,
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      isDense: true,
      filled: true,
      fillColor: AppTheme.dashMutedSurfaceOf(context),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(inputRadius),
        borderSide: BorderSide(color: hairlineOf(context)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(inputRadius),
        borderSide: BorderSide(color: hairlineOf(context)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(inputRadius),
        borderSide: BorderSide(color: accentOf(context), width: 1.6),
      ),
    );
  }

  static Widget ddText(String text) {
    return Text(
      text,
      overflow: TextOverflow.ellipsis,
      maxLines: 1,
      softWrap: false,
    );
  }

  static Widget initialsAvatar(
    BuildContext context,
    String name, {
    double size = 40,
  }) {
    final parts = name.trim().split(RegExp(r'\s+'));
    var initials = '';
    if (parts.isNotEmpty && parts.first.isNotEmpty) {
      initials += parts.first[0].toUpperCase();
    }
    if (parts.length > 1 && parts.last.isNotEmpty) {
      initials += parts.last[0].toUpperCase();
    }
    if (initials.isEmpty) initials = '?';
    final ac = accentOf(context);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [ac.withValues(alpha: 0.22), ac.withValues(alpha: 0.10)],
        ),
        border: Border.all(color: ac.withValues(alpha: 0.28)),
      ),
      child: Text(
        initials,
        style: TextStyle(
          fontFamily: 'NotoSans',
          color: ac,
          fontWeight: FontWeight.w800,
          fontSize: size * 0.34,
        ),
      ),
    );
  }

  static Widget statusBadge({
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          height: 1.1,
        ),
      ),
    );
  }

  static Widget sectionLabel(
    BuildContext context,
    String title, {
    String? subtitle,
    Widget? trailing,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontFamily: 'NotoSans',
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  color: primaryTextOf(context),
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.3,
                    color: secondaryTextOf(context),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) trailing,
      ],
    );
  }

  static const List<String> _shortMonths = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  static String formatDateShort(DateTime date) {
    final d = date.toLocal();
    return '${_shortMonths[d.month - 1]} ${d.day}, ${d.year}';
  }

  static int daysSince(DateTime date) {
    final now = DateTime.now();
    final local = date.toLocal();
    return DateTime(now.year, now.month, now.day)
        .difference(DateTime(local.year, local.month, local.day))
        .inDays;
  }

  static String relativeApplied(DateTime date) {
    final days = daysSince(date);
    if (days <= 0) return 'Today';
    if (days == 1) return '1 day ago';
    if (days < 30) return '$days days ago';
    if (days < 60) return '1 month ago';
    return '${days ~/ 30} months ago';
  }

  static bool isNewApplication(DateTime? createdAt) {
    if (createdAt == null) return false;
    return daysSince(createdAt) <= 3;
  }
}
