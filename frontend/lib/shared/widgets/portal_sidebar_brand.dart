import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'collapsible_dashboard_sidebar.dart';
import 'package:hrms_plaridel/features/notifications/models/notification_tap_result.dart';
import 'dashboard_header_actions.dart';

/// Sidebar width — keep in sync with dashboard sidebars.
const double kDashboardSidebarWidth = 276;

double dashboardHeaderBarHeight(BuildContext context) {
  return MediaQuery.sizeOf(context).width < 600 ? 72 : 76;
}

/// Municipality seal in a circle (sidebar, header, rail).
class PlaridelCircleLogo extends StatelessWidget {
  const PlaridelCircleLogo({
    super.key,
    required this.size,
    this.borderWidth = 2,
    this.showShadow = true,
    this.innerPaddingFactor = 0.08,
  });

  final double size;
  final double borderWidth;
  final bool showShadow;

  /// Inset between circle edge and seal artwork (breathing room inside ring).
  final double innerPaddingFactor;

  static const _asset = 'assets/images/hrmslogo.png';

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: borderWidth > 0
            ? Border.all(
                color: AppTheme.primaryNavy.withValues(alpha: 0.2),
                width: borderWidth,
              )
            : null,
        boxShadow: showShadow
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ]
            : null,
      ),
      child: ClipOval(
        child: Padding(
          padding: EdgeInsets.all(size * innerPaddingFactor),
          child: Image.asset(
            _asset,
            width: size,
            height: size,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
            gaplessPlayback: true,
            errorBuilder: (context, error, stackTrace) {
              debugPrint('HRMS logo failed to load: $error');
              return ColoredBox(
                color: AppTheme.primaryNavy.withValues(alpha: 0.08),
                child: Icon(
                  Icons.hub_rounded,
                  size: size * 0.4,
                  color: AppTheme.primaryNavy,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Logo + title block (sidebar or top header).
class DashboardHeaderBrand extends StatelessWidget {
  const DashboardHeaderBrand({
    super.key,
    this.compact = false,
    this.mobileHeader = false,
    this.maxLogoSize,
  });

  /// Slightly smaller logo/text for narrow headers or drawer.
  final bool compact;

  /// Mobile top bar: maximize text space and scale to fit without ellipsis.
  final bool mobileHeader;

  /// Caps logo diameter (e.g. header bar height minus vertical padding).
  final double? maxLogoSize;

  @override
  Widget build(BuildContext context) {
    final primaryColor = AppTheme.dashTextPrimaryOf(context);
    final taglineColor = AppTheme.dashTextSecondaryOf(context);
    final baseLogo = mobileHeader ? 44.0 : (compact ? 56.0 : 72.0);
    var logoSize = baseLogo;
    final cap = maxLogoSize;
    if (cap != null && logoSize > cap) {
      logoSize = cap;
    }
    final titleSize = mobileHeader ? 9.5 : (compact ? 9.5 : 11.0);
    final tagSize = mobileHeader ? 7.5 : (compact ? 7.0 : 8.0);

    final titleStyle = TextStyle(
      color: primaryColor,
      fontSize: titleSize,
      fontWeight: FontWeight.w800,
      height: 1.15,
      letterSpacing: mobileHeader ? 0.2 : 0.35,
    );
    final taglineStyle = TextStyle(
      color: taglineColor.withValues(alpha: 0.88),
      fontSize: tagSize,
      fontWeight: FontWeight.w400,
      height: 1.1,
      letterSpacing: mobileHeader ? 0.25 : 0.4,
    );

    Widget titleBlock() {
      final lines = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('HUMAN RESOURCE', style: titleStyle, maxLines: 1),
          Text('MANAGEMENT SYSTEM', style: titleStyle, maxLines: 1),
          SizedBox(height: mobileHeader ? 1 : (compact ? 2 : 4)),
          Text('INTEGRATED SOLUTIONS', style: taglineStyle, maxLines: 1),
        ],
      );

      if (mobileHeader) {
        return FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: lines,
        );
      }

      return lines;
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        PlaridelCircleLogo(size: logoSize),
        SizedBox(width: mobileHeader ? 6 : (compact ? 8 : 12)),
        Expanded(child: titleBlock()),
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
    this.sidebarCollapsed = false,
    this.compactActions = false,
    this.onViewAllNotifications,
    this.onNotificationTap,
  });

  final Widget trailing;
  final VoidCallback? onViewAllNotifications;
  final void Function(NotificationTapResult? result)? onNotificationTap;

  /// When false (desktop), brand lives in the sidebar rail; this bar is actions only.
  final bool showBrand;
  final bool showMenuButton;
  final VoidCallback? onMenuPressed;

  /// Desktop rail collapse — hamburger at start of content header (edusync-style).
  final bool showSidebarToggle;
  final VoidCallback? onSidebarToggle;
  final bool sidebarCollapsed;
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
              icon: AnimatedRotation(
                turns: sidebarCollapsed ? 0.5 : 0,
                duration: kDashboardSidebarAnimationDuration,
                curve: Curves.easeInOutCubic,
                child: const Icon(Icons.menu_rounded),
              ),
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
            Expanded(
              child: DashboardHeaderBrand(
                compact: showMenuButton || isNarrow,
                mobileHeader: isNarrow,
                maxLogoSize: barH - 16,
              ),
            )
          else
            const Spacer(),
          DashboardHeaderActions(
            compact: compact,
            onViewAllNotifications: onViewAllNotifications,
            onNotificationTap: onNotificationTap,
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
  const SidebarRailHeader({super.key, this.collapsed = false});

  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    final hairline = AppTheme.dashHairlineOf(context);
    final barH = dashboardHeaderBarHeight(context);

    final t = SidebarCollapseScope.maybeOf(context) ?? (collapsed ? 1.0 : 0.0);
    final hPad = lerpDouble(10, 4, t)!;

    return Container(
      height: barH,
      padding: EdgeInsets.symmetric(horizontal: hPad),
      decoration: BoxDecoration(
        color: AppTheme.dashPanelOf(context),
        border: Border(bottom: BorderSide(color: hairline)),
      ),
      child: sidebarCollapseCrossfade(
        expanded: Align(
          alignment: Alignment.centerLeft,
          child: DashboardHeaderBrand(compact: true, maxLogoSize: barH - 14),
        ),
        collapsed: const Center(child: _SidebarRailMedallion()),
      ),
    );
  }
}

/// Collapsed rail logo — seal + rotating orange accent arc.
class _SidebarRailMedallion extends StatelessWidget {
  const _SidebarRailMedallion();

  @override
  Widget build(BuildContext context) {
    const size = 48.0;
    return SidebarRotatingAccentRing(
      size: size,
      boxShadow: [
        BoxShadow(
          color: AppTheme.primaryNavy.withValues(alpha: 0.2),
          blurRadius: 14,
          offset: const Offset(0, 4),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: PlaridelCircleLogo(
          size: size - 10,
          borderWidth: 0,
          showShadow: false,
          innerPaddingFactor: 0.1,
        ),
      ),
    );
  }
}

class _SidebarRailLogoMark extends StatelessWidget {
  const _SidebarRailLogoMark({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return PlaridelCircleLogo(size: size, showShadow: false);
  }
}
