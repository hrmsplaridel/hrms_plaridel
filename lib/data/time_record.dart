import 'package:dio/dio.dart';

import '../api/client.dart';

/// One DTR (Daily Time Record) entry: time-in/out for a user on a date.
class TimeRecord {
  const TimeRecord({
    this.id,
    required this.userId,
    required this.recordDate,
    this.timeIn,
    this.timeOut,
    this.totalHours,
    this.status,
    this.remarks,
    this.createdAt,
    this.updatedAt,
    this.employeeName,
  });

  final String? id;
  final String userId;
  final DateTime recordDate;
  final DateTime? timeIn;
  final DateTime? timeOut;
  final double? totalHours;
  /// present | late | absent | on_leave
  final String? status;
  final String? remarks;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  /// Joined from profiles.full_name when listing for admin
  final String? employeeName;

  static const String tableName = 'time_records';

  factory TimeRecord.fromJson(Map<String, dynamic> json) {
    return TimeRecord(
      id: json['id']?.toString(),
      userId: json['user_id'] as String? ?? '',
      recordDate: json['record_date'] != null
          ? DateTime.parse(json['record_date'] as String)
          : DateTime.now(),
      timeIn: json['time_in'] != null
          ? DateTime.tryParse(json['time_in'] as String)
          : null,
      timeOut: json['time_out'] != null
          ? DateTime.tryParse(json['time_out'] as String)
          : null,
      totalHours: _parseDouble(json['total_hours']),
      status: json['status']?.toString(),
      remarks: json['remarks']?.toString(),
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'] as String)
          : null,
      employeeName: _extractEmployeeName(json),
    );
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

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'user_id': userId,
      'record_date': recordDate.toIso8601String().split('T').first,
      'time_in': timeIn?.toIso8601String(),
      'time_out': timeOut?.toIso8601String(),
      'total_hours': totalHours,
      'status': status,
      'remarks': remarks,
      'updated_at': DateTime.now().toIso8601String(),
    };
  }

  TimeRecord copyWith({
    String? id,
    String? userId,
    DateTime? recordDate,
    DateTime? timeIn,
    DateTime? timeOut,
    double? totalHours,
    String? status,
    String? remarks,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? employeeName,
  }) {
    return TimeRecord(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      recordDate: recordDate ?? this.recordDate,
      timeIn: timeIn ?? this.timeIn,
      timeOut: timeOut ?? this.timeOut,
      totalHours: totalHours ?? this.totalHours,
      status: status ?? this.status,
      remarks: remarks ?? this.remarks,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      employeeName: employeeName ?? this.employeeName,
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
    int? limit,
  }) async {
    try {
      final params = <String, dynamic>{};
      if (startDate != null) params['start_date'] = startDate.toIso8601String().split('T').first;
      if (endDate != null) params['end_date'] = endDate.toIso8601String().split('T').first;
      if (userId != null && userId.isNotEmpty) params['employee_id'] = userId;
      if (limit != null) params['limit'] = limit;
      final res = await ApiClient.instance.get<List<dynamic>>(
        '/api/dtr-daily-summary',
        queryParameters: params,
      );
      final data = res.data ?? [];
      return data.map((e) => TimeRecord.fromJson(Map<String, dynamic>.from(e as Map))).toList();
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
    final today = DateTime.now().toIso8601String().split('T').first;
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
        'attendance_date': record.recordDate.toIso8601String().split('T').first,
        'time_in': record.timeIn?.toIso8601String(),
        'time_out': record.timeOut?.toIso8601String(),
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
        'time_in': record.timeIn?.toIso8601String(),
        'time_out': record.timeOut?.toIso8601String(),
        'total_hours': record.totalHours,
        'status': record.status,
        'remarks': record.remarks,
      },
    );
  }

  /// Upsert: get today for user, then update if exists else insert.
  Future<void> upsert(TimeRecord record) async {
    final existing = await getTodayForUser(record.userId);
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
      final res = await ApiClient.instance.get<Map<String, dynamic>>('/api/dtr-daily-summary/summary');
      final data = res.data;
      return (data?['present_today'] as int?) ?? 0;
    } on DioException catch (_) {
      return 0;
    }
  }

  /// Count late today. Uses GET /api/dtr-daily-summary/summary.
  Future<int> countLateToday() async {
    try {
      final res = await ApiClient.instance.get<Map<String, dynamic>>('/api/dtr-daily-summary/summary');
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
