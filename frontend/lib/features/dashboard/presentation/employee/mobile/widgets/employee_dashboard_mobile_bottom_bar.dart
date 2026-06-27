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
    final hairline = AppTheme.dashHairlineOf(context);
    final panel = AppTheme.dashPanelOf(context);
    final hrmsUnread = context.select<NotificationProvider, int>(
      (p) => p.unreadCount,
    );
    final docUnread = context.select<DocuTrackerProvider, int>(
      (p) => p.unreadNotificationsCount,
    );
    final unread = hrmsUnread + docUnread;

    return Material(
      color: panel,
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: hairline)),
        ),
        child: SafeArea(
          top: false,
          minimum: const EdgeInsets.only(bottom: 4),
          child: SizedBox(
            height: DashboardMobileBottomNav.barHeight,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
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
            ),
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
    final fg = selected ? Colors.white : inactive;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              color: selected ? AppTheme.primaryNavy : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                _IconWithBadge(icon: icon, color: fg, badgeCount: badgeCount),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: fg,
                      fontSize: 10.5,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      height: 1.0,
                      letterSpacing: -0.1,
                    ),
                  ),
                ),
              ],
            ),
          ),
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
