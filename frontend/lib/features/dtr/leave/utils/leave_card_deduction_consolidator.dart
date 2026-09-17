import 'package:hrms_plaridel/features/dtr/leave/models/leave_balance_ledger.dart';

const _attendanceDeduction = 'attendance_deduction';
const _attendanceDeductionAdjusted = 'attendance_deduction_adjusted';
const _zeroTolerance = 0.0005;

/// Converts attendance ledger movements into the effective monthly deductions
/// that belong on an official leave card. The audit ledger remains unchanged.
List<LeaveBalanceLedgerEntry> consolidateLeaveCardDeductions(
  Iterable<LeaveBalanceLedgerEntry> entries,
) {
  final result = <LeaveBalanceLedgerEntry>[];
  final attendanceByMonth = <String, List<LeaveBalanceLedgerEntry>>{};

  for (final entry in entries) {
    if (!_isAttendanceDeduction(entry)) {
      result.add(entry);
      continue;
    }

    final serviceMonth = entry.metadataJson?['service_month']
        ?.toString()
        .trim();
    if (serviceMonth == null || serviceMonth.isEmpty) {
      result.add(entry);
      continue;
    }
    attendanceByMonth.putIfAbsent(serviceMonth, () => []).add(entry);
  }

  for (final monthlyEntries in attendanceByMonth.values) {
    monthlyEntries.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final first = monthlyEntries.first;
    final latest = monthlyEntries.last;
    final netDays = monthlyEntries.fold<double>(
      0,
      (total, entry) => total + entry.daysChanged,
    );

    // A fully reversed deduction has no effective leave-card movement.
    if (netDays <= _zeroTolerance) continue;

    result.add(
      LeaveBalanceLedgerEntry(
        id: latest.id,
        userId: latest.userId,
        employeeName: latest.employeeName,
        leaveType: latest.leaveType,
        action: _attendanceDeduction,
        affectedBucket: latest.affectedBucket,
        daysChanged: netDays,
        oldValue: first.oldValue,
        newValue: latest.newValue,
        relatedLeaveRequestId: latest.relatedLeaveRequestId,
        actorUserId: latest.actorUserId,
        actorName: latest.actorName,
        actorKind: latest.actorKind,
        remarks: latest.remarks,
        metadataJson: {...?latest.metadataJson, 'deducted_days': netDays},
        // Keep the month in its original chronological position on the card.
        createdAt: first.createdAt,
      ),
    );
  }

  return result;
}

bool _isAttendanceDeduction(LeaveBalanceLedgerEntry entry) {
  return entry.action == _attendanceDeduction ||
      entry.action == _attendanceDeductionAdjusted;
}
