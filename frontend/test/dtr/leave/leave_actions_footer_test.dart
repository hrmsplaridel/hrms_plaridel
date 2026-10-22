import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/providers/leave_provider.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/repositories/mock_leave_repository.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_request.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_type.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/admin/widgets/admin_leave_details_side_sheet.dart';

void main() {
  for (final width in [1100.0, 360.0]) {
    for (final approved in [false, true]) {
      testWidgets(
        'Leave action footer stays visible, width=$width approved=$approved',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(width, 640);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          final provider = LeaveProvider(repository: MockLeaveRepository());
          final request = LeaveRequest(
            id: 'request',
            userId: 'employee',
            employeeName: 'Applicant',
            leaveType: LeaveType.sickLeave,
            status: approved
                ? LeaveRequestStatus.approved
                : LeaveRequestStatus.pendingDepartmentHead,
            approvedAt: DateTime.now(),
            reason: List.filled(
              40,
              'Long reason that requires scrolling.',
            ).join(' '),
          );
          final calls = <String>[];
          addTearDown(() async {
            await tester.pumpWidget(const SizedBox.shrink());
            provider.dispose();
          });
          await tester.pumpWidget(
            ChangeNotifierProvider.value(
              value: provider,
              child: MaterialApp(
                home: Scaffold(
                  body: AdminLeaveDetailsSideSheet(
                    initial: request,
                    isDepartmentHead: true,
                    currentReviewerId: 'reviewer',
                    onApprove: (_) async => calls.add('Approve'),
                    onReturn: (_) async => calls.add('Return'),
                    onReject: (_) async => calls.add('Reject'),
                    onPreview: (_) async => calls.add('Preview Form'),
                    onPrint: (_) async => calls.add('Print Form'),
                    onRevoke: (_) async => calls.add('Revoke Approval'),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final footer = find.byKey(
            const ValueKey('leave-request-actions-footer'),
          );
          expect(footer, findsOneWidget);
          expect(find.text('Actions'), findsNothing);
          final actions = approved
              ? ['Revoke Approval', 'Preview Form', 'Print Form']
              : ['Approve', 'Return', 'Reject', 'Preview Form', 'Print Form'];
          for (final label in actions) {
            final button = find.descendant(
              of: footer,
              matching: find.text(label),
            );
            expect(button, findsOneWidget);
            expect(
              find.ancestor(
                of: button,
                matching: find.byType(SingleChildScrollView),
              ),
              findsNothing,
            );
            expect(tester.getRect(button).bottom, lessThan(640));
          }
          expect(tester.getRect(footer).bottom, closeTo(640, 1));
          final before = tester.getRect(footer);
          final body = find.byKey(
            const ValueKey('leave-request-details-scroll'),
          );
          await tester.drag(body, const Offset(0, -450));
          await tester.pumpAndSettle();
          expect(tester.getRect(footer), before);
          for (final label in actions) {
            await tester.tap(
              find.descendant(of: footer, matching: find.text(label)),
            );
          }
          expect(calls, actions);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
