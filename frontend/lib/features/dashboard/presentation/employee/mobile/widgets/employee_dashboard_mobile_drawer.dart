import 'package:flutter/material.dart';

import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/dashboard/presentation/employee/mobile/widgets/employee_dashboard_mobile_nav_items.dart';
import 'package:hrms_plaridel/shared/widgets/collapsible_dashboard_sidebar.dart';
import 'package:hrms_plaridel/shared/widgets/portal_sidebar_brand.dart';
import 'package:hrms_plaridel/shared/widgets/user_avatar.dart';

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
              child: _DrawerProfileTile(
                displayName: displayName,
                avatarPath: avatarPath,
                onTap: () {
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

class _DrawerProfileTile extends StatelessWidget {
  const _DrawerProfileTile({
    required this.displayName,
    required this.avatarPath,
    required this.onTap,
  });

  final String displayName;
  final String? avatarPath;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppTheme.dashMutedSurfaceOf(context),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppTheme.primaryNavy.withValues(alpha: 0.25),
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppTheme.primaryNavy.withValues(alpha: 0.5),
                    width: 2,
                  ),
                ),
                child: UserAvatar(
                  avatarPath: avatarPath,
                  radius: 20,
                  backgroundColor: AppTheme.dashHairlineOf(context),
                  placeholderIconColor: AppTheme.primaryNavy,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      displayName.isNotEmpty ? displayName : 'User',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppTheme.dashTextPrimaryOf(context),
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'View profile',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppTheme.dashTextSecondaryOf(context),
                        fontSize: 12,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 22,
                color: AppTheme.dashTextSecondaryOf(
                  context,
                ).withValues(alpha: 0.7),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
