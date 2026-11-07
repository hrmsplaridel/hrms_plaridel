import 'dart:ui';

import 'package:hrms_plaridel/features/docutracker/models/document_builder.dart';
import 'package:hrms_plaridel/features/docutracker/utils/docutracker_memo_layout.dart';

Rect docuTrackerSignatureRect(DocuTrackerSignatureField field, Size pageSize) =>
    Rect.fromLTWH(
      field.x * pageSize.width,
      field.y * pageSize.height,
      field.width * pageSize.width,
      field.height * pageSize.height,
    );

/// Where a signed signature that is not an official Memo slot is painted.
///
/// [stored] is never modified. When it covers the letterhead, body, footer,
/// or closing block and a clear gap remains, that gap is used. When no gap
/// can hold the signature at its saved size, [stored] is returned.
Rect docuTrackerLegacyMemoSignatureFraction(
  Rect stored, {
  Iterable<Rect> occupied = const <Rect>[],
}) {
  final hitsClosing = DocuTrackerMemoLayout.closingObstacles.any(
    stored.overlaps,
  );
  final hitsBand = DocuTrackerMemoLayout.pageBands.any(stored.overlaps);
  if (!hitsClosing && !hitsBand) return stored;
  final blocked = <Rect>[
    ...DocuTrackerMemoLayout.closingObstacles,
    ...DocuTrackerMemoLayout.pageBands,
    ...occupied,
  ];
  final maxBottom = DocuTrackerMemoLayout.letterheadFooterTop - 0.004;
  final minTop = DocuTrackerMemoLayout.closingTop;
  if (stored.height > maxBottom - minTop || stored.width <= 0) return stored;
  final rightLimit = 1 - DocuTrackerMemoLayout.marginX;
  for (
    var top = minTop;
    top + stored.height <= maxBottom + 0.0001;
    top += 0.01
  ) {
    for (
      var left = DocuTrackerMemoLayout.marginX;
      left + stored.width <= rightLimit + 0.0001;
      left += 0.02
    ) {
      final candidate = Rect.fromLTWH(left, top, stored.width, stored.height);
      if (blocked.any(candidate.overlaps)) continue;
      return candidate;
    }
  }
  return stored;
}

class DocuTrackerSignaturePlacement {
  const DocuTrackerSignaturePlacement(this.field, this.fraction);

  final DocuTrackerSignatureField field;
  final Rect fraction;
}

/// Editor and PDF share this list. Signed legacy fields move to a clear gap
/// when one exists. Unsigned fields and fields that already fit stay put.
/// Nothing here writes coordinates back to the field.
List<DocuTrackerSignaturePlacement> docuTrackerLegacyMemoSignaturePlacements(
  Iterable<DocuTrackerSignatureField> fields,
) {
  final occupied = <Rect>[];
  final placements = <DocuTrackerSignaturePlacement>[];
  for (final field in fields) {
    final stored = Rect.fromLTWH(field.x, field.y, field.width, field.height);
    final fraction = field.isSigned
        ? docuTrackerLegacyMemoSignatureFraction(stored, occupied: occupied)
        : stored;
    occupied.add(fraction);
    placements.add(DocuTrackerSignaturePlacement(field, fraction));
  }
  return placements;
}
