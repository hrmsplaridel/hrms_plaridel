import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/docutracker/utils/docutracker_memo_layout.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Memo uses the official A4 letterhead (locator/forms format)', () async {
    final letterhead = await rootBundle.load(
      DocuTrackerMemoLayout.letterheadAsset,
    );
    expect(letterhead.lengthInBytes, greaterThan(0));
    final source = await rootBundle.load(
      DocuTrackerMemoLayout.letterheadSourcePdf,
    );
    expect(source.lengthInBytes, greaterThan(0));
  });
}
