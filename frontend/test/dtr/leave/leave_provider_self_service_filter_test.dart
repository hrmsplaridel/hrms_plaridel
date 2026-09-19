import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/providers/leave_provider.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/repositories/mock_leave_repository.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_balance.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_request.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_type.dart';

void main() {
  test('My Leave ignores filters selected in a reviewer queue', () async {
    final repository = _SelfServiceFilterRepository();
    final provider = LeaveProvider(repository: repository);
    addTearDown(provider.dispose);
    provider.onAuthUserChanged('employee-a');

    provider.setFilters(
      status: LeaveRequestStatus.pending,
      leaveType: LeaveType.sickLeave,
    );
    await provider.loadMyLeaveData('employee-a', forceRefresh: true);

    expect(repository.receivedStatus, isNull);
    expect(
      provider.myRequests.map((request) => request.status),
      containsAll([LeaveRequestStatus.pending, LeaveRequestStatus.approved]),
    );
  });
}

class _SelfServiceFilterRepository extends MockLeaveRepository {
  LeaveRequestStatus? receivedStatus;

  @override
  Future<List<LeaveRequest>> listMyRequests(
    String userId, {
    LeaveRequestStatus? status,
    int? limit,
  }) async {
    receivedStatus = status;
    return [
      _request('pending-request', LeaveRequestStatus.pending),
      _request('approved-request', LeaveRequestStatus.approved),
    ];
  }

  @override
  Future<List<LeaveBalance>> getBalancesForUser(String userId) async =>
      const [];
}

LeaveRequest _request(String id, LeaveRequestStatus status) => LeaveRequest(
  id: id,
  userId: 'employee-a',
  leaveType: LeaveType.vacationLeave,
  startDate: DateTime(2026, 9, 21),
  endDate: DateTime(2026, 9, 21),
  workingDaysApplied: 1,
  status: status,
);
