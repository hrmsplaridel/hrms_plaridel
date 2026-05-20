import 'package:flutter/material.dart';

import '../../landingpage/constants/app_theme.dart';
import '../../notifications/notification_tap_result.dart';
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
  const SidebarRailHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final hairline = AppTheme.dashHairlineOf(context);
    final barH = dashboardHeaderBarHeight(context);

    return Container(
      height: barH,
      width: kDashboardSidebarWidth,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: AppTheme.dashPanelOf(context),
        border: Border(
          bottom: BorderSide(color: hairline),
        ),
      ),
      child: const DashboardHeaderBrand(compact: true),
    );
  }
}
