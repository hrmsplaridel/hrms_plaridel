import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/providers/leave_provider.dart';
import '../shared/pages/leave_main.dart';
import 'package:hrms_plaridel/features/dtr/management/approvals/pages/workflow_approval_inbox_page.dart';

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
  bool _hasWorkflowAssignments = false;

  Future<void> _checkWorkflowAssignments() async {
    try {
      final assigned = await loadAssignedWorkflowRequests('leave');
      if (mounted) {
        setState(() => _hasWorkflowAssignments = assigned.isNotEmpty);
      }
    } catch (_) {
      // A failed request does not establish a workflow reviewer assignment.
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<LeaveProvider>().checkIsDepartmentHead(forceRefresh: true);
        _checkWorkflowAssignments();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final access = context.watch<LeaveProvider>();
    final assigned =
        access.canReviewPendingLeave || access.canViewReviewHistory;
    if (!assigned && !_hasWorkflowAssignments) return widget.requestsContent;
    return LeaveMain(
      isDepartmentHead: assigned,
      canAccessApprovals: assigned || _hasWorkflowAssignments,
      canReviewPending: access.canReviewPendingLeave || _hasWorkflowAssignments,
      initialSection: widget.initialSection,
      employeeRequestsContent: widget.requestsContent,
      adminApprovalsContent: widget.approvalsContent,
    );
  }
}
