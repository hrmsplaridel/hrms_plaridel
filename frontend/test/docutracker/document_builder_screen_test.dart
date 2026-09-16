import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:printing/printing.dart';
import 'package:printing/src/interface.dart';
import 'package:pdf/pdf.dart';
import 'package:hrms_plaridel/features/docutracker/data/providers/docutracker_provider.dart';
import 'package:hrms_plaridel/features/docutracker/models/document.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_builder.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/pages/docutracker_document_builder_screen.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/widgets/docutracker_signature_fields_panel.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/widgets/docutracker_signature_field_visual.dart';

final _signaturePng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8A'
  'AQUBAScY42YAAAAASUVORK5CYII=',
);

class _Provider extends DocuTrackerProvider {
  _Provider({
    this.editable = true,
    this.signed = false,
    this.invalidSignature = false,
    this.letterhead = false,
    this.invalidSignedPreview = false,
  });
  final bool editable;
  final bool signed;
  final bool invalidSignature;
  final bool letterhead;
  final bool invalidSignedPreview;
  List<DocuTrackerDocumentPage>? _savedPages;
  List<DocuTrackerSignatureField>? _fields;
  int saves = 0;
  int signs = 0;
  int moves = 0;
  @override
  Future<DocuTrackerDocumentBuilderData?> loadDocumentBuilder(
    String id,
  ) async => DocuTrackerDocumentBuilderData(
    documentId: id,
    currentUserId: 'me',
    revision: 1,
    canEditLayout: editable,
    canSign: true,
    formatVersion: letterhead ? 2 : 1,
    pages:
        _savedPages ??
        List.generate(
          3,
          (index) => DocuTrackerDocumentPage(
            delta: [
              {'insert': 'Page body ${index + 1}\n'},
            ],
          ),
        ),
    signatureFields:
        _fields ??
        [
          DocuTrackerSignatureField(
            id: 'field',
            pageNumber: 3,
            x: 0.1,
            y: 0.7,
            width: 0.3,
            height: 0.12,
            assignedSignerId: 'me',
            label: 'Approval',
            canSign: true,
            signedAt: signed ? DateTime.utc(2026, 9, 9) : null,
            lockedAt: signed ? DateTime.utc(2026, 9, 9) : null,
            signerName: signed ? 'Test signer' : null,
            signatureImageBytes: invalidSignature
                ? Uint8List.fromList([1, 2, 3])
                : signed
                ? _signaturePng
                : null,
          ),
        ],
  );

  @override
  Future<List<DocuTrackerSignatureAsset>> listSavedSignatures() async => [
    DocuTrackerSignatureAsset(
      id: 'asset',
      ownerUserId: 'me',
      mimeType: 'image/png',
      sourceType: 'drawn',
      isSaved: true,
      imageBytes: _signaturePng,
    ),
  ];

  @override
  Future<DocuTrackerDocumentBuilderData?> saveDocumentBuilder({
    required String documentId,
    required List<DocuTrackerDocumentPage> pages,
    required List<DocuTrackerSignatureField> signatureFields,
    required int revision,
  }) async {
    saves++;
    _savedPages = pages;
    _fields = signatureFields.indexed
        .map(
          (entry) => entry.$2.id.startsWith('local-')
              ? DocuTrackerSignatureField.fromJson({
                  ...entry.$2.toLayoutJson(),
                  'id': 'persisted-${entry.$1}',
                  'can_sign': true,
                })
              : entry.$2,
        )
        .toList();
    return loadDocumentBuilder(documentId);
  }

  @override
  Future<DocuTrackerDocumentBuilderData?> signDocumentField({
    required String documentId,
    required String fieldId,
    String? signatureAssetId,
    Uint8List? imageBytes,
    String mimeType = 'image/png',
    String sourceType = 'drawn',
    bool saveForReuse = false,
  }) async {
    signs++;
    final data = (await loadDocumentBuilder(documentId))!;
    _fields = data.signatureFields
        .map(
          (field) => field.id == fieldId
              ? DocuTrackerSignatureField.fromJson({
                  ...field.toLayoutJson(),
                  'can_sign': true,
                  'signed_at': '2026-09-09T00:00:00Z',
                  'locked_at': '2026-09-09T00:00:00Z',
                  'signature_image_base64': base64Encode(
                    invalidSignedPreview ? [1, 2, 3] : _signaturePng,
                  ),
                  'signer_name_snapshot': 'Test signer',
                })
              : field,
        )
        .toList();
    return loadDocumentBuilder(documentId);
  }

  @override
  Future<DocuTrackerDocumentBuilderData?> moveSignedDocumentField({
    required String documentId,
    required String fieldId,
    required double x,
    required double y,
  }) async {
    moves++;
    final data = (await loadDocumentBuilder(documentId))!;
    _fields = data.signatureFields
        .map(
          (field) => field.id == fieldId ? field.copyWith(x: x, y: y) : field,
        )
        .toList();
    return loadDocumentBuilder(documentId);
  }
}

class _Printing extends PrintingPlatform {
  Uint8List? exported;
  bool fail = false;
  @override
  Future<bool> sharePdf(
    Uint8List bytes,
    String filename,
    Rect bounds,
    String? subject,
    String? body,
    List<String>? emails,
  ) async {
    exported = bytes;
    if (fail) throw StateError('Simulated share failure');
    return true;
  }

  @override
  Future<PrintingInfo> info() async => const PrintingInfo(canRaster: false);
  @override
  Future<bool> layoutPdf(
    Printer? printer,
    LayoutCallback onLayout,
    String name,
    PdfPageFormat format,
    bool dynamicLayout,
    bool usePrinterSettings,
    OutputType outputType,
    bool forceCustomPrintPaper,
  ) async {
    exported = await onLayout(format);
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pumpBuilder(
  WidgetTester tester,
  double width, {
  bool editable = true,
  _Provider? provider,
  bool nestedNavigator = false,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 900);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.binding.setSurfaceSize(Size(width, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ChangeNotifierProvider<DocuTrackerProvider>(
      create: (_) => provider ?? _Provider(editable: editable),
      child: MaterialApp(
        home: nestedNavigator
            ? Navigator(
                onGenerateInitialRoutes: (_, _) => [
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        const Scaffold(body: Text('Previous screen')),
                  ),
                  MaterialPageRoute<void>(
                    builder: (_) => const DocuTrackerDocumentBuilderScreen(
                      document: DocuTrackerDocument(
                        id: 'doc',
                        documentType: 'memo',
                        title: 'Office memorandum',
                      ),
                    ),
                  ),
                ],
              )
            : const DocuTrackerDocumentBuilderScreen(
                document: DocuTrackerDocument(
                  id: 'doc',
                  documentType: 'memo',
                  title: 'Office memorandum',
                ),
              ),
      ),
    ),
  );
  await tester.pump();
  for (
    var i = 0;
    i < 50 && find.byType(quill.QuillEditor).evaluate().isEmpty;
    i++
  ) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  await tester.pumpAndSettle();
}

Future<void> _more(WidgetTester tester, String action) async {
  await tester.tap(find.byTooltip('More'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(action));
  await tester.pumpAndSettle();
}

BoxDecoration _signatureDecoration(WidgetTester tester) =>
    tester
            .widget<DecoratedBox>(
              find
                  .ancestor(
                    of: find.byType(DocuTrackerSignatureFieldVisual),
                    matching: find.byType(DecoratedBox),
                  )
                  .first,
            )
            .decoration
        as BoxDecoration;

Future<void> _finishSigning(WidgetTester tester) async {
  // Real image decoding is not advanced by the test's fake clock.
  for (var i = 0; i < 30; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
    if (find.text('Signature added and locked.').evaluate().isNotEmpty ||
        find.textContaining('Signature replaced.').evaluate().isNotEmpty ||
        find.textContaining('Signature saved, but').evaluate().isNotEmpty) {
      break;
    }
  }
  await tester.pumpAndSettle();
}

void main() {
  for (final width in [360.0, 768.0, 1440.0]) {
    testWidgets('signing immediately displays its page and image at $width', (
      tester,
    ) async {
      final provider = _Provider();
      await _pumpBuilder(tester, width, provider: provider);
      await tester.tap(find.byTooltip('Signatures'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('sign-field')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Saved').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use signature'));
      await _finishSigning(tester);
      expect(provider.signs, 1);
      expect(find.text('Page 3 of 3'), findsOneWidget);
      final visual = find.byType(DocuTrackerSignatureFieldVisual);
      expect(visual, findsOneWidget);
      expect(
        tester.widget<DocuTrackerSignatureFieldVisual>(visual).field.isSigned,
        isTrue,
      );
      final rawImage = find.descendant(
        of: visual,
        matching: find.byType(RawImage),
      );
      expect(rawImage, findsOneWidget);
      expect(tester.widget<RawImage>(rawImage).image, isNotNull);
      expect(_signatureDecoration(tester).color, Colors.transparent);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'failed preview preserves confirmed signature and shows an error',
    (tester) async {
      final provider = _Provider(invalidSignedPreview: true);
      await _pumpBuilder(tester, 1440, provider: provider);
      await tester.tap(find.byTooltip('Signatures'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('sign-field')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Saved').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use signature'));
      await _finishSigning(tester);
      expect(provider.signs, 1);
      expect(find.text('Page 3 of 3'), findsOneWidget);
      expect(find.textContaining('Signature saved, but'), findsOneWidget);
      expect(find.text('Signature image unavailable'), findsOneWidget);
      expect(
        tester
            .widget<DocuTrackerSignatureFieldVisual>(
              find.byType(DocuTrackerSignatureFieldVisual),
            )
            .field
            .isSigned,
        isTrue,
      );
      expect(
        tester
            .widget<DocuTrackerSignatureFieldsPanel>(
              find.byType(DocuTrackerSignatureFieldsPanel),
            )
            .isBusy,
        isFalse,
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final width in [360.0, 768.0, 1440.0]) {
    for (final tool in ['Format', 'Zoom']) {
      testWidgets('Close $tool preserves nested builder at $width', (
        tester,
      ) async {
        await _pumpBuilder(tester, width, nestedNavigator: true);
        final controller = tester
            .widget<quill.QuillEditor>(find.byType(quill.QuillEditor))
            .controller;
        controller.replaceText(
          0,
          0,
          'Unsaved ',
          const TextSelection(baseOffset: 0, extentOffset: 7),
        );
        await _more(tester, tool);
        await tester.tap(find.byTooltip('Close $tool'));
        await tester.pumpAndSettle();
        expect(find.byTooltip('Close $tool'), findsNothing);
        expect(find.byType(quill.QuillEditor), findsOneWidget);
        expect(find.text('Previous screen'), findsNothing);
        final restored = tester
            .widget<quill.QuillEditor>(find.byType(quill.QuillEditor))
            .controller;
        expect(identical(controller, restored), isTrue);
        expect(restored.document.toPlainText(), startsWith('Unsaved '));
        expect(
          restored.selection,
          const TextSelection(baseOffset: 0, extentOffset: 7),
        );
        expect(tester.takeException(), isNull);
      });
    }
  }
  for (final width in [360.0, 768.0, 1440.0]) {
    testWidgets('compact builder and on-demand tools at $width', (
      tester,
    ) async {
      await _pumpBuilder(tester, width);
      expect(find.byType(quill.QuillEditor), findsOneWidget);
      expect(find.byType(DocuTrackerSignatureFieldsPanel), findsNothing);
      expect(find.text('Document actions'), findsNothing);
      expect(find.byTooltip('Bold'), findsNothing);
      expect(find.text('Page 1 of 3'), findsOneWidget);
      final fittedPage = find
          .ancestor(
            of: find.byType(quill.QuillEditor),
            matching: find.byType(FittedBox),
          )
          .first;
      final pageRect = tester.getRect(fittedPage);
      expect(pageRect.left, greaterThanOrEqualTo(0));
      expect(pageRect.right, lessThanOrEqualTo(width));
      expect(pageRect.top, greaterThanOrEqualTo(56));
      expect(pageRect.bottom, lessThanOrEqualTo(852));
      await tester.tap(find.byTooltip('Signatures'));
      await tester.pumpAndSettle();
      expect(find.text('Add Signature Field'), findsOneWidget);
      expect(find.text('Insert My Signature'), findsOneWidget);
      await tester.tap(find.byTooltip('Close signature fields'));
      await tester.pumpAndSettle();
      final controller = tester
          .widget<quill.QuillEditor>(find.byType(quill.QuillEditor))
          .controller;
      controller.updateSelection(
        const TextSelection(baseOffset: 0, extentOffset: 4),
        quill.ChangeSource.local,
      );
      await _more(tester, 'Format');
      expect(find.byTooltip('Bold'), findsOneWidget);
      await tester.tap(find.byTooltip('Bold'));
      await tester.pump();
      expect(
        controller.selection,
        const TextSelection(baseOffset: 0, extentOffset: 4),
      );
      expect(controller.document.toDelta().toJson().first['attributes'], {
        'bold': true,
      });
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('navigation retains unsaved text and formatting selection', (
    tester,
  ) async {
    await _pumpBuilder(tester, 1440);
    final controller = tester
        .widget<quill.QuillEditor>(find.byType(quill.QuillEditor))
        .controller;
    controller.replaceText(
      0,
      0,
      'Edited ',
      const TextSelection(baseOffset: 0, extentOffset: 6),
    );
    await tester.pumpAndSettle();
    await _more(tester, 'Format');
    await tester.tap(find.byTooltip('Bold'));
    await tester.pump();
    expect(controller.document.toDelta().toJson().first['attributes'], {
      'bold': true,
    });
    await tester.tapAt(const Offset(10, 500));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Next page'));
    await tester.pumpAndSettle();
    expect(find.text('Page 2 of 3'), findsOneWidget);
    await tester.tap(find.byTooltip('Previous page'));
    await tester.pumpAndSettle();
    final restored = tester
        .widget<quill.QuillEditor>(find.byType(quill.QuillEditor))
        .controller;
    expect(identical(restored, controller), isTrue);
    expect(restored.document.toPlainText(), startsWith('Edited Page body 1'));
    expect(find.text('Unsaved changes'), findsOneWidget);
    await _more(tester, 'Add Page');
    expect(find.text('Page 4 of 4'), findsOneWidget);
    await tester.tap(find.byTooltip('Choose page'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Page 2'));
    await tester.pumpAndSettle();
    expect(find.text('Page 2 of 4'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('signature Go to opens its page; viewer cannot add or format', (
    tester,
  ) async {
    await _pumpBuilder(tester, 1440, editable: false);
    await tester.tap(find.byTooltip('Signatures'));
    await tester.pumpAndSettle();
    expect(find.text('Add Signature Field'), findsNothing);
    expect(find.text('Insert My Signature'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('go-to-field')));
    await tester.pumpAndSettle();
    expect(find.text('Page 3 of 3'), findsOneWidget);
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    expect(find.text('Format'), findsNothing);
    expect(find.text('Add Page'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'panel inserts, replaces, drags signatures and deletes only unsigned fields',
    (tester) async {
      final provider = _Provider();
      await _pumpBuilder(tester, 1440, provider: provider);
      await tester.tap(find.byTooltip('Signatures'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Insert My Signature'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Saved').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use signature'));
      await _finishSigning(tester);
      expect(provider.saves, 1);
      expect(provider.signs, 1);
      final field = tester
          .widget<DocuTrackerSignatureFieldVisual>(
            find.byType(DocuTrackerSignatureFieldVisual),
          )
          .field;
      expect(field.isSigned, isTrue);
      expect(field.canSign, isTrue);
      expect(find.byType(DocuTrackerSignatureFieldsPanel), findsOneWidget);
      expect(
        tester
            .widget<DocuTrackerSignatureFieldsPanel>(
              find.byType(DocuTrackerSignatureFieldsPanel),
            )
            .isBusy,
        isFalse,
      );
      expect(find.byKey(ValueKey('delete-${field.id}')), findsNothing);
      await tester.tap(find.byKey(ValueKey('sign-${field.id}')));
      await tester.pumpAndSettle();
      expect(find.text('Replace signature?'), findsOneWidget);
      await tester.tap(find.text('Replace'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Saved').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use signature'));
      await _finishSigning(tester);
      expect(provider.signs, 2);
      await tester.drag(
        find
            .ancestor(
              of: find.byType(DocuTrackerSignatureFieldVisual),
              matching: find.byType(GestureDetector),
            )
            .first,
        const Offset(35, -30),
      );
      await tester.pumpAndSettle();
      expect(provider.moves, 1);
      final moved = tester
          .widget<DocuTrackerSignatureFieldVisual>(
            find.byType(DocuTrackerSignatureFieldVisual),
          )
          .field;
      expect(moved.x, greaterThan(field.x));
      expect(moved.y, lessThan(field.y));
      await tester.tap(find.byKey(const ValueKey('delete-field')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('delete-field')), findsNothing);
      expect(find.text('Unsaved changes'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final fail in [false, true]) {
    testWidgets(
      'all pages export and page two is restored (share failure: $fail)',
      (tester) async {
        final previous = PrintingPlatform.instance;
        final printing = _Printing()..fail = fail;
        PrintingPlatform.instance = printing;
        addTearDown(() => PrintingPlatform.instance = previous);
        await _pumpBuilder(
          tester,
          1440,
          provider: _Provider(signed: true, letterhead: true),
        );
        await tester.tap(find.byTooltip('Next page'));
        await tester.pumpAndSettle();
        final controller = tester
            .widget<quill.QuillEditor>(find.byType(quill.QuillEditor))
            .controller;
        controller.updateSelection(
          const TextSelection(baseOffset: 0, extentOffset: 4),
          quill.ChangeSource.local,
        );
        await _more(tester, 'Zoom');
        await tester.tap(find.text('Fit width'));
        await tester.pump();
        await tester.tap(find.byTooltip('Close Zoom'));
        await tester.pumpAndSettle();
        final canvas = tester
            .widget<SingleChildScrollView>(
              find.byKey(const ValueKey('canvas-1')),
            )
            .controller!;
        canvas.jumpTo(180);
        await tester.pump();
        final originalOffset = canvas.offset;
        await tester.tap(find.byTooltip('More'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Export PDF'));
        final renderedPages = <String>[];
        var sawBlockingProgress = false;
        var sawReadOnly = false;
        // toImage uses the engine; allow its real asynchronous work between frames.
        for (var i = 0; i < 100 && printing.exported == null; i++) {
          await tester.pump(const Duration(milliseconds: 50));
          if (find
              .byKey(const ValueKey('builder-export-barrier'))
              .evaluate()
              .isNotEmpty) {
            sawBlockingProgress = true;
            sawReadOnly = sawReadOnly || controller.readOnly;
            expect(
              tester
                  .widget<IconButton>(
                    find.byWidgetPredicate(
                      (widget) =>
                          widget is IconButton && widget.tooltip == 'Next page',
                    ),
                  )
                  .onPressed,
              isNull,
            );
            final editor = tester.widget<quill.QuillEditor>(
              find.byType(quill.QuillEditor),
            );
            final body = editor.controller.document.toPlainText();
            if (renderedPages.isEmpty || renderedPages.last != body) {
              renderedPages.add(body);
            }
            expect(
              find.byKey(const ValueKey('docutracker-printable-header')),
              findsOneWidget,
            );
            expect(
              find.byKey(const ValueKey('docutracker-printable-footer')),
              findsOneWidget,
            );
            final pageBoundary = tester.renderObject<RenderRepaintBoundary>(
              find
                  .ancestor(
                    of: find.byType(quill.QuillEditor),
                    matching: find.byType(RepaintBoundary),
                  )
                  .first,
            );
            expect(pageBoundary.size, const Size(794, 1123));
            if (body.contains('3')) {
              // The actual page captured for PDF must not white out the text
              // underneath the signed field, just as in the editor.
              final decoration = _signatureDecoration(tester);
              expect(decoration.color, Colors.transparent);
              expect(
                (decoration.border! as Border).top.color,
                Colors.transparent,
              );
              expect(
                tester
                    .widget<DocuTrackerSignatureFieldVisual>(
                      find.byType(DocuTrackerSignatureFieldVisual),
                    )
                    .exportMode,
                isTrue,
              );
              expect(find.text('Test signer'), findsOneWidget);
            }
          }
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)),
          );
        }
        await tester.pumpAndSettle();
        expect(printing.exported, isNotNull);
        expect(sawBlockingProgress, isTrue);
        expect(sawReadOnly, isTrue);
        // Preparation/restoration may render page two before and after capture.
        final first = renderedPages.indexOf('Page body 1\n');
        expect(renderedPages.skip(first).take(3), [
          'Page body 1\n',
          'Page body 2\n',
          'Page body 3\n',
        ]);
        final source = latin1.decode(printing.exported!);
        expect(RegExp(r'/Type\s*/Page\b').allMatches(source), hasLength(3));
        expect(find.text('Page 2 of 3'), findsOneWidget);
        expect(
          controller.selection,
          const TextSelection(baseOffset: 0, extentOffset: 4),
        );
        expect(controller.readOnly, isFalse);
        expect(canvas.offset, originalOffset);
        await _more(tester, 'Zoom');
        expect(find.text('100% of page width'), findsOneWidget);
        await tester.tap(find.byTooltip('Close Zoom'));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('builder-export-barrier')),
          findsNothing,
        );
        if (fail) {
          expect(
            find.text('Could not export the PDF. Please try again.'),
            findsOneWidget,
          );
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('image capture preparation failure restores page and selection', (
    tester,
  ) async {
    final previous = PrintingPlatform.instance;
    final printing = _Printing();
    PrintingPlatform.instance = printing;
    addTearDown(() => PrintingPlatform.instance = previous);
    await _pumpBuilder(
      tester,
      768,
      provider: _Provider(signed: true, invalidSignature: true),
    );
    await tester.tap(find.byTooltip('Next page'));
    await tester.pumpAndSettle();
    final controller = tester
        .widget<quill.QuillEditor>(find.byType(quill.QuillEditor))
        .controller;
    controller.updateSelection(
      const TextSelection(baseOffset: 1, extentOffset: 4),
      quill.ChangeSource.local,
    );
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Export PDF'));
    for (
      var i = 0;
      i < 50 &&
          find
              .text('Could not export the PDF. Please try again.')
              .evaluate()
              .isEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }
    await tester.pumpAndSettle();
    expect(
      find.text('Could not export the PDF. Please try again.'),
      findsOneWidget,
    );
    expect(printing.exported, isNull);
    expect(find.text('Page 2 of 3'), findsOneWidget);
    expect(
      controller.selection,
      const TextSelection(baseOffset: 1, extentOffset: 4),
    );
    expect(controller.readOnly, isFalse);
    expect(find.byKey(const ValueKey('builder-export-barrier')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
