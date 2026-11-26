import 'package:flutter/material.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';

/// Page names for the admin DTR section indexes (see `_DtrContentState`).
/// Names match the DTR home cards and Workforce Setup tabs.
String adminDtrSectionTitle(int section) => switch (section) {
  1 => 'Time Logs',
  2 => 'Reports',
  3 => 'Employees',
  4 => 'Assignments',
  5 => 'Departments',
  6 => 'Positions',
  7 => 'Shifts',
  8 => 'Leave Management',
  9 => 'Holidays',
  10 => 'Attendance Policies',
  11 => 'Biometric Devices',
  12 => 'Locator & Pass Management',
  13 => 'Weekly Schedule',
  14 => 'Approvals & Signatories',
  _ => 'DTR',
};

class AdminDtrCrumb {
  const AdminDtrCrumb(this.label, [this.onTap]);
  final String label;

  /// Null for the current page (last crumb).
  final VoidCallback? onTap;
}

/// "DTR › Workforce Setup › Shifts" trail shown above a DTR page.
class AdminDtrBreadcrumb extends StatelessWidget {
  const AdminDtrBreadcrumb({super.key, required this.trail});

  final List<AdminDtrCrumb> trail;

  @override
  Widget build(BuildContext context) {
    final dark = AppTheme.dashIsDark(context);
    final link = dark ? AppTheme.primaryNavyLight : AppTheme.primaryNavy;
    final muted = AppTheme.dashTextSecondaryOf(context);

    return Semantics(
      container: true,
      label: 'Breadcrumb',
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (var i = 0; i < trail.length; i++) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Icon(Icons.chevron_right_rounded, size: 18, color: muted),
              ),
            if (trail[i].onTap != null)
              TextButton(
                onPressed: trail[i].onTap,
                style: TextButton.styleFrom(
                  foregroundColor: link,
                  minimumSize: const Size(0, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  textStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: Text(trail[i].label),
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  trail[i].label,
                  style: TextStyle(
                    color: AppTheme.dashTextPrimaryOf(context),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
