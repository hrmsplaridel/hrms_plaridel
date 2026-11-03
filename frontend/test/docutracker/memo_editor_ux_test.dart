import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:hrms_plaridel/features/docutracker/data/providers/docutracker_provider.dart';
import 'package:hrms_plaridel/features/docutracker/models/document.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_builder.dart';
import 'package:hrms_plaridel/features/docutracker/models/docutracker_memo_template.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/pages/docutracker_document_builder_screen.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/widgets/docutracker_builder_chrome.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/widgets/docutracker_memo_sheet.dart';
import 'package:hrms_plaridel/features/docutracker/services/employee_directory_lookup.dart';
import 'package:hrms_plaridel/features/docutracker/utils/docutracker_memo_layout.dart';

const _memo = DocuTrackerMemoTemplate(
  to: 'All Department Heads',
  subject: 'Quarterly accomplishment reports',
  date: 'October 7, 2026',
  cc: 'HRMDO\nFile',
);

final _signaturePng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8A'
  'AQUBAScY42YAAAAASUVORK5CYII=',
);

DocuTrackerSignatureField _slotField(
  String label,
  Rect rect,
  String signerId,
  String signerName, {
  String? position,
  bool canSign = false,
  bool signed = false,
}) => DocuTrackerSignatureField(
  id: 'field-$label',
  pageNumber: 1,
  x: rect.left,
  y: rect.top,
  width: rect.width,
  height: rect.height,
  assignedSignerId: signerId,
  assignedSignerName: signerName,
  assignedSignerPosition: position,
  canSign: canSign,
  label: label,
  signatureAssetId: signed ? 'asset-1' : null,
  signatureImageBytes: signed ? _signaturePng : null,
  signerName: signed ? signerName : null,
  signedAt: signed ? DateTime.utc(2026, 10, 7) : null,
  lockedAt: signed ? DateTime.utc(2026, 10, 7) : null,
);

DocuTrackerDocument _document({String status = 'draft'}) =>
    DocuTrackerDocument.fromJson({
      'id': 'memo-ux-doc',
      'document_type': 'memo',
      'title': 'Quarterly accomplishment reports',
      'description': 'Body',
      'status': status,
      'created_by': 'me',
      'release_required': true,
    });

class _UxProvider extends DocuTrackerProvider {
  _UxProvider({
    this.editable = true,
    this.failSave = false,
  });

  final bool editable;
  final bool failSave;
  int saveCalls = 0;
  List<DocuTrackerDocumentPage>? savedPages;

  @override
  String? get builderError => failSave && saveCalls > 0
      ? 'Validation failed: Subject is required.'
      : super.builderError;

  @override
  Future<DocuTrackerDocumentBuilderData?> loadDocumentBuilder(
    String id,
  ) async => DocuTrackerDocumentBuilderData(
    documentId: id,
    currentUserId: 'me',
    revision: 1,
    canEditLayout: editable,
    canSign: false,
    formatVersion: 2,
    pages: [
      const DocuTrackerDocumentPage(
        memo: _memo,
        delta: [
          {'insert': 'Please submit the reports on time.\n'},
        ],
      ),
    ],
    signatureFields: [
      _slotField(
        DocuTrackerMemoLayout.preparedFieldLabel,
        DocuTrackerMemoLayout.preparedField,
        'me',
        'Prep Officer',
        position: 'HRMO III',
        canSign: true,
      ),
      _slotField(
        DocuTrackerMemoLayout.approvedFieldLabel,
        DocuTrackerMemoLayout.approvedField,
        'mayor',
        'Town Mayor',
        position: 'Municipal Mayor',
      ),
    ],
  );

  @override
  Future<DocuTrackerDocumentBuilderData?> saveDocumentBuilder({
    required String documentId,
    required List<DocuTrackerDocumentPage> pages,
    required List<DocuTrackerSignatureField> signatureFields,
    required int revision,
  }) async {
    saveCalls++;
    if (failSave) {
      return null;
    }
    savedPages = pages;
    return loadDocumentBuilder(documentId);
  }

  @override
  Future<List<DocuTrackerSignatureAsset>> listSavedSignatures() async =>
      const <DocuTrackerSignatureAsset>[];

  @override
  Future<DocuTrackerDocument?> fetchDocument(String documentId) async => null;

  @override
  Future<List<EmployeeDirectoryEntry>> loadEmployeeDirectoryEntries() async =>
      const <EmployeeDirectoryEntry>[];
}

Future<void> _pumpMemoEditor(
  WidgetTester tester,
  _UxProvider provider, {
  Size size = const Size(1440, 1300),
  Brightness brightness = Brightness.light,
  String status = 'draft',
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(provider.dispose);
  await tester.pumpWidget(
    ChangeNotifierProvider<DocuTrackerProvider>.value(
      value: provider,
      child: MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          brightness: brightness,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFFE65100),
            brightness: brightness,
          ),
        ),
        home: DocuTrackerDocumentBuilderScreen(
          document: _document(status: status),
        ),
      ),
    ),
  );
  await tester.pump();
  for (
    var i = 0;
    i < 50 && find.byType(DocuTrackerMemoSheet).evaluate().isEmpty;
    i++
  ) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Memo editor UX', () {
    testWidgets('shows Memo fields, draft chrome, and Save Draft affordance', (
      tester,
    ) async {
      await _pumpMemoEditor(tester, _UxProvider());
      expect(find.byKey(const ValueKey('memo-field-to')), findsOneWidget);
      expect(find.byKey(const ValueKey('memo-field-subject')), findsOneWidget);
      expect(find.byKey(const ValueKey('memo-field-date')), findsOneWidget);
      expect(find.byKey(const ValueKey('memo-field-cc')), findsOneWidget);
      expect(find.byKey(const ValueKey('memo-body')), findsOneWidget);
      expect(find.text('Memo draft editor'), findsOneWidget);
      expect(find.textContaining('Save Draft here'), findsOneWidget);
      expect(find.text('Save Draft'), findsOneWidget);
      expect(find.byTooltip('Fit page'), findsOneWidget);
      expect(find.byTooltip('Fit width'), findsOneWidget);
      expect(find.text('Click to sign'), findsOneWidget);
      expect(find.text('Awaiting signature'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('marks dirty state and saves draft with feedback', (
      tester,
    ) async {
      final provider = _UxProvider();
      await _pumpMemoEditor(tester, provider);
      expect(find.text('Saved'), findsWidgets);
      await tester.enterText(
        find.byKey(const ValueKey('memo-field-to')),
        'All Offices',
      );
      await tester.pumpAndSettle();
      expect(find.text('Unsaved changes'), findsOneWidget);
      expect(find.byTooltip('Save — Unsaved changes'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('docutracker-builder-save-draft')),
      );
      await tester.pumpAndSettle();
      expect(provider.saveCalls, 1);
      expect(provider.savedPages!.single.memo!.to, 'All Offices');
      expect(find.text('Memo draft saved.'), findsOneWidget);
      expect(find.text('Saved'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('warns on back navigation with unsaved Memo changes', (
      tester,
    ) async {
      await _pumpMemoEditor(tester, _UxProvider());
      await tester.enterText(
        find.byKey(const ValueKey('memo-field-subject')),
        'Updated subject',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Unsaved changes'), findsWidgets);
      expect(
        find.textContaining('Leave without saving the draft?'),
        findsOneWidget,
      );
      await tester.tap(find.text('Stay'));
      await tester.pumpAndSettle();
      expect(find.byType(DocuTrackerMemoSheet), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('memo-field-subject')))
            .controller!
            .text,
        'Updated subject',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows validation errors after a failed Save Draft', (
      tester,
    ) async {
      final provider = _UxProvider(failSave: true);
      await _pumpMemoEditor(tester, provider);
      await tester.enterText(
        find.byKey(const ValueKey('memo-field-cc')),
        'File only',
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('docutracker-builder-save-draft')),
      );
      await tester.pumpAndSettle();
      expect(provider.saveCalls, 1);
      expect(
        find.text('Validation failed: Subject is required.'),
        findsOneWidget,
      );
      expect(find.text('Unsaved changes'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('read-only Memo hides Save Draft and editing hint', (
      tester,
    ) async {
      await _pumpMemoEditor(
        tester,
        _UxProvider(editable: false),
        status: 'submitted',
      );
      expect(find.text('Save Draft'), findsNothing);
      expect(find.text('Memo · view only'), findsOneWidget);
      expect(find.textContaining('view-only'), findsOneWidget);
      expect(find.text('Read-only'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('narrow layout keeps Memo controls reachable', (tester) async {
      await _pumpMemoEditor(
        tester,
        _UxProvider(),
        size: const Size(390, 844),
      );
      expect(find.byType(DocuTrackerMemoSheet), findsOneWidget);
      expect(
        find.byKey(const ValueKey('docutracker-builder-save-draft')),
        findsOneWidget,
      );
      expect(find.byType(DocuTrackerBuilderCanvasBar), findsOneWidget);
      expect(find.byTooltip('Fit width'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('memo-field-to')),
        'Mayor\nDepartment Heads',
      );
      await tester.pumpAndSettle();
      expect(find.text('Unsaved'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('dark theme keeps Memo paper and chrome usable', (
      tester,
    ) async {
      await _pumpMemoEditor(
        tester,
        _UxProvider(),
        brightness: Brightness.dark,
      );
      expect(find.byType(DocuTrackerMemoSheet), findsOneWidget);
      expect(find.text('Save Draft'), findsOneWidget);
      expect(find.text('Memo draft editor'), findsOneWidget);
      final sheet = tester.widget<ColoredBox>(
        find.descendant(
          of: find.byType(DocuTrackerMemoSheet),
          matching: find.byType(ColoredBox),
        ).first,
      );
      expect(sheet.color, Colors.white);
      expect(tester.takeException(), isNull);
    });

    testWidgets('zoom fit controls update without clearing Memo fields', (
      tester,
    ) async {
      await _pumpMemoEditor(tester, _UxProvider());
      await tester.enterText(
        find.byKey(const ValueKey('memo-field-date')),
        'November 3, 2026',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Fit width'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Fit page'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('memo-field-date')))
            .controller!
            .text,
        'November 3, 2026',
      );
      expect(find.text('Unsaved changes'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
