import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/recruitment/data/hire_credentials_email_copy.dart';

void main() {
  test('hire email tells the applicant to wait for HR before logging in', () {
    final body = buildHireCredentialsEmailPreview(
      applicantName: 'Jane Doe',
      username: 'jane@example.com',
      password: '8FDFxfs%t5Sk',
    );

    expect(body, contains('Hello Jane Doe,'));
    expect(body, contains('Username: jane@example.com'));
    expect(body, contains('Password: 8FDFxfs%t5Sk'));
    expect(body, contains('Sign in only after HR tells you to'));
    expect(body, contains('Keep this password private'));
    expect(body, isNot(contains('Please sign in to the HRMS')));
  });
}
