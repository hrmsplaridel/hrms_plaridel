/// Copy shown in the admin hire-email preview and sent via EmailJS `account_note`.
const String kHireLoginInstructions =
    'Please wait for the HR Head or Admin before you sign in. They will tell you when and how to access HRMS.\n\n'
    'How to log in (only after HR instructs you):\n'
    '1. Keep this username and temporary password private. Do not share them with anyone.\n'
    '2. Open the LGU Plaridel HRMS login page when the HR Head or Admin tells you to.\n'
    '3. Enter the username and password in this email.\n'
    '4. Change your password if the system asks you to after the first login.\n\n'
    'Do not try to log in on your own before you receive those instructions.';

String buildHireCredentialsEmailPreview({
  required String applicantName,
  required String username,
  required String password,
}) {
  final name = applicantName.trim().isEmpty ? 'Applicant' : applicantName.trim();
  final user = username.trim();
  final pass = password;
  final credBlock = user.isNotEmpty || pass.isNotEmpty
      ? '\n\nUsername: ${user.isNotEmpty ? user : '…'}\n'
            'Password: ${pass.isNotEmpty ? pass : '…'}\n'
      : '\n\nUsername: …\nPassword: …\n';
  return 'Hello $name,\n\n'
      'Congratulations on joining LGU Plaridel. Your HRMS login details are below.'
      '$credBlock\n'
      'Your employee account has been created.\n\n'
      '$kHireLoginInstructions\n\n'
      'This email is not encrypted. Keep your password private. If you did not expect this email, contact HR immediately.\n\n'
      'Best regards,\n'
      'Human Resource Management Office\n'
      'LGU Plaridel';
}
