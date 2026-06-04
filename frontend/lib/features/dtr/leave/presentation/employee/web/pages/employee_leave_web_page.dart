import 'package:flutter/widgets.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/employee/desktop/pages/employee_leave_desktop_page.dart'
    as desktop;

class EmployeeLeaveWebPage extends StatelessWidget {
  const EmployeeLeaveWebPage({
    super.key,
    this.onFileLeavePressed,
    this.showFileLeaveAction = true,
  });

  final VoidCallback? onFileLeavePressed;
  final bool showFileLeaveAction;

  @override
  Widget build(BuildContext context) {
    return desktop.EmployeeLeaveScreen(
      onFileLeavePressed: onFileLeavePressed,
      showFileLeaveAction: showFileLeaveAction,
    );
  }
}
