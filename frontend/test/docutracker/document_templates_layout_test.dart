import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/docutracker/models/document.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_purchase_items.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/widgets/docutracker_printable_page_frame.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/widgets/docutracker_purchase_items_table.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/widgets/docutracker_purchase_signature_band.dart';
import 'package:hrms_plaridel/features/docutracker/utils/docutracker_draft_text.dart';

void main() {
  for (final type in ['memo', 'purchaseRequest']) {
    testWidgets(
      '$type template fits the official letterhead body and prints without editing controls',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(794, 1123);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final fonts = FontLoader('Roboto')
          ..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
        await fonts.load();
        final document = DocuTrackerDocument(
          documentType: type,
          title: 'Office supplies and procedures',
          description:
              'For the daily operations of the Human Resource Management and Development Office.',
        );
        final controller = quill.QuillController(
          document: quill.Document.fromJson(
            DocuTrackerDraftText.composePage(document).delta,
          ),
          selection: const TextSelection.collapsed(offset: 0),
          readOnly: true,
        );
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: const [
              quill.FlutterQuillLocalizations.delegate,
            ],
            home: Scaffold(
              body: DocuTrackerPrintablePageFrame(
                documentTitle: document.title,
                // Tiny image exercises the real full-background letterhead margins.
                letterheadImageBytes: base64Decode(
                  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
                ),
                child: quill.QuillEditor.basic(
                  controller: controller,
                  config: const quill.QuillEditorConfig(
                    scrollable: false,
                    expands: true,
                    padding: EdgeInsets.zero,
                    embedBuilders: [
                      DocuTrackerPurchaseItemsEmbedBuilder(editable: false),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final editorFinder = find.byElementPredicate(
          (element) =>
              element is RenderObjectElement &&
              element.renderObject is quill.RenderEditor,
        );
        final editor = tester.renderObject<quill.RenderEditor>(editorFinder);
        final caret = editor.getLocalRectForCaret(
          TextPosition(offset: controller.document.length - 1),
        );
        final body = tester.getRect(find.byType(quill.QuillEditor));
        expect(
          editor.localToGlobal(caret.bottomRight).dy,
          lessThanOrEqualTo(body.bottom),
          reason: 'Template must not run into the footer',
        );
        expect(find.byTooltip('Click to edit purchase items'), findsNothing);
        if (type == 'purchaseRequest') {
          expect(find.byType(DocuTrackerPurchaseItemsTable), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'short purchase table and signature boxes fit one official page',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 680,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DocuTrackerPurchaseItemsTable(
                      items: DocumentPurchaseItems.blank(),
                    ),
                    const DocuTrackerPurchaseSignatureBand(
                      fields: [],
                      onSign: null,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('Awaiting assignment'), findsNWidgets(2));
      expect(find.text('Requested by'), findsOneWidget);
      expect(find.text('Approved by'), findsOneWidget);
      final height =
          tester.getSize(find.byType(DocuTrackerPurchaseItemsTable)).height +
          tester.getSize(find.byType(DocuTrackerPurchaseSignatureBand)).height;
      expect(height, lessThan(590));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('many purchase rows are taller than the official one-page body', (
    tester,
  ) async {
    final rows = List.generate(
      20,
      (index) => ['${index + 1}', 'pc', 'Item ${index + 1}', '1', '10', '10'],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: 680,
              child: DocuTrackerPurchaseItemsTable(
                items: DocumentPurchaseItems(rows: rows, total: '200'),
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text('Item 20'), findsOneWidget);
    expect(find.text('TOTAL'), findsOneWidget);
    final height = tester
        .getSize(find.byType(DocuTrackerPurchaseItemsTable))
        .height;
    // Letterhead body minus the title and the signature band is about 590px.
    expect(height, greaterThan(590));
  });
}
