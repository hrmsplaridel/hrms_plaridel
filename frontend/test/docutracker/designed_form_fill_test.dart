import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/docutracker/models/document.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_status.dart';
import 'package:hrms_plaridel/features/docutracker/models/docutracker_memo_template.dart';
import 'package:hrms_plaridel/features/docutracker/utils/docutracker_designed_form_fill.dart';

void main() {
  DocuTrackerDocument doc({
    required String type,
    String? id = '11111111-1111-1111-1111-111111111111',
    bool sourceOnly = false,
  }) => DocuTrackerDocument(
    id: id,
    documentType: type,
    title: 'Sample',
    description: 'Body text',
    status: DocumentStatus.pending,
    sourceOnly: sourceOnly,
  );

  test('memo and purchase request attempt designed fill when an id exists', () {
    expect(
      docuTrackerShouldAttemptDesignedFormFill(doc(type: 'memo')),
      isTrue,
    );
    expect(
      docuTrackerShouldAttemptDesignedFormFill(doc(type: 'purchaseRequest')),
      isTrue,
    );
  });

  test('custom types with an id attempt fill mode', () {
    expect(
      docuTrackerShouldAttemptDesignedFormFill(doc(type: 'travel_order')),
      isTrue,
    );
  });

  test('source-only and unsaved drafts skip fill mode', () {
    expect(
      docuTrackerShouldAttemptDesignedFormFill(
        doc(type: 'travel_order', sourceOnly: true),
      ),
      isFalse,
    );
    expect(
      docuTrackerShouldAttemptDesignedFormFill(
        doc(type: 'travel_order', id: null),
      ),
      isFalse,
    );
  });

  test('writable sources include Memo fields', () {
    expect(docuTrackerFillSourceIsWritable('title'), isTrue);
    expect(docuTrackerFillSourceIsWritable('subject'), isTrue);
    expect(docuTrackerFillSourceIsWritable('description'), isTrue);
    expect(docuTrackerFillSourceIsWritable('body'), isTrue);
    expect(docuTrackerFillSourceIsWritable('to'), isTrue);
    expect(docuTrackerFillSourceIsWritable('date'), isTrue);
    expect(docuTrackerFillSourceIsWritable('cc'), isTrue);
    expect(docuTrackerFillSourceIsWritable('document_number'), isFalse);
    expect(docuTrackerFillStorageKey('title'), 'title');
    expect(docuTrackerFillStorageKey('subject'), 'title');
    expect(docuTrackerFillStorageKey('description'), 'description');
    expect(docuTrackerFillStorageKey('body'), 'description');
    expect(docuTrackerFillStorageKey('to'), isNull);
  });

  test('fill values expose memo to/subject/body when template is provided', () {
    final values = docuTrackerFillValuesFromDocument(
      doc(type: 'memo'),
      memo: const DocuTrackerMemoTemplate(
        to: 'All Heads',
        subject: 'Reports',
        date: 'November 12, 2026',
        cc: 'Mayor',
      ),
    );
    expect(values['to'], 'All Heads');
    expect(values['subject'], 'Reports');
    expect(values['date'], 'November 12, 2026');
    expect(values['cc'], 'Mayor');
    expect(values['body'], 'Body text');
    expect(values['memorandum_heading'], 'MEMORANDUM');
  });

  test('fill values expose document title and description', () {
    final values = docuTrackerFillValuesFromDocument(doc(type: 'travel_order'));
    expect(values['title'], 'Sample');
    expect(values['description'], 'Body text');
    expect(values['document_type'], 'travel_order');
  });
}
