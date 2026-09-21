import 'package:flutter/widgets.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/admin/desktop/pages/admin_leave_desktop_page.dart'
    as desktop;

class AdminLeaveScreen extends StatelessWidget {
  const AdminLeaveScreen({
    super.key,
    this.isDepartmentHead = false,
    this.canReviewPending = true,
  });

  final bool isDepartmentHead;
  final bool canReviewPending;

  @override
  Widget build(BuildContext context) {
    return desktop.AdminLeaveScreen(
      isDepartmentHead: isDepartmentHead,
      canReviewPending: canReviewPending,
    );
  }
}
