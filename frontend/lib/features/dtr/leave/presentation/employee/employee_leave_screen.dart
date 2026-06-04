import 'package:flutter/widgets.dart';
import 'package:hrms_plaridel/core/utils/platform_layout.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/employee/desktop/pages/employee_leave_desktop_page.dart'
    as desktop;
import 'package:hrms_plaridel/features/dtr/leave/presentation/employee/mobile/pages/employee_leave_mobile_page.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/employee/web/pages/employee_leave_web_page.dart';

class EmployeeLeaveScreen extends StatelessWidget {
  const EmployeeLeaveScreen({
    super.key,
    this.onFileLeavePressed,
    this.showFileLeaveAction = true,
  });

  final VoidCallback? onFileLeavePressed;
  final bool showFileLeaveAction;

  @override
  Widget build(BuildContext context) {
    return PlatformLayoutBuilder(
      mobile: (_) => EmployeeLeaveMobilePage(
        onFileLeavePressed: onFileLeavePressed,
        showFileLeaveAction: showFileLeaveAction,
      ),
      web: (_) => EmployeeLeaveWebPage(
        onFileLeavePressed: onFileLeavePressed,
        showFileLeaveAction: showFileLeaveAction,
      ),
      desktop: (_) => desktop.EmployeeLeaveScreen(
        onFileLeavePressed: onFileLeavePressed,
        showFileLeaveAction: showFileLeaveAction,
      ),
    );
  }
}
