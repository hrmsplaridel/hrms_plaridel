import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/providers/leave_provider.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/repositories/mock_leave_repository.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_request.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_type.dart';

void main() {
  test('upcoming leave uses the official HRMS date', () async {
    final repository = _OfficialDateLeaveRepository(
      officialDate: DateTime(2026, 9, 14),
    );
    final provider = LeaveProvider(repository: repository);
    addTearDown(provider.dispose);
    provider.onAuthUserChanged('employee-a');

    await provider.loadMyLeaveData('employee-a', forceRefresh: true);

    expect(provider.officialDate, DateTime(2026, 9, 14));
    expect(provider.upcomingApprovedRequests.map((request) => request.id), [
      'future-request',
    ]);
  });

  test('official date failure does not fall back to the device date', () async {
    final repository = _OfficialDateLeaveRepository(
      officialDateError: Exception('Official date unavailable.'),
    );
    final provider = LeaveProvider(repository: repository);
    addTearDown(provider.dispose);
    provider.onAuthUserChanged('employee-a');

    await provider.loadOfficialDate(forceRefresh: true);

    expect(provider.officialDate, isNull);
    expect(provider.officialDateLoading, isFalse);
    expect(provider.officialDateError, 'Official date unavailable.');
    expect(provider.upcomingApprovedRequests, isEmpty);
  });
}

class _OfficialDateLeaveRepository extends MockLeaveRepository {
  _OfficialDateLeaveRepository({this.officialDate, this.officialDateError});

  final DateTime? officialDate;
  final Object? officialDateError;

  @override
  Future<DateTime> getOfficialDate() async {
    if (officialDateError != null) throw officialDateError!;
    return officialDate!;
  }

  @override
  Future<List<LeaveRequest>> listMyRequests(
    String userId, {
    LeaveRequestStatus? status,
    int? limit,
  }) async => [
    _request('past-request', DateTime(2026, 9, 13)),
    _request('future-request', DateTime(2026, 9, 15)),
  ];
}

LeaveRequest _request(String id, DateTime date) => LeaveRequest(
  id: id,
  userId: 'employee-a',
  leaveType: LeaveType.vacationLeave,
  startDate: date,
  endDate: date,
  workingDaysApplied: 1,
  status: LeaveRequestStatus.approved,
);
