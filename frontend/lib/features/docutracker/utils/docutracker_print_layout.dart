import 'package:hrms_plaridel/features/dtr/locator/models/locator_print_layout.dart';
import 'package:hrms_plaridel/features/dtr/locator/utils/locator_form_signatories.dart';

/// Field catalog for DocuTracker designed printed forms.
Map<String, String> docuTrackerPrintLayoutFields() => const {
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

Map<String, String> docuTrackerPrintLayoutSignatures() => const {
  'prepared_by': 'Prepared by',
  'approved_by': 'Approved by',
  'reviewer': 'Reviewer',
  'department_head': 'Department head',
  'mayor': 'Municipal Mayor',
  'applicant': 'Applicant / Creator',
};

Map<String, dynamic> docuTrackerPrintLayoutSample({
  required String documentTypeLabel,
}) => {
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

LocatorPrintedSignatory docuTrackerPrintSampleSignatory(String source) =>
    LocatorPrintedSignatory(
      name: 'Sample signer',
      positionTitle: switch (source) {
        'mayor' => 'Municipal Mayor',
        'department_head' => 'Department Head',
        'approved_by' => 'Approving Authority',
        'prepared_by' || 'applicant' => 'Document preparer',
        _ => 'Reviewer',
      },
    );

LocatorPrintLayout docuTrackerPrintLayoutDefaults({
  String orientation = 'portrait',
  String paperSize = 'a4',
}) {
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
