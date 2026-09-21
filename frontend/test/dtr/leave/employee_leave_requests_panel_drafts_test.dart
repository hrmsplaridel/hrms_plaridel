import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_request.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_type.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/employee/shared/widgets/employee_leave_requests_panel.dart';

void main() {
  testWidgets('Drafts tab shows only editable draft requests', (tester) async {
    final draft = _request(
      id: 'draft-request',
      type: LeaveType.vacationLeave,
      status: LeaveRequestStatus.draft,
    );
    final approved = _request(
      id: 'approved-request',
      type: LeaveType.sickLeave,
      status: LeaveRequestStatus.approved,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: EmployeeLeaveRequestsPanel(
              requests: [draft, approved],
              loading: false,
              error: null,
              onRetry: () {},
              totalRequests: 2,
              hasMore: false,
              loadingMore: false,
              loadMoreError: null,
              onLoadMore: () {},
              onEdit: (_) {},
              onCancel: (_) {},
              onPrint: (_) {},
              onPreview: (_) {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('Vacation Leave'), findsOneWidget);
    expect(find.text('Sick Leave'), findsOneWidget);

    await tester.tap(find.text('Drafts'));
    await tester.pump();

    expect(find.text('Vacation Leave'), findsOneWidget);
    expect(find.text('Sick Leave'), findsNothing);
  });
}

LeaveRequest _request({
  required String id,
  required LeaveType type,
  required LeaveRequestStatus status,
}) {
  return LeaveRequest(
    id: id,
    userId: 'employee-a',
    leaveType: type,
    startDate: DateTime(2026, 9, 21),
    endDate: DateTime(2026, 9, 21),
    workingDaysApplied: 1,
    status: status,
  );
}
