import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/providers/leave_provider.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/repositories/mock_leave_repository.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_balance.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_type.dart';

void main() {
  test('formal form credits use request scope and propagate errors', () async {
    final repository = _FormCreditsRepository();
    final provider = LeaveProvider(repository: repository);
    addTearDown(provider.dispose);

    final balances = await provider.fetchFormCreditsForRequestStrict('request-1');
    expect(repository.requestIds, ['request-1']);
    expect(repository.generalBalanceCalls, 0);
    expect(balances.single.earnedDays, 6.25);

    repository.fail = true;
    await expectLater(
      provider.fetchFormCreditsForRequestStrict('request-2'),
      throwsA(isA<Exception>()),
    );
    expect(repository.requestIds, ['request-1', 'request-2']);
    expect(repository.generalBalanceCalls, 0);
  });
}

class _FormCreditsRepository extends MockLeaveRepository {
  final List<String> requestIds = [];
  int generalBalanceCalls = 0;
  bool fail = false;

  @override
  Future<List<LeaveBalance>> getBalancesForUser(String userId) async {
    generalBalanceCalls++;
    throw StateError('General balances are not available to reviewers');
  }

  @override
  Future<List<LeaveBalance>> getFormCreditsForRequest(String requestId) async {
    requestIds.add(requestId);
    if (fail) throw Exception('Could not verify form credits');
    return const [
      LeaveBalance(
        userId: 'employee',
        leaveType: LeaveType.vacationLeave,
        earnedDays: 6.25,
      ),
    ];
  }
}
