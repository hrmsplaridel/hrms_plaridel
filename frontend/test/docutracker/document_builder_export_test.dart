import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_builder.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/widgets/docutracker_signature_field_visual.dart';
import 'package:hrms_plaridel/features/docutracker/utils/docutracker_pdf_export.dart';
import 'package:hrms_plaridel/features/docutracker/utils/docutracker_signature_geometry.dart';

void main() {
  final signedField = DocuTrackerSignatureField(
    id: 'field-1',
    pageNumber: 1,
    x: 0.4,
    y: 0.5,
    width: 0.3,
    height: 0.12,
    assignedSignerId: 'signer-1',
    assignedSignerName: 'Assigned Signer',
    label: 'Sign Here',
    canSign: true,
    signatureAssetId: 'asset-1',
    signedBy: 'signer-1',
    signerName: 'Assigned Signer',
    signedAt: DateTime.utc(2026, 8, 30, 0, 30),
    lockedAt: DateTime.utc(2026, 8, 30, 0, 30),
  );

  test('signature geometry preserves normalized A4 placement', () {
    const editorSize = Size(794, 1123);
    const pdfSize = Size(595.28, 841.89);

    final editorRect = docuTrackerSignatureRect(signedField, editorSize);
    final pdfRect = docuTrackerSignatureRect(signedField, pdfSize);

    expect(
      editorRect.left / editorSize.width,
      closeTo(signedField.x, 0.000001),
    );
    expect(
      editorRect.top / editorSize.height,
      closeTo(signedField.y, 0.000001),
    );
    expect(pdfRect.left / pdfSize.width, closeTo(signedField.x, 0.000001));
    expect(pdfRect.top / pdfSize.height, closeTo(signedField.y, 0.000001));
    expect(pdfRect.width / pdfSize.width, closeTo(signedField.width, 0.000001));
    expect(
      pdfRect.height / pdfSize.height,
      closeTo(signedField.height, 0.000001),
    );
  });

  testWidgets('PDF signature visual omits editor interaction hints', (
    tester,
  ) async {
    Future<void> pumpVisual({required bool exportMode}) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 240,
            height: 136,
            child: DocuTrackerSignatureFieldVisual(
              field: signedField,
              signable: true,
              exportMode: exportMode,
            ),
          ),
        ),
      ),
    );

    await pumpVisual(exportMode: false);
    expect(find.text('Drag to move • Click to change'), findsOneWidget);

    await pumpVisual(exportMode: true);
    expect(find.text('Drag to move • Click to change'), findsNothing);
    expect(find.text('Assigned Signer'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('captured page images build a multi-page A4 PDF', () async {
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8A'
      'AQUBAScY42YAAAAASUVORK5CYII=',
    );

    final pdf = await buildDocuTrackerA4Pdf([png, png]);
    final source = latin1.decode(pdf, allowInvalid: true);

    expect(ascii.decode(pdf.sublist(0, 4)), '%PDF');
    expect(RegExp(r'/Type\s*/Page\b').allMatches(source), hasLength(2));
    expect(source, contains('/MediaBox'));
  });
}
