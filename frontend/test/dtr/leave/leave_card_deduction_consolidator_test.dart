import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_balance_ledger.dart';
import 'package:hrms_plaridel/features/dtr/leave/utils/leave_card_deduction_consolidator.dart';

void main() {
  test('fully reversed attendance deduction is omitted from leave card', () {
    final rows = consolidateLeaveCardDeductions([
      _entry(id: 'original', days: 4.99),
      _entry(id: 'correction', days: -4.99, adjusted: true),
    ]);

    expect(rows, isEmpty);
  });

  test('partially corrected month is shown once using its net deduction', () {
    final rows = consolidateLeaveCardDeductions([
      _entry(id: 'original', days: 1.25),
      _entry(id: 'correction', days: -0.3, adjusted: true),
    ]);

    expect(rows, hasLength(1));
    expect(rows.single.action, 'attendance_deduction');
    expect(rows.single.daysChanged, closeTo(0.95, 0.0001));
    expect(rows.single.metadataJson?['deducted_days'], closeTo(0.95, 0.0001));
  });
}

LeaveBalanceLedgerEntry _entry({
  required String id,
  required double days,
  bool adjusted = false,
}) {
  return LeaveBalanceLedgerEntry(
    id: id,
    userId: 'employee-1',
    leaveType: 'vacationLeave',
    action: adjusted ? 'attendance_deduction_adjusted' : 'attendance_deduction',
    affectedBucket: 'used',
    daysChanged: days,
    actorKind: 'system',
    metadataJson: const {'service_month': '2026-08'},
    createdAt: DateTime.utc(2026, 9, adjusted ? 15 : 1),
  );
}
