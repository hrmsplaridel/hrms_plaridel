/// A single parsed row from a biometric .dat file.
class BiometricParsedRow {
  const BiometricParsedRow({
    required this.biometricUserId,
    required this.loggedAt,
    required this.rawLine,
    this.verifyCode,
    this.punchCode,
    this.workCode,
  });

  final String biometricUserId;
  final DateTime loggedAt;
  final String rawLine;
  final String? verifyCode;
  final String? punchCode;
  final String? workCode;
}
