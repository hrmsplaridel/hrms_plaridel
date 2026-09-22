import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/providers/leave_provider.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/repositories/leave_repository.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/repositories/mock_leave_repository.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_request.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_type.dart';

void main() {
  test(
    'personal refresh does not replace HR or department-head queues',
    () async {
      final provider = LeaveProvider(repository: _ScopedLeaveRepository());
      addTearDown(provider.dispose);
      provider.onAuthUserChanged('reviewer');

      await provider.loadRequests(forceRefresh: true);
      await provider.loadDepartmentHeadRequests(forceRefresh: true);
      expect(provider.requests.map((r) => r.id), ['hr-request']);
      expect(provider.departmentHeadRequests.map((r) => r.id), [
        'head-request',
      ]);

      await provider.loadMyLeaveRequests('reviewer', forceRefresh: true);
      expect(provider.myRequests.map((r) => r.id), ['my-request']);
      expect(provider.requests.map((r) => r.id), ['hr-request']);
      expect(provider.departmentHeadRequests.map((r) => r.id), [
        'head-request',
      ]);
      expect(provider.pendingCount, 1);

      await provider.loadRequests(forceRefresh: true);
      expect(provider.myRequests.map((r) => r.id), ['my-request']);
    },
  );

  test(
    'saving a personal draft does not insert it into reviewer queues',
    () async {
      final provider = LeaveProvider(repository: _ScopedLeaveRepository());
      addTearDown(provider.dispose);
      provider.onAuthUserChanged('reviewer');
      await provider.loadRequests(forceRefresh: true);
      await provider.loadDepartmentHeadRequests(forceRefresh: true);

      final saved = await provider.saveDraft(_request('draft', 'reviewer'));

      expect(saved, isNotNull);
      expect(provider.myRequests.map((r) => r.id), ['draft']);
      expect(provider.requests.map((r) => r.id), ['hr-request']);
      expect(provider.departmentHeadRequests.map((r) => r.id), [
        'head-request',
      ]);
    },
  );
}

class _ScopedLeaveRepository extends MockLeaveRepository {
  @override
  Future<List<LeaveRequest>> listMyRequests(
    String userId, {
    LeaveRequestStatus? status,
    int? limit,
  }) async => [_request('my-request', userId)];

  @override
  Future<List<LeaveRequest>> listRequests({
    LeaveRequestQuery query = const LeaveRequestQuery(),
  }) async => [_request('hr-request', 'employee-a')];

  @override
  Future<List<LeaveRequest>> listDepartmentHeadRequests({
    LeaveRequestQuery query = const LeaveRequestQuery(),
  }) async => [_request('head-request', 'employee-b')];
}

LeaveRequest _request(String id, String userId) => LeaveRequest(
  id: id,
  userId: userId,
  leaveType: LeaveType.vacationLeave,
  startDate: DateTime(2026, 9, 21),
  endDate: DateTime(2026, 9, 21),
  workingDaysApplied: 1,
  status: LeaveRequestStatus.pending,
);
