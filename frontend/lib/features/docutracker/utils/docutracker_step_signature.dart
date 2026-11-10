import 'dart:typed_data';
import 'dart:ui';

import 'package:hrms_plaridel/features/docutracker/models/document_builder.dart';
import 'package:hrms_plaridel/features/docutracker/models/docutracker_transition_signature.dart';
import 'package:hrms_plaridel/features/docutracker/utils/docutracker_memo_layout.dart';
import 'package:hrms_plaridel/features/docutracker/utils/docutracker_purchase_layout.dart';

/// How an approval or forward should capture the reviewer's signature.
enum DocuTrackerStepSignatureKind {
  /// This person already signed the document. No new ink is written.
  alreadySigned,

  /// Sign the field already assigned to this person, in its stored area.
  existingField,

  /// Add this person's signature at [rect] without asking them to drag it.
  newField,

  /// The server will not let this person add a signature.
  unavailable,
}

/// The signature action to take before a workflow step continues.
class DocuTrackerStepSignaturePlan {
  const DocuTrackerStepSignaturePlan._(
    this.kind, {
    this.fieldId,
    this.rect,
    this.pageNumber = 1,
    this.label,
  });

  const DocuTrackerStepSignaturePlan.alreadySigned()
    : this._(DocuTrackerStepSignatureKind.alreadySigned);

  const DocuTrackerStepSignaturePlan.existingField(String fieldId)
    : this._(DocuTrackerStepSignatureKind.existingField, fieldId: fieldId);

  const DocuTrackerStepSignaturePlan.newField({
    required Rect rect,
    int pageNumber = 1,
    String? label,
  }) : this._(
         DocuTrackerStepSignatureKind.newField,
         rect: rect,
         pageNumber: pageNumber,
         label: label,
       );

  const DocuTrackerStepSignaturePlan.unavailable()
    : this._(DocuTrackerStepSignatureKind.unavailable);

  final DocuTrackerStepSignatureKind kind;
  final String? fieldId;
  final Rect? rect;
  final int pageNumber;
  final String? label;
}

const _slotOrder = <String>[
  DocuTrackerMemoLayout.preparedFieldLabel,
  DocuTrackerMemoLayout.notedFieldLabel,
  DocuTrackerMemoLayout.approvedFieldLabel,
];

const _box = Size(0.28, 0.08);

const _candidates = <Offset>[
  Offset(0.56, 0.73),
  Offset(0.13, 0.73),
  Offset(0.58, 0.36),
  Offset(0.18, 0.36),
];

DocuTrackerStepSignaturePlan? _officialSlotFor(
  String userId, {
  required bool memo,
  DocuTrackerMemoSignatories? signatories,
}) {
  if (!memo || signatories == null) return null;
  final slots = <(DocuTrackerMemoDepartmentHead?, Rect, String)>[
    (
      signatories.preparedBy,
      DocuTrackerMemoLayout.preparedField,
      DocuTrackerMemoLayout.preparedFieldLabel,
    ),
    (
      signatories.notedBy,
      DocuTrackerMemoLayout.notedField,
      DocuTrackerMemoLayout.notedFieldLabel,
    ),
    (
      signatories.approvedBy,
      DocuTrackerMemoLayout.approvedField,
      DocuTrackerMemoLayout.approvedFieldLabel,
    ),
  ];
  for (final slot in slots) {
    if (slot.$1?.id != userId) continue;
    return DocuTrackerStepSignaturePlan.newField(rect: slot.$2, label: slot.$3);
  }
  return null;
}

DocuTrackerStepSignaturePlan? _purchaseSlotFor(
  List<DocuTrackerSignatureField> fields, {
  required bool purchaseRequest,
  required bool finalApproval,
}) {
  if (!purchaseRequest) return null;
  final slots = finalApproval
      ? const [
          (
            DocuTrackerPurchaseLayout.approvedField,
            DocuTrackerPurchaseLayout.approvedLabel,
          ),
          (
            DocuTrackerPurchaseLayout.requestedField,
            DocuTrackerPurchaseLayout.requestedLabel,
          ),
        ]
      : const [
          (
            DocuTrackerPurchaseLayout.requestedField,
            DocuTrackerPurchaseLayout.requestedLabel,
          ),
          (
            DocuTrackerPurchaseLayout.approvedField,
            DocuTrackerPurchaseLayout.approvedLabel,
          ),
        ];
  for (final slot in slots) {
    final taken = fields.any(
      (field) => field.pageNumber == 1 && field.label == slot.$2,
    );
    if (taken) continue;
    return DocuTrackerStepSignaturePlan.newField(rect: slot.$1, label: slot.$2);
  }
  return null;
}

/// Chooses the signature that Approve or Forward should write.
///
/// An unsigned field already assigned to [userId] is signed where it sits,
/// official Memo lines first. When that person is the resolved official
/// signatory and the line has not been saved yet, the ink is aimed at that
/// line. A reviewer who owns none of those lines is placed in
/// [DocuTrackerMemoLayout.reviewerSignature]. When that band is already
/// taken, no second box is forced over the page. A purchase request uses
/// Requested by on an earlier step and Approved by on the last step. When
/// both of those boxes already belong to someone else, no extra signature
/// is floated over the form.
DocuTrackerStepSignaturePlan docuTrackerStepSignaturePlan({
  required String userId,
  required List<DocuTrackerSignatureField> fields,
  required bool canAddOwnSignature,
  required bool memo,
  DocuTrackerMemoSignatories? signatories,
  bool purchaseRequest = false,
  bool finalApproval = false,
}) {
  final signed = fields.any(
    (field) => field.isSigned && field.signedBy == userId,
  );
  if (signed) return const DocuTrackerStepSignaturePlan.alreadySigned();

  final mine = fields
      .where(
        (field) =>
            !field.isSigned &&
            field.assignedSignerId == userId &&
            !field.id.startsWith('local-'),
      )
      .toList(growable: false);
  mine.sort((a, b) {
    final aSlot = _slotOrder.indexOf(a.label);
    final bSlot = _slotOrder.indexOf(b.label);
    final aRank = aSlot < 0 ? _slotOrder.length : aSlot;
    final bRank = bSlot < 0 ? _slotOrder.length : bSlot;
    return aRank.compareTo(bRank);
  });
  if (mine.isNotEmpty) {
    return DocuTrackerStepSignaturePlan.existingField(mine.first.id);
  }
  final official = _officialSlotFor(
    userId,
    memo: memo,
    signatories: signatories,
  );
  if (official != null) return official;
  if (!canAddOwnSignature) {
    return const DocuTrackerStepSignaturePlan.unavailable();
  }

  final purchase = _purchaseSlotFor(
    fields,
    purchaseRequest: purchaseRequest,
    finalApproval: finalApproval,
  );
  if (purchase != null) return purchase;
  if (purchaseRequest) {
    return const DocuTrackerStepSignaturePlan.unavailable();
  }

  if (memo) {
    final rect = DocuTrackerMemoLayout.reviewerSignature;
    final blocked = <Rect>[
      for (final field in fields)
        Rect.fromLTWH(field.x, field.y, field.width, field.height),
      ...DocuTrackerMemoLayout.closingObstacles,
      ...DocuTrackerMemoLayout.pageBands,
    ];
    if (rect.right > 1 || rect.bottom > 1 || blocked.any(rect.overlaps)) {
      return const DocuTrackerStepSignaturePlan.unavailable();
    }
    return DocuTrackerStepSignaturePlan.newField(rect: rect);
  }

  final blocked = <Rect>[
    for (final field in fields)
      Rect.fromLTWH(field.x, field.y, field.width, field.height),
    if (memo) ...DocuTrackerMemoLayout.closingObstacles,
    if (memo) ...DocuTrackerMemoLayout.pageBands,
  ];
  for (final origin in _candidates) {
    final rect = Rect.fromLTWH(origin.dx, origin.dy, _box.width, _box.height);
    if (rect.right > 1 || rect.bottom > 1) continue;
    if (blocked.any(rect.overlaps)) continue;
    return DocuTrackerStepSignaturePlan.newField(rect: rect);
  }
  return DocuTrackerStepSignaturePlan.newField(
    rect: Rect.fromLTWH(0.56, 0.73, _box.width, _box.height),
  );
}

/// Builds the signature body for one workflow transition.
///
/// An existing signature and a placement the server will refuse both return
/// null. The caller must not send a body in those cases.
DocuTrackerTransitionSignature? docuTrackerTransitionSignatureForPlan({
  required DocuTrackerStepSignaturePlan plan,
  String? signatureAssetId,
  Uint8List? imageBytes,
  String mimeType = 'image/png',
  String sourceType = 'drawn',
  bool saveForReuse = false,
}) {
  switch (plan.kind) {
    case DocuTrackerStepSignatureKind.alreadySigned:
    case DocuTrackerStepSignatureKind.unavailable:
      return null;
    case DocuTrackerStepSignatureKind.existingField:
      return DocuTrackerTransitionSignature(
        fieldId: plan.fieldId,
        signatureAssetId: signatureAssetId,
        imageBytes: imageBytes,
        mimeType: mimeType,
        sourceType: sourceType,
        saveForReuse: saveForReuse,
      );
    case DocuTrackerStepSignatureKind.newField:
      final rect = plan.rect;
      if (rect == null) return null;
      return DocuTrackerTransitionSignature(
        pageNumber: plan.pageNumber,
        x: rect.left,
        y: rect.top,
        width: rect.width,
        height: rect.height,
        label: plan.label ?? 'Signature',
        signatureAssetId: signatureAssetId,
        imageBytes: imageBytes,
        mimeType: mimeType,
        sourceType: sourceType,
        saveForReuse: saveForReuse,
      );
  }
}
