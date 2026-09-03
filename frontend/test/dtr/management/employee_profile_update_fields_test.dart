import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/dtr/management/employees/data/employee_profile_update_fields.dart';

void main() {
  test('blank optional profile values are sent as explicit nulls', () {
    final fields = buildClearableEmployeeProfileUpdateFields(
      middleName: '  ',
      suffix: null,
      sex: 'Male',
      dateOfBirth: null,
      contactNumber: '',
      address: '   ',
      employmentType: null,
      salaryGrade: '',
    );

    expect(fields, containsPair('middle_name', null));
    expect(fields, containsPair('suffix', null));
    expect(fields, containsPair('date_of_birth', null));
    expect(fields, containsPair('contact_number', null));
    expect(fields, containsPair('address', null));
    expect(fields, containsPair('employment_type', null));
    expect(fields, containsPair('salary_grade', null));
    expect(fields, containsPair('sex', 'Male'));
  });

  test(
    'provided optional profile values are trimmed and dates are formatted',
    () {
      final fields = buildClearableEmployeeProfileUpdateFields(
        middleName: ' Santos ',
        suffix: ' Jr. ',
        sex: ' Female ',
        dateOfBirth: DateTime(1995, 4, 7),
        contactNumber: ' 09171234567 ',
        address: ' Street|Barangay|Plaridel|Misamis Occidental ',
        employmentType: ' regular ',
        salaryGrade: ' SG-12 ',
      );

      expect(fields['middle_name'], 'Santos');
      expect(fields['suffix'], 'Jr.');
      expect(fields['sex'], 'Female');
      expect(fields['date_of_birth'], '1995-04-07');
      expect(fields['contact_number'], '09171234567');
      expect(fields['address'], 'Street|Barangay|Plaridel|Misamis Occidental');
      expect(fields['employment_type'], 'regular');
      expect(fields['salary_grade'], 'SG-12');
    },
  );
}
