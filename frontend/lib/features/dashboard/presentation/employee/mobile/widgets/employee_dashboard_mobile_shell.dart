import 'package:flutter/material.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/dashboard/presentation/employee/mobile/widgets/employee_dashboard_mobile_nav_items.dart';
import 'package:hrms_plaridel/features/dashboard/presentation/employee/shared/widgets/employee_dashboard_layout_metrics.dart';
import 'package:hrms_plaridel/features/notifications/models/notification_tap_result.dart';
import 'package:hrms_plaridel/shared/widgets/dashboard_content_navigator.dart';
import 'package:hrms_plaridel/shared/widgets/dashboard_header_actions.dart';
import 'package:hrms_plaridel/shared/widgets/dashboard_mobile_bottom_nav.dart';
import 'package:hrms_plaridel/shared/widgets/portal_sidebar_brand.dart';

class EmployeeDashboardMobileShell extends StatelessWidget {
  const EmployeeDashboardMobileShell({
    super.key,
    required this.width,
    required this.avatarPath,
    required this.displayName,
    required this.selectedIndex,
    required this.navigatorKey,
    required this.homeBuilder,
    required this.settingsPanel,
    required this.onNavSelected,
    required this.onProfile,
    required this.onViewAllNotifications,
    required this.onNotificationTap,
    required this.onFileLeave,
    required this.onFileLocator,
  });

  final double width;
  final String? avatarPath;
  final String displayName;
  final int selectedIndex;
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget Function({
    required bool useMobileLeaveFab,
    required bool useMobileLocatorFab,
  })
  homeBuilder;
  final Widget settingsPanel;
  final ValueChanged<int> onNavSelected;
  final VoidCallback onProfile;
  final VoidCallback onViewAllNotifications;
  final void Function(NotificationTapResult? result) onNotificationTap;
  final VoidCallback onFileLeave;
  final VoidCallback onFileLocator;

  bool get _useMobileLeaveFab => width < 600 && selectedIndex == 2;
  bool get _useMobileLocatorFab => selectedIndex == 3;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.dashCanvasOf(context),
      floatingActionButton: _buildActionButton(),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      bottomNavigationBar: DashboardMobileBottomNav(
        items: employeeDashboardMobileNavItems,
        selectedIndex: selectedIndex < employeeDashboardMobileNavItems.length
            ? selectedIndex
            : -1,
        onSelected: onNavSelected,
      ),
      body: SafeArea(
        child: Column(
          children: [
            DashboardAppHeaderBar(
              compactActions: width < 600,
              onViewAllNotifications: onViewAllNotifications,
              onNotificationTap: onNotificationTap,
              trailing: DashboardAccountMenuButton(
                avatarPath: avatarPath,
                compact: width < 600,
                tooltip: displayName,
                onProfile: onProfile,
              ),
            ),
            Expanded(
              child: ColoredBox(
                color: AppTheme.dashCanvasOf(context),
                child: DashboardContentNavigator(
                  navigatorKey: navigatorKey,
                  homeRefreshKey: Object.hash(
                    selectedIndex,
                    displayName,
                    width,
                    _useMobileLeaveFab,
                    _useMobileLocatorFab,
                  ),
                  homeBuilder: () => homeBuilder(
                    useMobileLeaveFab: _useMobileLeaveFab,
                    useMobileLocatorFab: _useMobileLocatorFab,
                  ),
                  settingsPanel: settingsPanel,
                  homeScrollPadding: employeeMainScrollPadding(
                    context,
                    mobileNav: true,
                  ),
                  settingsScrollPadding: EdgeInsets.fromLTRB(
                    12,
                    8,
                    12,
                    28 + DashboardMobileBottomNav.scrollPaddingExtra(context),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget? _buildActionButton() {
    if (!_useMobileLeaveFab && !_useMobileLocatorFab) return null;
    return FloatingActionButton.extended(
      heroTag: _useMobileLeaveFab
          ? 'employee-dashboard-file-leave-fab'
          : 'employee-dashboard-file-locator-fab',
      onPressed: _useMobileLeaveFab ? onFileLeave : onFileLocator,
      icon: const Icon(Icons.add_rounded),
      label: Text(_useMobileLeaveFab ? 'File Leave' : 'File Request'),
      backgroundColor: AppTheme.primaryNavy,
      foregroundColor: Colors.white,
    );
  }
}
