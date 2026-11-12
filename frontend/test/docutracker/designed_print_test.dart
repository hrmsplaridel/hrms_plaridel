import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/docutracker/models/document.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_builder.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_status.dart';
import 'package:hrms_plaridel/features/docutracker/models/docutracker_memo_template.dart';
import 'package:hrms_plaridel/features/docutracker/utils/docutracker_designed_print.dart';

void main() {
  test('maps document fields into designed print sources', () {
    final form = docuTrackerPrintFormFromDocument(
      DocuTrackerDocument(
        id: 'doc-1',
        documentNumber: 'DOC-2026-000042',
        documentType: 'travel_order',
        title: 'Official travel',
        description: 'Attend training',
        creatorName: 'Ana Reyes',
        status: DocumentStatus.pending,
        createdAt: DateTime.utc(2026, 11, 3, 8),
      ),
    );
    expect(form['title'], 'Official travel');
    expect(form['document_number'], 'DOC-2026-000042');
    expect(form['created_by_name'], 'Ana Reyes');
    expect(form['status'], 'pending');
    expect(form['date'], contains('November'));
    expect(form['description'], 'Attend training');
  });

  test('memo metadata feeds subject/date and To into description', () {
    final form = docuTrackerPrintFormFromDocument(
      const DocuTrackerDocument(
        documentType: 'memo',
        title: 'Reports',
        description: 'Body note',
      ),
      memo: const DocuTrackerMemoTemplate(
        to: 'All Heads',
        subject: 'Quarterly reports',
        date: 'November 3, 2026',
        cc: 'Mayor',
      ),
    );
    expect(form['subject'], 'Quarterly reports');
    expect(form['date'], 'November 3, 2026');
    expect(form['to'], 'All Heads');
    expect(form['cc'], 'Mayor');
    expect(form['body'], 'Body note');
    expect(form['memorandum_heading'], 'MEMORANDUM');
    expect(form['description'], contains('To:\nAll Heads'));
    expect(form['description'], contains('Body note'));
  });

  test('signature labels map onto designed print sources', () {
    final mapped = docuTrackerPrintSignatoriesFromFields([
      DocuTrackerSignatureField(
        id: '1',
        pageNumber: 1,
        x: 0.1,
        y: 0.7,
        width: 0.3,
        height: 0.1,
        assignedSignerId: 'u1',
        label: 'Prepared by',
        assignedSignerName: 'Prep Officer',
        assignedSignerPosition: 'HRMO',
        signatureImageBytes: Uint8List.fromList([1, 2, 3]),
        signerName: 'Prep Officer',
        signedAt: DateTime.utc(2026, 11, 3),
        lockedAt: DateTime.utc(2026, 11, 3),
      ),
      const DocuTrackerSignatureField(
        id: '2',
        pageNumber: 1,
        x: 0.5,
        y: 0.7,
        width: 0.3,
        height: 0.1,
        assignedSignerId: 'u2',
        label: 'Approved by',
        assignedSignerName: 'Town Mayor',
        assignedSignerPosition: 'Municipal Mayor',
      ),
    ]);
    expect(mapped['prepared_by']!.name, 'Prep Officer');
    expect(mapped['prepared_by']!.signatureBytes, isNotNull);
    expect(mapped['approved_by']!.name, 'Town Mayor');
    expect(mapped['approved_by']!.signatureBytes, isNull);
  });

  test('Requested by fills the purchase-request Prepared by line', () {
    final mapped = docuTrackerPrintSignatoriesFromFields([
      const DocuTrackerSignatureField(
        id: 'requested',
        pageNumber: 1,
        x: 0.11,
        y: 0.69,
        width: 0.34,
        height: 0.085,
        assignedSignerId: 'u1',
        label: 'Requested by',
        signerName: 'Tope Zapitan',
        signerPositionSnapshot: 'Department Head',
        signedAt: null,
      ),
    ]);
    expect(mapped['prepared_by']!.name, 'Tope Zapitan');
  });
}
