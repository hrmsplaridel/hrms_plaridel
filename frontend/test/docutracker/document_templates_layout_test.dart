import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/docutracker/models/document.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/widgets/docutracker_printable_page_frame.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/widgets/docutracker_purchase_items_table.dart';
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
}
