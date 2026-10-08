import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_builder.dart';
import 'package:hrms_plaridel/features/dtr/leave/utils/leave_form_signatories.dart';

DocuTrackerSourceSignature signedSlot(String slot, String signerId) {
  return DocuTrackerSourceSignature(
    slotKey: slot,
    label: slot,
    assignedSignerId: signerId,
    canSign: false,
    signatureAssetId: 'signature-1',
    signatureImageBytes: Uint8List.fromList([1, 2, 3]),
    signedBy: signerId,
    signerName: 'Backup Reviewer',
    signedAt: DateTime.utc(2026, 9, 22),
  );
}

void main() {
  for (final signer in ['primary-hr', 'backup-hr', null]) {
    test('7.A signature belongs only to the primary: $signer', () {
      final signature = signer == null
          ? null
          : signedSlot('hr_approver', signer);
      final result = composeLeaveFormSignatories(
        certificationOfficer: const LeaveFormSignatoryInfo(
          userId: 'primary-hr',
          name: 'Primary HR',
          title: 'HR Officer',
        ),
        approvingAuthority: const LeaveFormSignatoryInfo(
          userId: 'mayor',
          name: 'Mayor',
        ),
        hrApproverSignature: signature,
      );
      expect(result.certificationOfficer?.name, 'Primary HR');
      expect(
        result.certificationOfficerSignature,
        signer == 'primary-hr' ? same(signature) : isNull,
      );
      expect(result.hrApproverSignature, isNull);
    });
  }
  test('backup review does not replace official form signatories', () {
    final signatories = composeLeaveFormSignatories(
      recommendationOfficer: const LeaveFormSignatoryInfo(
        userId: 'head-1',
        name: 'Official Department Head',
        title: 'Department Head',
      ),
      approvingAuthority: const LeaveFormSignatoryInfo(
        userId: 'mayor-1',
        name: 'Official Mayor',
        title: 'Mayor',
      ),
      departmentHeadSignature: signedSlot('department_head', 'backup-1'),
      hrApproverSignature: signedSlot('hr_approver', 'backup-2'),
    );

    expect(signatories.recommendationOfficer?.name, 'Official Department Head');
    expect(signatories.approvingAuthority?.name, 'Official Mayor');
    expect(signatories.departmentHeadSignature, isNull);
    expect(signatories.hrApproverSignature, isNull);
  });

  test('an official signer keeps their own form signature', () {
    final departmentSignature = signedSlot('department_head', 'head-1');
    final finalSignature = signedSlot('hr_approver', 'mayor-1');
    final signatories = composeLeaveFormSignatories(
      recommendationOfficer: const LeaveFormSignatoryInfo(
        userId: 'head-1',
        name: 'Official Department Head',
      ),
      approvingAuthority: const LeaveFormSignatoryInfo(
        userId: 'mayor-1',
        name: 'Official Mayor',
      ),
      departmentHeadSignature: departmentSignature,
      hrApproverSignature: finalSignature,
    );

    expect(signatories.departmentHeadSignature, same(departmentSignature));
    expect(signatories.hrApproverSignature, same(finalSignature));
  });
}
