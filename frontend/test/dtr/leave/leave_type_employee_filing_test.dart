import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_type.dart';

void main() {
  test('Mandatory/Forced Leave is employee-fileable', () {
    expect(LeaveType.mandatoryForcedLeave.employeeCanFile, isTrue);
    expect(
      LeaveType.mandatoryForcedLeave.balanceLedgerType,
      LeaveType.vacationLeave,
    );
    expect(LeaveType.mandatoryForcedLeave.maxDays, 5);
  });
}
