/// User model from API (replaces Supabase User).
/// Used by [AuthProvider]; matches backend /auth/me and /auth/login response.
class AppUser {
  const AppUser({
    required this.id,
    required this.email,
    this.role,
    this.fullName,
    this.avatarPath,
    this.contactNumber,
    this.employeeNumber,
    this.dateHired,
    this.employmentStatus,
    this.employmentType,
    this.departmentName,
    this.positionName,
    this.sex,
    this.dateOfBirth,
    this.address,
    this.civilStatus,
    this.nationality,
    this.firstName,
    this.middleName,
    this.lastName,
    this.suffix,
  });

  final String id;
  final String email;
  final String? role;
  final String? fullName;
  final String? avatarPath;
  final String? contactNumber;
  final int? employeeNumber;
  final DateTime? dateHired;
  final String? employmentStatus;
  final String? employmentType;
  final String? departmentName;
  final String? positionName;
  final String? sex;
  final DateTime? dateOfBirth;
  final String? address;
  final String? civilStatus;
  final String? nationality;
  final String? firstName;
  final String? middleName;
  final String? lastName;
  final String? suffix;

  /// For compatibility with code that used Supabase User.userMetadata.
  /// e.g. userMetadata['full_name'], userMetadata['avatar_path'], userMetadata['phone'].
  Map<String, dynamic> get userMetadata => {
        if (fullName != null) 'full_name': fullName,
        if (avatarPath != null) 'avatar_path': avatarPath,
        if (contactNumber != null) 'phone': contactNumber,
        if (middleName != null) 'middle_name': middleName,
        if (suffix != null) 'suffix': suffix,
      };

  factory AppUser.fromJson(Map<String, dynamic> json) {
    final meta = json['user_metadata'] as Map<String, dynamic>?;
    return AppUser(
      id: json['id'] as String? ?? '',
      email: json['email'] as String? ?? '',
      role: json['role'] as String?,
      fullName: json['full_name'] as String? ?? meta?['full_name'] as String?,
      avatarPath: json['avatar_path'] as String? ?? meta?['avatar_path'] as String?,
      contactNumber: json['contact_number'] as String? ?? meta?['phone'] as String?,
      employeeNumber: _parseInt(json['employee_number']),
      dateHired: _parseDate(json['date_hired']),
      employmentStatus: json['employment_status'] as String?,
      employmentType: json['employment_type'] as String?,
      departmentName: json['department_name'] as String?,
      positionName: json['position_name'] as String?,
      sex: json['sex'] as String?,
      dateOfBirth: _parseDate(json['date_of_birth']),
      address: json['address'] as String?,
      civilStatus: json['civil_status'] as String?,
      nationality: json['nationality'] as String?,
      firstName: json['first_name'] as String?,
      middleName: json['middle_name'] as String? ?? meta?['middle_name'] as String?,
      lastName: json['last_name'] as String?,
      suffix: json['suffix'] as String? ?? meta?['suffix'] as String?,
    );
  }

  static int? _parseInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }

  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    return DateTime.tryParse(v.toString());
  }

  /// Short ID for profile/header (never the auth UUID).
  String get displayEmployeeId {
    if (employeeNumber != null) {
      final n = employeeNumber!;
      return n < 10000 ? n.toString().padLeft(4, '0') : n.toString();
    }
    return syntheticEmployeeId(id);
  }

  /// Stable pseudo-random 5-digit ID when [employeeNumber] is not set.
  static String syntheticEmployeeId(String userId) {
    if (userId.isEmpty) return '00000';
    var hash = 17;
    for (final unit in userId.codeUnits) {
      hash = 0x1fffffff & (hash * 31 + unit);
    }
    final n = 10000 + (hash.abs() % 90000);
    return n.toString();
  }
}
