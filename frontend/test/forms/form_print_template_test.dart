import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/forms/models/form_print_template.dart';

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
}
