import 'package:flutter/widgets.dart';
import 'package:hrms_plaridel/core/utils/platform_layout.dart';
import 'package:hrms_plaridel/features/dashboard/presentation/employee/desktop/pages/employee_dashboard_desktop_page.dart'
    as desktop;
import 'package:hrms_plaridel/features/dashboard/presentation/employee/mobile/pages/employee_dashboard_mobile_page.dart';
import 'package:hrms_plaridel/features/dashboard/presentation/employee/web/pages/employee_dashboard_web_page.dart';

export 'package:hrms_plaridel/features/dashboard/presentation/employee/desktop/pages/employee_dashboard_desktop_page.dart'
    show EmployeeAttendanceOverviewSection;

class EmployeeDashboard extends StatelessWidget {
  const EmployeeDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return PlatformLayoutBuilder(
      mobile: (_) => const EmployeeDashboardMobilePage(),
      web: (_) => const EmployeeDashboardWebPage(),
      desktop: (_) => const desktop.EmployeeDashboardDesktopPage(),
    );
  }
}
