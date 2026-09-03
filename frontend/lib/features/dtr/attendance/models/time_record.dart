import 'package:dio/dio.dart';

import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/dtr/locator/models/locator_request_type.dart';

class AttendancePolicySnapshot {
  const AttendancePolicySnapshot({
    this.id,
    required this.workHoursPerDay,
    required this.useEquivalentDayConversion,
    required this.deductLate,
    required this.deductUndertime,
    required this.combineLateAndUndertime,
    required this.deductionMultiplier,
  });

  final String? id;
  final double workHoursPerDay;
  final bool useEquivalentDayConversion;
  final bool deductLate;
  final bool deductUndertime;
  final bool combineLateAndUndertime;
  final double deductionMultiplier;

  factory AttendancePolicySnapshot.fromJson(Map<String, dynamic> json) {
    return AttendancePolicySnapshot(
      id: json['id']?.toString(),
      workHoursPerDay: TimeRecord._parseDouble(json['work_hours_per_day']) ?? 8,
      useEquivalentDayConversion:
          json['use_equivalent_day_conversion'] != false,
      deductLate: json['deduct_late'] == true,
      deductUndertime: json['deduct_undertime'] != false,
      combineLateAndUndertime: json['combine_late_and_undertime'] == true,
      deductionMultiplier:
          TimeRecord._parseDouble(json['deduction_multiplier']) ?? 1,
    );
  }
}

class AttendanceReportDeduction {
  const AttendanceReportDeduction({
    required this.lateMinutes,
    required this.undertimeMinutes,
    required this.absenceMinutes,
    required this.totalMinutes,
    required this.equivalentDay,
  });

  final int lateMinutes;
  final int undertimeMinutes;
  final int absenceMinutes;
  final int totalMinutes;
  final double equivalentDay;

  factory AttendanceReportDeduction.fromJson(Map<String, dynamic> json) {
    return AttendanceReportDeduction(
      lateMinutes: TimeRecord._parseInt(json['late_minutes']) ?? 0,
      undertimeMinutes: TimeRecord._parseInt(json['undertime_minutes']) ?? 0,
      absenceMinutes: TimeRecord._parseInt(json['absence_minutes']) ?? 0,
      totalMinutes: TimeRecord._parseInt(json['total_minutes']) ?? 0,
      equivalentDay: TimeRecord._parseDouble(json['equivalent_day']) ?? 0,
    );
  }
}

/// One DTR (Daily Time Record) entry: AM/PM time-in/out for a user on a date.
/// timeIn = AM in, breakOut = AM out (lunch), breakIn = PM in, timeOut = PM out (end of day).
class TimeRecord {
  const TimeRecord({
    this.id,
    required this.userId,
    required this.recordDate,
    this.timeIn,
    this.breakOut,
    this.breakIn,
    this.timeOut,
    this.totalHours,
    this.lateMinutes,
    this.undertimeMinutes,
    this.status,
    this.pmStatus,
    this.remarks,
    this.holidayId,
    this.leaveRequestId,
    this.leaveCoverageId,
    this.isLeaveCovered = false,
    this.createdAt,
    this.updatedAt,
    this.employeeName,
    this.holidayName,
    this.coverage,
    this.attendanceRemark,
    this.leaveTypeName,
    this.source,
    this.locatorSlipId,
    this.locatorSlipRequestType,
    this.locatorSlipRequestTypeLabel,
    this.locatorSlipDtrSlotLabel,
    this.locatorSlipDtrPrintLabel,
    this.locatorSlipCoverageMode,
    this.locatorSlipSegments,
    this.shiftPunchMode = 'auto',
    this.combineLateAndUndertime = false,
    this.attendancePolicy,
    this.reportDeduction,
  });

  final String? id;
  final String userId;
  final DateTime recordDate;
  final DateTime? timeIn;
  final DateTime? breakOut;
  final DateTime? breakIn;
  final DateTime? timeOut;
  final double? totalHours;

  /// Late minutes (AM + PM). From backend or computed.
  final int? lateMinutes;

  /// Undertime minutes (left before shift end). From backend or computed.
  final int? undertimeMinutes;

  /// present | late | absent | on_leave | holiday (AM status)
  final String? status;

  /// present | late (PM status; null = absent or no break_in)
  final String? pmStatus;
  final String? remarks;

  /// Set when date is a configured holiday.
  final String? holidayId;

  /// Set when date has approved leave.
  final String? leaveRequestId;

  /// Active approved-leave overlay covering an underlying DTR row.
  final String? leaveCoverageId;

  /// True for both current coverage rows and approved legacy leave-linked rows.
  final bool isLeaveCovered;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Joined from profiles.full_name when listing for admin
  final String? employeeName;

  /// When status is holiday, name of the holiday from holidays table
  final String? holidayName;

  /// Holiday/suspension coverage: whole_day | am_only | pm_only (when holiday_id is set).
  final String? coverage;

  /// Shift-aware attendance remark from backend: On Time, Late, Undertime, Late + Undertime, Incomplete, Invalid Log, Absent, Holiday, Leave, or specific leave type (e.g. Sick Leave).
  final String? attendanceRemark;

  /// Leave type display name when status is on_leave (e.g. Sick Leave, Vacation Leave).
  final String? leaveTypeName;

  /// Attendance source: 'manual' (admin entry), 'system' (biometric), 'adjusted' (admin correction).
  final String? source;

  /// Approved locator-slip metadata (when present in DTR payload).
  final String? locatorSlipId;
  final String? locatorSlipRequestType;
  final String? locatorSlipRequestTypeLabel;
  final String? locatorSlipDtrSlotLabel;
  final String? locatorSlipDtrPrintLabel;
  final String? locatorSlipCoverageMode;
  final List<String>? locatorSlipSegments;

  /// Employee's shift punch mode for this record's date.
  /// Values: 'auto', 'full_day', 'am_only', 'pm_only', 'single_session'.
  final String shiftPunchMode;

  /// When true, official DTR exports display late minutes in the undertime column.
  /// Stored and on-screen late/undertime values remain separate.
  final bool combineLateAndUndertime;

  /// Effective backend-resolved policy for this employee and attendance date.
  final AttendancePolicySnapshot? attendancePolicy;

  /// Official per-date report contribution calculated by the backend.
  final AttendanceReportDeduction? reportDeduction;

  LocatorRequestType get locatorRequestType =>
      LocatorRequestType.fromCode(locatorSlipRequestType);

  String get locatorSlipSlotLabel =>
      _nonEmpty(locatorSlipDtrSlotLabel) ?? locatorRequestType.dtrSlotLabel;

  String get locatorSlipPrintLabel =>
      _nonEmpty(locatorSlipDtrPrintLabel) ?? locatorRequestType.dtrPrintLabel;

  String get locatorSlipDisplayLabel =>
      _nonEmpty(locatorSlipRequestTypeLabel) ??
      (locatorRequestType == LocatorRequestType.workFromHome
          ? locatorRequestType.shortLabel
          : locatorRequestType.label);

  static String? _nonEmpty(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  static const String tableName = 'time_records';

  /// Parse API record_date (YYYY-MM-DD or ISO timestamp) as local calendar date to avoid timezone display bugs.
  static DateTime _parseRecordDate(dynamic value) {
    if (value == null) return DateTime.now();
    final s = value.toString().split('T').first.trim();
    final parts = s.split('-');
    if (parts.length == 3) {
      final y = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      final d = int.tryParse(parts[2]);
      if (y != null && m != null && d != null) return DateTime(y, m, d);
    }
    return DateTime.tryParse(s) ?? DateTime.now();
  }

  factory TimeRecord.fromJson(Map<String, dynamic> json) {
    return TimeRecord(
      id: json['id']?.toString(),
      userId: json['user_id'] as String? ?? '',
      recordDate: _parseRecordDate(json['record_date']),
      timeIn: json['time_in'] != null
          ? DateTime.tryParse(json['time_in'] as String)
          : null,
      breakOut: json['break_out'] != null
          ? DateTime.tryParse(json['break_out'] as String)
          : null,
      breakIn: json['break_in'] != null
          ? DateTime.tryParse(json['break_in'] as String)
          : null,
      timeOut: json['time_out'] != null
          ? DateTime.tryParse(json['time_out'] as String)
          : null,
      totalHours: _parseDouble(json['total_hours']),
      lateMinutes: _parseInt(json['late_minutes']),
      undertimeMinutes: _parseInt(json['undertime_minutes']),
      status: json['status']?.toString(),
      pmStatus: json['pm_status']?.toString(),
      remarks: json['remarks']?.toString(),
      holidayId: json['holiday_id']?.toString(),
      leaveRequestId: json['leave_request_id']?.toString(),
      leaveCoverageId: json['leave_coverage_id']?.toString(),
      isLeaveCovered:
          json['is_leave_covered'] == true ||
          json['leave_coverage_id'] != null ||
          (json['status'] == 'on_leave' && json['leave_request_id'] != null),
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'] as String)
          : null,
      employeeName: _extractEmployeeName(json),
      holidayName: json['holiday_name']?.toString(),
      coverage: json['coverage']?.toString(),
      attendanceRemark: json['attendance_remark']?.toString(),
      leaveTypeName: json['leave_type_name']?.toString(),
      source: json['source']?.toString(),
      locatorSlipId: json['locator_slip_id']?.toString(),
      locatorSlipRequestType: json['locator_slip_request_type']?.toString(),
      locatorSlipRequestTypeLabel: json['locator_slip_request_type_label']
          ?.toString(),
      locatorSlipDtrSlotLabel: json['locator_slip_dtr_slot_label']?.toString(),
      locatorSlipDtrPrintLabel: json['locator_slip_dtr_print_label']
          ?.toString(),
      locatorSlipCoverageMode: json['locator_slip_coverage_mode']?.toString(),
      locatorSlipSegments: (json['locator_slip_segments'] is List)
          ? (json['locator_slip_segments'] as List)
                .map((e) => e.toString())
                .toList()
          : null,
      shiftPunchMode: json['shift_punch_mode']?.toString() ?? 'auto',
      combineLateAndUndertime: json['combine_late_and_undertime'] == true,
      attendancePolicy: json['attendance_policy'] is Map
          ? AttendancePolicySnapshot.fromJson(
              Map<String, dynamic>.from(json['attendance_policy'] as Map),
            )
          : null,
      reportDeduction: json['report_deduction'] is Map
          ? AttendanceReportDeduction.fromJson(
              Map<String, dynamic>.from(json['report_deduction'] as Map),
            )
          : null,
    );
  }

  static int? _parseInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    return int.tryParse(v.toString());
  }

  static String? _extractEmployeeName(Map<String, dynamic> json) {
    final profiles = json['profiles'];
    if (profiles is Map) {
      return profiles['full_name']?.toString();
    }
    return json['employee_name']?.toString();
  }

  static double? _parseDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  /// ISO string in UTC for API (so server stores correct time; display uses toLocal()).
  static String? _toUtcIso(DateTime? dt) => dt?.toUtc().toIso8601String();

  /// Calendar date YYYY-MM-DD from local date components (avoids UTC off-by-one when sending to API).
  static String _toDateOnlyString(DateTime d) {
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'user_id': userId,
      'record_date': _toDateOnlyString(recordDate),
      'time_in': _toUtcIso(timeIn),
      'break_out': _toUtcIso(breakOut),
      'break_in': _toUtcIso(breakIn),
      'time_out': _toUtcIso(timeOut),
      'total_hours': totalHours,
      'late_minutes': lateMinutes,
      'undertime_minutes': undertimeMinutes,
      'status': status,
      'pm_status': pmStatus,
      'remarks': remarks,
      'updated_at': DateTime.now().toIso8601String(),
    };
  }

  TimeRecord copyWith({
    String? id,
    String? userId,
    DateTime? recordDate,
    DateTime? timeIn,
    DateTime? breakOut,
    DateTime? breakIn,
    DateTime? timeOut,
    double? totalHours,
    int? lateMinutes,
    int? undertimeMinutes,
    String? status,
    String? pmStatus,
    String? remarks,
    String? holidayId,
    String? leaveRequestId,
    String? leaveCoverageId,
    bool? isLeaveCovered,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? employeeName,
    String? holidayName,
    String? attendanceRemark,
    String? leaveTypeName,
    String? source,
    String? locatorSlipId,
    String? locatorSlipRequestType,
    String? locatorSlipRequestTypeLabel,
    String? locatorSlipDtrSlotLabel,
    String? locatorSlipDtrPrintLabel,
    String? locatorSlipCoverageMode,
    List<String>? locatorSlipSegments,
    String? shiftPunchMode,
    bool? combineLateAndUndertime,
    AttendancePolicySnapshot? attendancePolicy,
    AttendanceReportDeduction? reportDeduction,
  }) {
    return TimeRecord(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      recordDate: recordDate ?? this.recordDate,
      timeIn: timeIn ?? this.timeIn,
      breakOut: breakOut ?? this.breakOut,
      breakIn: breakIn ?? this.breakIn,
      timeOut: timeOut ?? this.timeOut,
      totalHours: totalHours ?? this.totalHours,
      lateMinutes: lateMinutes ?? this.lateMinutes,
      undertimeMinutes: undertimeMinutes ?? this.undertimeMinutes,
      status: status ?? this.status,
      pmStatus: pmStatus ?? this.pmStatus,
      remarks: remarks ?? this.remarks,
      holidayId: holidayId ?? this.holidayId,
      leaveRequestId: leaveRequestId ?? this.leaveRequestId,
      leaveCoverageId: leaveCoverageId ?? this.leaveCoverageId,
      isLeaveCovered: isLeaveCovered ?? this.isLeaveCovered,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      employeeName: employeeName ?? this.employeeName,
      holidayName: holidayName ?? this.holidayName,
      attendanceRemark: attendanceRemark ?? this.attendanceRemark,
      leaveTypeName: leaveTypeName ?? this.leaveTypeName,
      source: source ?? this.source,
      locatorSlipId: locatorSlipId ?? this.locatorSlipId,
      locatorSlipRequestType:
          locatorSlipRequestType ?? this.locatorSlipRequestType,
      locatorSlipRequestTypeLabel:
          locatorSlipRequestTypeLabel ?? this.locatorSlipRequestTypeLabel,
      locatorSlipDtrSlotLabel:
          locatorSlipDtrSlotLabel ?? this.locatorSlipDtrSlotLabel,
      locatorSlipDtrPrintLabel:
          locatorSlipDtrPrintLabel ?? this.locatorSlipDtrPrintLabel,
      locatorSlipCoverageMode:
          locatorSlipCoverageMode ?? this.locatorSlipCoverageMode,
      locatorSlipSegments: locatorSlipSegments ?? this.locatorSlipSegments,
      shiftPunchMode: shiftPunchMode ?? this.shiftPunchMode,
      combineLateAndUndertime:
          combineLateAndUndertime ?? this.combineLateAndUndertime,
      attendancePolicy: attendancePolicy ?? this.attendancePolicy,
      reportDeduction: reportDeduction ?? this.reportDeduction,
    );
  }
}

/// Aggregated counts for the admin DTR dashboard (from GET /api/dtr-daily-summary/summary).
class DtrSummaryCounts {
  const DtrSummaryCounts({
    required this.presentToday,
    required this.lateToday,
    required this.onLeaveToday,
    required this.pendingApproval,
  });

  final int presentToday;
  final int lateToday;
  final int onLeaveToday;
  final int pendingApproval;
}

class DeletedTimeRecord {
  const DeletedTimeRecord({
    required this.id,
    required this.deletedDtrSummaryId,
    required this.userId,
    required this.recordDate,
    required this.source,
    required this.reason,
    required this.deletedAt,
    this.employeeName,
    this.deletedByName,
    this.restoredByName,
    this.restorationReason,
    this.restoredAt,
  });

  final String id;
  final String deletedDtrSummaryId;
  final String userId;
  final DateTime recordDate;
  final String source;
  final String reason;
  final DateTime deletedAt;
  final String? employeeName;
  final String? deletedByName;
  final String? restoredByName;
  final String? restorationReason;
  final DateTime? restoredAt;

  bool get isRestored => restoredAt != null;

  factory DeletedTimeRecord.fromJson(Map<String, dynamic> json) {
    return DeletedTimeRecord(
      id: json['id']?.toString() ?? '',
      deletedDtrSummaryId: json['deleted_dtr_summary_id']?.toString() ?? '',
      userId: json['employee_id']?.toString() ?? '',
      recordDate: TimeRecord._parseRecordDate(json['attendance_date']),
      source: json['source']?.toString() ?? 'system',
      reason: json['reason']?.toString() ?? '',
      deletedAt:
          DateTime.tryParse(json['deleted_at']?.toString() ?? '') ??
          DateTime.now(),
      employeeName: json['employee_name']?.toString(),
      deletedByName: json['deleted_by_name']?.toString(),
      restoredByName: json['restored_by_name']?.toString(),
      restorationReason: json['restoration_reason']?.toString(),
      restoredAt: DateTime.tryParse(json['restored_at']?.toString() ?? ''),
    );
  }
}

class TimeRecordPage {
  const TimeRecordPage({
    required this.items,
    required this.total,
    required this.limit,
    required this.offset,
    this.reportableThrough,
  });

  final List<TimeRecord> items;
  final int total;
  final int limit;
  final int offset;
  final DateTime? reportableThrough;
}

/// Repository for DTR time records. Uses backend API (dtr_daily_summary); Supabase logic commented out.
class TimeRecordRepo {
  TimeRecordRepo._();
  static final TimeRecordRepo instance = TimeRecordRepo._();

  /// List time records for admin (all users). Uses GET /api/dtr-daily-summary.
  ///
  /// Date-range responses are paginated by the backend. Use [listPageForAdmin]
  /// when the caller needs the total count or subsequent pages.
  Future<List<TimeRecord>> listForAdmin({
    DateTime? startDate,
    DateTime? endDate,
    String? userId,
    String? departmentId,
    int? limit,
    int? offset,
    bool recompute = false,
  }) async {
    final page = await listPageForAdmin(
      startDate: startDate,
      endDate: endDate,
      userId: userId,
      departmentId: departmentId,
      limit: limit,
      offset: offset,
      recompute: recompute,
    );
    return page.items;
  }

  Future<TimeRecordPage> listPageForAdmin({
    DateTime? startDate,
    DateTime? endDate,
    String? userId,
    String? departmentId,
    int? limit,
    int? offset,
    bool recompute = false,
  }) async {
    try {
      final params = <String, dynamic>{};
      if (startDate != null) {
        params['start_date'] = TimeRecord._toDateOnlyString(startDate);
      }
      if (endDate != null) {
        params['end_date'] = TimeRecord._toDateOnlyString(endDate);
      }
      if (userId != null && userId.isNotEmpty) params['employee_id'] = userId;
      if (departmentId != null && departmentId.isNotEmpty) {
        params['department_id'] = departmentId;
      }
      if (limit != null) params['limit'] = limit;
      if (offset != null) params['offset'] = offset;
      if (recompute) params['recompute'] = true;
      final res = await ApiClient.instance.get<List<dynamic>>(
        '/api/dtr-daily-summary',
        queryParameters: params,
      );
      final data = res.data ?? [];
      final items = data
          .map((e) => TimeRecord.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      final responseTotal = int.tryParse(
        res.headers.value('x-total-count') ?? '',
      );
      final responseLimit = int.tryParse(res.headers.value('x-limit') ?? '');
      final responseOffset = int.tryParse(res.headers.value('x-offset') ?? '');
      final reportableThrough = DateTime.tryParse(
        res.headers.value('x-reportable-through') ?? '',
      );
      return TimeRecordPage(
        items: items,
        total: responseTotal ?? items.length,
        limit: responseLimit ?? limit ?? items.length,
        offset: responseOffset ?? offset ?? 0,
        reportableThrough: reportableThrough,
      );
    } on DioException catch (_) {
      rethrow;
    }
  }

  /// List time records for current user (employee).
  Future<List<TimeRecord>> listForUser({
    required String userId,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    return listForAdmin(
      userId: userId,
      startDate: startDate,
      endDate: endDate,
      limit: 500,
    );
  }

  /// Get today's biometric attendance record for a user.
  Future<TimeRecord?> getTodayForUser(String userId) async {
    final now = DateTime.now();
    final today = TimeRecord._toDateOnlyString(
      DateTime(now.year, now.month, now.day),
    );
    final list = await listForAdmin(
      userId: userId,
      startDate: DateTime.parse(today),
      endDate: DateTime.parse(today),
      limit: 1,
    );
    return list.isEmpty ? null : list.first;
  }

  /// Insert a manual time record. Uses POST /api/dtr-daily-summary.
  Future<TimeRecord> insert(TimeRecord record) async {
    final res = await ApiClient.instance.post<Map<String, dynamic>>(
      '/api/dtr-daily-summary',
      data: {
        'attendance_date': TimeRecord._toDateOnlyString(record.recordDate),
        'time_in': TimeRecord._toUtcIso(record.timeIn),
        'break_out': TimeRecord._toUtcIso(record.breakOut),
        'break_in': TimeRecord._toUtcIso(record.breakIn),
        'time_out': TimeRecord._toUtcIso(record.timeOut),
        'total_hours': record.totalHours ?? 0,
        if (record.userId.isNotEmpty) 'employee_id': record.userId,
      },
    );
    final data = res.data;
    if (data == null) throw Exception('No data returned');
    return TimeRecord.fromJson(data);
  }

  /// Update an existing manual record. Uses PUT /api/dtr-daily-summary/:id.
  Future<void> update(
    TimeRecord record, {
    bool editUnderlyingAttendance = false,
  }) async {
    if (record.id == null) return;
    await ApiClient.instance.put(
      '/api/dtr-daily-summary/${record.id}',
      data: {
        'time_in': TimeRecord._toUtcIso(record.timeIn),
        'break_out': TimeRecord._toUtcIso(record.breakOut),
        'break_in': TimeRecord._toUtcIso(record.breakIn),
        'time_out': TimeRecord._toUtcIso(record.timeOut),
        'total_hours': record.totalHours,
        'status': record.status,
        'pm_status': record.pmStatus,
        'remarks': record.remarks,
        if (editUnderlyingAttendance) 'edit_underlying_attendance': true,
      },
    );
  }

  /// Recalculate one saved DTR row using the current shift and attendance policy.
  Future<TimeRecord> recalculate(String id) async {
    final res = await ApiClient.instance.post<Map<String, dynamic>>(
      '/api/dtr-daily-summary/$id/recalculate',
    );
    final data = res.data;
    if (data == null) throw Exception('No data returned');
    return TimeRecord.fromJson(data);
  }

  /// Get record for a user on a specific date (for upsert by date).
  Future<TimeRecord?> getRecordForUserForDate(
    String userId,
    DateTime date,
  ) async {
    final dateStr = TimeRecord._toDateOnlyString(date);
    final list = await listForAdmin(
      userId: userId,
      startDate: DateTime.parse(dateStr),
      endDate: DateTime.parse(dateStr),
      limit: 1,
    );
    return list.isEmpty ? null : list.first;
  }

  /// Upsert: get record for this user and record date; update if exists else insert.
  Future<void> upsert(TimeRecord record) async {
    final date = DateTime(
      record.recordDate.year,
      record.recordDate.month,
      record.recordDate.day,
    );
    final existing = await getRecordForUserForDate(record.userId, date);
    if (existing != null && existing.id != null) {
      await update(record.copyWith(id: existing.id));
    } else {
      await insert(record);
    }
  }

  /// Delete a processed record while preserving its biometric evidence and audit snapshot.
  Future<void> delete(String id, {required String reason}) async {
    await ApiClient.instance.delete(
      '/api/dtr-daily-summary/$id',
      data: {'reason': reason},
    );
  }

  Future<List<DeletedTimeRecord>> listDeleted({
    bool includeRestored = true,
    DateTime? startDate,
    DateTime? endDate,
    String? userId,
    int limit = 500,
  }) async {
    final params = <String, dynamic>{
      'include_restored': includeRestored,
      'limit': limit,
    };
    if (startDate != null) {
      params['start_date'] = TimeRecord._toDateOnlyString(startDate);
    }
    if (endDate != null) {
      params['end_date'] = TimeRecord._toDateOnlyString(endDate);
    }
    if (userId?.trim().isNotEmpty == true) {
      params['employee_id'] = userId!.trim();
    }
    final response = await ApiClient.instance.get<Map<String, dynamic>>(
      '/api/dtr-daily-summary/deletions',
      queryParameters: params,
    );
    final items = response.data?['items'];
    if (items is! List) return const [];
    return items
        .whereType<Map>()
        .map(
          (item) => DeletedTimeRecord.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList();
  }

  Future<void> restoreDeleted(
    String deletionId, {
    required String reason,
  }) async {
    await ApiClient.instance.post(
      '/api/dtr-daily-summary/deletions/$deletionId/restore',
      data: {'reason': reason},
    );
  }

  /// Admin dashboard counts in one round-trip (DTR + leave).
  /// Uses GET /api/dtr-daily-summary/summary.
  Future<DtrSummaryCounts> fetchSummaryCounts() async {
    try {
      final res = await ApiClient.instance.get<Map<String, dynamic>>(
        '/api/dtr-daily-summary/summary',
      );
      final data = res.data;
      return DtrSummaryCounts(
        presentToday: _jsonInt(data, 'present_today'),
        lateToday: _jsonInt(data, 'late_today'),
        onLeaveToday: _jsonInt(data, 'on_leave_today'),
        pendingApproval: _jsonInt(data, 'pending_approval'),
      );
    } on DioException catch (_) {
      return const DtrSummaryCounts(
        presentToday: 0,
        lateToday: 0,
        onLeaveToday: 0,
        pendingApproval: 0,
      );
    }
  }

  static int _jsonInt(Map<String, dynamic>? data, String key) {
    final v = data?[key];
    if (v is int) return v;
    if (v is num) return v.round();
    return 0;
  }

  /// List recent time records for admin dashboard.
  Future<List<TimeRecord>> listRecent({int limit = 20}) async {
    return listForAdmin(limit: limit);
  }
}
