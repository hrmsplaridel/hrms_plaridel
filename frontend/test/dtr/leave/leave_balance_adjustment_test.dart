import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/repositories/mock_leave_repository.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_balance_ledger.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_type.dart';

void main() {
  test(
    'manual adjustment preserves earned, used, and pending buckets',
    () async {
      final repository = MockLeaveRepository();
      const userId = 'employee-1';
      final before = await repository.getBalanceForUserByType(
        userId,
        LeaveType.vacationLeave,
      );

      final saved = await repository.applyBalanceAdjustment(
        userId: userId,
        leaveType: LeaveType.vacationLeave,
        adjustmentDays: 1.25,
        remarks: 'Opening balance correction',
        asOfDate: DateTime(2026, 8, 8),
      );

      expect(before, isNotNull);
      expect(saved.earnedDays, before!.earnedDays);
      expect(saved.usedDays, before.usedDays);
      expect(saved.pendingDays, before.pendingDays);
      expect(saved.adjustedDays, before.adjustedDays + 1.25);
    },
  );

  test('ledger result reads the adjusted movement summary', () {
    final result = LeaveLedgerResult.fromJson({
      'total': 1,
      'limit': 50,
      'offset': 0,
      'rows': const [],
      'summary': {'earned': 10, 'used': 2, 'pending': 1, 'adjusted': -1.25},
    });

    expect(result.summaryEarned, 10);
    expect(result.summaryUsed, 2);
    expect(result.summaryPending, 1);
    expect(result.summaryAdjusted, -1.25);
  });
}
