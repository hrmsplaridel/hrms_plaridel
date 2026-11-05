import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hrms_plaridel/features/docutracker/models/document_builder.dart';
import 'package:hrms_plaridel/features/docutracker/utils/docutracker_memo_layout.dart';
import 'package:hrms_plaridel/features/docutracker/utils/docutracker_signature_geometry.dart';

DocuTrackerSignatureField _signed({
  required String id,
  required double x,
  required double y,
  required double width,
  required double height,
  String label = 'Signature',
}) {
  final signedAt = DateTime.utc(2026, 9, 10, 2, 15);
  return DocuTrackerSignatureField(
    id: id,
    pageNumber: 1,
    x: x,
    y: y,
    width: width,
    height: height,
    assignedSignerId: 'signer',
    label: label,
    canSign: false,
    signedAt: signedAt,
    lockedAt: signedAt,
    signerName: 'Kristoffer Zapitan',
  );
}

void main() {
  test('a signed legacy mark that fits moves off the closing block', () {
    const stored = Rect.fromLTWH(0.046, 0.476, 0.30, 0.12);
    final shown = docuTrackerLegacyMemoSignatureFraction(stored);

    expect(shown, isNot(equals(stored)));
    expect(shown.top, greaterThanOrEqualTo(DocuTrackerMemoLayout.closingTop));
    expect(shown.bottom, lessThan(DocuTrackerMemoLayout.letterheadFooterTop));
    for (final obstacle in DocuTrackerMemoLayout.closingObstacles) {
      expect(shown.overlaps(obstacle), isFalse, reason: '$obstacle');
    }
    for (final band in DocuTrackerMemoLayout.pageBands) {
      expect(shown.overlaps(band), isFalse, reason: '$band');
    }
    expect(stored, const Rect.fromLTWH(0.046, 0.476, 0.30, 0.12));
  });

  test('a signature that already clears the closing block stays stored', () {
    const stored = Rect.fromLTWH(0.56, 0.74, 0.2, 0.05);
    expect(docuTrackerLegacyMemoSignatureFraction(stored), stored);
  });

  test(
    'a signature that cannot fit a clear gap keeps its stored rectangle',
    () {
      const stored = Rect.fromLTWH(0.1, 0.52, 0.8, 0.4);
      expect(docuTrackerLegacyMemoSignatureFraction(stored), stored);
    },
  );

  test(
    'editor and PDF placement leaves unsigned fields and stored ids intact',
    () {
      final legacy = _signed(
        id: 'legacy',
        x: 0.046,
        y: 0.476,
        width: 0.3,
        height: 0.12,
      );
      final prepared = DocuTrackerSignatureField(
        id: 'prepared',
        pageNumber: 1,
        x: DocuTrackerMemoLayout.preparedField.left,
        y: DocuTrackerMemoLayout.preparedField.top,
        width: DocuTrackerMemoLayout.preparedField.width,
        height: DocuTrackerMemoLayout.preparedField.height,
        assignedSignerId: 'head',
        label: 'Prepared by',
        canSign: false,
      );
      final placements = docuTrackerLegacyMemoSignaturePlacements([
        legacy,
        prepared,
      ]);

      expect(placements, hasLength(2));
      expect(placements[0].field.id, 'legacy');
      expect(placements[0].field.x, 0.046);
      expect(placements[0].field.y, 0.476);
      expect(
        placements[0].fraction.overlaps(DocuTrackerMemoLayout.preparedField),
        isFalse,
      );
      expect(placements[1].field.id, 'prepared');
      expect(
        placements[1].fraction.top,
        DocuTrackerMemoLayout.preparedField.top,
      );
      expect(
        placements[1].fraction.left,
        DocuTrackerMemoLayout.preparedField.left,
      );
    },
  );
}
