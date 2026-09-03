import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/dtr/assistant/data/dtr_assistant_leave_prefill.dart';
import 'package:hrms_plaridel/features/dtr/assistant/data/dtr_assistant_message_model.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_type.dart';

void main() {
  test('assistant action prefills adoption leave and its special fields', () {
    const action = DtrAssistantAction(
      id: 'open-adoption',
      label: 'Open leave form',
      type: 'open_leave_form',
      payload: {
        'leaveType': 'adoptionLeave',
        'startDate': '2026-08-01',
        'endDate': '2026-08-10',
        'adoptionPlacementDate': '2026-08-01',
        'adoptionParentRole': 'primaryAdoptiveParent',
        'reason': 'Adoption placement',
      },
    );

    final request = leaveRequestFromAssistantAction(action, 'employee-1');

    expect(request.leaveType, LeaveType.adoptionLeave);
    expect(request.adoptionPlacementDate, DateTime(2026, 8, 1));
    expect(
      request.adoptionParentRole,
      AdoptionParentRole.primaryAdoptiveParent,
    );
    expect(request.workingDaysApplied, 10);
    expect(request.reason, 'Adoption placement');
  });

  test('assistant action maps short special-leave aliases correctly', () {
    const cases = <String, LeaveType>{
      'vawc': LeaveType.tenDayVawcLeave,
      'calamity': LeaveType.specialEmergencyCalamityLeave,
      'special leave for women': LeaveType.specialLeaveBenefitsForWomen,
      'spl': LeaveType.specialPrivilegeLeave,
    };

    for (final entry in cases.entries) {
      final request = leaveRequestFromAssistantAction(
        DtrAssistantAction(
          id: entry.key,
          label: 'Open leave form',
          type: 'open_leave_form',
          payload: {'leaveType': entry.key},
        ),
        'employee-1',
      );
      expect(request.leaveType, entry.value, reason: entry.key);
    }
  });
}
