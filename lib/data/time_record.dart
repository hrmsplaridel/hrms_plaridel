import 'package:dio/dio.dart';

import '../api/client.dart';

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
    this.createdAt,
    this.updatedAt,
    this.employeeName,
    this.holidayName,
    this.coverage,
    this.attendanceRemark,
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
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Joined from profiles.full_name when listing for admin
  final String? employeeName;

  /// When status is holiday, name of the holiday from holidays table
  final String? holidayName;

  /// Holiday/suspension coverage: whole_day | am_only | pm_only (when holiday_id is set).
  final String? coverage;

  /// Shift-aware attendance remark from backend: On Time, Late, Undertime, Late + Undertime, Incomplete, Invalid Log, Absent, Holiday, Leave.
  final String? attendanceRemark;

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
  static String? _toUtcIso(DateTime? dt) =>
      dt == null ? null : dt.toUtc().toIso8601String();

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
    DateTime? createdAt,
    DateTime? updatedAt,
    String? employeeName,
    String? holidayName,
    String? attendanceRemark,
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
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      employeeName: employeeName ?? this.employeeName,
      holidayName: holidayName ?? this.holidayName,
      attendanceRemark: attendanceRemark ?? this.attendanceRemark,
    );
  }
}

/// Repository for DTR time records. Uses backend API (dtr_daily_summary); Supabase logic commented out.
class TimeRecordRepo {
  TimeRecordRepo._();
  static final TimeRecordRepo instance = TimeRecordRepo._();

  /// List time records for admin (all users). Uses GET /api/dtr-daily-summary.
  Future<List<TimeRecord>> listForAdmin({
    DateTime? startDate,
    DateTime? endDate,
    String? userId,
    String? departmentId,
    int? limit,
  }) async {
    try {
      final params = <String, dynamic>{};
      if (startDate != null)
        params['start_date'] = TimeRecord._toDateOnlyString(startDate);
      if (endDate != null)
        params['end_date'] = TimeRecord._toDateOnlyString(endDate);
      if (userId != null && userId.isNotEmpty) params['employee_id'] = userId;
      if (departmentId != null && departmentId.isNotEmpty)
        params['department_id'] = departmentId;
      if (limit != null) params['limit'] = limit;
      final res = await ApiClient.instance.get<List<dynamic>>(
        '/api/dtr-daily-summary',
        queryParameters: params,
      );
      final data = res.data ?? [];
      return data
          .map((e) => TimeRecord.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
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

  /// Get today's record for a user (for clock in/out).
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

  /// Insert time record (clock in). Uses POST /api/dtr-daily-summary.
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

  /// Update existing record (clock out or admin edit). Uses PUT /api/dtr-daily-summary/:id.
  Future<void> update(TimeRecord record) async {
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
      },
    );
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

  /// Delete record (admin). Uses DELETE /api/dtr-daily-summary/:id.
  Future<void> delete(String id) async {
    await ApiClient.instance.delete('/api/dtr-daily-summary/$id');
  }

  /// Count present today. Uses GET /api/dtr-daily-summary/summary.
  Future<int> countPresentToday() async {
    try {
      final res = await ApiClient.instance.get<Map<String, dynamic>>(
        '/api/dtr-daily-summary/summary',
      );
      final data = res.data;
      return (data?['present_today'] as int?) ?? 0;
    } on DioException catch (_) {
      return 0;
    }
  }

  /// Count late today. Uses GET /api/dtr-daily-summary/summary.
  Future<int> countLateToday() async {
    try {
      final res = await ApiClient.instance.get<Map<String, dynamic>>(
        '/api/dtr-daily-summary/summary',
      );
      final data = res.data;
      return (data?['late_today'] as int?) ?? 0;
    } on DioException catch (_) {
      return 0;
    }
  }

  /// List recent time records for admin dashboard.
  Future<List<TimeRecord>> listRecent({int limit = 20}) async {
    return listForAdmin(limit: limit);
  }
}
