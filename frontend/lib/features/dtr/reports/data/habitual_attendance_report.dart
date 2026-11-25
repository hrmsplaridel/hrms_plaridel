import 'package:hrms_plaridel/core/api/client.dart';

/// Loads the habitual tardiness/undertime report for [year].
typedef HabitualAttendanceLoader =
    Future<HabitualAttendanceReport> Function(int year, String? departmentId);

Future<HabitualAttendanceReport> fetchHabitualAttendanceReport(
  int year,
  String? departmentId,
) async {
  final response = await ApiClient.instance.get<Map<String, dynamic>>(
    '/api/dtr-daily-summary/habitual-attendance',
    queryParameters: {
      'year': year,
      if (departmentId != null && departmentId.isNotEmpty)
        'department_id': departmentId,
    },
  );
  return HabitualAttendanceReport.fromJson(response.data ?? const {});
}

class HabitualMetric {
  const HabitualMetric({
    required this.monthly,
    required this.qualifyingMonths,
    required this.habitual,
  });

  /// Instance counts for January..December.
  final List<int> monthly;
  final List<int> qualifyingMonths;
  final bool habitual;

  factory HabitualMetric.fromJson(Object? json) {
    final map = json is Map ? json : const {};
    final rawMonthly = map['monthly'] is List ? map['monthly'] as List : [];
    return HabitualMetric(
      monthly: List.generate(
        12,
        (i) =>
            i < rawMonthly.length ? (rawMonthly[i] as num?)?.toInt() ?? 0 : 0,
      ),
      qualifyingMonths: [
        for (final m in (map['qualifying_months'] as List? ?? const []))
          (m as num).toInt(),
      ],
      habitual: map['habitual'] == true,
    );
  }
}

class HabitualAttendanceEmployee {
  const HabitualAttendanceEmployee({
    required this.employeeId,
    required this.employeeName,
    required this.tardiness,
    required this.undertime,
  });

  final String employeeId;
  final String employeeName;
  final HabitualMetric tardiness;
  final HabitualMetric undertime;

  bool get isHabitual => tardiness.habitual || undertime.habitual;

  factory HabitualAttendanceEmployee.fromJson(Map<String, dynamic> json) {
    final name = (json['employee_name'] as String?)?.trim() ?? '';
    return HabitualAttendanceEmployee(
      employeeId: '${json['employee_id'] ?? ''}',
      employeeName: name.isEmpty ? 'Unnamed employee' : name,
      tardiness: HabitualMetric.fromJson(json['tardiness']),
      undertime: HabitualMetric.fromJson(json['undertime']),
    );
  }
}

class HabitualAttendanceReport {
  const HabitualAttendanceReport({
    required this.year,
    required this.through,
    required this.threshold,
    required this.employees,
  });

  final int year;
  final String through;
  final int threshold;
  final List<HabitualAttendanceEmployee> employees;

  factory HabitualAttendanceReport.fromJson(Map<String, dynamic> json) {
    return HabitualAttendanceReport(
      year: (json['year'] as num?)?.toInt() ?? DateTime.now().year,
      through: '${json['through'] ?? ''}',
      threshold: (json['threshold'] as num?)?.toInt() ?? 10,
      employees: [
        for (final e in (json['employees'] as List? ?? const []))
          if (e is Map)
            HabitualAttendanceEmployee.fromJson(Map<String, dynamic>.from(e)),
      ],
    );
  }
}
