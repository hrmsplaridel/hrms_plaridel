import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_type.dart';

void main() {
  test('keeps compatible built-in document types', () {
    expect(
      documentTypeFromString('purchase_request'),
      DocumentType.purchaseRequest,
    );
    expect(documentTypeFromString('Memo'), DocumentType.memo);
  });

  test('preserves unknown document types instead of falling back to memo', () {
    final type = documentTypeFromString('travel_order');

    expect(type.value, 'travel_order');
    expect(type.displayName, 'Travel Order');
  });

  test('creates a stable value from an admin-entered name', () {
    final type = DocumentType.fromDisplayName('Travel Order');

    expect(type.value, 'travel_order');
    expect(type.displayName, 'Travel Order');
  });
}
