import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:printing/src/interface.dart';
import 'package:provider/provider.dart';

import 'package:hrms_plaridel/features/docutracker/data/providers/docutracker_provider.dart';
import 'package:hrms_plaridel/features/docutracker/models/document.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_builder.dart';
import 'package:hrms_plaridel/features/docutracker/models/docutracker_memo_template.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/pages/docutracker_document_builder_screen.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/widgets/docutracker_memo_sheet.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/widgets/docutracker_signature_field_visual.dart';
import 'package:hrms_plaridel/features/docutracker/services/employee_directory_lookup.dart';
import 'package:hrms_plaridel/features/docutracker/utils/docutracker_draft_text.dart';
import 'package:hrms_plaridel/features/docutracker/utils/docutracker_memo_layout.dart';
import 'package:hrms_plaridel/features/docutracker/utils/docutracker_memo_pdf.dart';

const _multilineTo =
    'All Department Heads\nRegular Employees\n(This Municipality)';

const _memo = DocuTrackerMemoTemplate(
  to: _multilineTo,
  subject: 'Quarterly accomplishment reports',
  date: 'October 7, 2026',
  cc: 'All Concerned\nHRMDO\nFile',
);

final _signaturePng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8A'
  'AQUBAScY42YAAAAASUVORK5CYII=',
);

DocuTrackerSignatureField _field(
  String label,
  Rect rect,
  String signerId,
  String signerName, {
  String? position,
  String? role,
  bool canSign = false,
  bool signed = false,
  // Identity frozen at signing; defaults to the live identity.
  String? signedName,
  String? signedPosition,
  String? signedRole,
  bool legacySnapshot = false,
}) => DocuTrackerSignatureField(
  id: 'field-$label',
  pageNumber: 1,
  // Stored geometry is ignored for Memo slots; keep it off-template.
  x: rect.left / 2,
  y: rect.top / 2,
  width: rect.width,
  height: rect.height,
  assignedSignerId: signerId,
  assignedSignerName: signerName,
  assignedSignerPosition: position,
  assignedSignerRole: role,
  canSign: canSign,
  label: label,
  signatureAssetId: signed ? 'asset-1' : null,
  signatureImageBytes: signed ? _signaturePng : null,
  signerName: signed ? signedName ?? signerName : null,
  signerPositionSnapshot: signed && !legacySnapshot
      ? signedPosition ?? position
      : null,
  signerRoleSnapshot: signed && !legacySnapshot ? signedRole ?? role : null,
  signedAt: signed ? DateTime.utc(2026, 10, 7) : null,
  lockedAt: signed ? DateTime.utc(2026, 10, 7) : null,
);

DocuTrackerSignatureField _prepared({
  bool canSign = false,
  bool signed = false,
}) => _field(
  DocuTrackerMemoLayout.preparedFieldLabel,
  DocuTrackerMemoLayout.preparedField,
  'me',
  'Prep Officer',
  position: 'HRMO III',
  role: 'hr',
  canSign: canSign,
  signed: signed,
);

DocuTrackerSignatureField _approved({
  bool canSign = false,
  bool signed = false,
}) => _field(
  DocuTrackerMemoLayout.approvedFieldLabel,
  DocuTrackerMemoLayout.approvedField,
  'mayor',
  'Town Mayor',
  position: 'Municipal Mayor',
  role: 'mayor',
  canSign: canSign,
  signed: signed,
);

final _defaultFields = [_prepared(), _approved()];

DocuTrackerDocument _document({
  String? releasedAt,
  String? createdAt,
  String? status,
}) => DocuTrackerDocument.fromJson({
  'id': 'memo-doc',
  'document_type': 'memo',
  'title': 'Quarterly accomplishment reports',
  'description': 'Submit the reports to the HR office.',
  'status': status ?? (releasedAt == null ? 'draft' : 'approved'),
  'created_by': 'me',
  if (createdAt != null) 'created_at': createdAt,
  'release_required': true,
  if (releasedAt != null) ...{
    'released_at': releasedAt,
    'released_to_department_id': 'dept-eng',
    'released_to_department_name': 'Engineering Office',
    'released_by': 'hr-1',
    'released_by_name': 'Maria Santos',
    'release_remarks': 'For implementation',
  },
});

class _MemoProvider extends DocuTrackerProvider {
  _MemoProvider({
    this.editable = true,
    this.blank = false,
    this.latest,
    this.directory = const <EmployeeDirectoryEntry>[],
    this.fields,
  });

  final bool editable;
  final bool blank;
  final DocuTrackerDocument? latest;
  final List<EmployeeDirectoryEntry> directory;
  final List<DocuTrackerSignatureField>? fields;
  List<DocuTrackerDocumentPage>? savedPages;
  List<DocuTrackerSignatureField>? savedFields;
  int fetches = 0;

  @override
  Future<DocuTrackerDocumentBuilderData?> loadDocumentBuilder(
    String id,
  ) async => DocuTrackerDocumentBuilderData(
    documentId: id,
    currentUserId: 'me',
    revision: savedPages == null ? (blank ? 0 : 3) : 4,
    canEditLayout: editable,
    canSign: false,
    formatVersion: 2,
    pages:
        savedPages ??
        (blank
            ? [DocuTrackerDocumentPage.empty()]
            : [
                const DocuTrackerDocumentPage(
                  memo: _memo,
                  delta: [
                    {'insert': 'Please submit the reports on time.\n'},
                  ],
                ),
              ]),
    signatureFields:
        savedFields ??
        fields ??
        (blank ? const <DocuTrackerSignatureField>[] : _defaultFields),
  );

  @override
  Future<DocuTrackerDocumentBuilderData?> saveDocumentBuilder({
    required String documentId,
    required List<DocuTrackerDocumentPage> pages,
    required List<DocuTrackerSignatureField> signatureFields,
    required int revision,
  }) async {
    // Exercise the real JSON wire format.
    savedPages = pages
        .map((page) => DocuTrackerDocumentPage.fromJson(page.toJson()))
        .toList();
    // The server assigns ids and decides who can sign.
    savedFields = [
      for (final field in signatureFields)
        DocuTrackerSignatureField(
          id: field.id.startsWith('local-') ? 'saved-${field.label}' : field.id,
          pageNumber: field.pageNumber,
          x: field.x,
          y: field.y,
          width: field.width,
          height: field.height,
          assignedSignerId: field.assignedSignerId,
          assignedSignerName: field.assignedSignerName,
          assignedSignerPosition: field.assignedSignerPosition,
          assignedSignerRole: field.assignedSignerRole,
          canSign: field.assignedSignerId == 'me',
          label: field.label,
        ),
    ];
    return loadDocumentBuilder(documentId);
  }

  @override
  Future<List<DocuTrackerSignatureAsset>> listSavedSignatures() async =>
      const <DocuTrackerSignatureAsset>[];

  @override
  Future<DocuTrackerDocument?> fetchDocument(String documentId) async {
    fetches++;
    return latest;
  }

  @override
  Future<List<EmployeeDirectoryEntry>> loadEmployeeDirectoryEntries() async =>
      directory;
}

class _Printing extends PrintingPlatform {
  Uint8List? exported;

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
  _MemoProvider provider, {
  DocuTrackerDocument? document,
  bool prefill = false,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1440, 1300);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(provider.dispose);
  await tester.pumpWidget(
    ChangeNotifierProvider<DocuTrackerProvider>.value(
      value: provider,
      child: MaterialApp(
        home: DocuTrackerDocumentBuilderScreen(
          document: document ?? _document(),
          prefillNewDraft: prefill,
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

Rect _rect(WidgetTester tester, String key) =>
    tester.getRect(find.byKey(ValueKey(key)));

/// Page-relative fraction rectangle of a widget on the memo sheet.
Rect _fractionOf(WidgetTester tester, Finder finder) {
  final page = tester.getRect(find.byType(DocuTrackerMemoSheet));
  final rect = tester.getRect(finder);
  return Rect.fromLTWH(
    (rect.left - page.left) / page.width,
    (rect.top - page.top) / page.height,
    rect.width / page.width,
    rect.height / page.height,
  );
}

Finder _slot(DocuTrackerMemoSlot slot) =>
    find.byKey(ValueKey('memo-signatory-${slot.name}'));

String _slotText(WidgetTester tester, String part, DocuTrackerMemoSlot slot) =>
    tester
        .widget<Text>(find.byKey(ValueKey('memo-signatory-$part-${slot.name}')))
        .data!;

Finder _slotImage(DocuTrackerMemoSlot slot) => find.descendant(
  of: find.byKey(ValueKey('memo-signature-area-${slot.name}')),
  matching: find.byType(Image),
);

/// Every word of [text] appears as PDF text.
void _expectPdfWords(String source, String text) {
  for (final word in text.split(' ')) {
    expect(source, contains('($word'), reason: word);
  }
}

String _fieldText(WidgetTester tester, String key) =>
    tester.widget<TextField>(find.byKey(ValueKey(key))).controller!.text;

/// Body words and their PDF baselines (points from the page bottom), per page.
List<List<({String word, double y})>> _bodyWordsByPage(Uint8List bytes) {
  final source = latin1.decode(bytes);
  final streams = RegExp(
    r'stream\r?\n(.*?)endstream',
    dotAll: true,
  ).allMatches(source).map((match) => match.group(1)!);
  // Graphics-state saves/restores, transforms (non-splitting groups are
  // painted in local coordinates) and body words.
  const number = r'([\d.-]+)';
  final operation = RegExp(
    r'(?<=^|\s)(q|Q)(?=\s)'
    '|$number $number $number $number $number $number cm'
    r'|BT /F\d+ [\d.]+ Tf [\d.-]+ Tc [\d.-]+ ([\d.-]+) Td \[\((Line\d+)\)\]TJ',
  );
  List<({String word, double y})> words(String stream) {
    // Vertical part of the current transform: pageY = scale * y + offset.
    var transform = (scale: 1.0, offset: 0.0);
    final saved = <({double scale, double offset})>[];
    final result = <({String word, double y})>[];
    for (final match in operation.allMatches(stream)) {
      if (match.group(1) == 'q') {
        saved.add(transform);
      } else if (match.group(1) == 'Q') {
        transform = saved.removeLast();
      } else if (match.group(2) != null) {
        final d = double.parse(match.group(5)!);
        final f = double.parse(match.group(7)!);
        transform = (
          scale: transform.scale * d,
          offset: transform.scale * f + transform.offset,
        );
      } else {
        final y = double.parse(match.group(8)!);
        result.add((
          word: match.group(9)!,
          y: transform.scale * y + transform.offset,
        ));
      }
    }
    return result;
  }

  return [
    for (final stream in streams.where(
      (stream) => stream.contains('MUNICIPALITY'),
    ))
      words(stream),
  ];
}

/// Builds a memo with [lines] body lines and checks that no body word lands
/// in the closing block (last page) or the footer (other pages). Returns the
/// page count.
Future<int> _checkNoOverlap(int lines) async {
  final bytes = await buildDocuTrackerMemoPdf(
    memo: _memo,
    body: [
      for (var i = 0; i < lines; i++) {'insert': 'Line$i\n'},
    ],
    signatureFields: _defaultFields,
    compress: false,
  );
  final source = latin1.decode(bytes);
  final pages = _bodyWordsByPage(bytes);
  final reason = '$lines lines';
  // Letterhead and footer repeat on every page.
  expect(
    RegExp(r'\(MUNICIPALITY\)').allMatches(source).length,
    pages.length,
    reason: reason,
  );
  expect(
    RegExp(r'\(Misamisnon\)').allMatches(source).length,
    pages.length,
    reason: reason,
  );
  // Signature labels print once, on the last page only.
  expect(RegExp(r'\(Prepared\)').allMatches(source), hasLength(1));
  expect(RegExp(r'\(Approved\)').allMatches(source), hasLength(1));
  final printed = pages.expand((page) => page).map((w) => w.word).toSet();
  expect(printed, {for (var i = 0; i < lines; i++) 'Line$i'}, reason: reason);
  // The closing block never sits alone on a page without memo text.
  expect(pages.last, isNotEmpty, reason: reason);
  final height = PdfPageFormat.a4.height;
  final closingTop = (1 - DocuTrackerMemoLayout.closingTop) * height;
  final footerTop = (1 - DocuTrackerMemoLayout.footerStrip.top) * height;
  for (final (index, page) in pages.indexed) {
    final floor = index == pages.length - 1 ? closingTop : footerTop;
    for (final word in page) {
      expect(
        word.y,
        greaterThan(floor),
        reason: '$reason: ${word.word} on page ${index + 1}',
      );
    }
  }
  return pages.length;
}

void main() {
  group('Memo template storage', () {
    test('page 1 keeps memo metadata out of the Quill delta', () {
      final page = DocuTrackerDocumentPage.fromJson([
        _memo.toOperation(),
        {'insert': 'Body\n'},
      ]);
      expect(page.memo?.to, _multilineTo);
      expect(page.memo?.subject, _memo.subject);
      expect(page.delta, [
        {'insert': 'Body\n'},
      ]);
      expect(() => quill.Document.fromJson(page.delta), returnsNormally);
      final json = page.toJson();
      expect(json.first[DocuTrackerMemoTemplate.operationKey], 'memo_v1');
      expect(json.skip(1), page.delta);
      final legacy = DocuTrackerDocumentPage.fromJson([
        {'insert': 'Free-form memo\n'},
      ]);
      expect(legacy.memo, isNull);
      expect(legacy.toJson(), legacy.delta);
    });

    test('starter fills Subject and a Manila creation date, nothing else', () {
      final page = DocuTrackerDraftText.composePage(
        _document(createdAt: '2026-10-06T17:30:00Z'),
      );
      expect(page.memo?.subject, 'Quarterly accomplishment reports');
      expect(page.memo?.date, 'October 7, 2026');
      expect(page.memo?.to, isEmpty);
      expect(page.memo?.cc, isEmpty);
      final body = quill.Document.fromJson(page.delta).toPlainText();
      expect(body, contains('Submit the reports to the HR office.'));
      expect(body, isNot(contains('MEMORANDUM')));
      expect(body, isNot(contains('Prepared by')));
    });

    test('release details exist only for an officially released memo', () {
      expect(DocuTrackerMemoRelease.fromDocument(_document()), isNull);
      final approved = _document(status: 'approved');
      expect(approved.isAwaitingRelease, isTrue);
      expect(DocuTrackerMemoRelease.fromDocument(approved), isNull);
      final release = DocuTrackerMemoRelease.fromDocument(
        _document(releasedAt: '2026-10-09T07:42:00Z'),
      )!;
      expect(release.departmentName, 'Engineering Office');
      expect(release.releasedByName, 'Maria Santos');
      expect(release.remarks, 'For implementation');
    });
  });

  group('Memo signer identity snapshot', () {
    DocuTrackerMemoSignatory prepared(DocuTrackerSignatureField field) =>
        DocuTrackerMemoSignatory(DocuTrackerMemoSlot.preparedBy, field);
    DocuTrackerMemoSignatory approved(DocuTrackerSignatureField field) =>
        DocuTrackerMemoSignatory(DocuTrackerMemoSlot.approvedBy, field);

    test('unsigned block prints the live name and position', () {
      final live = _field(
        DocuTrackerMemoLayout.preparedFieldLabel,
        DocuTrackerMemoLayout.preparedField,
        'me',
        'Prep Officer',
        position: 'HRMO IV',
        role: 'hr',
      );
      expect(prepared(live).printedName, 'PREP OFFICER');
      expect(prepared(live).position, 'HRMO IV');
    });

    test('signing snapshot is read from the server payload', () {
      final field = DocuTrackerSignatureField.fromJson({
        'id': 'f1',
        'page_number': 1,
        'assigned_signer_id': 'me',
        'assigned_signer_name': 'Prep Officer',
        'assigned_signer_position': 'HRMO IV',
        'assigned_signer_role': 'hr',
        'label': 'Prepared by',
        'signed_by': 'me',
        'signer_name_snapshot': 'Prep Officer',
        'signer_position_snapshot': 'HRMO III',
        'signer_role_snapshot': 'hr',
        'signed_at': '2026-10-07T00:00:00Z',
        'locked_at': '2026-10-07T00:00:00Z',
      });
      expect(field.signerPositionSnapshot, 'HRMO III');
      expect(field.signerRoleSnapshot, 'hr');
      expect(field.copyWith(x: 0.2).signerPositionSnapshot, 'HRMO III');
      expect(prepared(field).position, 'HRMO III');
    });

    test('a later promotion keeps the position held at signing', () {
      final promoted = _field(
        DocuTrackerMemoLayout.preparedFieldLabel,
        DocuTrackerMemoLayout.preparedField,
        'me',
        'Prep Officer',
        position: 'HRMO IV',
        role: 'hr',
        signed: true,
        signedPosition: 'HRMO III',
      );
      expect(prepared(promoted).printedName, 'PREP OFFICER');
      expect(prepared(promoted).position, 'HRMO III');
    });

    test('a later name change keeps the name signed with', () {
      final renamed = _field(
        DocuTrackerMemoLayout.preparedFieldLabel,
        DocuTrackerMemoLayout.preparedField,
        'me',
        'Prep Officer-Reyes',
        position: 'HRMO III',
        role: 'hr',
        signed: true,
        signedName: 'Prep Officer',
      );
      expect(prepared(renamed).printedName, 'PREP OFFICER');
    });

    test('a new Mayor never replaces the Mayor who signed', () {
      // The former Mayor's directory record no longer says Mayor.
      final formerMayor = _field(
        DocuTrackerMemoLayout.approvedFieldLabel,
        DocuTrackerMemoLayout.approvedField,
        'mayor',
        'Town Mayor',
        role: 'employee',
        signed: true,
        signedPosition: 'Municipal Mayor',
        signedRole: 'mayor',
      );
      expect(approved(formerMayor).isMayor, isTrue);
      expect(approved(formerMayor).printedName, 'HON. TOWN MAYOR');
      expect(approved(formerMayor).position, 'Municipal Mayor');
    });

    test('a signer who later becomes Mayor keeps the old title', () {
      final later = _field(
        DocuTrackerMemoLayout.preparedFieldLabel,
        DocuTrackerMemoLayout.preparedField,
        'me',
        'Prep Officer',
        position: 'Municipal Mayor',
        role: 'mayor',
        signed: true,
        signedPosition: 'HRMO III',
        signedRole: 'hr',
      );
      expect(prepared(later).printedName, 'PREP OFFICER');
      expect(prepared(later).position, 'HRMO III');
    });

    test('legacy signatures without a snapshot invent no title', () {
      final legacy = _field(
        DocuTrackerMemoLayout.approvedFieldLabel,
        DocuTrackerMemoLayout.approvedField,
        'mayor',
        'Town Mayor',
        position: 'Municipal Mayor',
        role: 'mayor',
        signed: true,
        legacySnapshot: true,
      );
      expect(approved(legacy).printedName, 'TOWN MAYOR');
      expect(approved(legacy).position, isNull);
    });
  });

  group('Memo vector PDF', () {
    test('short memo is one sharp A4 page with every section', () async {
      final bytes = await buildDocuTrackerMemoPdf(
        memo: _memo,
        body: const [
          {'insert': 'Line1 Line2\n'},
        ],
        signatureFields: _defaultFields,
        compress: false,
      );
      final source = latin1.decode(bytes);
      expect(source, startsWith('%PDF'));
      expect(RegExp(r'/Type\s*/Page\b').allMatches(source), hasLength(1));
      expect(source, contains('/MediaBox[0 0 595.27559 841.88976]'));
      for (final text in [
        'MUNICIPALITY',
        'MEMORANDUM',
        'Department',
        'Quarterly',
        'Prepared',
        'Approved',
        'Cc:',
        'PREP',
        'MAYOR',
        'Misamisnon',
      ]) {
        expect(source, contains('($text'), reason: text);
      }
      // Vector text, not a captured page image.
      expect(source, isNot(contains('/Subtype/Image')));
      expect(source, isNot(contains('RELEASED')));
    });

    test('released memo prints the backend release details', () async {
      final bytes = await buildDocuTrackerMemoPdf(
        memo: _memo,
        body: const [
          {'insert': 'Line1\n'},
        ],
        signatureFields: _defaultFields,
        release: DocuTrackerMemoRelease.fromDocument(
          _document(releasedAt: '2026-10-09T07:42:00Z'),
        ),
        compress: false,
      );
      final source = latin1.decode(bytes);
      expect(source, contains('(RELEASED)'));
      expect(source, contains('(Engineering)'));
      expect(source, contains('(Santos)'));
      expect(source, contains('(implementation)'));
    });

    test(
      'long body flows onto extra pages and never reaches the closing block',
      () async {
        var maxPages = 0;
        // Every length up to three pages, so some bodies end just above the
        // closing block and others are pushed past it.
        for (var lines = 1; lines <= 110; lines += 3) {
          maxPages = math.max(maxPages, await _checkNoOverlap(lines));
        }
        expect(maxPages, greaterThanOrEqualTo(3));
      },
    );

    test('blank body lines keep one line of space', () async {
      Future<double> gap(List<Map<String, dynamic>> body) async {
        final words = _bodyWordsByPage(
          await buildDocuTrackerMemoPdf(
            memo: _memo,
            body: body,
            signatureFields: _defaultFields,
            compress: false,
          ),
        ).single;
        return words.first.y - words.last.y;
      }

      final adjacent = await gap(const [
        {'insert': 'Line1\nLine2\n'},
      ]);
      final separated = await gap(const [
        {'insert': 'Line1\n\nLine2\n\n\n'},
      ]);
      const lineHeight =
          DocuTrackerMemoLayout.bodyFontSize *
          DocuTrackerMemoLayout.pointsPerPixel *
          DocuTrackerMemoLayout.bodyLineHeight;
      expect(separated - adjacent, closeTo(lineHeight, 0.5));
    });

    test('PDF font is the bundled Noto Sans, never a download', () async {
      expect(await loadDocuTrackerMemoPdfTheme(), isNotNull);
    });

    test(
      'signed slot adds only the signature; name and position stay',
      () async {
        Future<String> pdf(List<DocuTrackerSignatureField> fields) async =>
            latin1.decode(
              await buildDocuTrackerMemoPdf(
                memo: _memo,
                body: const [
                  {'insert': 'Line1\n'},
                ],
                signatureFields: fields,
                compress: false,
              ),
            );
        final unsigned = await pdf([_prepared(), _approved()]);
        final signed = await pdf([_prepared(signed: true), _approved()]);
        expect(unsigned, isNot(contains('/Subtype/Image')));
        expect(signed, contains('/Subtype/Image'));
        for (final source in [unsigned, signed]) {
          _expectPdfWords(source, 'PREP OFFICER');
          _expectPdfWords(source, 'HRMO III');
          _expectPdfWords(source, 'HON. TOWN MAYOR');
          _expectPdfWords(source, 'Municipal Mayor');
        }
        // No signing timestamp or other text is added by the signature.
        expect(signed, isNot(contains('(Signed')));
      },
    );

    test(
      'unassigned Approved by prints a blank line, no placeholder',
      () async {
        final source = latin1.decode(
          await buildDocuTrackerMemoPdf(
            memo: _memo,
            body: const [
              {'insert': 'Line1\n'},
            ],
            signatureFields: [_prepared()],
            compress: false,
          ),
        );
        expect(source, contains('(Approved'));
        expect(source, isNot(contains('(HON.')));
        expect(source, isNot(contains('(configured')));
      },
    );
  });

  group('Memo builder sheet', () {
    testWidgets('renders every section with locked labels', (tester) async {
      final provider = _MemoProvider();
      await _pumpBuilder(tester, provider);
      for (final key in [
        'memo-seal',
        'memo-header',
        'memo-logo-asenso',
        'memo-logo-bagong-pilipinas',
        'memo-peach-band',
        'memo-title',
        'memo-divider',
        'memo-body',
        'memo-prepared-label',
        'memo-approved-label',
        'memo-field-cc',
        'memo-footer',
        'memo-slogan',
      ]) {
        expect(find.byKey(ValueKey(key)), findsOneWidget, reason: key);
      }
      expect(find.text(DocuTrackerMemoLayout.municipality), findsOneWidget);
      expect(find.text(DocuTrackerMemoLayout.office), findsOneWidget);
      expect(find.text('MEMORANDUM'), findsOneWidget);
      expect(find.text('Prepared by:'), findsOneWidget);
      expect(find.text('Approved by:'), findsOneWidget);
      expect(find.text(DocuTrackerMemoLayout.slogan), findsOneWidget);
      // Fixed labels are not editable text fields.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('memo-header')),
          matching: find.byType(EditableText),
        ),
        findsNothing,
      );
      expect(find.byType(TextField), findsNWidgets(4));
      expect(provider.fetches, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('multiline To, then Subject and Date above the divider', (
      tester,
    ) async {
      await _pumpBuilder(tester, _MemoProvider());
      expect(_fieldText(tester, 'memo-field-to'), _multilineTo);
      final to = _rect(tester, 'memo-field-to');
      final subject = _rect(tester, 'memo-field-subject');
      final date = _rect(tester, 'memo-field-date');
      final divider = _rect(tester, 'memo-divider');
      final body = _rect(tester, 'memo-body');
      expect(to.height, greaterThan(date.height * 2.5));
      expect(to.bottom, lessThanOrEqualTo(subject.top));
      expect(subject.bottom, lessThanOrEqualTo(date.top));
      expect(date.bottom, lessThanOrEqualTo(divider.top));
      expect(divider.bottom, lessThanOrEqualTo(body.top));
      expect(subject.left, to.left);
      expect(date.left, to.left);
      expect(
        _rect(tester, 'memo-label-subject').left,
        _rect(tester, 'memo-label-to').left,
      );
      expect(_fieldText(tester, 'memo-field-subject'), _memo.subject);
      expect(_fieldText(tester, 'memo-field-date'), _memo.date);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Prepared by and Approved by blocks sit at the template', (
      tester,
    ) async {
      await _pumpBuilder(tester, _MemoProvider());
      final prepared = _fractionOf(
        tester,
        _slot(DocuTrackerMemoSlot.preparedBy),
      );
      final approved = _fractionOf(
        tester,
        _slot(DocuTrackerMemoSlot.approvedBy),
      );
      for (final (actual, expected) in [
        (prepared, DocuTrackerMemoLayout.preparedField),
        (approved, DocuTrackerMemoLayout.approvedField),
      ]) {
        expect(actual.left, closeTo(expected.left, 0.002));
        expect(actual.top, closeTo(expected.top, 0.002));
      }
      final page = tester.getRect(find.byType(DocuTrackerMemoSheet));
      final preparedLabel = _rect(tester, 'memo-prepared-label');
      final approvedLabel = _rect(tester, 'memo-approved-label');
      expect(
        preparedLabel.top,
        lessThan(page.top + prepared.top * page.height),
      );
      expect(
        approvedLabel.top,
        lessThan(page.top + approved.top * page.height),
      );
      expect(approvedLabel.left, greaterThan(preparedLabel.left));
      // Body area ends before the closing block.
      expect(_rect(tester, 'memo-body').bottom, lessThan(preparedLabel.top));
      expect(tester.takeException(), isNull);
    });

    testWidgets('approved but unreleased memo shows no release block', (
      tester,
    ) async {
      await _pumpBuilder(
        tester,
        _MemoProvider(editable: false, latest: _document(status: 'approved')),
      );
      expect(find.byKey(const ValueKey('memo-release-block')), findsNothing);
      expect(find.text('RELEASED'), findsNothing);
      // Read-only viewers see values, not inputs.
      expect(find.byType(TextField), findsNothing);
      expect(find.text(_multilineTo), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('released memo shows backend release info, To unchanged', (
      tester,
    ) async {
      await _pumpBuilder(
        tester,
        _MemoProvider(
          editable: false,
          latest: _document(releasedAt: '2026-10-09T07:42:00Z'),
        ),
      );
      expect(find.byKey(const ValueKey('memo-release-block')), findsOneWidget);
      expect(find.text('RELEASED'), findsOneWidget);
      expect(find.text('Released to: Engineering Office'), findsOneWidget);
      expect(find.text('Released by: Maria Santos'), findsOneWidget);
      expect(find.text('Remarks: For implementation'), findsOneWidget);
      expect(find.textContaining('Date: October 9, 2026'), findsOneWidget);
      expect(find.text(_multilineTo), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('new memo prefills date and default signers, then saves', (
      tester,
    ) async {
      final provider = _MemoProvider(
        blank: true,
        directory: const [
          EmployeeDirectoryEntry(
            id: 'me',
            fullName: 'Prep Officer',
            positionName: 'HRMO III',
          ),
          EmployeeDirectoryEntry(
            id: 'mayor',
            fullName: 'Town Mayor',
            roleId: 'mayor',
          ),
        ],
      );
      await _pumpBuilder(
        tester,
        provider,
        prefill: true,
        document: _document(createdAt: '2026-10-06T17:30:00Z'),
      );
      const prepared = DocuTrackerMemoSlot.preparedBy;
      const approved = DocuTrackerMemoSlot.approvedBy;
      expect(_slotText(tester, 'name', prepared), 'PREP OFFICER');
      expect(_slotText(tester, 'position', prepared), 'HRMO III');
      expect(_slotText(tester, 'name', approved), 'HON. TOWN MAYOR');
      expect(_slotText(tester, 'position', approved), 'Municipal Mayor');
      expect(_fieldText(tester, 'memo-field-date'), 'October 7, 2026');
      expect(_fieldText(tester, 'memo-field-subject'), _memo.subject);
      expect(_fieldText(tester, 'memo-field-to'), isEmpty);
      expect(find.text('Unsaved changes'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('memo-field-to')),
        'All Department Heads\nRegular Employees',
      );
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      expect(find.text('Add Page'), findsNothing);
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Save — Unsaved changes'));
      await tester.pumpAndSettle();
      final saved = provider.savedPages!.single;
      expect(saved.memo?.to, 'All Department Heads\nRegular Employees');
      expect(saved.memo?.date, 'October 7, 2026');
      expect(
        quill.Document.fromJson(saved.delta).toPlainText(),
        contains('Submit the reports to the HR office.'),
      );
      final fields = {
        for (final field in provider.savedFields!) field.label: field,
      };
      expect(fields.keys, {
        DocuTrackerMemoLayout.preparedFieldLabel,
        DocuTrackerMemoLayout.approvedFieldLabel,
      });
      expect(fields['Prepared by']!.assignedSignerId, 'me');
      expect(fields['Approved by']!.assignedSignerId, 'mayor');
      expect(
        fields['Approved by']!.x,
        DocuTrackerMemoLayout.approvedField.left,
      );
      expect(fields['Approved by']!.y, DocuTrackerMemoLayout.approvedField.top);
      expect(find.text('Saved'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Approved by stays unassigned without a single active Mayor', (
      tester,
    ) async {
      await _pumpBuilder(
        tester,
        _MemoProvider(blank: true),
        prefill: true,
        document: _document(),
      );
      expect(find.text('Approved by:'), findsOneWidget);
      expect(
        _slotText(tester, 'name', DocuTrackerMemoSlot.approvedBy),
        'No Mayor signatory configured',
      );
      expect(_slotText(tester, 'position', DocuTrackerMemoSlot.approvedBy), '');
      expect(find.text('Click to sign'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'signatory names and positions come from the assigned signers',
      (tester) async {
        await _pumpBuilder(tester, _MemoProvider());
        const prepared = DocuTrackerMemoSlot.preparedBy;
        const approved = DocuTrackerMemoSlot.approvedBy;
        expect(_slotText(tester, 'name', prepared), 'PREP OFFICER');
        expect(_slotText(tester, 'position', prepared), 'HRMO III');
        expect(_slotText(tester, 'name', approved), 'HON. TOWN MAYOR');
        expect(_slotText(tester, 'position', approved), 'Municipal Mayor');
        // Unsigned: printed name and position, blank signature area.
        expect(_slotImage(prepared), findsNothing);
        expect(_slotImage(approved), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('creator cannot edit, move or delete the signatory blocks', (
      tester,
    ) async {
      await _pumpBuilder(tester, _MemoProvider());
      for (final slot in DocuTrackerMemoSlot.values) {
        expect(
          find.descendant(of: _slot(slot), matching: find.byType(EditableText)),
          findsNothing,
        );
      }
      // Only To, Subject, Date and Cc are inputs.
      expect(find.byType(TextField), findsNWidgets(4));
      expect(find.byType(DocuTrackerSignatureFieldVisual), findsNothing);
      final before = tester.getRect(_slot(DocuTrackerMemoSlot.approvedBy));
      await tester.drag(
        find.byKey(const ValueKey('memo-signatory-name-approvedBy')),
        const Offset(-120, -80),
      );
      await tester.pumpAndSettle();
      expect(tester.getRect(_slot(DocuTrackerMemoSlot.approvedBy)), before);

      await tester.tap(find.byTooltip('Signatures'));
      await tester.pumpAndSettle();
      expect(find.text('Add Signature Field'), findsNothing);
      expect(find.text('Insert My Signature'), findsNothing);
      for (final field in _defaultFields) {
        expect(find.byKey(ValueKey('go-to-${field.id}')), findsOneWidget);
        expect(find.byKey(ValueKey('delete-${field.id}')), findsNothing);
      }
      expect(find.text('Unsaved changes'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('only the assigned signer gets a signing area', (tester) async {
      await _pumpBuilder(
        tester,
        _MemoProvider(fields: [_prepared(canSign: true), _approved()]),
      );
      expect(find.text('Click to sign'), findsOneWidget);
      expect(
        find.descendant(
          of: _slot(DocuTrackerMemoSlot.preparedBy),
          matching: find.text('Click to sign'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _slot(DocuTrackerMemoSlot.approvedBy),
          matching: find.byType(GestureDetector),
        ),
        findsNothing,
      );
      expect(find.bySemanticsLabel('Approved by signature'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('tapping your slot on a new draft saves, then opens signing', (
      tester,
    ) async {
      final provider = _MemoProvider(
        blank: true,
        directory: const [
          EmployeeDirectoryEntry(
            id: 'me',
            fullName: 'Prep Officer',
            positionName: 'HRMO III',
          ),
        ],
      );
      await _pumpBuilder(
        tester,
        provider,
        prefill: true,
        document: _document(),
      );
      expect(provider.savedFields, isNull);
      await tester.tap(find.text('Click to sign'));
      for (var i = 0; i < 20 && find.text('Draw').evaluate().isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(provider.savedFields!.single.id, 'saved-Prepared by');
      expect(find.text('Draw'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      // Cancelling adds nothing; the printed lines are untouched.
      expect(
        _slotText(tester, 'name', DocuTrackerMemoSlot.preparedBy),
        'PREP OFFICER',
      );
      expect(_slotImage(DocuTrackerMemoSlot.preparedBy), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('signing adds the image above the unchanged printed name', (
      tester,
    ) async {
      await _pumpBuilder(
        tester,
        _MemoProvider(
          fields: [_prepared(canSign: true, signed: true), _approved()],
        ),
      );
      const prepared = DocuTrackerMemoSlot.preparedBy;
      expect(_slotImage(prepared), findsOneWidget);
      expect(_slotText(tester, 'name', prepared), 'PREP OFFICER');
      expect(_slotText(tester, 'position', prepared), 'HRMO III');
      final image = tester.getRect(_slotImage(prepared));
      final name = _rect(tester, 'memo-signatory-name-preparedBy');
      expect(image.bottom, lessThanOrEqualTo(name.top));
      expect(find.text('Click to sign'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('builder and PDF print the same signatory lines', (
      tester,
    ) async {
      final fields = [_prepared(signed: true), _approved()];
      await _pumpBuilder(tester, _MemoProvider(fields: fields));
      final source = latin1.decode(
        await tester.runAsync(
              () => buildDocuTrackerMemoPdf(
                memo: _memo,
                body: const [
                  {'insert': 'Line1\n'},
                ],
                signatureFields: fields,
                compress: false,
              ),
            ) ??
            Uint8List(0),
      );
      for (final slot in DocuTrackerMemoSlot.values) {
        _expectPdfWords(source, _slotText(tester, 'name', slot));
        _expectPdfWords(source, _slotText(tester, 'position', slot));
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('builder and PDF print the signing snapshot, not live data', (
      tester,
    ) async {
      final fields = [
        _field(
          DocuTrackerMemoLayout.preparedFieldLabel,
          DocuTrackerMemoLayout.preparedField,
          'me',
          'Renamed Officer',
          position: 'Supervising Administrative Officer',
          role: 'hr',
          signed: true,
          signedName: 'Prep Officer',
          signedPosition: 'HRMO III',
        ),
        _field(
          DocuTrackerMemoLayout.approvedFieldLabel,
          DocuTrackerMemoLayout.approvedField,
          'mayor',
          'Town Mayor',
          role: 'employee',
          signed: true,
          signedPosition: 'Municipal Mayor',
          signedRole: 'mayor',
        ),
      ];
      await _pumpBuilder(
        tester,
        _MemoProvider(editable: false, fields: fields),
      );
      const prepared = DocuTrackerMemoSlot.preparedBy;
      const approved = DocuTrackerMemoSlot.approvedBy;
      expect(_slotText(tester, 'name', prepared), 'PREP OFFICER');
      expect(_slotText(tester, 'position', prepared), 'HRMO III');
      expect(_slotText(tester, 'name', approved), 'HON. TOWN MAYOR');
      expect(_slotText(tester, 'position', approved), 'Municipal Mayor');
      final source = latin1.decode(
        await tester.runAsync(
              () => buildDocuTrackerMemoPdf(
                memo: _memo,
                body: const [
                  {'insert': 'Line1\n'},
                ],
                signatureFields: fields,
                compress: false,
              ),
            ) ??
            Uint8List(0),
      );
      for (final slot in DocuTrackerMemoSlot.values) {
        _expectPdfWords(source, _slotText(tester, 'name', slot));
        _expectPdfWords(source, _slotText(tester, 'position', slot));
      }
      expect(source, isNot(contains('(RENAMED')));
      expect(source, isNot(contains('(Supervising')));
      expect(tester.takeException(), isNull);
    });

    testWidgets('Print sends the vector A4 memo PDF', (tester) async {
      final previous = PrintingPlatform.instance;
      final printing = _Printing();
      PrintingPlatform.instance = printing;
      addTearDown(() => PrintingPlatform.instance = previous);
      final provider = _MemoProvider(
        editable: false,
        latest: _document(releasedAt: '2026-10-09T07:42:00Z'),
      );
      await _pumpBuilder(tester, provider);
      await tester.tap(find.byTooltip('Print'));
      for (var i = 0; i < 100 && printing.exported == null; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
      await tester.pumpAndSettle();
      final source = latin1.decode(printing.exported!);
      expect(source, startsWith('%PDF'));
      expect(RegExp(r'/Type\s*/Page\b').allMatches(source), hasLength(1));
      expect(source, contains('/MediaBox[0 0 595.27559 841.88976]'));
      // No full-page raster capture (794x1123 at 2x).
      expect(source, isNot(contains('/Width 1588')));
      expect(provider.fetches, 2);
      expect(
        find.byKey(const ValueKey('builder-export-barrier')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });
  });
}
