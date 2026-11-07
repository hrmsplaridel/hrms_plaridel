import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:provider/provider.dart';

import 'package:hrms_plaridel/features/docutracker/data/providers/docutracker_provider.dart';
import 'package:hrms_plaridel/features/docutracker/models/document.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_builder.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_purchase_items.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/pages/docutracker_document_builder_screen.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/widgets/docutracker_printable_page_frame.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/widgets/docutracker_purchase_items_table.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/widgets/docutracker_purchase_sheet.dart';
import 'package:hrms_plaridel/features/docutracker/utils/docutracker_purchase_layout.dart';
import 'package:hrms_plaridel/features/docutracker/services/employee_directory_lookup.dart';
import 'package:hrms_plaridel/features/docutracker/utils/docutracker_draft_text.dart';
import 'package:hrms_plaridel/features/docutracker/utils/docutracker_pdf_export.dart';
import 'package:hrms_plaridel/features/docutracker/utils/docutracker_purchase_pagination.dart';

const _png =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';

List<Map<String, dynamic>> _delta({
  required int rows,
  String Function(int index) descriptionFor = _shortDescription,
  String purpose = 'Buying printers for the office.',
}) {
  final items = DocumentPurchaseItems(
    rows: [
      for (var index = 0; index < rows; index++)
        ['${index + 1}', 'pc', descriptionFor(index), '1', '10.00', '10.00'],
    ],
    total: '${rows * 10}.00',
  );
  final starter = DocuTrackerDraftText.composePage(
    DocuTrackerDocument(
      documentType: 'purchaseRequest',
      title: 'Purchase Test',
      description: purpose,
    ),
  );
  return [
    for (final op in starter.delta)
      if (op['insert'] is Map) {'insert': items.toInsertJson()} else op,
  ];
}

String _shortDescription(int index) => 'Item ${index + 1}';

PurchaseDocumentPlan _plan({
  required int rows,
  String Function(int index) descriptionFor = _shortDescription,
  String purpose = 'Buying printers for the office.',
  String title = 'Purchase Test',
}) {
  return planPurchaseDocument(
    delta: _delta(rows: rows, descriptionFor: descriptionFor, purpose: purpose),
    title: title,
  );
}

void _expectCovered(PurchaseDocumentPlan plan, int rows) {
  final descriptions = [
    for (final page in plan.pages)
      for (final row in page.tableRows) row[2],
  ];
  expect(descriptions, hasLength(rows));
  for (var index = 0; index < rows; index++) {
    expect(descriptions[index], 'Item ${index + 1}');
  }
  expect(plan.pages.where((page) => page.showSignatures), hasLength(1));
  expect(plan.pages.last.showSignatures, isTrue);
  for (final page in plan.pages) {
    expect(page.contentHeight, greaterThan(0));
    expect(page.contentHeight, lessThanOrEqualTo(plan.bodyHeight + 0.5));
  }
}

Future<void> _expectPainted(
  WidgetTester tester,
  PurchaseDocumentPlan plan,
  List<Map<String, dynamic>> delta, {
  bool editable = false,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(900, 1600);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final controller = quill.QuillController(
    document: quill.Document.fromJson(delta),
    selection: const TextSelection.collapsed(offset: 0),
    readOnly: !editable,
  );
  addTearDown(controller.dispose);
  for (var index = 0; index < plan.pages.length; index++) {
    final slice = plan.pages[index];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: plan.contentWidth,
              height: plan.bodyHeight,
              child: DocuTrackerPurchaseSheet(
                controller: controller,
                plan: plan,
                slice: slice,
                editable: editable,
                fields: const [],
                onSign: null,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull, reason: 'slice $index');
    if (slice.hasTable) {
      expect(find.text('Item No.'), findsOneWidget, reason: 'slice $index');
      expect(find.text('Item Description'), findsOneWidget);
    }
    expect(
      find.text('Requested by'),
      slice.showSignatures ? findsOneWidget : findsNothing,
    );
    expect(
      find.text('Approved by'),
      slice.showSignatures ? findsOneWidget : findsNothing,
    );
  }
}

DocuTrackerSignatureField _slot(
  String id,
  String label,
  Rect rect, {
  bool signed = false,
}) {
  return DocuTrackerSignatureField(
    id: id,
    pageNumber: 1,
    x: rect.left,
    y: rect.top,
    width: rect.width,
    height: rect.height,
    assignedSignerId: 'me',
    assignedSignerName: 'Ada Officer',
    label: label,
    canSign: !signed,
    signatureImageBytes: signed ? base64Decode(_png) : null,
    signerName: signed ? 'Ada Officer' : null,
    signedAt: signed ? DateTime.utc(2026, 9, 9) : null,
    lockedAt: signed ? DateTime.utc(2026, 9, 9) : null,
  );
}

Future<void> _pumpSlice(
  WidgetTester tester, {
  required PurchaseDocumentPlan plan,
  required PurchasePageSlice slice,
  required List<DocuTrackerSignatureField> fields,
  ValueChanged<DocuTrackerSignatureField>? onSign,
  String? previewFieldId,
  Uint8List? previewBytes,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(900, 1600);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final controller = quill.QuillController(
    document: quill.Document.fromJson(const [
      {'insert': '\n'},
    ]),
    selection: const TextSelection.collapsed(offset: 0),
  );
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: plan.contentWidth,
            height: plan.bodyHeight,
            child: DocuTrackerPurchaseSheet(
              controller: controller,
              plan: plan,
              slice: slice,
              editable: false,
              fields: fields,
              onSign: onSign,
              placementPreviewFieldId: previewFieldId,
              placementPreviewBytes: previewBytes,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  expect(tester.takeException(), isNull);
}

class _Provider extends DocuTrackerProvider {
  _Provider(this.data);
  final DocuTrackerDocumentBuilderData data;

  @override
  Future<DocuTrackerDocumentBuilderData?> loadDocumentBuilder(
    String id,
  ) async => data;

  @override
  Future<DocuTrackerDocument?> fetchDocument(String documentId) async => null;

  @override
  Future<List<EmployeeDirectoryEntry>> loadEmployeeDirectoryEntries() async =>
      const [];
}

void main() {
  test('a stored purchase table cannot be empty', () {
    expect(
      () => DocumentPurchaseItems.decode('{"rows":[],"total":""}'),
      throwsFormatException,
    );
  });

  test('a purchase request without a table is still one signed page', () {
    final plan = planPurchaseDocument(
      delta: const [
        {'insert': 'PURCHASE REQUEST\n'},
      ],
      title: 'Purchase Test',
    );
    expect(plan.pages, hasLength(1));
    expect(plan.pages.single.hasTable, isFalse);
    expect(plan.pages.single.showSignatures, isTrue);
    expect(plan.pages.single.contentHeight, lessThanOrEqualTo(plan.bodyHeight));
  });

  test('short purchase requests stay on one A4 page', () {
    for (final count in [1, 3]) {
      final plan = _plan(rows: count);
      expect(plan.pages, hasLength(1), reason: '$count rows');
      _expectCovered(plan, count);
      expect(plan.pages.single.purpose, isNotEmpty);
      expect(plan.pages.single.preambleComplete, isTrue);
    }
  });

  test(
    'longer purchase requests keep every row and close on the last page',
    () {
      final ten = _plan(rows: 10);
      final twenty = _plan(rows: 20);
      final fifty = _plan(rows: 50);
      expect(ten.pages.length, greaterThanOrEqualTo(1));
      expect(twenty.pages.length, greaterThan(1));
      expect(fifty.pages.length, greaterThan(twenty.pages.length));
      _expectCovered(ten, 10);
      _expectCovered(twenty, 20);
      _expectCovered(fifty, 50);
      expect(twenty.pages.first.showSignatures, isFalse);
      expect(fifty.pages.first.showSignatures, isFalse);
    },
  );

  test('a very long description is split instead of dropped', () {
    final description = List.filled(
      80,
      'bonded paper for the records room',
    ).join(' ');
    final plan = _plan(rows: 1, descriptionFor: (_) => description);
    final painted = plan.pages
        .expand((page) => page.tableRows)
        .map((row) => row[2])
        .join();
    expect(painted, description);
    expect(plan.pages.last.showSignatures, isTrue);
    for (final page in plan.pages) {
      expect(page.contentHeight, lessThanOrEqualTo(plan.bodyHeight + 0.5));
    }
  });

  test('a long purpose stays with the signature boxes on the closing page', () {
    final purpose = List.filled(
      60,
      'The office needs these supplies this quarter.',
    ).join(' ');
    final plan = _plan(rows: 3, purpose: purpose);
    final painted = plan.pages
        .expand((page) => page.purpose)
        .map((paragraph) => paragraph.plain)
        .join();
    expect(painted, contains('office needs these supplies'));
    expect(plan.pages.last.showSignatures, isTrue);
    expect(plan.pages.last.purpose, isNotEmpty);
    if (plan.pages.length > 1) {
      expect(
        plan.pages
            .take(plan.pages.length - 1)
            .every((page) => page.purpose.isEmpty || !page.showSignatures),
        isTrue,
      );
    }
  });

  testWidgets('rendered slices stay inside the official body', (tester) async {
    for (final count in [1, 3, 10, 20]) {
      final delta = _delta(rows: count);
      final plan = planPurchaseDocument(delta: delta, title: 'Purchase Test');
      await _expectPainted(tester, plan, delta);
    }
  });

  testWidgets('read-only purchase slices do not offer item editing', (
    tester,
  ) async {
    final delta = _delta(rows: 3);
    final plan = planPurchaseDocument(delta: delta, title: 'Purchase Test');
    await _expectPainted(tester, plan, delta);
    expect(find.byTooltip('Click to edit purchase items'), findsNothing);
  });

  testWidgets('editable purchase slices can still open the item editor', (
    tester,
  ) async {
    final delta = _delta(rows: 3);
    final plan = planPurchaseDocument(delta: delta, title: 'Purchase Test');
    await _expectPainted(tester, plan, delta, editable: true);
    expect(find.byTooltip('Click to edit purchase items'), findsOneWidget);
  });

  test('each planned slice becomes one A4 PDF page', () async {
    final plan = _plan(rows: 20);
    final png = base64Decode(_png);
    final bytes = await buildDocuTrackerA4Pdf([
      for (var index = 0; index < plan.pages.length; index++) png,
    ]);
    final raw = latin1.decode(bytes, allowInvalid: true);
    final pages = RegExp(r'/Type\s*/Page(?!s)').allMatches(raw);
    expect(pages, hasLength(plan.pages.length));
    final boxes = RegExp(r'/MediaBox\s*\[([^\]]+)\]').allMatches(raw);
    expect(boxes, hasLength(plan.pages.length));
    for (final box in boxes) {
      final parts = box
          .group(1)!
          .trim()
          .split(RegExp(r'\s+'))
          .map(double.parse)
          .toList();
      expect(parts[2], closeTo(PdfPageFormat.a4.width, 0.2));
      expect(parts[3], closeTo(PdfPageFormat.a4.height, 0.2));
    }
    expect(
      docuTrackerPurchaseSheetCount(storedPages: 1, slices: plan.pages.length),
      plan.pages.length,
    );
    expect(
      docuTrackerPurchaseSheetCount(storedPages: 2, slices: plan.pages.length),
      plan.pages.length + 1,
    );
  });

  test('editing a long description adds a continuation page', () {
    final before = _plan(rows: 3);
    final controller = quill.QuillController(
      document: quill.Document.fromJson(_delta(rows: 3)),
      selection: const TextSelection.collapsed(offset: 0),
    );
    addTearDown(controller.dispose);
    final description = List.filled(80, 'bonded paper').join(' ');
    writePurchaseDocument(
      controller,
      _delta(rows: 3, descriptionFor: (_) => description),
    );
    final after = planPurchaseDocument(
      delta: [
        for (final operation in controller.document.toDelta().toJson())
          Map<String, dynamic>.from(operation as Map),
      ],
      title: 'Purchase Test',
    );
    expect(before.pages, hasLength(1));
    expect(after.pages.length, greaterThan(before.pages.length));
    final painted = after.pages
        .expand((page) => page.tableRows)
        .map((row) => row[2])
        .join();
    expect(painted, description * 3);
    expect(after.pages.last.showSignatures, isTrue);
    expect(after.pages.first.showSignatures, isFalse);
  });

  testWidgets('the editor pages through every purchase row', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 1200);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final delta = _delta(rows: 20);
    // This builder fixture uses the plain page margins. The official
    // letterhead budget is covered by the slice tests above.
    final plan = planPurchaseDocument(
      delta: delta,
      title: 'Purchase Test',
      contentWidth: 794 - 136,
      bodyHeight: 1123 - 144,
    );
    final provider = _Provider(
      DocuTrackerDocumentBuilderData(
        documentId: 'pr',
        currentUserId: 'me',
        revision: 2,
        canEditLayout: true,
        canSign: false,
        signatureFields: const [],
        formatVersion: 1,
        pages: [DocuTrackerDocumentPage(delta: delta)],
      ),
    );
    addTearDown(provider.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<DocuTrackerProvider>.value(
        value: provider,
        child: const MaterialApp(
          home: DocuTrackerDocumentBuilderScreen(
            document: DocuTrackerDocument(
              id: 'pr',
              documentType: 'purchaseRequest',
              title: 'Purchase Test',
              description: 'Buying printers for the office.',
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    for (
      var attempt = 0;
      attempt < 40 &&
          find.text('Page 1 of ${plan.pages.length}').evaluate().isEmpty;
      attempt++
    ) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('Page 1 of ${plan.pages.length}'), findsOneWidget);
    var sawLastItem = false;
    var sawSignatures = false;
    for (var page = 0; page < plan.pages.length; page++) {
      if (page > 0) {
        await tester.tap(find.byTooltip('Next page'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(
        find.text('Page ${page + 1} of ${plan.pages.length}'),
        findsOneWidget,
      );
      if (find.text('Item 20').evaluate().isNotEmpty) sawLastItem = true;
      if (find.text('Requested by').evaluate().isNotEmpty) {
        sawSignatures = true;
        expect(page, plan.pages.length - 1);
        expect(find.text('Approved by'), findsOneWidget);
      }
    }
    expect(sawLastItem, isTrue);
    expect(sawSignatures, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'the closing page signs the stored page-1 field and shows its preview',
    (tester) async {
      final plan = _plan(rows: 20);
      final requested = _slot(
        'requested',
        DocuTrackerPurchaseLayout.requestedLabel,
        DocuTrackerPurchaseLayout.requestedField,
      );
      final approved = _slot(
        'approved',
        DocuTrackerPurchaseLayout.approvedLabel,
        DocuTrackerPurchaseLayout.approvedField,
      );
      DocuTrackerSignatureField? tapped;
      await _pumpSlice(
        tester,
        plan: plan,
        slice: plan.pages.last,
        fields: [requested, approved],
        onSign: (field) => tapped = field,
      );
      expect(find.text('Requested by'), findsOneWidget);
      expect(find.text('Approved by'), findsOneWidget);
      await tester.tap(find.text('Awaiting signature').first);
      await tester.pump();
      expect(tapped?.id, 'requested');
      expect(tapped?.pageNumber, 1);
      expect(tapped?.x, DocuTrackerPurchaseLayout.requestedField.left);
      expect(tapped?.y, DocuTrackerPurchaseLayout.requestedField.top);

      await _pumpSlice(
        tester,
        plan: plan,
        slice: plan.pages.last,
        fields: [requested, approved],
        previewFieldId: requested.id,
        previewBytes: base64Decode(_png),
      );
      expect(
        find.byKey(const Key('docutracker_signature_preview')),
        findsOneWidget,
      );
      expect(find.text('Awaiting signature'), findsOneWidget);

      await _pumpSlice(
        tester,
        plan: plan,
        slice: plan.pages.first,
        fields: [requested, approved],
        previewFieldId: requested.id,
        previewBytes: base64Decode(_png),
      );
      expect(find.text('Requested by'), findsNothing);
      expect(
        find.byKey(const Key('docutracker_signature_preview')),
        findsNothing,
      );
    },
  );

  testWidgets('a saved signature is painted only on the closing page', (
    tester,
  ) async {
    final plan = _plan(rows: 20);
    final requested = _slot(
      'requested',
      DocuTrackerPurchaseLayout.requestedLabel,
      DocuTrackerPurchaseLayout.requestedField,
      signed: true,
    );
    await _pumpSlice(
      tester,
      plan: plan,
      slice: plan.pages.last,
      fields: [requested],
    );
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('ADA OFFICER'), findsOneWidget);
    await _pumpSlice(
      tester,
      plan: plan,
      slice: plan.pages.first,
      fields: [requested],
    );
    expect(find.byType(Image), findsNothing);
    expect(find.text('Requested by'), findsNothing);
  });

  testWidgets('a read-only closing page does not accept a signature tap', (
    tester,
  ) async {
    final plan = _plan(rows: 20);
    await _pumpSlice(
      tester,
      plan: plan,
      slice: plan.pages.last,
      fields: [
        _slot(
          'requested',
          DocuTrackerPurchaseLayout.requestedLabel,
          DocuTrackerPurchaseLayout.requestedField,
        ),
      ],
    );
    expect(find.byType(GestureDetector), findsNothing);
  });

  testWidgets('missing letterhead artwork does not clip a full body', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 1400);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final plan = _plan(rows: 20);
    final fullest = plan.pages.reduce(
      (a, b) => a.contentHeight >= b.contentHeight ? a : b,
    );
    final controller = quill.QuillController(
      document: quill.Document.fromJson(_delta(rows: 20)),
      selection: const TextSelection.collapsed(offset: 0),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: DocuTrackerPurchaseMetrics.paperWidth,
            height: DocuTrackerPurchaseMetrics.paperHeight,
            child: DocuTrackerPrintablePageFrame(
              documentTitle: 'Purchase Test',
              child: DocuTrackerPurchaseSheet(
                controller: controller,
                plan: plan,
                slice: fullest,
                editable: false,
                fields: const [],
                onSign: null,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('docutracker-printable-header')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('docutracker-printable-footer')),
      findsOneWidget,
    );
  });

  testWidgets('a rendered purchase table matches the measured row height', (
    tester,
  ) async {
    const rows = [
      ['1', 'pc', 'Paper', '1', '10', '10'],
      ['2', 'pc', 'Ink', '2', '20', '40'],
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: DocuTrackerPurchaseMetrics.contentWidth,
            child: DocuTrackerPurchaseItemsTable(
              items: DocumentPurchaseItems(rows: rows, total: '50'),
            ),
          ),
        ),
      ),
    );
    final rendered = tester
        .getSize(find.byType(DocuTrackerPurchaseItemsTable))
        .height;
    final columns = DocuTrackerPurchaseMetrics.columnWidths(
      DocuTrackerPurchaseMetrics.contentWidth,
    );
    double rowHeight(List<String> cells, {required bool heading}) {
      var height = DocuTrackerPurchaseMetrics.cellMinHeight;
      for (var index = 0; index < cells.length; index++) {
        height = mathMax(
          height,
          DocuTrackerPurchaseMetrics.cellHeight(
            cells[index],
            columnWidth: columns[index],
            heading: heading,
          ),
        );
      }
      return height;
    }

    final expected =
        rowHeight(DocumentPurchaseItems.headers, heading: true) +
        rowHeight(rows[0], heading: false) +
        rowHeight(rows[1], heading: false) +
        rowHeight(['', '', 'TOTAL', '', '', '50'], heading: false);
    expect((rendered - expected).abs(), lessThan(2));
  });
}

double mathMax(double a, double b) => a > b ? a : b;
