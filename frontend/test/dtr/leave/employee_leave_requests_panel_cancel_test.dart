import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_request.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_type.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/employee/shared/widgets/employee_leave_requests_panel.dart';

void main() {
  const cancellableStatuses = {
    LeaveRequestStatus.pending,
    LeaveRequestStatus.pendingDepartmentHead,
    LeaveRequestStatus.pendingHr,
    LeaveRequestStatus.returned,
  };

  for (final status in LeaveRequestStatus.values) {
    testWidgets('Cancel action follows employee workflow for ${status.name}', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 1000);
      addTearDown(() {
        tester.view.resetDevicePixelRatio();
        tester.view.resetPhysicalSize();
      });
      final request = LeaveRequest(
        id: 'request-${status.name}',
        userId: 'employee-a',
        leaveType: LeaveType.vacationLeave,
        startDate: DateTime(2026, 9, 21),
        endDate: DateTime(2026, 9, 22),
        workingDaysApplied: 2,
        status: status,
      );
      final cancelled = <LeaveRequest>[];
      final discarded = <LeaveRequest>[];
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
                onCancel: cancelled.add,
                onDiscard: discarded.add,
                onPrint: (_) {},
                onPreview: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Vacation Leave'));
      await tester.pumpAndSettle();
      expect(find.text('Leave details'), findsOneWidget);

      final cancel = find.widgetWithText(OutlinedButton, 'Cancel');
      final discard = find.widgetWithText(OutlinedButton, 'Discard');
      if (status == LeaveRequestStatus.draft) {
        expect(cancel, findsNothing);
        expect(discard, findsOneWidget);
        await tester.tap(discard);
        await tester.pumpAndSettle();
        expect(discarded, [same(request)]);
        expect(cancelled, isEmpty);
        return;
      }
      expect(discard, findsNothing);
      if (cancellableStatuses.contains(status)) {
        expect(cancel, findsOneWidget);
        if (status == LeaveRequestStatus.returned) {
          expect(find.widgetWithText(OutlinedButton, 'Edit'), findsOneWidget);
        }
        await tester.tap(cancel);
        await tester.pumpAndSettle();
        expect(cancelled, [same(request)]);
        expect(find.text('Leave details'), findsNothing);
      } else {
        expect(cancel, findsNothing);
        expect(cancelled, isEmpty);
      }
      expect(tester.takeException(), isNull);
    });
  }
}
