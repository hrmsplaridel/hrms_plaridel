import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_type.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_type_definition.dart';
import 'package:hrms_plaridel/features/dtr/leave/utils/leave_guidance.dart';

void main() {
  test(
    'Sick Leave requires a certificate above five days, with a legacy fallback',
    () {
      for (final threshold in [null, 5.0]) {
        final sick = LeaveTypeDefinition(
          name: 'sickLeave',
          displayName: 'Sick Leave',
          requiresAttachmentWhenOverDays: threshold,
        );
        expect(sick.requiresAttachmentForDays(4), false);
        expect(sick.requiresAttachmentForDays(5), false);
        expect(sick.requiresAttachmentForDays(6), true);
        expect(
          LeaveGuidance.forDefinition(sick).requirements,
          contains('more than 5'),
        );
      }
      expect(
        LeaveGuidance.forType(LeaveType.sickLeave).requirements,
        contains('more than 5'),
      );
    },
  );
  test(
    'custom inclusive thresholds and unconditional document requirements stay unchanged',
    () {
      const conditional = LeaveTypeDefinition(
        name: 'customLeave',
        displayName: 'Custom Leave',
        requiresAttachment: true,
        requiresAttachmentWhenOverDays: 3,
      );
      expect(conditional.requiresAttachmentForDays(2), false);
      expect(conditional.requiresAttachmentForDays(3), true);
      const unconditional = LeaveTypeDefinition(
        name: 'customLeave',
        displayName: 'Custom Leave',
        requiresAttachment: true,
      );
      expect(unconditional.requiresAttachmentForDays(1), true);
    },
  );
}
