/// Employee matched by biometric_user_id from users table.
class BiometricMatchedEmployee {
  const BiometricMatchedEmployee({
    required this.id,
    required this.biometricUserId,
    required this.fullName,
    this.employeeNumber,
    this.isActive = true,
    this.employmentStatus = 'active',
    this.dateHired,
    this.separationDate,
  });

  /// User UUID from users table (for import FK).
  final String id;
  final String biometricUserId;
  final String fullName;
  final int? employeeNumber;
  final bool isActive;
  final String employmentStatus;
  final String? dateHired;
  final String? separationDate;

  bool get isCurrentlyActive =>
      isActive && employmentStatus.trim().toLowerCase() == 'active';

  factory BiometricMatchedEmployee.fromJson(Map<String, dynamic> json) {
    final empNum = json['employee_number'];
    return BiometricMatchedEmployee(
      id: (json['id'] as String? ?? '').toString().trim(),
      biometricUserId: (json['biometric_user_id'] as String? ?? '').trim(),
      fullName: (json['full_name'] as String? ?? 'Unknown').trim(),
      employeeNumber: empNum is int
          ? empNum
          : (empNum != null ? int.tryParse(empNum.toString()) : null),
      isActive: json['is_active'] != false,
      employmentStatus: (json['employment_status'] ?? 'active').toString(),
      dateHired: json['date_hired']?.toString().split('T').first,
      separationDate: json['separation_date']?.toString().split('T').first,
    );
  }
}
