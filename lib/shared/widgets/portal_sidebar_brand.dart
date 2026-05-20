import 'package:flutter/material.dart';

import '../../landingpage/constants/app_theme.dart';
import 'dashboard_header_actions.dart';

/// Sidebar width — keep in sync with dashboard sidebars.
const double kDashboardSidebarWidth = 276;

double dashboardHeaderBarHeight(BuildContext context) {
  return MediaQuery.sizeOf(context).width < 600 ? 64 : 76;
}

/// Logo + title block (sidebar or top header).
class DashboardHeaderBrand extends StatelessWidget {
  const DashboardHeaderBrand({
    super.key,
    this.compact = false,
  });

  /// Slightly smaller logo/text for narrow headers or drawer.
  final bool compact;

  static const _logoAsset = 'assets/images/hrmslogo.png';

  @override
  Widget build(BuildContext context) {
    final primaryColor = AppTheme.dashTextPrimaryOf(context);
    final taglineColor = AppTheme.dashTextSecondaryOf(context);
    final logoW = compact ? 72.0 : 88.0;
    final logoH = compact ? 58.0 : 68.0;
    final titleSize = compact ? 10.0 : 11.5;
    final tagSize = compact ? 7.5 : 8.5;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: logoW,
            height: logoH,
            child: Image.asset(
              _logoAsset,
              width: logoW,
              height: logoH,
              fit: BoxFit.contain,
              alignment: Alignment.center,
              filterQuality: FilterQuality.high,
              gaplessPlayback: true,
              errorBuilder: (context, error, stackTrace) {
                debugPrint('HRMS logo failed to load: $error');
                return ColoredBox(
                  color: AppTheme.primaryNavy.withValues(alpha: 0.08),
                  child: Icon(
                    Icons.hub_rounded,
                    size: logoH * 0.45,
                    color: AppTheme.primaryNavy,
                  ),
                );
              },
            ),
          ),
        ),
        SizedBox(width: compact ? 8 : 12),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'HUMAN RESOURCE',
                style: TextStyle(
                  color: primaryColor,
                  fontSize: titleSize,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                  letterSpacing: 0.35,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                'MANAGEMENT SYSTEM',
                style: TextStyle(
                  color: primaryColor,
                  fontSize: titleSize,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                  letterSpacing: 0.35,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              SizedBox(height: compact ? 2 : 4),
              Text(
                'INTEGRATED SOLUTIONS',
                style: TextStyle(
                  color: taglineColor.withValues(alpha: 0.88),
                  fontSize: tagSize,
                  fontWeight: FontWeight.w600,
                  height: 1.15,
                  letterSpacing: 0.4,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Sidebar header (mobile drawer).
class PortalSidebarBrand extends StatelessWidget {
  const PortalSidebarBrand({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: DashboardHeaderBrand(compact: true),
    );
  }
}

/// Top bar: brand + actions (mobile) or actions only (desktop right column).
class DashboardAppHeaderBar extends StatelessWidget {
  const DashboardAppHeaderBar({
    super.key,
    required this.trailing,
    this.showBrand = true,
    this.showMenuButton = false,
    this.onMenuPressed,
    this.showSidebarToggle = false,
    this.onSidebarToggle,
    this.compactActions = false,
    this.onViewAllNotifications,
  });

  final Widget trailing;
  final VoidCallback? onViewAllNotifications;
  /// When false (desktop), brand lives in the sidebar rail; this bar is actions only.
  final bool showBrand;
  final bool showMenuButton;
  final VoidCallback? onMenuPressed;
  /// Desktop rail collapse — hamburger at start of content header (edusync-style).
  final bool showSidebarToggle;
  final VoidCallback? onSidebarToggle;
  final bool compactActions;

  @override
  Widget build(BuildContext context) {
    final hairline = AppTheme.dashHairlineOf(context);
    final isNarrow = MediaQuery.sizeOf(context).width < 600;
    final compact = compactActions || isNarrow;
    final barH = dashboardHeaderBarHeight(context);

    return Container(
      height: barH,
      padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 20),
      decoration: BoxDecoration(
        color: AppTheme.dashPanelOf(context),
        border: Border(bottom: BorderSide(color: hairline)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (showSidebarToggle && onSidebarToggle != null) ...[
            IconButton(
              icon: const Icon(Icons.menu_rounded),
              onPressed: onSidebarToggle,
              color: AppTheme.primaryNavy,
              tooltip: 'Toggle sidebar',
              style: IconButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.all(8),
              ),
            ),
            Container(
              width: 1,
              height: 40,
              margin: const EdgeInsets.symmetric(horizontal: 8),
              color: hairline,
            ),
          ],
          if (showMenuButton) ...[
            IconButton(
              icon: const Icon(Icons.menu_rounded),
              onPressed: onMenuPressed,
              color: AppTheme.dashTextPrimaryOf(context),
              tooltip: 'Menu',
              style: IconButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.all(8),
              ),
            ),
            Container(
              width: 1,
              height: 40,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              color: hairline,
            ),
          ],
          if (showBrand)
            Flexible(
              fit: FlexFit.loose,
              child: DashboardHeaderBrand(compact: showMenuButton || isNarrow),
            ),
          const Spacer(),
          DashboardHeaderActions(
            compact: compact,
            onViewAllNotifications: onViewAllNotifications,
          ),
          DashboardHeaderActionDivider(compact: compact, emphasized: true),
          trailing,
        ],
      ),
    );
  }
}

/// Brand block sized for the sidebar rail header (matches top bar height).
class SidebarRailHeader extends StatelessWidget {
  const SidebarRailHeader({
    super.key,
    this.collapsed = false,
  });

  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    final hairline = AppTheme.dashHairlineOf(context);
    final barH = dashboardHeaderBarHeight(context);

    return Container(
      height: barH,
      padding: EdgeInsets.symmetric(horizontal: collapsed ? 4 : 10),
      alignment: collapsed ? Alignment.center : Alignment.centerLeft,
      decoration: BoxDecoration(
        color: AppTheme.dashPanelOf(context),
        border: Border(
          bottom: BorderSide(color: hairline),
        ),
      ),
      child: collapsed
          ? const _SidebarRailMedallion()
          : const Align(
              alignment: Alignment.centerLeft,
              child: DashboardHeaderBrand(compact: true),
            ),
    );
  }
}

/// Collapsed rail logo — circular medallion with HRMS accent ring.
class _SidebarRailMedallion extends StatelessWidget {
  const _SidebarRailMedallion();

  static const _logoAsset = 'assets/images/hrmslogo.png';

  @override
  Widget build(BuildContext context) {
    final panel = AppTheme.dashPanelOf(context);
    const size = 44.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: panel,
            border: Border.all(
              color: AppTheme.primaryNavy.withValues(alpha: 0.25),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primaryNavy.withValues(alpha: 0.14),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _MedallionRingPainter(),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(7),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: Image.asset(
                    _logoAsset,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                    gaplessPlayback: true,
                    errorBuilder: (context, error, stackTrace) {
                      return Icon(
                        Icons.hub_rounded,
                        size: 22,
                        color: AppTheme.primaryNavy,
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Container(
          width: 24,
          height: 2,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(2),
            gradient: LinearGradient(
              colors: [
                AppTheme.primaryNavy.withValues(alpha: 0.15),
                AppTheme.primaryNavy,
                AppTheme.primaryNavy.withValues(alpha: 0.15),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _MedallionRingPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 2;

    final arcPaint = Paint()
      ..shader = const SweepGradient(
        startAngle: 0,
        colors: [
          AppTheme.primaryNavyLight,
          AppTheme.primaryNavy,
          AppTheme.letterheadNavy,
          AppTheme.primaryNavyLight,
        ],
        stops: [0, 0.35, 0.65, 1],
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -1.2,
      2.4,
      false,
      arcPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _SidebarRailLogoMark extends StatelessWidget {
  const _SidebarRailLogoMark({required this.size});

  final double size;

  static const _logoAsset = 'assets/images/hrmslogo.png';

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.asset(
        _logoAsset,
        width: size,
        height: size,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) {
          return Icon(
            Icons.hub_rounded,
            size: size * 0.55,
            color: AppTheme.primaryNavy,
          );
        },
      ),
    );
  }
}

