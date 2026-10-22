import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_request.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_type.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/employee/desktop/widgets/employee_leave_desktop_requests_content.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/shared/widgets/leave_status_chip.dart';

void main() {
  for (final width in [1040.0, 1560.0]) {
    for (final status in [
      LeaveRequestStatus.pendingDepartmentHead,
      LeaveRequestStatus.approved,
      LeaveRequestStatus.cancelled,
    ]) {
      testWidgets('table headers align with $status at width $width', (
        tester,
      ) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 600);
        addTearDown(() {
          tester.view.resetDevicePixelRatio();
          tester.view.resetPhysicalSize();
        });
        final controller = ScrollController();
        addTearDown(controller.dispose);
        final request = LeaveRequest(
          id: 'request',
          userId: 'employee',
          leaveType: LeaveType.vacationLeave,
          startDate: DateTime(2026, 10, 20),
          endDate: DateTime(2026, 10, 20),
          dateFiled: DateTime(2026, 10, 18),
          workingDaysApplied: 1,
          status: status,
        );
        LeaveRequest? opened;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: EmployeeLeaveDesktopRequestsContent(
                filters: const SizedBox.shrink(),
                requests: [request],
                allRequests: [request],
                loading: false,
                maxListHeight: 300,
                scrollController: controller,
                onOpenRequest: (value) => opened = value,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        for (final column in {
          'Leave Type': 'Vacation Leave',
          'Date Range': 'Oct 20, 2026 – Oct 20, 2026',
          'Days': '1.0',
          'Submitted': 'Oct 18, 2026',
        }.entries) {
          expect(
            tester.getTopLeft(find.text(column.key)).dx,
            closeTo(tester.getTopLeft(find.text(column.value)).dx, 0.5),
            reason: '${column.key} should align with its values',
          );
        }
        expect(
          tester.getCenter(find.text('Status')).dx,
          closeTo(tester.getCenter(find.byType(LeaveStatusChip)).dx, 0.5),
          reason: 'Status should be centered above its badge',
        );
        await tester.tap(find.text('Vacation Leave'));
        expect(opened, same(request));
        expect(tester.takeException(), isNull);
      });
    }
  }
}
