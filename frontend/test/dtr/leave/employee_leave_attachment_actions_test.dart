import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/providers/leave_provider.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/repositories/mock_leave_repository.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_request.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_type.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/employee/shared/widgets/employee_leave_requests_panel.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('pending request shows its attachment and read-only actions', (
    tester,
  ) async {
    await _pumpPanel(tester, _request(withAttachment: true));
    await tester.tap(find.text('Sick Leave'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('employee-leave-details-panel')),
      findsOneWidget,
    );
    expect(find.byType(Dialog), findsNothing);
    expect(find.text('medical-certificate.pdf'), findsOneWidget);
    expect(
      find.byKey(const Key('employee-leave-attachment-preview')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('employee-leave-attachment-download')),
      findsOneWidget,
    );
    expect(find.widgetWithText(OutlinedButton, 'Edit'), findsNothing);
  });

  testWidgets('request without attachment does not show attachment actions', (
    tester,
  ) async {
    await _pumpPanel(tester, _request(withAttachment: false));
    await tester.tap(find.text('Sick Leave'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('employee-leave-attachment')), findsNothing);
    expect(find.text('Preview'), findsNothing);
    expect(find.text('Download'), findsNothing);
  });

  testWidgets('attachment load failure shows the repository error', (
    tester,
  ) async {
    await _pumpPanel(
      tester,
      _request(withAttachment: true),
      repository: _FailingAttachmentRepository(),
    );
    await tester.tap(find.text('Sick Leave'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('employee-leave-attachment-preview')),
    );
    await tester.tap(
      find.byKey(const Key('employee-leave-attachment-preview')),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Attachment file not found'), findsOneWidget);
    expect(find.text('Leave details'), findsOneWidget);
  });
}

Future<void> _pumpPanel(
  WidgetTester tester,
  LeaveRequest request, {
  MockLeaveRepository? repository,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1200, 1000);
  addTearDown(() {
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
  });
  await tester.pumpWidget(
    ChangeNotifierProvider(
      create: (_) =>
          LeaveProvider(repository: repository ?? MockLeaveRepository()),
      child: MaterialApp(
        home: Scaffold(
          body: EmployeeLeaveRequestsPanel(
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
            onPrint: (_) {},
            onPreview: (_) {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

LeaveRequest _request({required bool withAttachment}) => LeaveRequest(
  id: 'request-a',
  userId: 'employee-a',
  leaveType: LeaveType.sickLeave,
  startDate: DateTime(2026, 9, 21),
  endDate: DateTime(2026, 9, 21),
  workingDaysApplied: 1,
  status: LeaveRequestStatus.pendingHr,
  attachmentName: withAttachment ? 'medical-certificate.pdf' : null,
  attachmentPath: withAttachment ? 'leave/request-a.pdf' : null,
);

class _FailingAttachmentRepository extends MockLeaveRepository {
  @override
  Future<List<int>?> getAttachmentBytes(String requestId) {
    throw Exception('Attachment file not found');
  }
}
