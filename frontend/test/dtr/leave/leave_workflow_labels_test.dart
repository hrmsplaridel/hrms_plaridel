import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_request.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_request_history.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_type.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/admin/widgets/admin_leave_screen_utils.dart';
import 'package:hrms_plaridel/features/dtr/leave/utils/leave_workflow_labels.dart';

void main() {
  final specific = <String, dynamic>{
    'steps': [
      {'label': 'Records verification', 'assignee_source': 'specific_users'},
    ],
    'current_step': 1,
  };

  for (final departmentView in [true, false]) {
    for (final status in [LeaveRequestStatus.approved, LeaveRequestStatus.rejectedByHr]) {
      test('specific-person $status stays neutral, department view=$departmentView', () {
        expect(adminLeaveStatusLabel(status,
          isDepartmentHead: departmentView,
          workflowSnapshot: specific,
        ), status == LeaveRequestStatus.approved ? 'Approved' : 'Rejected');
      });
    }
  }

  test('legacy compatibility statuses do not infer an HR role', () {
    expect(LeaveRequestStatus.pendingHr.displayName, 'Pending review');
    expect(LeaveRequestStatus.rejectedByHr.displayName, 'Rejected');
    expect(adminLeaveStatusLabel(LeaveRequestStatus.pendingHr,
      isDepartmentHead: true,
    ), 'Forwarded for review');
  });

  test('manual Mayor signing is retained for approved Leave forms', () {
    const request = LeaveRequest(
      userId: 'employee', leaveType: LeaveType.vacationLeave,
      status: LeaveRequestStatus.approved, finalReviewRoute: 'mayor',
    );
    expect(request.statusLabel, 'Approved for manual Mayor signing');
    expect(adminLeaveStatusLabel(request.status,
      isDepartmentHead: true, finalReviewRoute: 'mayor',
    ), request.statusLabel);
  });

  for (final action in ['approved', 'rejected', 'returned', 'workflow_step_approved']) {
    test('history $action does not invent HR or Mayor without a saved step', () {
      final entry = LeaveRequestHistoryEntry(
        id: 'event', requestId: 'request', action: action,
        toStatus: 'approved', fromStatus: 'pending_hr',
        actorName: 'Records Reviewer', actorRole: 'employee',
        actedAt: DateTime(2026, 10, 31),
      );
      expect(entry.actionLabel, {
        'approved': 'Approved', 'rejected': 'Rejected',
        'returned': 'Returned', 'workflow_step_approved': 'Step approved',
      }[action]);
      expect(entry.actorLabel, 'Records Reviewer');
    });
  }

  test('saved history labels retain the actual workflow step', () {
    final entry = LeaveRequestHistoryEntry(
      id: 'event', requestId: 'request', action: 'approved',
      toStatus: 'approved', actorName: 'Records Reviewer',
      actedAt: DateTime(2026, 10, 31),
      metadata: {'workflow_step': specific['steps'][0]},
    );
    expect(entry.actionLabel, 'Records verification approved');
    expect(entry.actorLabel, 'Records Reviewer');
  });

  test('approval feedback uses the next saved step instead of assuming HR', () {
    expect(leaveDepartmentApprovalMessage(
      status: 'pending_hr', workflowSnapshot: {
        'current_step': 0,
        'steps': [{'label': 'Records verification', 'assignee_source': 'specific_users'}],
      },
    ), 'Step approved. Forwarded to Records verification.');
    expect(leaveDepartmentApprovalMessage(status: 'pending_hr'),
        'Step approved. Forwarded for further review.');
    expect(leaveDepartmentApprovalMessage(status: 'approved', finalReviewRoute: 'mayor'),
        'Approved. The Mayor signs the printed form manually.');
    expect(leaveDepartmentApprovalMessage(status: 'approved', workflowSnapshot: specific),
        'Request approved.');
  });

  test('pending labels support legacy steps and ignore completed or invalid indexes', () {
    expect(leavePendingStepLabel({'steps': ['department', 'hr'], 'current_step': 1}),
        'HR Review');
    expect(leavePendingStepLabel({'steps': ['hr'], 'current_step': 1}), isNull);
    expect(leavePendingStepLabel({'steps': ['hr'], 'current_step': -1}), isNull);
    expect(leavePendingStepLabel({'steps': ['hr'], 'current_step': 0, 'outcome': 'approved'}), isNull);
  });

  test('saved specific-person steps override a stale manual route hint', () {
    expect(leaveApprovedStatusLabel('mayor', workflowSnapshot: specific), 'Approved');
  });
}
