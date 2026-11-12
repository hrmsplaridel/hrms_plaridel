import 'package:hrms_plaridel/features/dtr/locator/models/locator_print_layout.dart';
import 'package:hrms_plaridel/features/dtr/locator/utils/locator_form_signatories.dart';

bool _isMemoType(String? documentType) {
  final key = (documentType ?? '').trim().toLowerCase();
  return key == 'memo';
}

/// Field catalog for DocuTracker designed printed forms.
///
/// When [documentType] is Memorandum, includes the official Memo field names
/// (To, Subject, Date, CC, Body) so Design layout matches the real form.
Map<String, String> docuTrackerPrintLayoutFields({String? documentType}) {
  final shared = <String, String>{
    'title': 'Title',
    'subject': 'Subject',
    'document_number': 'Document number',
    'description': 'Description',
    'document_type': 'Document type',
    'status': 'Status',
    'created_by_name': 'Prepared by name',
    'created_at': 'Created date',
    'department_name': 'Department',
    'date': 'Date',
  };
  if (!_isMemoType(documentType)) return shared;
  return <String, String>{
    'memorandum_heading': 'MEMORANDUM heading',
    'to': 'To',
    'subject': 'Subject',
    'date': 'Date',
    'cc': 'Copy furnished (CC)',
    'body': 'Body',
    'document_number': 'Document number',
    'title': 'Title (document list)',
    'description': 'Description (legacy)',
    'document_type': 'Document type',
    'status': 'Status',
    'created_by_name': 'Prepared by name',
    'created_at': 'Created date',
    'department_name': 'Department',
  };
}

Map<String, String> docuTrackerPrintLayoutSignatures({String? documentType}) {
  if (_isMemoType(documentType)) {
    return const {
      'prepared_by': 'Prepared by',
      'noted_by': 'Noted by',
      'approved_by': 'Approved by',
    };
  }
  return const {
    'prepared_by': 'Prepared by',
    'approved_by': 'Approved by',
    'noted_by': 'Noted by',
    'reviewer': 'Reviewer',
    'department_head': 'Department head',
    'mayor': 'Municipal Mayor',
    'applicant': 'Applicant / Creator',
  };
}

Map<String, dynamic> docuTrackerPrintLayoutSample({
  required String documentTypeLabel,
  String? documentType,
}) {
  final sample = <String, dynamic>{
    'title': 'Sample $documentTypeLabel',
    'subject': 'Sample $documentTypeLabel',
    'document_number': 'DOC-2026-000001',
    'description': 'Sample description for layout preview.',
    'document_type': documentTypeLabel,
    'status': 'draft',
    'created_by_name': 'Sample Employee',
    'created_at': '2026-11-03',
    'department_name': 'Human Resource Management Office',
    'date': 'November 3, 2026',
  };
  if (_isMemoType(documentType)) {
    sample.addAll({
      'memorandum_heading': 'MEMORANDUM',
      'to': 'All Department Heads',
      'subject': 'Quarterly reports',
      'date': 'November 12, 2026',
      'cc': 'Municipal Mayor\nHRMDO',
      'body':
          'State the purpose and background of this memorandum.\n\n'
          'State the instructions, required action, and deadline, if any.',
      'description':
          'State the purpose and background of this memorandum.\n\n'
          'State the instructions, required action, and deadline, if any.',
    });
  }
  return sample;
}

LocatorPrintedSignatory docuTrackerPrintSampleSignatory(String source) =>
    LocatorPrintedSignatory(
      name: 'Sample signer',
      positionTitle: switch (source) {
        'mayor' => 'Municipal Mayor',
        'department_head' || 'noted_by' => 'Department Head',
        'approved_by' => 'Approving Authority',
        'prepared_by' || 'applicant' => 'Document preparer',
        _ => 'Reviewer',
      },
    );

LocatorPrintLayout docuTrackerPrintLayoutDefaults({
  String orientation = 'portrait',
  String paperSize = 'a4',
  String? documentType,
}) {
  if (_isMemoType(documentType)) {
    return _memoPrintLayoutDefaults(
      orientation: orientation,
      paperSize: paperSize,
    );
  }
  final landscape = orientation == 'landscape';
  return LocatorPrintLayout(
    orientation: orientation,
    paperSize: paperSize,
    elements: [
      LocatorPrintElement(
        id: 'title',
        kind: 'field',
        source: 'title',
        label: 'Title',
        x: landscape ? 48 : 56,
        y: landscape ? 72 : 120,
        width: landscape ? 700 : 480,
        height: 36,
        fontSize: 16,
        bold: true,
        showLabel: false,
      ),
      LocatorPrintElement(
        id: 'document_number',
        kind: 'field',
        source: 'document_number',
        label: 'No.',
        x: landscape ? 48 : 56,
        y: landscape ? 120 : 170,
        width: landscape ? 320 : 240,
        height: 28,
        fontSize: 11,
      ),
      LocatorPrintElement(
        id: 'date',
        kind: 'field',
        source: 'date',
        label: 'Date',
        x: landscape ? 400 : 320,
        y: landscape ? 120 : 170,
        width: landscape ? 320 : 220,
        height: 28,
        fontSize: 11,
      ),
      LocatorPrintElement(
        id: 'description',
        kind: 'field',
        source: 'description',
        label: 'Description',
        x: landscape ? 48 : 56,
        y: landscape ? 170 : 230,
        width: landscape ? 700 : 480,
        height: 120,
        fontSize: 11,
      ),
      LocatorPrintElement(
        id: 'prepared_by',
        kind: 'signature',
        source: 'prepared_by',
        label: 'Prepared by',
        x: landscape ? 48 : 56,
        y: landscape ? 360 : 620,
        width: 220,
        height: 80,
        fontSize: 11,
      ),
      LocatorPrintElement(
        id: 'approved_by',
        kind: 'signature',
        source: 'approved_by',
        label: 'Approved by',
        x: landscape ? 420 : 320,
        y: landscape ? 360 : 620,
        width: 220,
        height: 80,
        fontSize: 11,
      ),
    ],
  );
}

/// Default designed layout for Memorandum — mirrors official Memo slots.
LocatorPrintLayout _memoPrintLayoutDefaults({
  required String orientation,
  required String paperSize,
}) {
  // Portrait A4 points measured from the official Plaridel memorandum sheet.
  // Landscape keeps a compact fallback; Memo production printing is portrait.
  final landscape = orientation == 'landscape';
  if (landscape) {
    return LocatorPrintLayout(
      orientation: orientation,
      paperSize: paperSize,
      elements: [
        LocatorPrintElement(
          id: 'memorandum_heading',
          kind: 'field',
          source: 'memorandum_heading',
          label: 'MEMORANDUM',
          x: 48,
          y: 88,
          width: 700,
          height: 28,
          fontSize: 16,
          bold: true,
          showLabel: false,
        ),
        LocatorPrintElement(
          id: 'to',
          kind: 'field',
          source: 'to',
          label: 'To',
          x: 48,
          y: 130,
          width: 700,
          height: 36,
          fontSize: 11,
        ),
        LocatorPrintElement(
          id: 'subject',
          kind: 'field',
          source: 'subject',
          label: 'Subject',
          x: 48,
          y: 176,
          width: 700,
          height: 28,
          fontSize: 11,
        ),
        LocatorPrintElement(
          id: 'date',
          kind: 'field',
          source: 'date',
          label: 'Date',
          x: 48,
          y: 214,
          width: 320,
          height: 28,
          fontSize: 11,
        ),
        LocatorPrintElement(
          id: 'body',
          kind: 'field',
          source: 'body',
          label: 'Body',
          x: 48,
          y: 260,
          width: 700,
          height: 140,
          fontSize: 11,
          showLabel: false,
        ),
        LocatorPrintElement(
          id: 'prepared_by',
          kind: 'signature',
          source: 'prepared_by',
          label: 'Prepared by',
          x: 48,
          y: 420,
          width: 200,
          height: 72,
          fontSize: 11,
        ),
        LocatorPrintElement(
          id: 'approved_by',
          kind: 'signature',
          source: 'approved_by',
          label: 'Approved by',
          x: 280,
          y: 470,
          width: 240,
          height: 72,
          fontSize: 11,
        ),
        LocatorPrintElement(
          id: 'cc',
          kind: 'field',
          source: 'cc',
          label: 'Cc',
          x: 48,
          y: 555,
          width: 320,
          height: 48,
          fontSize: 11,
        ),
      ],
    );
  }
  return LocatorPrintLayout(
    orientation: orientation,
    paperSize: paperSize,
    elements: [
      LocatorPrintElement(
        id: 'memorandum_heading',
        kind: 'field',
        source: 'memorandum_heading',
        label: 'MEMORANDUM',
        x: 65.5,
        y: 139,
        width: 464,
        height: 28,
        fontSize: 16,
        bold: true,
        showLabel: false,
      ),
      LocatorPrintElement(
        id: 'to',
        kind: 'field',
        source: 'to',
        label: 'To',
        x: 65.5,
        y: 182,
        width: 464,
        height: 36,
        fontSize: 11,
      ),
      LocatorPrintElement(
        id: 'subject',
        kind: 'field',
        source: 'subject',
        label: 'Subject',
        x: 65.5,
        y: 202,
        width: 464,
        height: 28,
        fontSize: 11,
      ),
      LocatorPrintElement(
        id: 'date',
        kind: 'field',
        source: 'date',
        label: 'Date',
        x: 65.5,
        y: 223,
        width: 320,
        height: 28,
        fontSize: 11,
      ),
      LocatorPrintElement(
        id: 'body',
        kind: 'field',
        source: 'body',
        label: 'Body',
        x: 65.5,
        y: 259,
        width: 464,
        height: 210,
        fontSize: 11,
        showLabel: false,
      ),
      LocatorPrintElement(
        id: 'prepared_by',
        kind: 'signature',
        source: 'prepared_by',
        label: 'Prepared by',
        x: 65.5,
        y: 493,
        width: 178,
        height: 72,
        fontSize: 11,
      ),
      LocatorPrintElement(
        id: 'approved_by',
        kind: 'signature',
        source: 'approved_by',
        label: 'Approved by',
        x: 256,
        y: 585,
        width: 250,
        height: 72,
        fontSize: 11,
      ),
      LocatorPrintElement(
        id: 'cc',
        kind: 'field',
        source: 'cc',
        label: 'Cc',
        x: 65.5,
        y: 674,
        width: 226,
        height: 48,
        fontSize: 11,
      ),
    ],
  );
}
