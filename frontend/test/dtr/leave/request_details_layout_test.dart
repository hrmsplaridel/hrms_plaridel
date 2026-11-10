import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:hrms_plaridel/core/utils/responsive_right_side_panel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/providers/leave_provider.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/repositories/mock_leave_repository.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_request.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_type.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/admin/widgets/admin_leave_details_side_sheet.dart';

void main() {
  testWidgets(
    'mobile approval details provide Material text styling on the full-screen route',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final provider = LeaveProvider(repository: MockLeaveRepository());
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: provider,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => openResponsiveRightSidePanel<void>(
                    context: context,
                    useRootNavigator: true,
                    builder: (_) => AdminLeaveDetailsSideSheet(
                      initial: const LeaveRequest(
                        userId: 'employee',
                        employeeName: 'Admin User',
                        leaveType: LeaveType.sickLeave,
                        status: LeaveRequestStatus.approved,
                        officeDepartment: 'Human Resources',
                        positionTitle: 'HR Officer',
                      ),
                      isDepartmentHead: false,
                      onApprove: (_) async {},
                      onReturn: (_) async {},
                      onReject: (_) async {},
                      onPrint: (_) async {},
                    ),
                  ),
                  child: const Text('Open approval details'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open approval details'));
      await tester.pumpAndSettle();
      for (final text in [
        'Admin User',
        'Leave Details',
        'Human Resources',
        'Salary',
      ]) {
        final paragraph = tester.renderObject<RenderParagraph>(find.text(text));
        expect(
          paragraph.text.style?.decoration,
          isNot(TextDecoration.underline),
          reason: '$text inherited fallback underline',
        );
        expect(
          paragraph.text.style?.decorationColor,
          isNot(const Color(0xffffff00)),
        );
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      provider.dispose();
    },
  );
  for (final width in [1100.0, 360.0]) {
    testWidgets('request details groups information at width $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final provider = LeaveProvider(repository: MockLeaveRepository());
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: provider,
          child: MaterialApp(
            home: Scaffold(
              body: AdminLeaveDetailsSideSheet(
                initial: const LeaveRequest(
                  userId: 'employee',
                  employeeName: 'Admin User',
                  officeDepartment: 'Human Resources',
                  positionTitle:
                      'Human Resource Management and Development Officer',
                  salary: 1234413,
                  leaveType: LeaveType.others,
                  otherPurposeDetails: 'Preventive screening',
                  reason: 'Scheduled preventive health screening.',
                  status: LeaveRequestStatus.rejectedByHr,
                ),
                isDepartmentHead: false,
                onApprove: (_) async {},
                onReturn: (_) async {},
                onReject: (_) async {},
                onPrint: (_) async {},
              ),
            ),
          ),
        ),
      );
      expect(find.text('Employee Information'), findsOneWidget);
      expect(find.text('Leave Details'), findsOneWidget);
      expect(find.text('Additional Context'), findsOneWidget);
      expect(find.text('₱1,234,413.00'), findsOneWidget);
      final department = tester.getTopLeft(find.text('Human Resources'));
      final position = tester.getTopLeft(
        find.text('Human Resource Management and Development Officer'),
      );
      if (width > 600) {
        expect(position.dy, department.dy);
        expect(position.dx, greaterThan(department.dx));
      } else {
        expect(position.dy, greaterThan(department.dy));
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      provider.dispose();
    });
  }
}
