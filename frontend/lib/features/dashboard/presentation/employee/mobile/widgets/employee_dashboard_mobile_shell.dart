import 'package:flutter/material.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/dashboard/presentation/employee/mobile/widgets/employee_dashboard_mobile_bottom_bar.dart';
import 'package:hrms_plaridel/features/dashboard/presentation/employee/mobile/widgets/employee_dashboard_mobile_drawer.dart';
import 'package:hrms_plaridel/features/dashboard/presentation/employee/mobile/widgets/employee_dashboard_mobile_nav_items.dart';
import 'package:hrms_plaridel/features/dashboard/presentation/employee/tutorial/employee_tutorial_controller.dart';
import 'package:hrms_plaridel/features/notifications/models/notification_tap_result.dart';
import 'package:hrms_plaridel/shared/widgets/portal_sidebar_brand.dart';

class EmployeeDashboardMobileShell extends StatelessWidget {
  const EmployeeDashboardMobileShell({
    super.key,
    required this.width,
    required this.avatarPath,
    required this.displayName,
    required this.selectedIndex,
    required this.content,
    required this.onNavSelected,
    required this.onProfile,
    required this.onViewAllNotifications,
    required this.onNotificationTap,
    required this.onFileLeave,
    required this.onFileLocator,
    required this.onTutorial,
    required this.showMobileLeaveFab,
  });

  final double width;
  final String? avatarPath;
  final String displayName;
  final int selectedIndex;

  /// Nested dashboard content navigator owned by the parent page so desktop ↔
  /// mobile chrome swaps do not remount routes or dispose open documents.
  final Widget content;
  final ValueChanged<int> onNavSelected;
  final VoidCallback onProfile;
  final VoidCallback onViewAllNotifications;
  final void Function(NotificationTapResult? result) onNotificationTap;
  final VoidCallback onFileLeave;
  final VoidCallback onFileLocator;
  final VoidCallback onTutorial;
  final bool showMobileLeaveFab;

  bool get _useMobileLeaveFab =>
      width < 600 && selectedIndex == 2 && showMobileLeaveFab;
  bool get _useMobileLocatorFab => selectedIndex == 3;

  @override
  Widget build(BuildContext context) {
    final menuActive =
        selectedIndex >= 1 &&
        selectedIndex < employeeDashboardMobileNavItems.length;

    return Scaffold(
      backgroundColor: AppTheme.dashCanvasOf(context),
      drawer: EmployeeDashboardMobileDrawer(
        displayName: displayName,
        avatarPath: avatarPath,
        selectedIndex: selectedIndex,
        onNavSelected: onNavSelected,
        onProfile: onProfile,
      ),
      bottomNavigationBar: Builder(
        builder: (innerContext) => EmployeeDashboardMobileBottomBar(
          dashboardSelected: selectedIndex == 0,
          menuActive: menuActive,
          onDashboard: () => onNavSelected(0),
          onMenu: () => Scaffold.of(innerContext).openDrawer(),
          onNotifications: onViewAllNotifications,
        ),
      ),
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                DashboardAppHeaderBar(
                  compactActions: width < 600,
                  showNotifications: false,
                  onViewAllNotifications: onViewAllNotifications,
                  onNotificationTap: onNotificationTap,
                  trailing: EmployeeTutorialButton(onPressed: onTutorial),
                ),
                Expanded(
                  child: ColoredBox(
                    color: AppTheme.dashCanvasOf(context),
                    child: content,
                  ),
                ),
              ],
            ),
          ),
          if (_buildFileActionButton() case final actionButton?)
            Positioned(right: 16, bottom: 16, child: actionButton),
        ],
      ),
    );
  }

  Widget? _buildFileActionButton() {
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
