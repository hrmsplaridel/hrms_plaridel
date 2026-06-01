import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_status.dart';

void main() {
  test('DocumentStatus serializes to snake_case', () {
    expect(DocumentStatus.inReview.value, 'in_review');
    expect(DocumentStatus.approved.value, 'approved');
  });

  test('documentStatusFromString handles snake_case and camelCase', () {
    expect(documentStatusFromString('in_review'), DocumentStatus.inReview);
    expect(documentStatusFromString('inReview'), DocumentStatus.inReview);
    expect(documentStatusFromString('overdue'), DocumentStatus.overdue);
  });
}
