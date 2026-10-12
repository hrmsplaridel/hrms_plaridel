import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/providers/leave_provider.dart';
import '../shared/pages/leave_main.dart';

/// Admins retain personal filing while reviewing assigned department requests.
class AdminMyLeaveEntry extends StatefulWidget {
  const AdminMyLeaveEntry({
    super.key,
    required this.requestsContent,
    this.approvalsContent,
    this.initialSection = LeaveSection.requests,
  });
  final Widget requestsContent;
  final Widget? approvalsContent;
  final LeaveSection initialSection;

  @override
  State<AdminMyLeaveEntry> createState() => _AdminMyLeaveEntryState();
}

class _AdminMyLeaveEntryState extends State<AdminMyLeaveEntry> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<LeaveProvider>().checkIsDepartmentHead(forceRefresh: true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final access = context.watch<LeaveProvider>();
    final assigned =
        access.canReviewPendingLeave || access.canViewReviewHistory;
    if (!assigned) return widget.requestsContent;
    return LeaveMain(
      isDepartmentHead: true,
      canReviewPending: access.canReviewPendingLeave,
      initialSection: widget.initialSection,
      employeeRequestsContent: widget.requestsContent,
      adminApprovalsContent: widget.approvalsContent,
    );
  }
}
