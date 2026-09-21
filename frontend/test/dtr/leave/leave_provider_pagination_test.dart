import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/providers/leave_provider.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/repositories/leave_repository.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/repositories/mock_leave_repository.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_request.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_type.dart';

void main() {
  test(
    'My Leave loads later pages without duplicating overlapping rows',
    () async {
      final repository = _PagingLeaveRepository(
        pages: {
          0: LeaveRequestPage(
            items: [_request('request-3'), _request('request-2')],
            total: 3,
            limit: 50,
            offset: 0,
          ),
          2: LeaveRequestPage(
            items: [_request('request-2'), _request('request-1')],
            total: 3,
            limit: 50,
            offset: 2,
          ),
        },
      );
      final provider = LeaveProvider(repository: repository);
      addTearDown(provider.dispose);
      provider.onAuthUserChanged('employee-a');

      await provider.loadMyLeaveRequests('employee-a');

      expect(provider.myRequests.map((request) => request.id), [
        'request-3',
        'request-2',
      ]);
      expect(provider.myRequestsTotal, 3);
      expect(provider.myRequestsHasMore, isTrue);

      await provider.loadMoreMyLeaveRequests('employee-a');

      expect(provider.myRequests.map((request) => request.id), [
        'request-3',
        'request-2',
        'request-1',
      ]);
      expect(provider.myRequestsTotal, 3);
      expect(provider.myRequestsHasMore, isFalse);
      expect(provider.myRequestsLoadMoreError, isNull);
      expect(repository.requestedOffsets, [0, 2]);
    },
  );

  test('failed Load More preserves requests already shown', () async {
    final repository = _PagingLeaveRepository(
      pages: {
        0: LeaveRequestPage(
          items: [_request('request-2'), _request('request-1')],
          total: 3,
          limit: 50,
          offset: 0,
        ),
      },
      failingOffsets: {2},
    );
    final provider = LeaveProvider(repository: repository);
    addTearDown(provider.dispose);
    provider.onAuthUserChanged('employee-a');

    await provider.loadMyLeaveRequests('employee-a');
    await provider.loadMoreMyLeaveRequests('employee-a');

    expect(provider.myRequests.map((request) => request.id), [
      'request-2',
      'request-1',
    ]);
    expect(provider.myRequestsTotal, 3);
    expect(provider.myRequestsHasMore, isTrue);
    expect(provider.myRequestsLoadingMore, isFalse);
    expect(provider.myRequestsLoadMoreError, isNotNull);
  });
}

class _PagingLeaveRepository extends MockLeaveRepository {
  _PagingLeaveRepository({required this.pages, this.failingOffsets = const {}});

  final Map<int, LeaveRequestPage> pages;
  final Set<int> failingOffsets;
  final List<int> requestedOffsets = [];

  @override
  Future<LeaveRequestPage> listMyRequestPage(
    String userId, {
    required int limit,
    required int offset,
  }) async {
    requestedOffsets.add(offset);
    if (failingOffsets.contains(offset)) {
      throw Exception('Later page failed');
    }
    return pages[offset]!;
  }
}

LeaveRequest _request(String id) => LeaveRequest(
  id: id,
  userId: 'employee-a',
  leaveType: LeaveType.vacationLeave,
  startDate: DateTime(2026, 9, 21),
  endDate: DateTime(2026, 9, 21),
  workingDaysApplied: 1,
  status: LeaveRequestStatus.approved,
);
