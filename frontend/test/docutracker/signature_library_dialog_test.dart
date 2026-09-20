import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/docutracker/data/providers/docutracker_provider.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_builder.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/widgets/docutracker_signature_library_dialog.dart';

final Uint8List _signaturePng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8A'
  'AQUBAScY42YAAAAASUVORK5CYII=',
);

class _SignatureLibraryProvider extends DocuTrackerProvider {
  final List<DocuTrackerSignatureAsset> assets = [
    DocuTrackerSignatureAsset(
      id: 'signature-1',
      ownerUserId: 'me',
      mimeType: 'image/png',
      sourceType: 'drawn',
      isSaved: true,
      imageBytes: _signaturePng,
      displayName: 'Official Signature',
    ),
    DocuTrackerSignatureAsset(
      id: 'signature-2',
      ownerUserId: 'me',
      mimeType: 'image/png',
      sourceType: 'uploaded',
      isSaved: true,
      imageBytes: _signaturePng,
      displayName: 'Short Signature',
    ),
  ];

  String? removedId;
  String? renamedName;

  @override
  Future<List<DocuTrackerSignatureAsset>> listSavedSignatures() async =>
      List.unmodifiable(assets);

  @override
  Future<DocuTrackerSignatureAsset> renameSavedSignature({
    required String assetId,
    required String displayName,
  }) async {
    renamedName = displayName;
    return assets.firstWhere((asset) => asset.id == assetId);
  }

  @override
  Future<void> removeSavedSignature(String assetId) async {
    removedId = assetId;
    assets.removeWhere((asset) => asset.id == assetId);
  }
}

void main() {
  testWidgets('library lists multiple signatures and safely removes one', (
    tester,
  ) async {
    final provider = _SignatureLibraryProvider();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () => showDocuTrackerSignatureLibraryDialog(
              context,
              provider: provider,
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('My Signatures'), findsOneWidget);
    expect(find.text('Official Signature'), findsOneWidget);
    expect(find.text('Short Signature'), findsOneWidget);

    await tester.tap(find.byTooltip('Signature actions').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(find.text('Remove Signature?'), findsOneWidget);
    expect(
      find.textContaining('Documents already signed with it will not change'),
      findsOneWidget,
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await tester.pumpAndSettle();

    expect(provider.removedId, 'signature-1');
    expect(find.text('Official Signature'), findsNothing);
    expect(find.text('Short Signature'), findsOneWidget);
  });

  testWidgets('library fits a 360 pixel screen', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final provider = _SignatureLibraryProvider();

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDocuTrackerSignatureLibraryDialog(
              context,
              provider: provider,
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('docutracker-add-saved-signature')),
      findsOneWidget,
    );
  });

  testWidgets('naming dialog submits and disposes safely', (tester) async {
    final provider = _SignatureLibraryProvider();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () => showDocuTrackerSignatureLibraryDialog(
              context,
              provider: provider,
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Signature actions').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();

    expect(find.text('Rename Signature'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'My approval signature');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(provider.renamedName, 'My approval signature');
    expect(find.text('My Signatures'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
