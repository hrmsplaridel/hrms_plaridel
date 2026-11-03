import 'package:flutter/widgets.dart';
import 'package:hrms_plaridel/features/dashboard/presentation/employee/desktop/pages/employee_dashboard_desktop_page.dart'
    as desktop;

export 'package:hrms_plaridel/features/dashboard/presentation/employee/desktop/pages/employee_dashboard_desktop_page.dart'
    show EmployeeAttendanceDetailsSection, EmployeeAttendanceOverviewSection;

class EmployeeDashboard extends StatelessWidget {
  const EmployeeDashboard({super.key});

  /// Survives former PlatformLayoutBuilder mobile/web/desktop wrapper swaps so
  /// nested DocuTracker routes and editor state are not disposed on resize.
  static final GlobalKey _hostKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    // Mobile/desktop chrome is handled inside the page from MediaQuery width.
    // Do not swap MobilePage / WebPage wrappers here — that remounted State.
    return desktop.EmployeeDashboardDesktopPage(key: _hostKey);
  }
}
