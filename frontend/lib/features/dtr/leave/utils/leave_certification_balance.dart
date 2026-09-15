import 'package:hrms_plaridel/features/dtr/leave/models/leave_balance.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_request.dart';

/// Returns the credit balance after the application shown in section 7.A.
/// Pending requests are already reserved in `pendingDays`, while approved
/// requests are already included in `usedDays`.
double leaveCertificationBalanceAfterApplication({
  required LeaveBalance balance,
  required LeaveRequestStatus requestStatus,
  required double applicationDays,
}) {
  final applicationAlreadyReflected =
      requestStatus.isPending || requestStatus == LeaveRequestStatus.approved;
  return applicationAlreadyReflected
      ? balance.availableDays
      : balance.availableDays - applicationDays;
}
