import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/providers/leave_provider.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/repositories/mock_leave_repository.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_request.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_type.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/admin/widgets/admin_leave_details_side_sheet.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/admin/widgets/admin_leave_request_queue.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/shared/widgets/leave_status_chip.dart';

void main() {
  for (final width in [1440.0, 420.0]) {
    for (final status in [
      LeaveRequestStatus.pendingHr,
      LeaveRequestStatus.approved,
      LeaveRequestStatus.rejectedByHr,
    ]) {
      testWidgets('specific-person Leave $status queue and details at $width', (tester) async {
        tester.view.physicalSize = Size(width, 1400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final provider = LeaveProvider(repository: MockLeaveRepository());
        addTearDown(provider.dispose);
        final request = LeaveRequest(
          id: 'specific', userId: 'applicant', employeeName: 'Applicant',
          leaveType: LeaveType.sickLeave, status: status,
          workflowSnapshot: {
            'current_step': status.isPending ? 0 : 1,
            'steps': [
              {'label': 'Records verification', 'assignee_source': 'specific_users'},
            ],
            'decisions': [
              if (!status.isPending) {
                'step': 0,
                'action': status == LeaveRequestStatus.approved ? 'approve' : 'reject',
                'reviewer_name': 'Records Reviewer',
                'acted_at': '2026-10-31T08:00:00Z',
              },
            ],
          },
        );
        final expected = status.isPending ? 'Pending Records verification'
            : status == LeaveRequestStatus.approved ? 'Approved' : 'Rejected';
        await tester.pumpWidget(MaterialApp(home: Scaffold(
          body: SingleChildScrollView(child: AdminLeaveRequestQueuePanel(
            requests: [request], filterKey: 'test', isDepartmentHead: true,
            loading: false, initialLoadComplete: true, initialLoadAttempted: true,
            onRetry: () {}, totalCount: 1, hasMore: false, loadingMore: false,
            loadMoreError: null, onLoadMore: () {}, selectedRequest: null,
            filterBar: const SizedBox.shrink(), onSelect: (_) {},
          )),
        )));
        await tester.pumpAndSettle();
        expect(find.widgetWithText(LeaveStatusChip, expected), findsOneWidget);
        await tester.pumpWidget(ChangeNotifierProvider.value(
          value: provider,
          child: MaterialApp(home: Scaffold(body: AdminLeaveDetailsSideSheet(
            initial: request, isDepartmentHead: true,
            onApprove: (_) async {}, onReturn: (_) async {},
            onReject: (_) async {}, onPrint: (_) async {},
          ))),
        ));
        await tester.pumpAndSettle();
        expect(find.widgetWithText(LeaveStatusChip, expected), findsOneWidget);
        expect(find.text('Approved by HR'), findsNothing);
        expect(find.text('Rejected by HR'), findsNothing);
        if (!status.isPending) {
          expect(find.textContaining('Records Reviewer'), findsWidgets);
          expect(find.text('Records verification · $expected'), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('direct-to-HR leave does not invent department approval', (
    tester,
  ) async {
    final provider = LeaveProvider(repository: MockLeaveRepository());
    addTearDown(provider.dispose);
    final request = LeaveRequest(
      id: 'head-own-leave',
      userId: 'department-head',
      leaveType: LeaveType.sickLeave,
      status: LeaveRequestStatus.pendingHr,
    );
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: provider,
      child: MaterialApp(home: Scaffold(body: AdminLeaveDetailsSideSheet(
        initial: request,
        isDepartmentHead: false,
        onApprove: (_) async {},
        onReturn: (_) async {},
        onReject: (_) async {},
        onPrint: (_) async {},
      ))),
    ));
    expect(find.text('Approved by Department Reviewer'), findsNothing);
    expect(find.text('Forwarded to HR'), findsNothing);
    expect(find.text('Pending review'), findsWidgets);
  });

  testWidgets('recorded backup approval remains visible in leave history', (
    tester,
  ) async {
    final provider = LeaveProvider(repository: MockLeaveRepository());
    addTearDown(provider.dispose);
    final request = LeaveRequest(
      id: 'reviewed-head-leave',
      userId: 'department-head',
      leaveType: LeaveType.sickLeave,
      status: LeaveRequestStatus.pendingHr,
      departmentHeadAction: 'department_head_approved',
      departmentHeadReviewerName: 'Backup Reviewer',
      departmentHeadReviewedAt: DateTime(2026, 9, 22, 9),
    );
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: provider,
      child: MaterialApp(home: Scaffold(body: AdminLeaveDetailsSideSheet(
        initial: request,
        isDepartmentHead: false,
        onApprove: (_) async {},
        onReturn: (_) async {},
        onReject: (_) async {},
        onPrint: (_) async {},
      ))),
    ));
    expect(find.text('Approved by Department Reviewer'), findsOneWidget);
    expect(find.text('Forwarded for review'), findsOneWidget);
    expect(find.textContaining('Backup Reviewer'), findsWidgets);
  });

  testWidgets('unassigned final reviewer sees no decision actions', (tester) async {
    final provider = LeaveProvider(repository: MockLeaveRepository());
    addTearDown(provider.dispose);
    final request = LeaveRequest(
      id: 'pending-leave',
      userId: 'employee',
      leaveType: LeaveType.vacationLeave,
      status: LeaveRequestStatus.pendingHr,
    );
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: MaterialApp(
          home: Scaffold(
            body: AdminLeaveDetailsSideSheet(
              initial: request,
              isDepartmentHead: false,
              canReviewPending: false,
              onApprove: (_) async {},
              onReturn: (_) async {},
              onReject: (_) async {},
              onPrint: (_) async {},
            ),
          ),
        ),
      ),
    );
    expect(find.text('Approve'), findsNothing);
    expect(find.text('Return'), findsNothing);
    expect(find.text('Reject'), findsNothing);
  });

  testWidgets('assigned final reviewer cannot act on their own request', (tester) async {
    final provider = LeaveProvider(repository: MockLeaveRepository());
    addTearDown(provider.dispose);
    final request = LeaveRequest(
      id: 'own-pending-leave',
      userId: 'reviewer',
      leaveType: LeaveType.vacationLeave,
      status: LeaveRequestStatus.pendingHr,
    );
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: MaterialApp(
          home: Scaffold(
            body: AdminLeaveDetailsSideSheet(
              initial: request,
              isDepartmentHead: false,
              currentReviewerId: 'reviewer',
              onApprove: (_) async {},
              onReturn: (_) async {},
              onReject: (_) async {},
              onPrint: (_) async {},
            ),
          ),
        ),
      ),
    );
    expect(find.text('Approve'), findsNothing);
    expect(find.text('Return'), findsNothing);
    expect(find.text('Reject'), findsNothing);
  });

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
