import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/providers/leave_provider.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/repositories/mock_leave_repository.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_balance.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_request.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_type.dart';

void main() {
  test('an older My Leave refresh cannot overwrite a newer result', () async {
    final repository = _OrderedRefreshLeaveRepository();
    final provider = LeaveProvider(repository: repository);
    addTearDown(provider.dispose);
    provider.onAuthUserChanged('employee-a');

    final olderLoad = provider.loadMyLeaveData(
      'employee-a',
      forceRefresh: true,
    );
    await repository.waitForCalls(1);

    final newerLoad = provider.loadMyLeaveData(
      'employee-a',
      forceRefresh: true,
    );
    await repository.waitForCalls(2);

    repository.completeCall(1, status: LeaveRequestStatus.approved, days: 8);
    await newerLoad;
    expect(provider.requests.single.status, LeaveRequestStatus.approved);
    expect(provider.balances.single.earnedDays, 8);
    expect(provider.loading, isFalse);

    repository.completeCall(0, status: LeaveRequestStatus.pending, days: 5);
    await olderLoad;
    expect(provider.requests.single.status, LeaveRequestStatus.approved);
    expect(provider.balances.single.earnedDays, 8);
    expect(provider.loading, isFalse);
    expect(provider.error, isNull);

    await provider.loadMyLeaveData('employee-a');
    expect(provider.requests.single.status, LeaveRequestStatus.approved);
    expect(provider.balances.single.earnedDays, 8);
    expect(repository.requestCallCount, 2);
    expect(repository.balanceCallCount, 2);
  });

  test('an older refresh failure cannot replace a newer success', () async {
    final repository = _OrderedRefreshLeaveRepository();
    final provider = LeaveProvider(repository: repository);
    addTearDown(provider.dispose);
    provider.onAuthUserChanged('employee-a');

    final olderLoad = provider.loadMyLeaveData(
      'employee-a',
      forceRefresh: true,
    );
    await repository.waitForCalls(1);
    final newerLoad = provider.loadMyLeaveData(
      'employee-a',
      forceRefresh: true,
    );
    await repository.waitForCalls(2);

    repository.completeCall(1, status: LeaveRequestStatus.approved, days: 8);
    await newerLoad;
    repository.failCall(0);
    await olderLoad;

    expect(provider.requests.single.status, LeaveRequestStatus.approved);
    expect(provider.balances.single.earnedDays, 8);
    expect(provider.loading, isFalse);
    expect(provider.error, isNull);
  });
}

class _OrderedRefreshLeaveRepository extends MockLeaveRepository {
  final List<Completer<List<LeaveRequest>>> _requestCalls = [];
  final List<Completer<List<LeaveBalance>>> _balanceCalls = [];

  int get requestCallCount => _requestCalls.length;
  int get balanceCallCount => _balanceCalls.length;

  Future<void> waitForCalls(int count) async {
    while (_requestCalls.length < count || _balanceCalls.length < count) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  void completeCall(
    int index, {
    required LeaveRequestStatus status,
    required double days,
  }) {
    _requestCalls[index].complete([_request(status)]);
    _balanceCalls[index].complete([_balance(days)]);
  }

  void failCall(int index) {
    _requestCalls[index].completeError(Exception('stale request failed'));
    _balanceCalls[index].completeError(Exception('stale balance failed'));
  }

  @override
  Future<List<LeaveRequest>> listMyRequests(
    String userId, {
    LeaveRequestStatus? status,
    int? limit,
  }) {
    final completer = Completer<List<LeaveRequest>>();
    _requestCalls.add(completer);
    return completer.future;
  }

  @override
  Future<List<LeaveBalance>> getBalancesForUser(String userId) {
    final completer = Completer<List<LeaveBalance>>();
    _balanceCalls.add(completer);
    return completer.future;
  }
}

LeaveRequest _request(LeaveRequestStatus status) => LeaveRequest(
  id: 'request-a',
  userId: 'employee-a',
  leaveType: LeaveType.vacationLeave,
  startDate: DateTime(2026, 9, 21),
  endDate: DateTime(2026, 9, 21),
  workingDaysApplied: 1,
  status: status,
);

LeaveBalance _balance(double days) => LeaveBalance(
  id: 'balance-a',
  userId: 'employee-a',
  leaveType: LeaveType.vacationLeave,
  leaveTypeName: LeaveType.vacationLeave.value,
  earnedDays: days,
);
