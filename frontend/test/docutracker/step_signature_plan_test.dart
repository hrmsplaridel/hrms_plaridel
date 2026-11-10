import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_builder.dart';
import 'package:hrms_plaridel/features/docutracker/utils/docutracker_memo_layout.dart';
import 'package:hrms_plaridel/features/docutracker/utils/docutracker_purchase_layout.dart';
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

  test('Prepared by, Noted by, and Approved by sign their own lines', () {
    for (final entry in const [
      ('prepared', 'Prepared by'),
      ('noted', 'Noted by'),
      ('approved', 'Approved by'),
    ]) {
      final plan = docuTrackerStepSignaturePlan(
        userId: 'signer',
        canAddOwnSignature: true,
        memo: true,
        fields: [
          _field(id: 'prepared', signerId: 'hr-head', label: 'Prepared by'),
          _field(id: 'noted', signerId: 'office', label: 'Noted by'),
          _field(id: 'approved', signerId: 'mayor', label: 'Approved by'),
          _field(id: entry.$1, signerId: 'signer', label: entry.$2),
        ],
      );
      expect(plan.kind, DocuTrackerStepSignatureKind.existingField);
      expect(plan.fieldId, entry.$1);
    }
  });

  test('a purchase request signs Requested by, then Approved by', () {
    final requested = docuTrackerStepSignaturePlan(
      userId: 'reviewer',
      canAddOwnSignature: true,
      memo: false,
      purchaseRequest: true,
      fields: const [],
    );
    expect(requested.kind, DocuTrackerStepSignatureKind.newField);
    expect(requested.label, DocuTrackerPurchaseLayout.requestedLabel);
    expect(requested.rect, DocuTrackerPurchaseLayout.requestedField);

    final approved = docuTrackerStepSignaturePlan(
      userId: 'mayor',
      canAddOwnSignature: true,
      memo: false,
      purchaseRequest: true,
      finalApproval: true,
      fields: [
        _field(id: 'requested', signerId: 'reviewer', label: 'Requested by'),
      ],
    );
    expect(approved.label, DocuTrackerPurchaseLayout.approvedLabel);
    expect(approved.rect, DocuTrackerPurchaseLayout.approvedField);

    final own = docuTrackerStepSignaturePlan(
      userId: 'reviewer',
      canAddOwnSignature: true,
      memo: false,
      purchaseRequest: true,
      fields: [
        _field(id: 'requested', signerId: 'reviewer', label: 'Requested by'),
      ],
    );
    expect(own.kind, DocuTrackerStepSignatureKind.existingField);
    expect(own.fieldId, 'requested');

    final full = docuTrackerStepSignaturePlan(
      userId: 'other',
      canAddOwnSignature: true,
      memo: false,
      purchaseRequest: true,
      fields: [
        _field(id: 'requested', signerId: 'reviewer', label: 'Requested by'),
        _field(id: 'approved', signerId: 'mayor', label: 'Approved by'),
      ],
    );
    expect(full.kind, DocuTrackerStepSignatureKind.unavailable);
  });

  test('an official signer without a saved line signs that line', () {
    final plan = docuTrackerStepSignaturePlan(
      userId: 'hr-head',
      canAddOwnSignature: false,
      memo: true,
      fields: const [],
      signatories: DocuTrackerMemoSignatories(
        preparedBy: DocuTrackerMemoDepartmentHead(
          id: 'hr-head',
          fullName: 'HR Head',
        ),
        notedBy: DocuTrackerMemoDepartmentHead(
          id: 'office',
          fullName: "Mayor's Office",
        ),
      ),
    );
    expect(plan.kind, DocuTrackerStepSignatureKind.newField);
    expect(plan.rect, DocuTrackerMemoLayout.preparedField);
    expect(plan.label, 'Prepared by');
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
    expect(plan.rect, DocuTrackerMemoLayout.reviewerSignature);
    final rect = plan.rect!;
    for (final obstacle in DocuTrackerMemoLayout.closingObstacles) {
      expect(rect.overlaps(obstacle), isFalse);
    }
    for (final band in DocuTrackerMemoLayout.pageBands) {
      expect(rect.overlaps(band), isFalse);
    }
  });

  test('another person\'s official line is not signed', () {
    final plan = docuTrackerStepSignaturePlan(
      userId: 'reviewer',
      canAddOwnSignature: true,
      memo: true,
      fields: [
        _field(id: 'noted', signerId: 'mayor-office', label: 'Noted by'),
      ],
    );
    expect(plan.kind, DocuTrackerStepSignatureKind.newField);
    expect(plan.fieldId, isNull);
    expect(plan.rect, DocuTrackerMemoLayout.reviewerSignature);
    expect(plan.rect!.overlaps(DocuTrackerMemoLayout.notedField), isFalse);
  });

  test('a crowded Memorandum does not gain a second reviewer signature', () {
    final spot = DocuTrackerMemoLayout.reviewerSignature;
    final plan = docuTrackerStepSignaturePlan(
      userId: 'reviewer',
      canAddOwnSignature: true,
      memo: true,
      fields: [
        _field(
          id: 'reviewer-signature',
          signerId: 'earlier-reviewer',
          label: 'Signature',
          x: spot.left,
          y: spot.top,
        ),
      ],
    );
    expect(plan.kind, DocuTrackerStepSignatureKind.unavailable);
  });

  test(
    'an earlier signature is not replaced and a second line is not signed',
    () {
      final plan = docuTrackerStepSignaturePlan(
        userId: 'reviewer',
        canAddOwnSignature: true,
        memo: true,
        fields: [
          _field(
            id: 'prepared',
            signerId: 'reviewer',
            label: 'Prepared by',
            signed: true,
          ),
          _field(id: 'noted', signerId: 'reviewer', label: 'Noted by'),
        ],
      );
      expect(plan.kind, DocuTrackerStepSignatureKind.alreadySigned);
      expect(plan.fieldId, isNull);
    },
  );

  test('several unsigned official lines use the earliest line', () {
    final plan = docuTrackerStepSignaturePlan(
      userId: 'reviewer',
      canAddOwnSignature: true,
      memo: true,
      fields: [
        _field(id: 'approved', signerId: 'reviewer', label: 'Approved by'),
        _field(id: 'prepared', signerId: 'reviewer', label: 'Prepared by'),
        _field(id: 'noted', signerId: 'reviewer', label: 'Noted by'),
      ],
    );
    expect(plan.kind, DocuTrackerStepSignatureKind.existingField);
    expect(plan.fieldId, 'prepared');
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

  test('official and free signatures become one transition body', () {
    final ink = Uint8List.fromList(const [1, 2, 3]);
    final official = docuTrackerStepSignaturePlan(
      userId: 'reviewer',
      canAddOwnSignature: true,
      memo: false,
      fields: [
        _field(id: 'noted-id', signerId: 'reviewer', label: 'Noted by'),
        _field(id: 'other', signerId: 'mayor', label: 'Approved by'),
      ],
    );
    final officialBody = docuTrackerTransitionSignatureForPlan(
      plan: official,
      imageBytes: ink,
      sourceType: 'drawn',
    );
    expect(officialBody?.fieldId, 'noted-id');
    expect(officialBody?.toJson()['field_id'], 'noted-id');
    expect(officialBody?.toJson().containsKey('position_x'), isFalse);

    final free = docuTrackerStepSignaturePlan(
      userId: 'reviewer',
      canAddOwnSignature: true,
      memo: false,
      fields: const [],
    );
    final freeBody = docuTrackerTransitionSignatureForPlan(
      plan: free,
      signatureAssetId: 'asset-1',
    );
    expect(freeBody?.fieldId, isNull);
    expect(freeBody?.label, 'Signature');
    expect(freeBody?.toJson()['signature_asset_id'], 'asset-1');
    expect(freeBody?.toJson().containsKey('image_base64'), isFalse);

    final already = docuTrackerStepSignaturePlan(
      userId: 'reviewer',
      canAddOwnSignature: true,
      memo: false,
      fields: [
        _field(
          id: 'noted-id',
          signerId: 'reviewer',
          label: 'Noted by',
          signed: true,
        ),
      ],
    );
    expect(
      docuTrackerTransitionSignatureForPlan(plan: already, imageBytes: ink),
      isNull,
    );
  });
}
