/// Short note shown in the admin hire-email preview and sent as EmailJS `login_instructions`.
const String kHireLoginInstructions =
    'Sign in only after HR tells you to. Keep this password private.';

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
      'Welcome to LGU Plaridel HRMS. Your login details:'
      '$credBlock\n'
      'Your account is ready. $kHireLoginInstructions\n\n'
      'HR Office\n'
      'LGU Plaridel';
}
