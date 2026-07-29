class BiometricAttendanceLog {
  const BiometricAttendanceLog({
    required this.id,
    required this.userId,
    required this.biometricUserId,
    required this.employeeName,
    required this.loggedAt,
    required this.importedAt,
    this.employeeNumber,
    this.verifyCode,
    this.punchCode,
    this.workCode,
    this.sourceName,
  });

  final String id;
  final String userId;
  final String biometricUserId;
  final String employeeName;
  final int? employeeNumber;
  final DateTime loggedAt;
  final DateTime importedAt;
  final String? verifyCode;
  final String? punchCode;
  final String? workCode;
  final String? sourceName;

  factory BiometricAttendanceLog.fromJson(Map<String, dynamic> json) {
    return BiometricAttendanceLog(
      id: json['id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? '',
      biometricUserId: json['biometric_user_id']?.toString() ?? '',
      employeeName: json['employee_name']?.toString() ?? 'Unknown employee',
      employeeNumber: (json['employee_number'] as num?)?.toInt(),
      loggedAt: DateTime.parse(json['logged_at'].toString()),
      importedAt: DateTime.parse(json['imported_at'].toString()),
      verifyCode: json['verify_code']?.toString(),
      punchCode: json['punch_code']?.toString(),
      workCode: json['work_code']?.toString(),
      sourceName: json['source_file_name']?.toString(),
    );
  }
}

class BiometricAttendanceLogPage {
  const BiometricAttendanceLogPage({
    required this.total,
    required this.limit,
    required this.offset,
    required this.rows,
  });

  final int total;
  final int limit;
  final int offset;
  final List<BiometricAttendanceLog> rows;

  factory BiometricAttendanceLogPage.fromJson(Map<String, dynamic> json) {
    final rawRows = json['rows'] as List<dynamic>? ?? const [];
    return BiometricAttendanceLogPage(
      total: (json['total'] as num?)?.toInt() ?? 0,
      limit: (json['limit'] as num?)?.toInt() ?? 25,
      offset: (json['offset'] as num?)?.toInt() ?? 0,
      rows: rawRows
          .map(
            (row) => BiometricAttendanceLog.fromJson(
              Map<String, dynamic>.from(row as Map),
            ),
          )
          .toList(),
    );
  }
}
