import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/docutracker/utils/docutracker_memo_layout.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Memo preview and PDF use the bundled municipal seal after asset rename', () async {
    final seal = await rootBundle.load(DocuTrackerMemoLayout.sealAsset);
    expect(seal.lengthInBytes, greaterThan(0));
  });
}
