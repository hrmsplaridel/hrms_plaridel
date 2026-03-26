/// Employee matched by biometric_user_id from users table.
class BiometricMatchedEmployee {
  const BiometricMatchedEmployee({
    required this.id,
    required this.biometricUserId,
    required this.fullName,
    this.employeeNumber,
  });

  /// User UUID from users table (for import FK).
  final String id;
  final String biometricUserId;
  final String fullName;
  final int? employeeNumber;

  factory BiometricMatchedEmployee.fromJson(Map<String, dynamic> json) {
    final empNum = json['employee_number'];
    return BiometricMatchedEmployee(
      id: (json['id'] as String? ?? '').toString().trim(),
      biometricUserId: (json['biometric_user_id'] as String? ?? '').trim(),
      fullName: (json['full_name'] as String? ?? 'Unknown').trim(),
      employeeNumber: empNum is int
          ? empNum
          : (empNum != null ? int.tryParse(empNum.toString()) : null),
    );
  }
}
