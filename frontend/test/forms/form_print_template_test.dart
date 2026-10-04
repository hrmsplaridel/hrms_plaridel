import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/forms/models/form_print_template.dart';
import 'package:hrms_plaridel/features/forms/presentation/admin/pages/rsp_print_background_page.dart';

void main() {
  test('RSP and L&D catalogs stay separate', () {
    final rsp = FormPrintCatalog.formsFor('rsp').map((e) => e.key).toSet();
    final ld = FormPrintCatalog.formsFor('ld').map((e) => e.key).toSet();
    expect(rsp, containsAll(<String>['bi', 'ojt_work_immersion']));
    expect(ld, containsAll(<String>['idp', 'learning_application_plan']));
    expect(rsp.intersection(ld), isEmpty);
  });

  test('paper sizes include letter and long bond', () {
    expect(FormPrintCatalog.paperById('letter')?.widthPt, 612);
    expect(FormPrintCatalog.paperById('long_13')?.heightPt, 936);
    expect(FormPrintCatalog.paperById('letter_landscape')?.aspectRatio, greaterThan(1));
    expect(
      FormPrintCatalog.paperMenuLabel(FormPrintCatalog.paperById('long_13')!),
      contains('8.5'),
    );
    expect(
      FormPrintCatalog.paperMenuLabel(FormPrintCatalog.paperById('long_13')!),
      contains('13'),
    );
  });

  test('RSP print background orientation maps to existing paper sizes', () {
    expect(
      resolveRspPrintPaperId(familyId: 'letter', landscape: false),
      'letter',
    );
    expect(
      resolveRspPrintPaperId(familyId: 'letter', landscape: true),
      'letter_landscape',
    );
    expect(
      resolveRspPrintPaperId(familyId: 'long_13', landscape: true),
      'long_13_landscape',
    );
    expect(
      resolveRspPrintPaperId(familyId: 'long_13', landscape: true),
      'long_13_landscape',
    );
    expect(rspPrintPaperIsLandscape('long_landscape'), isTrue);
    expect(rspPrintPaperIsLandscape('letter_landscape'), isTrue);
    expect(rspPrintPaperIsLandscape('long_13'), isFalse);
    final letter = FormPrintCatalog.paperById('letter')!;
    expect(rspPrintDimensionLabel(letter), '8.5 × 11 in');
    final long = FormPrintCatalog.paperById('long_13')!;
    expect(rspPrintDimensionLabel(long), '8.5 × 13 in');
    final wide = FormPrintCatalog.paperById('letter_landscape')!;
    expect(rspPrintDimensionLabel(wide), '11 × 8.5 in');
  });
}
