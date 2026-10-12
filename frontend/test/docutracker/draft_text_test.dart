import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:hrms_plaridel/providers/auth_provider.dart';
import 'package:hrms_plaridel/features/docutracker/data/providers/docutracker_provider.dart';
import 'package:hrms_plaridel/features/docutracker/models/document.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_builder.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_type.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_purchase_items.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/widgets/docutracker_purchase_items_table.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/pages/docutracker_document_builder_screen.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/widgets/docutracker_create_document_dialog.dart';
import 'package:hrms_plaridel/features/docutracker/services/employee_directory_lookup.dart';
import 'package:hrms_plaridel/features/docutracker/utils/docutracker_draft_text.dart';

const _document = DocuTrackerDocument(
  id: 'draft',
  documentType: 'memo',
  title: 'Office meeting',
  description: 'Please discuss the updated office procedures.',
);

DocuTrackerDocumentBuilderData _data({
  bool editable = true,
  int revision = 0,
  List<DocuTrackerDocumentPage>? pages,
  List<DocuTrackerSignatureField> fields = const [],
}) => DocuTrackerDocumentBuilderData(
  documentId: 'draft',
  currentUserId: 'me',
  pages: pages ?? [DocuTrackerDocumentPage.empty()],
  signatureFields: fields,
  revision: revision,
  canEditLayout: editable,
  canSign: false,
);

class _DraftProvider extends DocuTrackerProvider {
  _DraftProvider(this.data);
  DocuTrackerDocumentBuilderData data;
  List<DocuTrackerDocumentPage>? savedPages;

  @override
  Future<DocuTrackerDocumentBuilderData?> loadDocumentBuilder(
    String id,
  ) async => data;

  @override
  Future<DocuTrackerDocument?> createDocument({
    required String title,
    required DocumentType documentType,
    String? description,
    String? filePath,
    String? fileName,
    required String createdBy,
  }) async => DocuTrackerDocument(
    id: 'draft',
    documentType: documentType.value,
    title: title,
    description: description,
  );

  @override
  Future<DocuTrackerDocumentBuilderData?> saveDocumentBuilder({
    required String documentId,
    required List<DocuTrackerDocumentPage> pages,
    required List<DocuTrackerSignatureField> signatureFields,
    required int revision,
  }) async {
    savedPages = pages;
    data = _data(pages: pages, revision: revision + 1, fields: signatureFields);
    return data;
  }

  @override
  Future<DocuTrackerDocument?> fetchDocument(String documentId) async => null;

  @override
  Future<List<EmployeeDirectoryEntry>> loadEmployeeDirectoryEntries() async =>
      const <EmployeeDirectoryEntry>[];
}

String _memoField(WidgetTester tester, String key) =>
    tester.widget<TextField>(find.byKey(ValueKey(key))).controller!.text;

Future<void> _pump(
  WidgetTester tester,
  _DraftProvider provider, {
  bool prefill = true,
  bool create = false,
  DocuTrackerDocument document = _document,
  Size size = const Size(1440, 1000),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(provider.dispose);
  final auth = AuthProvider();
  addTearDown(auth.dispose);
  await tester.pumpWidget(
    ChangeNotifierProvider<DocuTrackerProvider>.value(
      value: provider,
      child: MaterialApp(
        home: create
            ? Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    onPressed: () => showDocuTrackerCreateDocumentDialog(
                      context,
                      auth: auth,
                      provider: provider,
                      allowedDocumentTypes: const [
                        DocumentType.memo,
                        DocumentType.purchaseRequest,
                      ],
                    ),
                    child: const Text('New document'),
                  ),
                ),
              )
            : DocuTrackerDocumentBuilderScreen(
                document: document,
                prefillNewDraft: prefill,
              ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

quill.QuillController _controller(WidgetTester tester) =>
    tester.widget<quill.QuillEditor>(find.byType(quill.QuillEditor)).controller;

void main() {
  test('PR table cells round-trip through existing page Delta JSON', () {
    final items = DocumentPurchaseItems(
      rows: const [
        ['1', 'ream', 'A4 paper', '2', '250.00', '500.00'],
      ],
      total: '500.00',
    );
    final page = quill.Document.fromJson([
      {'insert': items.toInsertJson()},
      {'insert': '\n'},
    ]);
    final insert = page.toDelta().toJson().first['insert'] as Map;
    final restored = DocumentPurchaseItems.decode(
      insert[DocumentPurchaseItems.embedType],
    );
    expect(restored.rows, items.rows);
    expect(restored.total, '500.00');
    expect(
      () => DocumentPurchaseItems.decode('{"rows":[["short"]],"total":""}'),
      throwsFormatException,
    );
  });

  testWidgets(
    'purchase request has editable ruled cells that persist on Save',
    (tester) async {
      final provider = _DraftProvider(_data());
      await _pump(
        tester,
        provider,
        document: const DocuTrackerDocument(
          id: 'draft',
          documentType: 'purchaseRequest',
          title: 'Office supplies',
          description: 'For daily office use.',
        ),
      );
      expect(find.byType(DocuTrackerPurchaseItemsTable), findsOneWidget);
      expect(
        _controller(tester).document.toPlainText(),
        contains('Purpose: For daily office use.'),
      );
      await tester.tap(find.byTooltip('Click to edit purchase items'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('purchase-cell-0-2')),
        'A4 paper',
      );
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      expect(find.text('A4 paper'), findsOneWidget);
      await tester.tap(find.byTooltip('Save — Unsaved changes'));
      await tester.pumpAndSettle();
      final insert =
          provider.savedPages!.first.delta.firstWhere(
                (op) => op['insert'] is Map,
              )['insert']
              as Map;
      expect(
        DocumentPurchaseItems.decode(
          insert[DocumentPurchaseItems.embedType],
        ).rows.first[2],
        'A4 paper',
      );
      expect(find.text('A4 paper'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'memo starter uses the official template with exact title and description',
    () {
      final text = DocuTrackerDraftText.compose(
        _document,
        now: DateTime.utc(2026, 10, 6, 17, 30),
      );
      expect(text, contains('MEMORANDUM'));
      expect(text, contains('Subject: Office meeting'));
      expect(text, contains('Date: October 7, 2026'));
      expect(text, contains(_document.description!));
      expect(text, contains('[State the instructions'));
      // Sender/signature blocks belong to the template's signature fields.
      expect(text, isNot(contains('[SENDER NAME]')));
      expect(text, isNot(contains('null')));
    },
  );

  test(
    'purchase request and custom types have appropriate starter wording',
    () {
      final purchase = DocuTrackerDraftText.compose(
        const DocuTrackerDocument(
          documentType: 'purchaseRequest',
          title: 'Office supplies',
        ),
      );
      expect(purchase, contains('PURCHASE REQUEST'));
      expect(purchase, contains('LGU: Municipality of Plaridel'));
      expect(purchase, contains('F/P/P:'));
      expect(purchase, contains('Item Description'));
      expect(purchase, contains('Approved by:'));
      expect(purchase, contains('[Explain why the items are needed.]'));
      final custom = DocuTrackerDraftText.compose(
        const DocuTrackerDocument(
          documentType: 'office_letter',
          title: 'Invitation',
          description: '  First line.\nSecond line.  ',
        ),
      );
      expect(custom, contains('Subject: Invitation'));
      expect(custom, contains('First line.\nSecond line.'));
      expect(custom, contains('Please see the following details'));
    },
  );

  test('only an editable untouched blank page can be prefilled', () {
    expect(DocuTrackerDraftText.canPrefill(_data()), isTrue);
    expect(DocuTrackerDraftText.canPrefill(_data(editable: false)), isFalse);
    expect(DocuTrackerDraftText.canPrefill(_data(revision: 1)), isFalse);
    expect(
      DocuTrackerDraftText.canPrefill(
        _data(
          pages: [
            DocuTrackerDocumentPage.empty(),
            DocuTrackerDocumentPage.empty(),
          ],
        ),
      ),
      isFalse,
    );
    expect(
      DocuTrackerDraftText.canPrefill(
        _data(
          pages: const [
            DocuTrackerDocumentPage(
              delta: [
                {'insert': 'Existing text\n'},
              ],
            ),
          ],
        ),
      ),
      isFalse,
    );
    expect(
      DocuTrackerDraftText.canPrefill(
        _data(
          pages: const [
            DocuTrackerDocumentPage(
              delta: [
                {
                  'insert': {'image': 'existing-image'},
                },
              ],
            ),
          ],
        ),
      ),
      isFalse,
    );
    expect(
      DocuTrackerDraftText.canPrefill(
        _data(
          fields: const [
            DocuTrackerSignatureField(
              id: 'field',
              pageNumber: 1,
              x: 0.1,
              y: 0.7,
              width: 0.3,
              height: 0.12,
              assignedSignerId: 'me',
              label: 'Approval',
            ),
          ],
        ),
      ),
      isFalse,
    );
  });

  testWidgets('memo starter stays editable and saves user changes', (
    tester,
  ) async {
    final provider = _DraftProvider(_data());
    await _pump(tester, provider);
    final controller = _controller(tester);
    expect(controller.document.toPlainText(), contains(_document.description!));
    expect(_memoField(tester, 'memo-field-subject'), 'Office meeting');
    expect(find.text('Unsaved changes'), findsOneWidget);
    expect(provider.savedPages, isNull);
    await tester.enterText(
      find.byKey(const ValueKey('memo-field-to')),
      'All employees',
    );
    controller.replaceText(
      0,
      0,
      'Reminder: ',
      const TextSelection.collapsed(offset: 10),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Save — Unsaved changes'));
    await tester.pumpAndSettle();
    expect(provider.savedPages, hasLength(1));
    expect(provider.savedPages!.single.memo?.to, 'All employees');
    expect(
      quill.Document.fromJson(provider.savedPages!.single.delta).toPlainText(),
      startsWith('Reminder: '),
    );
    expect(_memoField(tester, 'memo-field-to'), 'All employees');
    expect(find.text('Saved'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final scenario in [
    'existing text',
    'saved blank',
    'read only',
    'not new',
  ]) {
    testWidgets('prefill does not overwrite $scenario', (tester) async {
      final data = _data(
        editable: scenario != 'read only',
        revision: scenario == 'saved blank' ? 1 : 0,
        pages: scenario == 'existing text'
            ? const [
                DocuTrackerDocumentPage(
                  delta: [
                    {'insert': 'Keep this text\n'},
                  ],
                ),
              ]
            : null,
      );
      final provider = _DraftProvider(data);
      await _pump(tester, provider, prefill: scenario != 'not new');
      expect(
        _controller(tester).document.toPlainText(),
        scenario == 'existing text' ? 'Keep this text\n' : '\n',
      );
      expect(find.text('Unsaved changes'), findsNothing);
      expect(provider.savedPages, isNull);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'Create Draft opens Builder with the entered title and description',
    (tester) async {
      final provider = _DraftProvider(_data());
      await _pump(tester, provider, create: true);
      await tester.tap(find.text('New document'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('docutracker-create-type-memo')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('docutracker-create-title')),
        'Staff orientation',
      );
      await tester.enterText(
        find.byKey(const Key('docutracker-create-purpose')),
        'Discuss the new attendance guidelines.',
      );
      await tester.tap(find.byKey(const Key('docutracker-create-submit')));
      await tester.pumpAndSettle();
      final text = _controller(tester).document.toPlainText();
      expect(_memoField(tester, 'memo-field-subject'), 'Staff orientation');
      expect(text, contains('Discuss the new attendance guidelines.'));
      expect(find.text('Unsaved changes'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Create Draft uses a mobile bottom sheet without clipping', (
    tester,
  ) async {
    final provider = _DraftProvider(_data());
    await _pump(tester, provider, create: true, size: const Size(360, 800));
    await tester.tap(find.text('New document'));
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.text('What are you creating?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('docutracker-create-type-memo')));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNWidgets(2));
    expect(find.byKey(const Key('docutracker-create-attach')), findsOneWidget);
    expect(find.byKey(const Key('docutracker-create-submit')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
