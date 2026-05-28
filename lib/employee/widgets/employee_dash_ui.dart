import 'package:flutter/material.dart';

import '../../dtr/widgets/real_time_clock.dart';
import '../../landingpage/constants/app_theme.dart';
import '../../shared/utils/time_greeting.dart';

/// Dashboard accent colors (aligned with admin home welcome banner).
class _EmployeeDashColors {
  static const Color accentOrange = Color(0xFFE85D04);
}

/// Shared visual primitives for the employee portal dashboard home.
class EmployeeDashUi {
  EmployeeDashUi._();

  static const double radiusLg = 20;
  static const double radiusMd = 16;

  static BoxDecoration welcomeBanner(BuildContext context) {
    final dark = AppTheme.dashIsDark(context);
    return BoxDecoration(
      borderRadius: BorderRadius.circular(radiusLg),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: dark
            ? [
                const Color(0xFF252D3D),
                const Color(0xFF1E2430),
              ]
            : [
                const Color(0xFFFFF8F3),
                Colors.white,
                const Color(0xFFF5F8FF),
              ],
      ),
      border: Border.all(
        color: dark
            ? AppTheme.dashHairlineOf(context)
            : _EmployeeDashColors.accentOrange.withValues(alpha: 0.14),
      ),
      boxShadow: [
        BoxShadow(
          color: _EmployeeDashColors.accentOrange.withValues(
            alpha: dark ? 0.12 : 0.08,
          ),
          blurRadius: 28,
          offset: const Offset(0, 10),
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: dark ? 0.25 : 0.04),
          blurRadius: 16,
          offset: const Offset(0, 4),
        ),
      ],
    );
  }

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
      border: Border.all(
        color: accent.withValues(alpha: dark ? 0.35 : 0.2),
      ),
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
    return TextButton.styleFrom(
      foregroundColor: AppTheme.primaryNavy,
      backgroundColor: AppTheme.primaryNavy.withValues(alpha: 0.06),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      textStyle: const TextStyle(
        fontWeight: FontWeight.w600,
        fontSize: 13,
      ),
    );
  }

  static TextStyle metricLabel(BuildContext context) => TextStyle(
        color: AppTheme.dashTextSecondaryOf(context),
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.55,
      );
}

/// Gradient welcome hero for the employee dashboard home.
class EmployeeWelcomeBanner extends StatelessWidget {
  const EmployeeWelcomeBanner({
    super.key,
    required this.displayName,
    required this.isNarrow,
  });

  final String displayName;
  final bool isNarrow;

  @override
  Widget build(BuildContext context) {
    final primary = AppTheme.dashTextPrimaryOf(context);
    final secondary = AppTheme.dashTextSecondaryOf(context);
    final greeting = personalizedTimeGreeting(displayName);

    final copy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: EdgeInsets.symmetric(
            horizontal: isNarrow ? 8 : 10,
            vertical: isNarrow ? 4 : 5,
          ),
          decoration: BoxDecoration(
            color: _EmployeeDashColors.accentOrange.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: _EmployeeDashColors.accentOrange.withValues(alpha: 0.22),
            ),
          ),
          child: Text(
            'Employee Portal',
            style: TextStyle(
              color: _EmployeeDashColors.accentOrange,
              fontSize: isNarrow ? 10.5 : 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
        ),
        SizedBox(height: isNarrow ? 8 : 12),
        Text(
          greeting,
          style: TextStyle(
            color: primary,
            fontSize: isNarrow ? 19 : 28,
            fontWeight: FontWeight.w800,
            height: 1.15,
          ),
          maxLines: isNarrow ? 2 : 3,
          overflow: TextOverflow.ellipsis,
        ),
        SizedBox(height: isNarrow ? 5 : 8),
        Text(
          "Here's your latest overview of your HR activities.",
          style: TextStyle(
            color: secondary,
            fontSize: isNarrow ? 12.5 : 15,
            height: isNarrow ? 1.3 : 1.45,
          ),
          maxLines: isNarrow ? 2 : null,
          overflow: isNarrow ? TextOverflow.ellipsis : null,
        ),
      ],
    );

    return Container(
      padding: EdgeInsets.all(isNarrow ? 14 : 26),
      decoration: EmployeeDashUi.welcomeBanner(context),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (isNarrow)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: copy),
                const SizedBox(width: 10),
                const RealTimeClock(
                  compact: true,
                  accentColor: _EmployeeDashColors.accentOrange,
                ),
              ],
            )
          else ...[
            Positioned(
              right: -16,
              top: -24,
              child: Container(
                width: 160,
                height: 160,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      _EmployeeDashColors.accentOrange.withValues(alpha: 0.12),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: -8,
              bottom: -16,
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppTheme.letterheadNavy.withValues(alpha: 0.08),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: copy),
                const SizedBox(width: 20),
                const RealTimeClock(
                  accentColor: _EmployeeDashColors.accentOrange,
                ),
              ],
            ),
          ],
        ],
      ),
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
                colors: [
                  AppTheme.primaryNavy.withValues(alpha: 0.14),
                  AppTheme.letterheadNavy.withValues(alpha: 0.08),
                ],
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppTheme.primaryNavy.withValues(alpha: 0.12),
              ),
            ),
            child: Icon(icon, color: AppTheme.primaryNavy, size: 22),
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
          colors: [
            color.withValues(alpha: 0.2),
            color.withValues(alpha: 0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Icon(icon, color: color, size: 26),
    );
  }
}
