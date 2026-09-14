import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/providers/leave_provider.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/repositories/mock_leave_repository.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_balance.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_request.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_type.dart';

void main() {
  test('request success remains visible when balances fail', () async {
    final repository = _PartialLoadLeaveRepository(failBalances: true);
    final provider = LeaveProvider(repository: repository);
    addTearDown(provider.dispose);
    provider.onAuthUserChanged('employee-a');

    await provider.loadMyLeaveData('employee-a', forceRefresh: true);

    expect(provider.requests, hasLength(1));
    expect(provider.myRequestsLoaded, isTrue);
    expect(provider.myRequestsError, isNull);
    expect(provider.balances, isEmpty);
    expect(provider.myBalancesLoaded, isFalse);
    expect(
      provider.myBalancesError,
      'Leave credits are temporarily unavailable.',
    );
    expect(provider.loading, isFalse);
  });

  test('balance success remains visible when requests fail', () async {
    final repository = _PartialLoadLeaveRepository(failRequests: true);
    final provider = LeaveProvider(repository: repository);
    addTearDown(provider.dispose);
    provider.onAuthUserChanged('employee-a');

    await provider.loadMyLeaveData('employee-a', forceRefresh: true);

    expect(provider.requests, isEmpty);
    expect(provider.myRequestsLoaded, isFalse);
    expect(
      provider.myRequestsError,
      'Leave requests are temporarily unavailable.',
    );
    expect(provider.balances, hasLength(1));
    expect(provider.myBalancesLoaded, isTrue);
    expect(provider.myBalancesError, isNull);
    expect(provider.loading, isFalse);
  });

  test('failed refresh preserves previously loaded section data', () async {
    final repository = _PartialLoadLeaveRepository();
    final provider = LeaveProvider(repository: repository);
    addTearDown(provider.dispose);
    provider.onAuthUserChanged('employee-a');
    await provider.loadMyLeaveData('employee-a', forceRefresh: true);

    repository
      ..failRequests = true
      ..failBalances = true;
    await provider.loadMyLeaveData('employee-a', forceRefresh: true);

    expect(provider.requests, hasLength(1));
    expect(provider.balances, hasLength(1));
    expect(provider.myRequestsLoaded, isTrue);
    expect(provider.myBalancesLoaded, isTrue);
    expect(provider.myRequestsError, isNotNull);
    expect(provider.myBalancesError, isNotNull);
  });
}

class _PartialLoadLeaveRepository extends MockLeaveRepository {
  _PartialLoadLeaveRepository({
    this.failRequests = false,
    this.failBalances = false,
  });

  bool failRequests;
  bool failBalances;

  @override
  Future<List<LeaveRequest>> listMyRequests(
    String userId, {
    LeaveRequestStatus? status,
    int? limit,
  }) async {
    if (failRequests) {
      throw Exception('Leave requests are temporarily unavailable.');
    }
    return [_request()];
  }

  @override
  Future<List<LeaveBalance>> getBalancesForUser(String userId) async {
    if (failBalances) {
      throw Exception('Leave credits are temporarily unavailable.');
    }
    return [_balance()];
  }
}

LeaveRequest _request() => LeaveRequest(
  id: 'request-a',
  userId: 'employee-a',
  leaveType: LeaveType.vacationLeave,
  startDate: DateTime(2026, 9, 21),
  endDate: DateTime(2026, 9, 21),
  workingDaysApplied: 1,
  status: LeaveRequestStatus.approved,
);

LeaveBalance _balance() => LeaveBalance(
  id: 'balance-a',
  userId: 'employee-a',
  leaveType: LeaveType.vacationLeave,
  leaveTypeName: LeaveType.vacationLeave.value,
  earnedDays: 8,
);
