import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/providers/leave_provider.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/repositories/leave_repository.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/repositories/mock_leave_repository.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_request.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_type.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/admin/widgets/admin_leave_details_side_sheet.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/admin/widgets/admin_leave_request_queue.dart';

void main() {
  test('personal refresh does not clear either review queue error', () async {
    final repository = _FailingReviewRepository()..fail = true;
    final provider = LeaveProvider(repository: repository);
    addTearDown(provider.dispose);
    provider.onAuthUserChanged('reviewer');

    await provider.loadRequests();
    await provider.loadDepartmentHeadRequests();
    expect(provider.reviewError(departmentHead: false), isNotNull);
    expect(provider.reviewError(departmentHead: true), isNotNull);

    await provider.loadMyLeaveData('reviewer');
    expect(provider.reviewError(departmentHead: false), isNotNull);
    expect(provider.reviewError(departmentHead: true), isNotNull);
  });

  test(
    'review state resets on account change and a new filter failure',
    () async {
      final repository = _FailingReviewRepository();
      final provider = LeaveProvider(repository: repository);
      addTearDown(provider.dispose);
      provider.onAuthUserChanged('reviewer-a');

      repository.fail = true;
      await provider.loadRequests();
      expect(provider.reviewError(departmentHead: false), isNotNull);
      expect(provider.reviewLoadAttempted(departmentHead: false), isTrue);
      expect(
        provider.reviewInitialLoadComplete(departmentHead: false),
        isFalse,
      );

      repository.fail = false;
      await provider.loadRequests();
      expect(provider.requests, hasLength(1));
      expect(provider.reviewInitialLoadComplete(departmentHead: false), isTrue);

      repository.fail = true;
      await provider.loadRequests(
        query: const LeaveRequestQuery(department: 'Records'),
      );
      expect(provider.requests, isEmpty);
      expect(
        provider.reviewInitialLoadComplete(departmentHead: false),
        isFalse,
      );
      expect(provider.reviewError(departmentHead: false), isNotNull);

      provider.onAuthUserChanged('reviewer-b');
      expect(provider.reviewError(departmentHead: false), isNull);
      expect(
        provider.reviewInitialLoadComplete(departmentHead: false),
        isFalse,
      );
      expect(provider.reviewLoading(departmentHead: false), isFalse);
      expect(provider.reviewLoadAttempted(departmentHead: false), isFalse);
    },
  );

  testWidgets('unavailable queue stays retryable after banner dismissal', (
    tester,
  ) async {
    var retries = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdminLeaveRequestQueuePanel(
            requests: const [],
            filterKey: '',
            isDepartmentHead: false,
            loading: false,
            initialLoadComplete: false,
            initialLoadAttempted: true,
            onRetry: () => retries++,
            totalCount: 0,
            hasMore: false,
            loadingMore: false,
            loadMoreError: null,
            onLoadMore: () {},
            selectedRequest: null,
            filterBar: const SizedBox.shrink(),
            onSelect: (_) {},
          ),
        ),
      ),
    );
    expect(find.textContaining('Requests unavailable'), findsOneWidget);
    expect(find.text('No leave requests matched the filters.'), findsNothing);
    await tester.tap(find.text('Retry'));
    expect(retries, 1);
  });

  testWidgets('history-only head cannot review a pending request', (
    tester,
  ) async {
    final provider = LeaveProvider(repository: MockLeaveRepository());
    addTearDown(provider.dispose);
    final request = LeaveRequest(
      id: 'historical-request',
      userId: 'employee',
      leaveType: LeaveType.vacationLeave,
      status: LeaveRequestStatus.pendingDepartmentHead,
    );
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: MaterialApp(
          home: Scaffold(
            body: AdminLeaveDetailsSideSheet(
              initial: request,
              isDepartmentHead: true,
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
    expect(find.text('Print Form'), findsOneWidget);
  });
}

class _FailingReviewRepository extends MockLeaveRepository {
  bool fail = false;

  @override
  Future<LeaveRequestPage> listReviewRequestsPage({
    required LeaveRequestQuery query,
    required bool departmentHead,
  }) async {
    if (fail) throw StateError('Network unavailable');
    return LeaveRequestPage(
      items: [
        LeaveRequest(
          id: 'request',
          userId: 'employee',
          leaveType: LeaveType.vacationLeave,
        ),
      ],
      total: 1,
      limit: query.limit ?? 200,
      offset: query.offset ?? 0,
    );
  }
}
