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
}
