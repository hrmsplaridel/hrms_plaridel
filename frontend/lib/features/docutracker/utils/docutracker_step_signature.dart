import 'dart:ui';

import 'package:hrms_plaridel/features/docutracker/models/document_builder.dart';
import 'package:hrms_plaridel/features/docutracker/utils/docutracker_memo_layout.dart';

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
  });

  const DocuTrackerStepSignaturePlan.alreadySigned()
    : this._(DocuTrackerStepSignatureKind.alreadySigned);

  const DocuTrackerStepSignaturePlan.existingField(String fieldId)
    : this._(DocuTrackerStepSignatureKind.existingField, fieldId: fieldId);

  const DocuTrackerStepSignaturePlan.newField({
    required Rect rect,
    int pageNumber = 1,
  }) : this._(
         DocuTrackerStepSignatureKind.newField,
         rect: rect,
         pageNumber: pageNumber,
       );

  const DocuTrackerStepSignaturePlan.unavailable()
    : this._(DocuTrackerStepSignatureKind.unavailable);

  final DocuTrackerStepSignatureKind kind;
  final String? fieldId;
  final Rect? rect;
  final int pageNumber;
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

/// Chooses the signature that Approve or Forward should write.
///
/// An unsigned field already assigned to [userId] is signed where it sits,
/// official Memo lines first. Otherwise a new signature is placed in the
/// first open spot that stays off the letterhead and the three Memo lines.
DocuTrackerStepSignaturePlan docuTrackerStepSignaturePlan({
  required String userId,
  required List<DocuTrackerSignatureField> fields,
  required bool canAddOwnSignature,
  required bool memo,
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
  if (!canAddOwnSignature) {
    return const DocuTrackerStepSignaturePlan.unavailable();
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
