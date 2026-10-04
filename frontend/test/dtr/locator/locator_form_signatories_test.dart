import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/dtr/locator/utils/locator_form_signatories.dart';

void main() {
  test('decodes PostgreSQL line-wrapped signature base64', () {
    final bytes = List<int>.generate(120, (index) => index);
    final encoded = base64Encode(bytes);
    for (final separator in ['\n', '\r\n']) {
      final person = LocatorPrintedSignatory.fromJson({
        'signature_image_base64':
            '${encoded.substring(0, 76)}$separator${encoded.substring(76)}',
      });
      expect(person.signatureBytes, bytes);
    }
  });

  test('invalid signature data fails rather than printing unsigned', () {
    expect(
      () => LocatorPrintedSignatory.fromJson({
        'signature_image_base64': 'invalid!',
      }),
      throwsFormatException,
    );
  });

  test('fixed names survive blank signatures after backup approval', () {
    final form = LocatorFormSignatories.fromJson({
      'print_signatories': {
        'department_head': {'name': 'Official Head'},
        'hr_approver': {
          'name': 'Official Final Approver',
          'position_title': 'Municipal HR Officer',
        },
        'applicant': {'name': 'Applicant'},
      },
    });
    expect(form.departmentHead.name, 'Official Head');
    expect(form.finalApprover.name, 'Official Final Approver');
    expect(form.finalApprover.positionTitle, 'Municipal HR Officer');
    expect(form.departmentHead.signatureBytes, isNull);
    expect(form.finalApprover.signatureBytes, isNull);
  });

  test(
    'uses only server-approved print ink, not raw pending signature slots',
    () {
      final form = LocatorFormSignatories.fromJson({
        'signatures': [
          {
            'slot_key': 'department_head',
            'signature_image_base64': base64Encode([1, 2]),
          },
        ],
        'print_signatories': {
          'department_head': {'name': 'Official Head'},
          'applicant': {
            'name': 'Applicant',
            'signature_image_base64': base64Encode([3, 4]),
          },
        },
        'print_form': {'office': 'Updated destination'},
      });
      expect(form.departmentHead.signatureBytes, isNull);
      expect(form.applicant.signatureBytes, [3, 4]);
      expect(form.form['office'], 'Updated destination');
    },
  );

  test('missing print payload is not silently treated as an unsigned form', () {
    expect(() => LocatorFormSignatories.fromJson({}), throwsFormatException);
  });
}
