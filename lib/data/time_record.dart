import 'package:supabase_flutter/supabase_flutter.dart';

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

class TimeRecordRepo {
  TimeRecordRepo._();
  static final TimeRecordRepo instance = TimeRecordRepo._();

  SupabaseClient get _client => Supabase.instance.client;

  /// List time records for admin (all users, with profile join).
  /// [startDate] and [endDate] filter by record_date. [limit] caps results.
  Future<List<TimeRecord>> listForAdmin({
    DateTime? startDate,
    DateTime? endDate,
    String? userId,
    int? limit,
  }) async {
    dynamic query = _client.from(TimeRecord.tableName).select('*, profiles!inner(full_name)');
    if (startDate != null) {
      query = query.gte('record_date', startDate.toIso8601String().split('T').first);
    }
    if (endDate != null) {
      query = query.lte('record_date', endDate.toIso8601String().split('T').first);
    }
    if (userId != null && userId.isNotEmpty) {
      query = query.eq('user_id', userId);
    }
    query = query.order('record_date', ascending: false).order('time_in', ascending: false);
    if (limit != null) {
      query = query.limit(limit);
    }

    final res = await query;
    return (res as List)
        .map((e) => _fromRow(e))
        .toList();
  }

  /// List time records for current user (employee).
  Future<List<TimeRecord>> listForUser({
    required String userId,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    dynamic query = _client.from(TimeRecord.tableName).select().eq('user_id', userId);
    if (startDate != null) {
      query = query.gte('record_date', startDate.toIso8601String().split('T').first);
    }
    if (endDate != null) {
      query = query.lte('record_date', endDate.toIso8601String().split('T').first);
    }
    query = query.order('record_date', ascending: false);

    final res = await query;
    return (res as List).map((e) => TimeRecord.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }

  TimeRecord _fromRow(dynamic row) {
    final m = Map<String, dynamic>.from(row as Map);
    final profiles = m['profiles'];
    if (profiles != null && profiles is Map) {
      m['employee_name'] = (profiles as Map<String, dynamic>)['full_name'];
    }
    m.remove('profiles');
    return TimeRecord.fromJson(m);
  }

  /// Get today's record for a user (for clock in/out).
  Future<TimeRecord?> getTodayForUser(String userId) async {
    final today = DateTime.now().toIso8601String().split('T').first;
    final res = await _client
        .from(TimeRecord.tableName)
        .select()
        .eq('user_id', userId)
        .eq('record_date', today)
        .maybeSingle();
    return res == null ? null : TimeRecord.fromJson(Map<String, dynamic>.from(res));
  }

  /// Insert or upsert time record (for clock in).
  Future<TimeRecord> insert(TimeRecord record) async {
    final payload = Map<String, dynamic>.from(record.toJson())..remove('id');
    final res = await _client
        .from(TimeRecord.tableName)
        .insert(payload)
        .select()
        .single();
    return TimeRecord.fromJson(Map<String, dynamic>.from(res));
  }

  /// Update existing record (for clock out or admin edit).
  Future<void> update(TimeRecord record) async {
    if (record.id == null) return;
    await _client
        .from(TimeRecord.tableName)
        .update(record.toJson())
        .eq('id', record.id!);
  }

  /// Upsert: insert or update if exists for (user_id, record_date).
  Future<void> upsert(TimeRecord record) async {
    final payload = Map<String, dynamic>.from(record.toJson())..remove('id');
    await _client.from(TimeRecord.tableName).upsert(
          payload,
          onConflict: 'user_id,record_date',
        );
  }

  /// Delete record (admin only).
  Future<void> delete(String id) async {
    await _client.from(TimeRecord.tableName).delete().eq('id', id);
  }

  /// Count present today (employees with time_in today).
  Future<int> countPresentToday() async {
    final today = DateTime.now().toIso8601String().split('T').first;
    final res = await _client
        .from(TimeRecord.tableName)
        .select()
        .eq('record_date', today)
        .not('time_in', 'is', null);
    return (res as List).length;
  }

  /// Count late today (time_in after 8:00 AM local - configurable later).
  /// Uses 8:00 as default office start.
  Future<int> countLateToday() async {
    final today = DateTime.now();
    final res = await _client
        .from(TimeRecord.tableName)
        .select()
        .eq('record_date', today.toIso8601String().split('T').first)
        .not('time_in', 'is', null);

    int count = 0;
    for (final row in res as List) {
      final timeInStr = (row as Map)['time_in']?.toString();
      if (timeInStr != null) {
        final timeIn = DateTime.tryParse(timeInStr)?.toLocal();
        if (timeIn != null) {
          final officeStart = DateTime(today.year, today.month, today.day, 8, 0);
          if (timeIn.isAfter(officeStart)) count++;
        }
      }
    }
    return count;
  }

  /// List recent time records (last N) for admin dashboard.
  Future<List<TimeRecord>> listRecent({int limit = 20}) async {
    final res = await _client
        .from(TimeRecord.tableName)
        .select('*, profiles!inner(full_name)')
        .order('record_date', ascending: false)
        .order('time_in', ascending: false)
        .limit(limit);

    return (res as List).map((e) => _fromRow(e)).toList();
  }
}
