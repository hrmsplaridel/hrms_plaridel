import 'dtr_export.dart';
import 'package:dio/dio.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/dtr/attendance/models/time_record.dart';
import 'package:hrms_plaridel/features/dtr/dtr_provider.dart';
import 'dtr_report_assignments.dart';

/// Report API requests and response parsing; selection and request guards stay in the page.
class DtrReportRepository {
  Future<DtrEmployeeReportLoad> fetchEmployeeReport(
    String employeeId, {
    required int year,
    required int month,
  }) async {
    final records = captureDtrReportLoad(
      TimeRecordRepo.instance.listPageForAdmin(
        startDate: DateTime(year, month, 1),
        endDate: DateTime(year, month + 1, 0),
        userId: employeeId,
        limit: 100,
        recompute: true,
      ),
    );
    final assignments = captureDtrReportLoad(
      fetchAssignmentTimelineForEmployee(employeeId, year: year, month: month),
    );
    final signatories = captureDtrReportLoad(
      DtrExport.resolveSignatories(requireVerifiedSource: true),
    );
    return DtrEmployeeReportLoad(
      records: await records,
      assignments: await assignments,
      signatories: await signatories,
    );
  }

  Future<List<int>> fetchAvailableReportYears({
    required int selectedYear,
  }) async {
    final response = await ApiClient.instance.get<Map<String, dynamic>>(
      '/api/dtr-daily-summary/report-years',
    );
    final rawYears = response.data?['years'];
    if (rawYears is! List) return [];
    final years =
        rawYears
            .map((value) => int.tryParse(value.toString()))
            .whereType<int>()
            .where((year) => year >= 1900 && year <= DateTime.now().year)
            .toSet()
            .toList()
          ..sort();
    if (!years.contains(selectedYear)) years.add(selectedYear);
    years.sort();
    return years;
  }

  Future<List<EmployeeOption>> fetchReportEmployees({
    required String? departmentId,
    required String employeeStatus,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    String dateKey(DateTime value) =>
        '${value.year.toString().padLeft(4, '0')}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')}';

    final params = <String, dynamic>{
      'status': employeeStatus,
      'role': 'All',
      'start_date': dateKey(startDate),
      'end_date': dateKey(endDate),
    };
    if (departmentId != null && departmentId.trim().isNotEmpty) {
      params['department_id'] = departmentId.trim();
    }
    final response = await ApiClient.instance.get<List<dynamic>>(
      '/api/employees',
      queryParameters: params,
    );
    return (response.data ?? [])
        .map((row) {
          final employee = Map<String, dynamic>.from(row as Map);
          final employeeNumber = employee['employee_number'];
          return EmployeeOption(
            id: employee['id']?.toString() ?? '',
            fullName: employee['full_name']?.toString() ?? 'Unknown',
            employeeNumber: employeeNumber is int
                ? employeeNumber
                : int.tryParse(employeeNumber?.toString() ?? ''),
            departmentName: employee['current_department_name']?.toString(),
            shiftPunchMode:
                employee['current_shift_punch_mode']?.toString() ?? 'auto',
            isActive: employee['is_active'] != false,
            employmentStatus: employee['employment_status']?.toString(),
          );
        })
        .where((employee) => employee.id.isNotEmpty)
        .toList(growable: false);
  }

  Future<List<DtrReportAssignment>> fetchAssignmentTimelineForEmployee(
    String employeeId, {
    required int year,
    required int month,
  }) async {
    final effectiveYear = year;
    final effectiveMonth = month;
    final res = await ApiClient.instance.get<List<dynamic>>(
      '/api/assignments',
      queryParameters: {
        'employee_id': employeeId,
        'status': 'All',
        'start_date': dtrReportDateKey(
          DateTime(effectiveYear, effectiveMonth, 1),
        ),
        'end_date': dtrReportDateKey(
          DateTime(effectiveYear, effectiveMonth + 1, 0),
        ),
      },
    );
    return parseDtrAssignmentTimeline(
      res.data ?? const [],
      year: effectiveYear,
      month: effectiveMonth,
    );
  }

  Future<DtrBulkReportBatch> fetchBulkReportBatch(
    List<EmployeeOption> employees, {
    required int year,
    required int month,
  }) async {
    String dateKey(DateTime value) =>
        '${value.year.toString().padLeft(4, '0')}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')}';

    final monthStart = DateTime(year, month, 1);
    final monthEnd = DateTime(year, month + 1, 0);
    final response = await ApiClient.instance.post<Map<String, dynamic>>(
      '/api/dtr-daily-summary/bulk-report',
      data: {
        'employee_ids': employees.map((employee) => employee.id).toList(),
        'start_date': dateKey(monthStart),
        'end_date': dateKey(monthEnd),
      },
      options: Options(receiveTimeout: const Duration(minutes: 2)),
    );
    final payload = response.data ?? const <String, dynamic>{};
    final employeeReports = <String, DtrBulkEmployeeReport>{};
    final failures = <String, String>{};

    for (final raw in (payload['employees'] as List? ?? const [])) {
      final row = Map<String, dynamic>.from(raw as Map);
      final employeeId = row['employee_id']?.toString() ?? '';
      if (employeeId.isEmpty) continue;
      final records = (row['records'] as List? ?? const [])
          .map(
            (record) =>
                TimeRecord.fromJson(Map<String, dynamic>.from(record as Map)),
          )
          .toList(growable: false);
      final reportableThrough = DateTime.tryParse(
        row['reportable_through']?.toString() ?? '',
      );
      employeeReports[employeeId] = DtrBulkEmployeeReport(
        recordsPage: TimeRecordPage(
          items: records,
          total: records.length,
          limit: records.length,
          offset: 0,
          reportableThrough: reportableThrough,
        ),
        assignmentTimeline: parseDtrAssignmentTimeline(
          row['assignments'] as List? ?? const [],
          year: year,
          month: month,
        ),
      );
    }
    for (final raw in (payload['errors'] as List? ?? const [])) {
      final row = Map<String, dynamic>.from(raw as Map);
      final employeeId = row['employee_id']?.toString() ?? '';
      if (employeeId.isEmpty) continue;
      failures[employeeId] =
          row['error']?.toString() ?? 'The report could not be prepared';
    }
    return DtrBulkReportBatch(employees: employeeReports, errors: failures);
  }
}

class DtrBulkEmployeeReport {
  const DtrBulkEmployeeReport({
    required this.recordsPage,
    required this.assignmentTimeline,
  });

  final TimeRecordPage recordsPage;
  final List<DtrReportAssignment> assignmentTimeline;
}

class DtrBulkReportBatch {
  const DtrBulkReportBatch({required this.employees, required this.errors});

  final Map<String, DtrBulkEmployeeReport> employees;
  final Map<String, String> errors;
}

class DtrReportLoadResult<T> {
  const DtrReportLoadResult.success(this.value) : error = null;
  const DtrReportLoadResult.failure(this.error) : value = null;

  final T? value;
  final Object? error;
  bool get succeeded => error == null;
}

Future<DtrReportLoadResult<T>> captureDtrReportLoad<T>(Future<T> future) async {
  try {
    return DtrReportLoadResult<T>.success(await future);
  } catch (error) {
    return DtrReportLoadResult<T>.failure(error);
  }
}

/// Independent results let the page distinguish failed, missing and ready sources.
class DtrEmployeeReportLoad {
  const DtrEmployeeReportLoad({
    required this.records,
    required this.assignments,
    required this.signatories,
  });
  final DtrReportLoadResult<TimeRecordPage> records;
  final DtrReportLoadResult<List<DtrReportAssignment>> assignments;
  final DtrReportLoadResult<DtrExportSignatories> signatories;
}
