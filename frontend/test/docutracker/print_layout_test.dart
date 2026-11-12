import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/docutracker/utils/docutracker_print_layout.dart';

void main() {
  test('DocuTracker print defaults include title and signatory slots', () {
    final layout = docuTrackerPrintLayoutDefaults();
    expect(layout.orientation, 'portrait');
    expect(layout.elements.map((e) => e.source), containsAll([
      'title',
      'document_number',
      'prepared_by',
      'approved_by',
    ]));
    expect(docuTrackerPrintLayoutFields().containsKey('title'), isTrue);
    expect(
      docuTrackerPrintLayoutSignatures().containsKey('approved_by'),
      isTrue,
    );
    final sample = docuTrackerPrintLayoutSample(
      documentTypeLabel: 'Travel Order',
    );
    expect(sample['title'], contains('Travel Order'));
  });

  test('Memo design layout exposes official Memo fields and slots', () {
    final fields = docuTrackerPrintLayoutFields(documentType: 'memo');
    expect(fields.keys, containsAll(['to', 'subject', 'date', 'cc', 'body']));
    expect(
      docuTrackerPrintLayoutSignatures(documentType: 'memo').keys,
      containsAll(['prepared_by', 'noted_by', 'approved_by']),
    );
    final layout = docuTrackerPrintLayoutDefaults(documentType: 'memo');
    expect(
      layout.elements.map((e) => e.source),
      containsAll([
        'memorandum_heading',
        'to',
        'subject',
        'date',
        'cc',
        'body',
        'prepared_by',
        'noted_by',
        'approved_by',
      ]),
    );
    final sample = docuTrackerPrintLayoutSample(
      documentTypeLabel: 'Memo',
      documentType: 'memo',
    );
    expect(sample['to'], contains('Department'));
    expect(sample['memorandum_heading'], 'MEMORANDUM');
  });
}
