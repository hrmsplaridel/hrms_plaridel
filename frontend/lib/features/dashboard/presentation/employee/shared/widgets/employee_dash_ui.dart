import 'package:flutter/material.dart';

import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/shared/widgets/dashboard_welcome_banner.dart';

/// Dashboard accent colors (aligned with admin home welcome banner).
class _EmployeeDashColors {
  static const Color accentOrange = Color(0xFFE85D04);
}

/// Shared visual primitives for the employee portal dashboard home.
class EmployeeDashUi {
  EmployeeDashUi._();

  static const double radiusLg = 20;
  static const double radiusMd = 16;

  static BoxDecoration elevatedPanel(BuildContext context) {
    final base = AppTheme.dashSurfaceCard(context, radius: radiusLg);
    final dark = AppTheme.dashIsDark(context);
    return base.copyWith(
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: dark ? 0.28 : 0.05),
          blurRadius: 20,
          offset: const Offset(0, 6),
        ),
        BoxShadow(
          color: _EmployeeDashColors.accentOrange.withValues(
            alpha: dark ? 0.06 : 0.03,
          ),
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
      ],
    );
  }

  static BoxDecoration summaryCard({
    required BuildContext context,
    required Color tint,
    required Color accent,
  }) {
    final dark = AppTheme.dashIsDark(context);
    return BoxDecoration(
      borderRadius: BorderRadius.circular(radiusMd),
      color: dark ? const Color(0xFF1E2430) : tint,
      border: Border.all(color: accent.withValues(alpha: dark ? 0.35 : 0.2)),
      boxShadow: [
        BoxShadow(
          color: accent.withValues(alpha: dark ? 0.14 : 0.1),
          blurRadius: 18,
          offset: const Offset(0, 6),
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: dark ? 0.2 : 0.035),
          blurRadius: 10,
          offset: const Offset(0, 3),
        ),
      ],
    );
  }

  static ButtonStyle ghostAction(BuildContext context) {
    final dark = AppTheme.dashIsDark(context);
    return TextButton.styleFrom(
      foregroundColor: dark ? AppTheme.primaryNavyLight : AppTheme.primaryNavy,
      backgroundColor: AppTheme.primaryNavy.withValues(
        alpha: dark ? 0.18 : 0.06,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
    );
  }

  static TextStyle metricLabel(BuildContext context) => TextStyle(
    color: AppTheme.dashTextSecondaryOf(context),
    fontSize: 11,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.55,
  );
}

/// Welcome hero for the employee dashboard home.
class EmployeeWelcomeBanner extends StatelessWidget {
  const EmployeeWelcomeBanner({
    super.key,
    required this.displayName,
    required this.isNarrow,
  });

  final String displayName;

  /// Kept for existing call sites. Layout follows the banner's own width.
  final bool isNarrow;

  @override
  Widget build(BuildContext context) {
    assert(isNarrow == isNarrow);
    return DashboardWelcomeBanner(
      portalLabel: 'Employee Portal',
      displayName: displayName,
      description: 'Welcome to your HRMS dashboard.',
    );
  }
}

/// Section title row with optional icon, subtitle, and trailing action.
class EmployeeSectionHeader extends StatelessWidget {
  const EmployeeSectionHeader({
    super.key,
    required this.title,
    this.icon,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final IconData? icon;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final primary = AppTheme.dashTextPrimaryOf(context);
    final secondary = AppTheme.dashTextSecondaryOf(context);
    final dark = AppTheme.dashIsDark(context);
    final accent = AppTheme.primaryNavy;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (icon != null) ...[
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: dark
                    ? [
                        accent.withValues(alpha: 0.28),
                        accent.withValues(alpha: 0.12),
                      ]
                    : [
                        accent.withValues(alpha: 0.14),
                        AppTheme.letterheadNavy.withValues(alpha: 0.08),
                      ],
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: accent.withValues(alpha: dark ? 0.35 : 0.12),
              ),
            ),
            child: Icon(
              icon,
              color: dark ? AppTheme.primaryNavyLight : accent,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: primary,
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                  letterSpacing: -0.35,
                  height: 1.2,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle!,
                  style: TextStyle(
                    color: secondary,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

/// Gradient icon tile for summary metric cards.
class EmployeeSummaryIconAccent extends StatelessWidget {
  const EmployeeSummaryIconAccent({
    super.key,
    required this.icon,
    required this.color,
  });

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color.withValues(alpha: 0.2), color.withValues(alpha: 0.08)],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Icon(icon, color: color, size: 26),
    );
  }
}
