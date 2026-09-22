import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/recruitment/data/recruitment_hire_prefill.dart';

void main() {
  test('hire email uses the Create Account password, not Employee123', () {
    expect(
      resolveHireLoginPassword(
        storedPassword: '8FDFxfs%t5Sk',
        persistedPassword: kDefaultEmployeeAccountPassword,
      ),
      '8FDFxfs%t5Sk',
    );
    expect(
      resolveHireLoginPassword(
        storedPassword: '',
        persistedPassword: 'AbcdEfgh!234',
      ),
      'AbcdEfgh!234',
    );
  });

  test('missing credentials generate a randomized password instead of the default', () {
    final password = resolveHireLoginPassword();
    expect(password, isNot(kDefaultEmployeeAccountPassword));
    expect(password.length, greaterThanOrEqualTo(12));
    expect(password, isNot(resolveHireLoginPassword()));
  });
}
