import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/docutracker/data/providers/docutracker_provider.dart';
import 'package:hrms_plaridel/features/notifications/data/notification_provider.dart';
import 'package:hrms_plaridel/shared/widgets/dashboard_mobile_bottom_nav.dart';

/// Compact 3-slot bottom bar for the employee mobile shell:
/// Dashboard · Menu (opens the feature drawer) · Notifications.
class EmployeeDashboardMobileBottomBar extends StatelessWidget {
  const EmployeeDashboardMobileBottomBar({
    super.key,
    required this.dashboardSelected,
    required this.menuActive,
    required this.onDashboard,
    required this.onMenu,
    required this.onNotifications,
  });

  /// Dashboard tab is the active content.
  final bool dashboardSelected;

  /// A feature opened from the drawer is the active content.
  final bool menuActive;

  final VoidCallback onDashboard;
  final VoidCallback onMenu;
  final VoidCallback onNotifications;

  @override
  Widget build(BuildContext context) {
    final panel = AppTheme.dashPanelOf(context);
    final canvas = AppTheme.dashCanvasOf(context);
    final hrmsUnread = context.select<NotificationProvider, int>(
      (p) => p.unreadCount,
    );
    final docUnread = context.select<DocuTrackerProvider, int>(
      (p) => p.unreadNotificationsCount,
    );
    final unread = hrmsUnread + docUnread;

    return ColoredBox(
      color: canvas,
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(24, 0, 24, 8),
        child: SizedBox(
          height: DashboardMobileBottomNav.barHeight,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                top: 16,
                child: Material(
                  color: panel,
                  elevation: 6,
                  shadowColor: Colors.black.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(28),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: _BottomBarItem(
                      icon: Icons.home_outlined,
                      label: 'Dashboard',
                      selected: dashboardSelected,
                      onTap: onDashboard,
                    ),
                  ),
                  Expanded(
                    child: _BottomBarItem(
                      icon: Icons.menu_rounded,
                      label: 'Menu',
                      selected: menuActive,
                      onTap: onMenu,
                    ),
                  ),
                  Expanded(
                    child: _BottomBarItem(
                      icon: Icons.notifications_outlined,
                      label: 'Notifications',
                      selected: false,
                      badgeCount: unread,
                      onTap: onNotifications,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomBarItem extends StatelessWidget {
  const _BottomBarItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.badgeCount = 0,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    final inactive = AppTheme.dashTextSecondaryOf(context);
    final accent = AppTheme.primaryNavy;
    final panel = AppTheme.dashPanelOf(context);
    final canvas = AppTheme.dashCanvasOf(context);

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkResponse(
        onTap: onTap,
        radius: 34,
        containedInkWell: true,
        highlightShape: BoxShape.rectangle,
        child: Stack(
          alignment: Alignment.topCenter,
          children: [
            AnimatedPositioned(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              top: selected ? 0 : 23,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                width: selected ? 46 : 26,
                height: selected ? 46 : 26,
                decoration: BoxDecoration(
                  color: selected ? panel : Colors.transparent,
                  shape: BoxShape.circle,
                  border: selected ? Border.all(color: canvas, width: 5) : null,
                ),
                alignment: Alignment.center,
                child: _IconWithBadge(
                  icon: icon,
                  color: selected ? accent : inactive,
                  badgeCount: badgeCount,
                ),
              ),
            ),
            Positioned(
              left: 4,
              right: 4,
              bottom: 7,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: selected ? accent : inactive,
                    fontSize: 9.5,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    height: 1,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IconWithBadge extends StatelessWidget {
  const _IconWithBadge({
    required this.icon,
    required this.color,
    required this.badgeCount,
  });

  final IconData icon;
  final Color color;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    final icon0 = Icon(icon, size: 22, color: color);
    if (badgeCount <= 0) return icon0;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        icon0,
        Positioned(
          right: -6,
          top: -4,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
            decoration: BoxDecoration(
              color: const Color(0xFFE53935),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                color: AppTheme.dashPanelOf(context),
                width: 1.2,
              ),
            ),
            child: Text(
              badgeCount > 99 ? '99+' : '$badgeCount',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                height: 1.2,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
