import 'package:flutter/material.dart';

import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/shared/utils/time_greeting.dart';
import 'package:hrms_plaridel/shared/widgets/admin_welcome_status_card.dart';

/// Shared Admin, Employee, and Mayor dashboard welcome banner.
///
/// Role copy is supplied by the caller. Time, weather, location, and refresh
/// stay on [AdminWelcomeStatusCard].
class DashboardWelcomeBanner extends StatelessWidget {
  const DashboardWelcomeBanner({
    super.key,
    required this.portalLabel,
    required this.displayName,
    required this.description,
  });

  final String portalLabel;
  final String displayName;
  final String description;

  static const Color _orange = Color(0xFFE85D04);

  @override
  Widget build(BuildContext context) {
    final primary = AppTheme.dashTextPrimaryOf(context);
    final secondary = AppTheme.dashTextSecondaryOf(context);
    final salutation = timeOfDayGreeting();
    final name = greetingFirstName(displayName);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final stacked = width < 1100;
        final compact = width < 480;
        final padding = EdgeInsets.symmetric(
          horizontal: compact ? 14 : (stacked ? 18 : 28),
          vertical: compact ? 14 : (stacked ? 16 : 20),
        );
        final greetingSize = compact ? 20.0 : (stacked ? 24.0 : 28.0);

        final greeting = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _PortalBadge(label: portalLabel, compact: compact),
            SizedBox(height: compact ? 8 : 10),
            Text.rich(
              TextSpan(
                style: TextStyle(
                  color: primary,
                  fontSize: greetingSize,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                  height: 1.2,
                ),
                children: [
                  TextSpan(text: '$salutation, '),
                  TextSpan(
                    text: name,
                    style: const TextStyle(color: _orange),
                  ),
                  const TextSpan(text: '!'),
                ],
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            SizedBox(height: compact ? 4 : 6),
            Text(
              description,
              style: TextStyle(
                color: secondary,
                fontSize: compact ? 12.5 : 14,
                height: 1.35,
              ),
            ),
          ],
        );

        final status = AdminWelcomeStatusCard(
          layout: WelcomeStatusLayout.adminHeader,
          fillWidth: stacked,
        );

        final body = stacked
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  greeting,
                  SizedBox(height: compact ? 14 : 16),
                  status,
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: greeting),
                  const SizedBox(width: 28),
                  status,
                ],
              );

        return ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: DecoratedBox(
            decoration: _decoration(context),
            child: Stack(
              children: [
                if (width >= 480)
                  const Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(painter: _WelcomeBannerPainter()),
                    ),
                  ),
                Padding(padding: padding, child: body),
              ],
            ),
          ),
        );
      },
    );
  }

  BoxDecoration _decoration(BuildContext context) {
    final dark = AppTheme.dashIsDark(context);
    return BoxDecoration(
      borderRadius: BorderRadius.circular(22),
      gradient: LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: dark
            ? const [Color(0xFF2A241F), Color(0xFF241F1C), Color(0xFF2A241F)]
            : const [Color(0xFFFFF8F3), Colors.white, Color(0xFFFFF6EE)],
      ),
      border: Border.all(
        color: dark
            ? AppTheme.dashHairlineOf(context)
            : _orange.withValues(alpha: 0.22),
      ),
      boxShadow: [
        BoxShadow(
          color: _orange.withValues(alpha: dark ? 0.14 : 0.08),
          blurRadius: 18,
          offset: const Offset(0, 6),
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: dark ? 0.22 : 0.04),
          blurRadius: 10,
          offset: const Offset(0, 2),
        ),
      ],
    );
  }
}

class _PortalBadge extends StatelessWidget {
  const _PortalBadge({required this.label, required this.compact});

  final String label;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 4 : 5,
      ),
      decoration: BoxDecoration(
        color: DashboardWelcomeBanner._orange.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: DashboardWelcomeBanner._orange.withValues(alpha: 0.28),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.home_rounded,
            size: compact ? 13 : 14,
            color: DashboardWelcomeBanner._orange,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: DashboardWelcomeBanner._orange,
              fontSize: compact ? 11 : 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.15,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}

class _WelcomeBannerPainter extends CustomPainter {
  const _WelcomeBannerPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final left = Paint()
      ..shader = const RadialGradient(
        colors: [Color(0x33F4A261), Color(0x00F4A261)],
      ).createShader(Rect.fromCircle(center: Offset.zero, radius: size.height));
    canvas.drawCircle(Offset(-8, size.height * 0.15), size.height * 0.95, left);

    final right = Paint()
      ..shader =
          const RadialGradient(
            colors: [Color(0x2EE85D04), Color(0x00E85D04)],
          ).createShader(
            Rect.fromCircle(
              center: Offset(size.width, size.height),
              radius: size.height * 0.9,
            ),
          );
    canvas.drawCircle(
      Offset(size.width + 12, size.height * 0.85),
      size.height * 0.8,
      right,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
