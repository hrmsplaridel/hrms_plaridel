import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/providers/leave_provider.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/repositories/mock_leave_repository.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_request.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_type.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/admin/widgets/admin_leave_details_side_sheet.dart';

void main() {
  testWidgets('leave details offer preview separately from print', (
    tester,
  ) async {
    final provider = LeaveProvider(repository: MockLeaveRepository());
    addTearDown(provider.dispose);
    var previews = 0;
    var prints = 0;
    final request = LeaveRequest(
      id: 'approved-leave',
      userId: 'employee',
      leaveType: LeaveType.vacationLeave,
      status: LeaveRequestStatus.approved,
    );

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: MaterialApp(
          home: Scaffold(
            body: AdminLeaveDetailsSideSheet(
              initial: request,
              isDepartmentHead: false,
              onApprove: (_) async {},
              onReturn: (_) async {},
              onReject: (_) async {},
              onPreview: (_) async => previews++,
              onPrint: (_) async => prints++,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Preview Form'), findsOneWidget);
    expect(find.text('Print Form'), findsOneWidget);
    await tester.ensureVisible(find.text('Preview Form'));
    await tester.tap(find.text('Preview Form'));
    await tester.pump();
    expect(previews, 1);
    expect(prints, 0);
  });
}
