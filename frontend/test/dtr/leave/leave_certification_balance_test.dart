import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_balance.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_request.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_type.dart';
import 'package:hrms_plaridel/features/dtr/leave/utils/leave_certification_balance.dart';

void main() {
  const approvedBalance = LeaveBalance(
    userId: 'employee-a',
    leaveType: LeaveType.vacationLeave,
    earnedDays: 6.25,
    usedDays: 2.96,
  );

  test('approved application is not deducted from used days twice', () {
    expect(
      leaveCertificationBalanceAfterApplication(
        balance: approvedBalance,
        requestStatus: LeaveRequestStatus.approved,
        applicationDays: 2,
      ),
      closeTo(3.29, 0.000001),
    );
  });

  test('approved certification rows reconcile around the application', () {
    final before = leaveCertificationBalanceBeforeApplication(
      balance: approvedBalance,
      requestStatus: LeaveRequestStatus.approved,
      applicationDays: 2,
    );
    final after = leaveCertificationBalanceAfterApplication(
      balance: approvedBalance,
      requestStatus: LeaveRequestStatus.approved,
      applicationDays: 2,
    );

    expect(before, closeTo(5.29, 0.000001));
    expect(after, closeTo(3.29, 0.000001));
    expect(before - 2, closeTo(after, 0.000001));
  });

  test('pending application is not deducted from reserved days twice', () {
    const pendingBalance = LeaveBalance(
      userId: 'employee-a',
      leaveType: LeaveType.vacationLeave,
      earnedDays: 6.25,
      usedDays: 0.96,
      pendingDays: 2,
    );

    expect(
      leaveCertificationBalanceAfterApplication(
        balance: pendingBalance,
        requestStatus: LeaveRequestStatus.pendingHr,
        applicationDays: 2,
      ),
      closeTo(3.29, 0.000001),
    );
  });

  test('draft application previews its deduction from available credits', () {
    const draftBalance = LeaveBalance(
      userId: 'employee-a',
      leaveType: LeaveType.vacationLeave,
      earnedDays: 6.25,
      usedDays: 0.96,
    );

    expect(
      leaveCertificationBalanceAfterApplication(
        balance: draftBalance,
        requestStatus: LeaveRequestStatus.draft,
        applicationDays: 2,
      ),
      closeTo(3.29, 0.000001),
    );
    expect(
      leaveCertificationBalanceBeforeApplication(
        balance: draftBalance,
        requestStatus: LeaveRequestStatus.draft,
        applicationDays: 2,
      ),
      closeTo(5.29, 0.000001),
    );
  });
}
