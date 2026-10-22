import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/dashboard/presentation/employee/mobile/widgets/employee_dashboard_mobile_nav_items.dart';
import 'package:hrms_plaridel/features/docutracker/data/providers/docutracker_provider.dart';
import 'package:hrms_plaridel/providers/auth_provider.dart';
import 'package:hrms_plaridel/shared/widgets/collapsible_dashboard_sidebar.dart';
import 'package:hrms_plaridel/shared/widgets/dashboard_header_actions.dart';
import 'package:hrms_plaridel/shared/widgets/portal_sidebar_brand.dart';

/// Left navigation drawer for the employee mobile shell.
///
/// Hosts every feature destination (Attendance, Leave, Locator, Training,
/// DocuTracker, …) so the bottom bar can stay uncluttered with just
/// Dashboard / Menu / Notifications.
class EmployeeDashboardMobileDrawer extends StatelessWidget {
  const EmployeeDashboardMobileDrawer({
    super.key,
    required this.displayName,
    required this.avatarPath,
    required this.selectedIndex,
    required this.onNavSelected,
    required this.onProfile,
  });

  final String displayName;
  final String? avatarPath;
  final int selectedIndex;
  final ValueChanged<int> onNavSelected;
  final VoidCallback onProfile;

  void _select(BuildContext context, int index) {
    Navigator.of(context).pop();
    onNavSelected(index);
  }

  @override
  Widget build(BuildContext context) {
    final hairline = AppTheme.dashHairlineOf(context);
    final pendingSignatures = context.select<DocuTrackerProvider, int>(
      (p) => p.pendingSourceSignatureActionCount,
    );

    return Drawer(
      backgroundColor: AppTheme.dashPanelOf(context),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: DashboardHeaderBrand(compact: true),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: DashboardSidebarProfileCard(
                displayName: displayName,
                subtitle: context.select<AuthProvider, String>(
                  (auth) => dashboardAccountRoleLabel(auth.user?.role),
                ),
                avatarPath: avatarPath,
                onProfile: () {
                  Navigator.of(context).pop();
                  onProfile();
                },
              ),
            ),
            Divider(height: 1, color: hairline),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  for (var i = 0;
                      i < employeeDashboardMobileNavItems.length;
                      i++)
                    DashboardSidebarNavTile(
                      icon: employeeDashboardMobileNavItems[i].icon,
                      label: employeeDashboardMobileNavItems[i].label,
                      selected: selectedIndex == i,
                      badgeCount: i == 6 ? pendingSignatures : 0,
                      onTap: () => _select(context, i),
                    ),
                ],
              ),
            ),
            Divider(height: 1, color: hairline),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Text(
                '© ${DateTime.now().year} HRMS',
                style: TextStyle(
                  color: AppTheme.dashTextSecondaryOf(
                    context,
                  ).withValues(alpha: 0.85),
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

