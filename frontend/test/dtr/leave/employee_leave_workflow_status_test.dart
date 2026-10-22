import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_request.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_type.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/employee/shared/widgets/employee_leave_requests_panel.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/shared/widgets/leave_status_chip.dart';

void main() {
  const steps = [
    {
      'label': 'Department Review',
      'assignee_source': 'submitter_department_reviewers',
    },
    {'label': 'HR Review', 'assignee_source': 'final_hr_reviewers'},
    {'label': 'Mayor Approval', 'assignee_source': 'active_mayor'},
  ];

  for (final width in [1200.0, 420.0]) {
    for (final current in [0, 1, 2]) {
      testWidgets(
        'employee badges show workflow step $current at width $width',
        (tester) async {
          await mountRequest(
            tester,
            width,
            LeaveRequest(
              id: 'request',
              userId: 'employee',
              leaveType: LeaveType.vacationLeave,
              status: current == 2
                  ? LeaveRequestStatus.pendingMayor
                  : LeaveRequestStatus.pendingHr,
              workflowSnapshot: {
                'name': 'Department → HR → Mayor',
                'version': 1,
                'steps': steps,
                'current_step': current,
              },
            ),
          );
          final expected = 'Pending ${steps[current]['label']}';
          expect(find.text(expected), findsOneWidget);
          await tester.tap(find.text('Vacation Leave').first);
          await tester.pumpAndSettle();
          expect(find.text('Leave details'), findsOneWidget);
          final details = find.byKey(const Key('employee-leave-details-panel'));
          expect(
            find.descendant(of: details, matching: find.text(expected)),
            findsOneWidget,
          );
          expect(
            find.descendant(of: details, matching: find.text('Pending HR')),
            findsNothing,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final status in [
    LeaveRequestStatus.draft,
    LeaveRequestStatus.returned,
    LeaveRequestStatus.approved,
    LeaveRequestStatus.rejectedByHr,
    LeaveRequestStatus.cancelled,
  ]) {
    testWidgets('completed and editable states keep ${status.displayName}', (
      tester,
    ) async {
      await mountRequest(
        tester,
        1200,
        LeaveRequest(
          id: 'request',
          userId: 'employee',
          leaveType: LeaveType.vacationLeave,
          status: status,
          workflowSnapshot: {'steps': steps, 'current_step': 0},
        ),
      );
      expect(
        find.widgetWithText(LeaveStatusChip, status.displayName),
        findsOneWidget,
      );
    });
  }

  testWidgets('legacy leave without a workflow keeps its status label', (
    tester,
  ) async {
    await mountRequest(
      tester,
      1200,
      const LeaveRequest(
        id: 'request',
        userId: 'employee',
        leaveType: LeaveType.vacationLeave,
        status: LeaveRequestStatus.pendingDepartmentHead,
      ),
    );
    expect(find.text('Pending Department Head'), findsOneWidget);
  });
}

Future<void> mountRequest(
  WidgetTester tester,
  double width,
  LeaveRequest request,
) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 1000);
  addTearDown(() {
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
  });
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: EmployeeLeaveRequestsPanel(
            requests: [request],
            loading: false,
            error: null,
            onRetry: () {},
            totalRequests: 1,
            hasMore: false,
            loadingMore: false,
            loadMoreError: null,
            onLoadMore: () {},
            onEdit: (_) {},
            onCancel: (_) {},
            onDiscard: (_) {},
            onPrint: (_) {},
            onPreview: (_) {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
