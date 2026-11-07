import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_builder.dart';
import 'package:hrms_plaridel/features/docutracker/utils/docutracker_memo_layout.dart';
import 'package:hrms_plaridel/features/docutracker/utils/docutracker_step_signature.dart';

DocuTrackerSignatureField _field({
  required String id,
  required String signerId,
  required String label,
  double x = 0.1,
  double y = 0.5,
  bool signed = false,
}) {
  return DocuTrackerSignatureField(
    id: id,
    pageNumber: 1,
    x: x,
    y: y,
    width: 0.3,
    height: 0.08,
    assignedSignerId: signerId,
    label: label,
    signedBy: signed ? signerId : null,
    signedAt: signed ? DateTime.utc(2026, 1, 1) : null,
    lockedAt: signed ? DateTime.utc(2026, 1, 1) : null,
  );
}

void main() {
  test('an existing signature is not written again', () {
    final plan = docuTrackerStepSignaturePlan(
      userId: 'reviewer',
      canAddOwnSignature: true,
      memo: true,
      fields: [
        _field(
          id: 'noted',
          signerId: 'reviewer',
          label: 'Noted by',
          signed: true,
        ),
      ],
    );
    expect(plan.kind, DocuTrackerStepSignatureKind.alreadySigned);
  });

  test('the assigned Memo line is signed in place', () {
    final plan = docuTrackerStepSignaturePlan(
      userId: 'reviewer',
      canAddOwnSignature: true,
      memo: true,
      fields: [
        _field(id: 'prepared', signerId: 'hr-head', label: 'Prepared by'),
        _field(id: 'noted', signerId: 'reviewer', label: 'Noted by'),
        _field(id: 'approved', signerId: 'reviewer', label: 'Approved by'),
      ],
    );
    expect(plan.kind, DocuTrackerStepSignatureKind.existingField);
    expect(plan.fieldId, 'noted');
  });

  test('a new Memo signature stays off the official lines', () {
    final plan = docuTrackerStepSignaturePlan(
      userId: 'reviewer',
      canAddOwnSignature: true,
      memo: true,
      fields: const [],
    );
    expect(plan.kind, DocuTrackerStepSignatureKind.newField);
    final rect = plan.rect!;
    for (final obstacle in DocuTrackerMemoLayout.closingObstacles) {
      expect(rect.overlaps(obstacle), isFalse);
    }
    for (final band in DocuTrackerMemoLayout.pageBands) {
      expect(rect.overlaps(band), isFalse);
    }
  });

  test('a reviewer who cannot add a signature is not given a new box', () {
    final plan = docuTrackerStepSignaturePlan(
      userId: 'reviewer',
      canAddOwnSignature: false,
      memo: false,
      fields: const [],
    );
    expect(plan.kind, DocuTrackerStepSignatureKind.unavailable);
  });
}
