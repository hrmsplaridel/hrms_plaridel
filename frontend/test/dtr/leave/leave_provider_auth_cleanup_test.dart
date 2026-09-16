import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/providers/leave_provider.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/repositories/mock_leave_repository.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_balance.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_request.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_type.dart';

void main() {
  test(
    'sign out clears every exposed leave session state immediately',
    () async {
      final repository = _StaticSessionLeaveRepository();
      final provider = LeaveProvider(repository: repository);
      addTearDown(provider.dispose);

      provider.onAuthUserChanged('employee-a');
      provider.setFilters(
        status: LeaveRequestStatus.approved,
        leaveType: LeaveType.vacationLeave,
      );
      await provider.loadMyLeaveData('employee-a');
      await provider.loadRequestById('request-a');

      expect(provider.requests, hasLength(1));
      expect(provider.balances, hasLength(1));
      expect(provider.selectedRequest?.userId, 'employee-a');
      expect(provider.filterStatus, LeaveRequestStatus.approved);
      expect(provider.filterLeaveType, LeaveType.vacationLeave);

      provider.onAuthUserChanged(null);

      expect(provider.requests, isEmpty);
      expect(provider.balances, isEmpty);
      expect(provider.selectedRequest, isNull);
      expect(provider.filterStatus, isNull);
      expect(provider.filterLeaveType, isNull);
      expect(provider.loading, isFalse);
      expect(provider.submitting, isFalse);
      expect(provider.reviewing, isFalse);
      expect(provider.error, isNull);
      expect(provider.deptHeadCheck, isNull);
    },
  );

  test('an old account load cannot repopulate a new leave session', () async {
    final repository = _DelayedSessionLeaveRepository();
    final provider = LeaveProvider(repository: repository);
    addTearDown(provider.dispose);

    provider.onAuthUserChanged('employee-a');
    final pendingLoad = provider.loadMyLeaveData(
      'employee-a',
      forceRefresh: true,
    );
    await Future.wait([
      repository.requestsStarted.future,
      repository.balancesStarted.future,
    ]);

    provider.onAuthUserChanged('employee-b');
    repository.completeLoad();
    await pendingLoad;

    expect(provider.requests, isEmpty);
    expect(provider.balances, isEmpty);
    expect(provider.selectedRequest, isNull);
    expect(provider.loading, isFalse);
    expect(provider.error, isNull);
  });

  test(
    'an old account mutation cannot restore selection after switching',
    () async {
      final repository = _DelayedSessionLeaveRepository();
      final provider = LeaveProvider(repository: repository);
      addTearDown(provider.dispose);

      provider.onAuthUserChanged('employee-a');
      final pendingSave = provider.saveDraft(_requestFor('employee-a'));
      await repository.saveStarted.future;
      expect(provider.submitting, isTrue);

      provider.onAuthUserChanged('employee-b');
      expect(provider.submitting, isFalse);
      repository.completeSave();

      expect(await pendingSave, isNull);
      expect(provider.requests, isEmpty);
      expect(provider.selectedRequest, isNull);
      expect(provider.submitting, isFalse);
      expect(provider.error, isNull);
    },
  );
}

LeaveRequest _requestFor(String userId) => LeaveRequest(
  id: 'request-$userId',
  userId: userId,
  leaveType: LeaveType.vacationLeave,
  startDate: DateTime(2026, 9, 21),
  endDate: DateTime(2026, 9, 21),
  workingDaysApplied: 1,
  status: LeaveRequestStatus.approved,
);

LeaveBalance _balanceFor(String userId) => LeaveBalance(
  id: 'balance-$userId',
  userId: userId,
  leaveType: LeaveType.vacationLeave,
  leaveTypeName: LeaveType.vacationLeave.value,
  earnedDays: 10,
);

class _StaticSessionLeaveRepository extends MockLeaveRepository {
  @override
  Future<List<LeaveRequest>> listMyRequests(
    String userId, {
    LeaveRequestStatus? status,
    int? limit,
  }) async => [_requestFor(userId)];

  @override
  Future<List<LeaveBalance>> getBalancesForUser(String userId) async => [
    _balanceFor(userId),
  ];

  @override
  Future<LeaveRequest?> getRequestById(String requestId) async =>
      _requestFor('employee-a');
}

class _DelayedSessionLeaveRepository extends MockLeaveRepository {
  final requestsStarted = Completer<void>();
  final balancesStarted = Completer<void>();
  final saveStarted = Completer<void>();
  final _requests = Completer<List<LeaveRequest>>();
  final _balances = Completer<List<LeaveBalance>>();
  final _saved = Completer<LeaveRequest>();

  void completeLoad() {
    _requests.complete([_requestFor('employee-a')]);
    _balances.complete([_balanceFor('employee-a')]);
  }

  void completeSave() => _saved.complete(_requestFor('employee-a'));

  @override
  Future<List<LeaveRequest>> listMyRequests(
    String userId, {
    LeaveRequestStatus? status,
    int? limit,
  }) {
    if (!requestsStarted.isCompleted) requestsStarted.complete();
    return _requests.future;
  }

  @override
  Future<List<LeaveBalance>> getBalancesForUser(String userId) {
    if (!balancesStarted.isCompleted) balancesStarted.complete();
    return _balances.future;
  }

  @override
  Future<LeaveRequest> saveDraft(LeaveRequest request) {
    if (!saveStarted.isCompleted) saveStarted.complete();
    return _saved.future;
  }
}
