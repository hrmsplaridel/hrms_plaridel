import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/core/api/config.dart';
import 'package:hrms_plaridel/core/api/user_facing_api_error.dart';
import 'package:hrms_plaridel/features/dtr/attendance/models/time_record.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/repositories/api_leave_repository.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/repositories/leave_repository.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_request.dart';
import 'package:hrms_plaridel/features/dtr/reports/data/dtr_dashboard_analytics_logic.dart';
import 'package:hrms_plaridel/features/dtr/reports/data/dtr_dashboard_analytics_models.dart';

// Previously used Supabase for auth; now use setUserFromApi(userId) from AuthProvider.

/// Payload sent by the backend when DTR data changes over websocket.
class DtrUpdateEvent {
  const DtrUpdateEvent({
    required this.action,
    this.userId,
    this.date,
    this.dateFrom,
    this.dateTo,
    this.userIds = const <String>{},
    this.dates = const <String>{},
    this.raw = const <String, dynamic>{},
  });

  final String action;
  final String? userId;
  final String? date;
  final String? dateFrom;
  final String? dateTo;
  final Set<String> userIds;
  final Set<String> dates;
  final Map<String, dynamic> raw;

  factory DtrUpdateEvent.fromJson(Map<String, dynamic> json) {
    Set<String> stringSet(dynamic value) {
      if (value is List) {
        return value
            .map((item) => item?.toString().trim() ?? '')
            .where((item) => item.isNotEmpty)
            .toSet();
      }
      final single = value?.toString().trim();
      return single == null || single.isEmpty ? <String>{} : {single};
    }

    final directUserId =
        json['userId']?.toString().trim() ?? json['user_id']?.toString().trim();
    final directDate =
        json['date']?.toString().trim() ??
        json['attendance_date']?.toString().trim();
    final userIds = {
      ...stringSet(json['userIds'] ?? json['user_ids']),
      if (directUserId != null && directUserId.isNotEmpty) directUserId,
    };
    final dates = {
      ...stringSet(json['dates']),
      if (directDate != null && directDate.isNotEmpty) directDate,
    };

    return DtrUpdateEvent(
      action: json['action']?.toString() ?? 'dtr_refresh',
      userId: directUserId?.isEmpty == true ? null : directUserId,
      date: directDate?.isEmpty == true ? null : directDate,
      dateFrom: json['dateFrom']?.toString() ?? json['date_from']?.toString(),
      dateTo: json['dateTo']?.toString() ?? json['date_to']?.toString(),
      userIds: userIds,
      dates: dates,
      raw: json,
    );
  }

  bool affectsUser(String? id) {
    final normalized = id?.trim();
    if (userIds.isEmpty && (userId == null || userId!.isEmpty)) return true;
    if (normalized == null || normalized.isEmpty) return false;
    return userIds.contains(normalized) || userId == normalized;
  }

  bool affectsDateRange(DateTime start, DateTime end) {
    final rangeStart = DateTime(start.year, start.month, start.day);
    final rangeEnd = DateTime(end.year, end.month, end.day);

    DateTime? parseDate(String? value) {
      final text = value?.trim();
      if (text == null || text.isEmpty) return null;
      final normalized = text.length >= 10 ? text.substring(0, 10) : text;
      final parsed = DateTime.tryParse(normalized);
      return parsed == null
          ? null
          : DateTime(parsed.year, parsed.month, parsed.day);
    }

    bool overlaps(DateTime from, DateTime to) {
      return !to.isBefore(rangeStart) && !from.isAfter(rangeEnd);
    }

    if (dates.isNotEmpty) {
      return dates
          .map((item) => parseDate(item))
          .whereType<DateTime>()
          .any((day) => overlaps(day, day));
    }

    final from = parseDate(dateFrom);
    final to = parseDate(dateTo);
    if (from != null || to != null) {
      return overlaps(from ?? to!, to ?? from!);
    }

    final single = parseDate(date);
    if (single != null) return overlaps(single, single);
    return true;
  }
}

/// Summary counts for DTR dashboard.
class DtrSummary {
  const DtrSummary({
    this.presentToday = 0,
    this.lateToday = 0,
    this.onLeaveToday = 0,
    this.pendingApproval = 0,
  });

  final int presentToday;
  final int lateToday;
  final int onLeaveToday;
  final int pendingApproval;
}

class _DtrCacheEntry<T> {
  const _DtrCacheEntry(this.value, this.cachedAt);

  final T value;
  final DateTime cachedAt;

  bool isFresh(Duration ttl) => DateTime.now().difference(cachedAt) < ttl;
}

class _DtrRecordsCacheKey {
  const _DtrRecordsCacheKey({
    required this.startDate,
    required this.endDate,
    required this.userId,
    required this.departmentId,
    required this.limit,
    required this.offset,
  });

  final String? startDate;
  final String? endDate;
  final String? userId;
  final String? departmentId;
  final int? limit;
  final int? offset;

  @override
  bool operator ==(Object other) {
    return other is _DtrRecordsCacheKey &&
        other.startDate == startDate &&
        other.endDate == endDate &&
        other.userId == userId &&
        other.departmentId == departmentId &&
        other.limit == limit &&
        other.offset == offset;
  }

  @override
  int get hashCode =>
      Object.hash(startDate, endDate, userId, departmentId, limit, offset);
}

class _EmployeeOptionsCacheKey {
  const _EmployeeOptionsCacheKey({
    required this.departmentId,
    required this.includePrivileged,
  });

  final String? departmentId;
  final bool includePrivileged;

  @override
  bool operator ==(Object other) {
    return other is _EmployeeOptionsCacheKey &&
        other.departmentId == departmentId &&
        other.includePrivileged == includePrivileged;
  }

  @override
  int get hashCode => Object.hash(departmentId, includePrivileged);
}

class _DateRangeCacheKey {
  const _DateRangeCacheKey({required this.startDate, required this.endDate});

  final String startDate;
  final String endDate;

  @override
  bool operator ==(Object other) {
    return other is _DateRangeCacheKey &&
        other.startDate == startDate &&
        other.endDate == endDate;
  }

  @override
  int get hashCode => Object.hash(startDate, endDate);
}

/// Simple employee profile for admin filters.
class EmployeeOption {
  const EmployeeOption({
    required this.id,
    required this.fullName,
    this.employeeNumber,
    this.departmentName,
    this.shiftPunchMode = 'auto',
  });
  final String id;
  final String fullName;

  /// Human-friendly number (1, 2, 3...) for display.
  final int? employeeNumber;

  /// From `current_department_name` when [loadEmployees] runs (for analytics grouping).
  final String? departmentName;

  /// Punch mode of the employee's current assigned shift.
  /// Values: auto, full_day, am_only, pm_only, single_session.
  final String shiftPunchMode;

  /// Display as EMP-001, EMP-002, etc., or "—" if null.
  String get displayEmployeeNo => employeeNumber != null
      ? 'EMP-${employeeNumber!.toString().padLeft(3, '0')}'
      : '—';
}

/// Simple department for admin filters.
class DepartmentOption {
  const DepartmentOption({required this.id, required this.name});
  final String id;
  final String name;
}

/// DTR state and operations. Used by admin DTR module and employee clock in/attendance.
/// Current user id is set via [setUserFromApi] (e.g. from AuthProvider after API login).
class DtrProvider extends ChangeNotifier {
  static const Duration _recordsCacheTtl = Duration(seconds: 60);
  static const Duration _summaryCacheTtl = Duration(seconds: 30);
  static const Duration _referenceCacheTtl = Duration(minutes: 5);

  WebSocketChannel? _wsChannel;
  StreamSubscription<dynamic>? _wsSubscription;
  Timer? _wsReconnectTimer;
  bool _disposed = false;
  final _dtrUpdateController = StreamController<void>.broadcast();
  final _dtrEventController = StreamController<DtrUpdateEvent>.broadcast();
  Stream<void> get onDtrUpdate => _dtrUpdateController.stream;
  Stream<DtrUpdateEvent> get onDtrEvent => _dtrEventController.stream;

  DtrProvider() {
    _initWebSocket();
  }

  void _initWebSocket() {
    if (_disposed) return;
    _wsReconnectTimer?.cancel();
    try {
      final wsUrl =
          '${ApiConfig.baseUrl.replaceFirst('http://', 'ws://').replaceFirst('https://', 'wss://')}/ws/biometrics';
      _closeWebSocket();
      final channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      _wsChannel = channel;
      _wsSubscription = channel.stream.listen(
        (message) {
          try {
            final data = jsonDecode(message);
            if (data is Map && data['event'] == 'dtr_refresh') {
              final event = DtrUpdateEvent.fromJson(
                Map<String, dynamic>.from(data),
              );
              invalidateCachedDtrData();
              _dtrEventController.add(event);
              _dtrUpdateController.add(null);
            }
          } catch (_) {}
        },
        onDone: _scheduleWebSocketReconnect,
        onError: (_) => _scheduleWebSocketReconnect(),
      );
      unawaited(
        channel.ready.catchError((_) {
          if (!_disposed && identical(_wsChannel, channel)) {
            _scheduleWebSocketReconnect();
          }
        }),
      );
    } catch (_) {
      _scheduleWebSocketReconnect();
    }
  }

  void _scheduleWebSocketReconnect() {
    if (_disposed) return;
    _wsReconnectTimer?.cancel();
    _wsReconnectTimer = Timer(const Duration(seconds: 5), _initWebSocket);
  }

  @override
  void dispose() {
    _disposed = true;
    _wsReconnectTimer?.cancel();
    _closeWebSocket();
    _dtrUpdateController.close();
    _dtrEventController.close();
    super.dispose();
  }

  void _closeWebSocket() {
    _wsSubscription?.cancel();
    _wsSubscription = null;
    try {
      _wsChannel?.sink.close();
    } catch (_) {}
    _wsChannel = null;
  }

  /// Current user id (from API auth). Set via setUserFromApi(auth.user?.id) when using API login.
  String? _userId;
  String? get userId => _userId;

  /// For compatibility: code that checked user != null can use userId != null.
  bool get hasUser => _userId != null;

  List<TimeRecord> _timeRecords = [];
  List<TimeRecord> get timeRecords => List.unmodifiable(_timeRecords);

  /// Admin dashboard analytics window (last 30 days); isolated from [timeRecords] / Time Logs.
  List<TimeRecord> _dashboardAnalyticsRecords = [];
  List<TimeRecord> get dashboardAnalyticsRecords =>
      List.unmodifiable(_dashboardAnalyticsRecords);

  bool _dashboardAnalyticsLoading = false;
  bool get dashboardAnalyticsLoading => _dashboardAnalyticsLoading;

  DtrDashboardAnalyticsSnapshot? _analyticsSnapshot;
  DtrDashboardAnalyticsSnapshot? get analyticsSnapshot => _analyticsSnapshot;

  /// Selected department name for charts (`null` or "All departments" = no filter).
  String? _analyticsDepartmentName;
  String? get analyticsDepartmentName => _analyticsDepartmentName;

  static const String analyticsAllDepartmentsLabel = 'All departments';

  final LeaveRepository _leaveRepository = const ApiLeaveRepository();
  final Map<_DtrRecordsCacheKey, _DtrCacheEntry<List<TimeRecord>>>
  _recordsCache = {};
  final Map<_EmployeeOptionsCacheKey, _DtrCacheEntry<List<EmployeeOption>>>
  _employeesCache = {};
  final Map<_DateRangeCacheKey, _DtrCacheEntry<Map<String, double>>>
  _leaveDistributionCache = {};
  _DtrCacheEntry<DtrSummary>? _summaryCache;
  _DtrCacheEntry<List<DepartmentOption>>? _departmentsCache;

  DtrSummary _summary = const DtrSummary();
  DtrSummary get summary => _summary;

  List<EmployeeOption> _employees = [];
  List<EmployeeOption> get employees => List.unmodifiable(_employees);

  List<DepartmentOption> _departments = [];
  List<DepartmentOption> get departments => List.unmodifiable(_departments);

  bool _loading = false;
  bool get loading => _loading;

  String? _error;
  String? get error => _error;

  /// True when Supabase returns PGRST205 (table not found) - time_records not created yet.
  bool _tableMissing = false;
  bool get tableMissing => _tableMissing;

  static bool _isTableNotFoundError(dynamic e) {
    final s = e.toString().toLowerCase();
    return s.contains('pgrst205') ||
        s.contains('could not find the table') ||
        (s.contains('relation') &&
            s.contains('time_records') &&
            s.contains('does not exist')) ||
        s.contains('perhaps you meant the table');
  }

  DateTime? _filterStart;
  DateTime? _filterEnd;
  DateTime? get filterStart => _filterStart;
  DateTime? get filterEnd => _filterEnd;

  String? _filterUserId;
  String? get filterUserId => _filterUserId;

  String? _filterDepartmentId;
  String? get filterDepartmentId => _filterDepartmentId;

  /// Today's record for current user (for clock in/out UI).
  TimeRecord? _todayRecord;
  TimeRecord? get todayRecord => _todayRecord;

  /// Shift start time in minutes from midnight (from /my-shift-today). Null = no shift or no restriction.
  int? _myShiftStartMinutes;
  int? get myShiftStartMinutes => _myShiftStartMinutes;

  /// Shift end time in minutes from midnight (from /my-shift-today). Null = no shift or no restriction.
  int? _myShiftEndMinutes;
  int? get myShiftEndMinutes => _myShiftEndMinutes;

  /// True if current time is before shift start (clock-in should be blocked).
  /// Allows clocking in 30 minutes before shift start as a grace window.
  bool get isBeforeShiftStart {
    if (_myShiftStartMinutes == null) return false;
    final now = DateTime.now();
    final nowMinutes = now.hour * 60 + now.minute;
    // Allow clock-in 30 minutes before shift start
    return nowMinutes < (_myShiftStartMinutes! - 30);
  }

  /// True if current time is past shift end (ALL clock actions should be blocked).
  bool get isPastShiftEnd {
    if (_myShiftEndMinutes == null) return false;
    final now = DateTime.now();
    return now.hour * 60 + now.minute > _myShiftEndMinutes!;
  }

  /// Legacy alias for backward compatibility.
  bool get isPmInPastShiftEnd => isPastShiftEnd;

  /// True if current time is outside the allowed shift window (before start or after end).
  bool get isOutsideShiftWindow => isBeforeShiftStart || isPastShiftEnd;

  /// Format shift start as "H:MM AM/PM" for display.
  String? get myShiftStartFormatted {
    if (_myShiftStartMinutes == null) return null;
    final h = _myShiftStartMinutes! ~/ 60;
    final m = _myShiftStartMinutes! % 60;
    final isPm = h >= 12;
    final h12 = h > 12 ? h - 12 : (h == 0 ? 12 : h);
    return '$h12:${m.toString().padLeft(2, '0')} ${isPm ? 'PM' : 'AM'}';
  }

  /// Format shift end as "H:MM AM/PM" for display.
  String? get myShiftEndFormatted {
    if (_myShiftEndMinutes == null) return null;
    final h = _myShiftEndMinutes! ~/ 60;
    final m = _myShiftEndMinutes! % 60;
    final isPm = h >= 12;
    final h12 = h > 12 ? h - 12 : (h == 0 ? 12 : h);
    return '$h12:${m.toString().padLeft(2, '0')} ${isPm ? 'PM' : 'AM'}';
  }

  /// Set current user id from API auth (e.g. AuthProvider.user?.id). Call after login or when restoring session.
  void setUserFromApi(String? id) {
    if (_userId == id) return;
    _userId = id;
    _todayRecord = null;
    invalidateCachedDtrData(includeReferenceData: true);
    notifyListeners();
  }

  static String? _normalizeOptional(String? value) {
    final text = value?.trim();
    return text == null || text.isEmpty ? null : text;
  }

  static String? _dateKey(DateTime? date) {
    if (date == null) return null;
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  static _DtrRecordsCacheKey _recordsKey({
    DateTime? startDate,
    DateTime? endDate,
    String? userId,
    String? departmentId,
    int? limit,
    int? offset,
  }) {
    return _DtrRecordsCacheKey(
      startDate: _dateKey(startDate),
      endDate: _dateKey(endDate),
      userId: _normalizeOptional(userId),
      departmentId: _normalizeOptional(departmentId),
      limit: limit,
      offset: offset,
    );
  }

  List<TimeRecord>? _readRecordsCache(_DtrRecordsCacheKey key) {
    final entry = _recordsCache[key];
    if (entry == null || !entry.isFresh(_recordsCacheTtl)) return null;
    return List<TimeRecord>.from(entry.value);
  }

  void _writeRecordsCache(_DtrRecordsCacheKey key, List<TimeRecord> records) {
    _recordsCache[key] = _DtrCacheEntry<List<TimeRecord>>(
      List<TimeRecord>.unmodifiable(records),
      DateTime.now(),
    );
  }

  /// Clears cached DTR reads. Call this after writes/imports or external DTR refresh events.
  void invalidateCachedDtrData({
    bool includeReferenceData = false,
    bool notify = false,
  }) {
    _recordsCache.clear();
    _leaveDistributionCache.clear();
    _summaryCache = null;
    if (includeReferenceData) {
      _employeesCache.clear();
      _departmentsCache = null;
    }
    if (notify) notifyListeners();
  }

  /// Load summary for admin dashboard (present, late, on leave, pending — from `/summary`).
  Future<void> loadSummary({bool forceRefresh = false}) async {
    final cached =
        !forceRefresh && _summaryCache?.isFresh(_summaryCacheTtl) == true
        ? _summaryCache!.value
        : null;
    if (cached != null) {
      _summary = cached;
      notifyListeners();
      return;
    }
    try {
      _error = null;
      _tableMissing = false;
      final c = await TimeRecordRepo.instance.fetchSummaryCounts();
      _summary = DtrSummary(
        presentToday: c.presentToday,
        lateToday: c.lateToday,
        onLeaveToday: c.onLeaveToday,
        pendingApproval: c.pendingApproval,
      );
      _summaryCache = _DtrCacheEntry<DtrSummary>(_summary, DateTime.now());
      notifyListeners();
    } catch (e) {
      if (_isTableNotFoundError(e)) {
        _tableMissing = true;
        _error = null;
        _summary = const DtrSummary();
      } else {
        _error = e.toString();
      }
      notifyListeners();
    }
  }

  /// Load time records for admin (with optional filters).
  /// When [silent] is true, does not set [loading] so existing data stays visible during refresh.
  ///
  /// When [forDashboardAnalytics] is true, loads the last 30 days into [dashboardAnalyticsRecords]
  /// and updates [analyticsSnapshot] without touching [timeRecords] or filter fields (Time Logs safe).
  Future<void> loadTimeRecordsForAdmin({
    DateTime? startDate,
    DateTime? endDate,
    String? userId,
    String? departmentId,
    int? limit,
    bool silent = false,
    bool forDashboardAnalytics = false,
    bool forceRefresh = false,
  }) async {
    if (forDashboardAnalytics) {
      await _loadDashboardAnalyticsData(forceRefresh: forceRefresh);
      return;
    }
    final normalizedUserId = _normalizeOptional(userId);
    final normalizedDepartmentId = _normalizeOptional(departmentId);
    final cacheKey = _recordsKey(
      startDate: startDate,
      endDate: endDate,
      userId: normalizedUserId,
      departmentId: normalizedDepartmentId,
      limit: limit,
    );
    final cached = forceRefresh ? null : _readRecordsCache(cacheKey);
    if (cached != null) {
      _tableMissing = false;
      _error = null;
      _filterStart = startDate;
      _filterEnd = endDate;
      _filterUserId = normalizedUserId;
      _filterDepartmentId = normalizedDepartmentId;
      _timeRecords = cached;
      if (!silent) _loading = false;
      notifyListeners();
      return;
    }
    if (!silent) {
      _loading = true;
      _error = null;
      notifyListeners();
    }
    try {
      _tableMissing = false;
      _filterStart = startDate;
      _filterEnd = endDate;
      _filterUserId = normalizedUserId;
      _filterDepartmentId = normalizedDepartmentId;
      final list = await TimeRecordRepo.instance.listForAdmin(
        startDate: startDate,
        endDate: endDate,
        userId: normalizedUserId,
        departmentId: normalizedDepartmentId,
        limit: limit,
      );
      _writeRecordsCache(cacheKey, list);
      _timeRecords = List<TimeRecord>.from(list);
      if (!silent) _loading = false;
      notifyListeners();
    } catch (e) {
      if (_isTableNotFoundError(e)) {
        _tableMissing = true;
        _error = null;
        _timeRecords = [];
      } else {
        _error = e.toString();
        _timeRecords =
            []; // Show sample data on any load failure for flexible UI
      }
      if (!silent) _loading = false;
      notifyListeners();
    }
  }

  Map<String, double> _dashboardLeaveByType = {};
  bool _dashboardLeaveFetchOk = false;

  Future<void> _loadDashboardAnalyticsData({bool forceRefresh = false}) async {
    if (_dashboardAnalyticsLoading) return;
    final now = DateTime.now();
    final endDay = DateTime(now.year, now.month, now.day);
    final startDay = endDay.subtract(const Duration(days: 29));
    final cacheKey = _recordsKey(startDate: startDay, endDate: endDay);
    final cached = forceRefresh ? null : _readRecordsCache(cacheKey);
    if (cached != null) {
      _tableMissing = false;
      _dashboardAnalyticsRecords = cached;
      if (_employees.isEmpty) {
        await loadEmployees(includePrivileged: true);
      }
      if (_departments.isEmpty) {
        await loadDepartments();
      }
      _dashboardLeaveByType = {};
      _dashboardLeaveFetchOk = false;
      try {
        _dashboardLeaveByType = await _loadLeaveDistributionForWindow(
          startDay,
          endDay,
          forceRefresh: forceRefresh,
        );
        _dashboardLeaveFetchOk = true;
      } catch (_) {
        _dashboardLeaveByType = {};
      }
      _recomputeAnalyticsSnapshot();
      notifyListeners();
      return;
    }
    _dashboardAnalyticsLoading = true;
    notifyListeners();
    try {
      _tableMissing = false;
      final list = await TimeRecordRepo.instance.listForAdmin(
        startDate: startDay,
        endDate: endDay,
      );
      _writeRecordsCache(cacheKey, list);
      _dashboardAnalyticsRecords = List<TimeRecord>.from(list);
      if (_employees.isEmpty) {
        await loadEmployees(includePrivileged: true);
      }
      if (_departments.isEmpty) {
        await loadDepartments();
      }
      _dashboardLeaveByType = {};
      _dashboardLeaveFetchOk = false;
      try {
        _dashboardLeaveByType = await _loadLeaveDistributionForWindow(
          startDay,
          endDay,
          forceRefresh: forceRefresh,
        );
        _dashboardLeaveFetchOk = true;
      } catch (_) {
        _dashboardLeaveByType = {};
      }
      _recomputeAnalyticsSnapshot();
    } catch (e) {
      if (_isTableNotFoundError(e)) {
        _tableMissing = true;
        _dashboardAnalyticsRecords = [];
        _analyticsSnapshot = null;
      }
    } finally {
      _dashboardAnalyticsLoading = false;
      notifyListeners();
    }
  }

  Future<Map<String, double>> _loadLeaveDistributionForWindow(
    DateTime start,
    DateTime end, {
    bool forceRefresh = false,
  }) async {
    final startKey = _dateKey(start)!;
    final endKey = _dateKey(end)!;
    final cacheKey = _DateRangeCacheKey(startDate: startKey, endDate: endKey);
    final cached = _leaveDistributionCache[cacheKey];
    if (!forceRefresh && cached != null && cached.isFresh(_recordsCacheTtl)) {
      return Map<String, double>.from(cached.value);
    }
    final list = await _leaveRepository.listRequests(
      query: const LeaveRequestQuery(
        status: LeaveRequestStatus.approved,
        limit: 500,
      ),
    );
    final map = <String, double>{};
    for (final r in list) {
      if (r.startDate == null || r.endDate == null) continue;
      final rs = DateTime(
        r.startDate!.year,
        r.startDate!.month,
        r.startDate!.day,
      );
      final re = DateTime(r.endDate!.year, r.endDate!.month, r.endDate!.day);
      if (re.isBefore(start) || rs.isAfter(end)) continue;
      final label = r.leaveTypeLabel;
      final days = r.workingDaysApplied ?? 1.0;
      map[label] = (map[label] ?? 0) + days;
    }
    _leaveDistributionCache[cacheKey] = _DtrCacheEntry<Map<String, double>>(
      Map<String, double>.unmodifiable(map),
      DateTime.now(),
    );
    return map;
  }

  void _recomputeAnalyticsSnapshot() {
    final now = DateTime.now();
    final endDay = DateTime(now.year, now.month, now.day);
    final map = _employeeDepartmentByUserId();
    _analyticsSnapshot = computeDashboardAnalytics(
      records: _dashboardAnalyticsRecords,
      userIdToDepartment: map,
      windowEnd: endDay,
      departmentFilter: _analyticsDepartmentName,
      leaveDaysByType: _dashboardLeaveByType,
      leaveDataAvailable: _dashboardLeaveFetchOk,
    );
  }

  Map<String, String> _employeeDepartmentByUserId() {
    final m = <String, String>{};
    for (final e in _employees) {
      final d = e.departmentName?.trim();
      if (d != null && d.isNotEmpty) m[e.id] = d;
    }
    return m;
  }

  /// Updates department filter for dashboard charts/table only (no API call).
  void setAnalyticsDepartmentFilter(String? departmentDisplayName) {
    final v =
        (departmentDisplayName == null ||
            departmentDisplayName == analyticsAllDepartmentsLabel)
        ? null
        : departmentDisplayName;
    if (_analyticsDepartmentName == v) return;
    _analyticsDepartmentName = v;
    _recomputeAnalyticsSnapshot();
    notifyListeners();
  }

  /// Load time records for current user (employee).
  Future<void> loadTimeRecordsForUser({
    DateTime? startDate,
    DateTime? endDate,
    bool forceRefresh = false,
  }) async {
    final uid = _userId;
    if (uid == null) return;
    final cacheKey = _recordsKey(
      startDate: startDate,
      endDate: endDate,
      userId: uid,
      limit: 500,
    );
    final cached = forceRefresh ? null : _readRecordsCache(cacheKey);
    if (cached != null) {
      _tableMissing = false;
      _error = null;
      _filterStart = startDate;
      _filterEnd = endDate;
      _filterUserId = uid;
      _filterDepartmentId = null;
      _timeRecords = cached;
      _loading = false;
      notifyListeners();
      return;
    }
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final list = await TimeRecordRepo.instance.listForUser(
        userId: uid,
        startDate: startDate,
        endDate: endDate,
      );
      _writeRecordsCache(cacheKey, list);
      _filterStart = startDate;
      _filterEnd = endDate;
      _filterUserId = uid;
      _filterDepartmentId = null;
      _timeRecords = List<TimeRecord>.from(list);
      _loading = false;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      _loading = false;
      notifyListeners();
    }
  }

  /// Load today's record for current user (clock in/out).
  Future<void> loadTodayRecord() async {
    final uid = _userId;
    if (uid == null) return;
    try {
      final rec = await TimeRecordRepo.instance.getTodayForUser(uid);
      _todayRecord = rec;
      notifyListeners();
    } catch (_) {
      _todayRecord = null;
      notifyListeners();
    }
  }

  /// Load current user's shift start/end time for today (for clock-in validation).
  Future<void> loadMyShiftToday() async {
    try {
      final res = await ApiClient.instance.get<Map<String, dynamic>>(
        '/api/dtr-daily-summary/my-shift-today',
      );
      final data = res.data;
      _myShiftStartMinutes = data?['start_minutes'] as int?;
      _myShiftEndMinutes = data?['end_minutes'] as int?;
      notifyListeners();
    } catch (_) {
      _myShiftStartMinutes = null;
      _myShiftEndMinutes = null;
      notifyListeners();
    }
  }

  /// Load employee list for admin filter.
  ///
  /// By default this keeps the historical behavior (only regular users).
  /// Set [includePrivileged] to true when admin/supervisor accounts should
  /// also appear in the selector.
  Future<void> loadEmployees({
    String? departmentId,
    bool includePrivileged = false,
    bool forceRefresh = false,
  }) async {
    final normalizedDepartmentId = _normalizeOptional(departmentId);
    final cacheKey = _EmployeeOptionsCacheKey(
      departmentId: normalizedDepartmentId,
      includePrivileged: includePrivileged,
    );
    final cached = _employeesCache[cacheKey];
    if (!forceRefresh && cached != null && cached.isFresh(_referenceCacheTtl)) {
      _employees = List<EmployeeOption>.from(cached.value);
      notifyListeners();
      return;
    }
    try {
      final params = <String, dynamic>{'status': 'Active'};
      if (!includePrivileged) {
        params['role'] = 'User';
      }
      if (normalizedDepartmentId != null) {
        params['department_id'] = normalizedDepartmentId;
      }
      final res = await ApiClient.instance.get<List<dynamic>>(
        '/api/employees',
        queryParameters: params,
      );
      final data = res.data ?? [];
      final employees = data.map((e) {
        final m = e as Map;
        final empNum = m['employee_number'];
        return EmployeeOption(
          id: m['id'] as String,
          fullName: (m['full_name'] as String? ?? 'Unknown'),
          employeeNumber: empNum is int
              ? empNum
              : (empNum != null ? int.tryParse(empNum.toString()) : null),
          departmentName: m['current_department_name']?.toString(),
          shiftPunchMode: m['current_shift_punch_mode']?.toString() ?? 'auto',
        );
      }).toList();
      _employeesCache[cacheKey] = _DtrCacheEntry<List<EmployeeOption>>(
        List<EmployeeOption>.unmodifiable(employees),
        DateTime.now(),
      );
      _employees = List<EmployeeOption>.from(employees);
      notifyListeners();
    } catch (_) {
      _employees = [];
      notifyListeners();
    }
  }

  /// Load department list for admin filter.
  Future<void> loadDepartments({bool forceRefresh = false}) async {
    if (!forceRefresh &&
        _departmentsCache != null &&
        _departmentsCache!.isFresh(_referenceCacheTtl)) {
      _departments = List<DepartmentOption>.from(_departmentsCache!.value);
      notifyListeners();
      return;
    }
    try {
      final res = await ApiClient.instance.get<List<dynamic>>(
        '/api/departments',
      );
      final data = res.data ?? [];
      final departments = data
          .map((e) {
            final m = e as Map;
            final id = m['id']?.toString();
            final name = m['name']?.toString() ?? '—';
            return id != null ? DepartmentOption(id: id, name: name) : null;
          })
          .whereType<DepartmentOption>()
          .toList();
      _departmentsCache = _DtrCacheEntry<List<DepartmentOption>>(
        List<DepartmentOption>.unmodifiable(departments),
        DateTime.now(),
      );
      _departments = List<DepartmentOption>.from(departments);
      notifyListeners();
    } catch (_) {
      _departments = [];
      notifyListeners();
    }
  }

  /// Clock in (AM In) for current user.
  Future<bool> clockIn() async {
    final uid = _userId;
    if (uid == null) return false;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final existing = await TimeRecordRepo.instance.getTodayForUser(uid);
      if (existing != null) {
        _error = 'Already clocked in today.';
        _loading = false;
        notifyListeners();
        return false;
      }
      final record = TimeRecord(
        userId: uid,
        recordDate: today,
        timeIn: now,
        breakOut: null,
        breakIn: null,
        timeOut: null,
        totalHours: null,
        status: 'present',
      );
      await TimeRecordRepo.instance.insert(record);
      invalidateCachedDtrData();
      await loadTodayRecord();
      if (_filterUserId == null && _filterStart == null) {
        await loadTimeRecordsForAdmin(forceRefresh: true);
      }
      _loading = false;
      notifyListeners();
      return true;
    } on DioException catch (e) {
      _error = (e.response?.data is Map && e.response?.data['error'] != null)
          ? e.response!.data['error'] as String
          : e.message ?? 'Clock-in failed.';
      _loading = false;
      notifyListeners();
      return false;
    } catch (e) {
      _error = userFacingApiError(e);
      _loading = false;
      notifyListeners();
      return false;
    }
  }

  /// Clock AM Out (lunch out).
  Future<bool> clockAmOut() async {
    final uid = _userId;
    if (uid == null) return false;
    final existing =
        _todayRecord ?? await TimeRecordRepo.instance.getTodayForUser(uid);
    if (existing == null || existing.breakOut != null) {
      _error = existing == null
          ? 'No clock-in found for today.'
          : 'Already clocked out (AM Out).';
      notifyListeners();
      return false;
    }
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final now = DateTime.now();
      final updated = existing.copyWith(breakOut: now);
      await TimeRecordRepo.instance.update(updated);
      invalidateCachedDtrData();
      await loadTodayRecord();
      await loadTimeRecordsForUser(forceRefresh: true);
      _loading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = userFacingApiError(e);
      _loading = false;
      notifyListeners();
      return false;
    }
  }

  /// PM In as first punch (afternoon arrival) - no AM punch, AM is absent.
  Future<bool> clockPmInAsFirst() async {
    final uid = _userId;
    if (uid == null) return false;
    final existing = await TimeRecordRepo.instance.getTodayForUser(uid);
    if (existing != null) {
      _error = 'Already have a record for today. Use PM In or PM Out.';
      notifyListeners();
      return false;
    }
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final record = TimeRecord(
        userId: uid,
        recordDate: today,
        timeIn: null,
        breakOut: null,
        breakIn: now,
        timeOut: null,
        totalHours: null,
        status: 'absent',
      );
      await TimeRecordRepo.instance.insert(record);
      invalidateCachedDtrData();
      await loadTodayRecord();
      if (_filterUserId == null && _filterStart == null) {
        await loadTimeRecordsForAdmin(forceRefresh: true);
      }
      _loading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = userFacingApiError(e);
      _loading = false;
      notifyListeners();
      return false;
    }
  }

  /// Clock PM In (return from lunch).
  Future<bool> clockPmIn() async {
    final uid = _userId;
    if (uid == null) return false;
    final existing =
        _todayRecord ?? await TimeRecordRepo.instance.getTodayForUser(uid);
    if (existing == null ||
        existing.breakOut == null ||
        existing.breakIn != null) {
      _error = existing == null
          ? 'No clock-in found for today.'
          : existing.breakOut == null
          ? 'Please clock AM Out first.'
          : 'Already clocked in (PM In).';
      notifyListeners();
      return false;
    }
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final now = DateTime.now();
      final updated = existing.copyWith(breakIn: now);
      await TimeRecordRepo.instance.update(updated);
      invalidateCachedDtrData();
      await loadTodayRecord();
      await loadTimeRecordsForUser(forceRefresh: true);
      _loading = false;
      notifyListeners();
      return true;
    } on DioException catch (e) {
      _error = (e.response?.data is Map && e.response?.data['error'] != null)
          ? e.response!.data['error'] as String
          : e.message ?? 'PM clock-in failed.';
      _loading = false;
      notifyListeners();
      return false;
    } catch (e) {
      _error = userFacingApiError(e);
      _loading = false;
      notifyListeners();
      return false;
    }
  }

  /// Clock out (PM Out) for current user.
  Future<bool> clockOut() async {
    final uid = _userId;
    if (uid == null) return false;
    final existing =
        _todayRecord ?? await TimeRecordRepo.instance.getTodayForUser(uid);
    if (existing == null || existing.timeOut != null) {
      _error = existing == null
          ? 'No clock-in found for today.'
          : 'Already clocked out.';
      notifyListeners();
      return false;
    }
    if (existing.breakOut != null && existing.breakIn == null) {
      _error = 'Please clock PM In first.';
      notifyListeners();
      return false;
    }
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final now = DateTime.now();
      double? hours;
      if (existing.timeIn != null) {
        if (existing.breakOut != null && existing.breakIn != null) {
          hours =
              (existing.breakOut!.difference(existing.timeIn!).inMinutes +
                  now.difference(existing.breakIn!).inMinutes) /
              60.0;
        } else {
          hours = now.difference(existing.timeIn!).inMinutes / 60.0;
        }
      } else if (existing.breakIn != null) {
        hours = now.difference(existing.breakIn!).inMinutes / 60.0;
      }
      final updated = existing.copyWith(timeOut: now, totalHours: hours);
      await TimeRecordRepo.instance.update(updated);
      invalidateCachedDtrData();
      await loadTodayRecord();
      await loadTimeRecordsForUser(forceRefresh: true);
      _loading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = userFacingApiError(e);
      _loading = false;
      notifyListeners();
      return false;
    }
  }

  /// Add manual entry (admin).
  Future<bool> addManualEntry(TimeRecord record) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      await TimeRecordRepo.instance.upsert(record);
      invalidateCachedDtrData();
      await loadTimeRecordsForAdmin(
        startDate: _filterStart,
        endDate: _filterEnd,
        userId: _filterUserId,
        departmentId: _filterDepartmentId,
        forceRefresh: true,
      );
      await loadSummary(forceRefresh: true);
      _loading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = userFacingApiError(e);
      _loading = false;
      notifyListeners();
      return false;
    }
  }

  /// Update entry (admin).
  Future<bool> updateEntry(TimeRecord record) async {
    if (record.id == null) return false;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      await TimeRecordRepo.instance.update(record);
      invalidateCachedDtrData();
      await loadTimeRecordsForAdmin(
        startDate: _filterStart,
        endDate: _filterEnd,
        userId: _filterUserId,
        departmentId: _filterDepartmentId,
        forceRefresh: true,
      );
      await loadSummary(forceRefresh: true);
      _loading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = userFacingApiError(e);
      _loading = false;
      notifyListeners();
      return false;
    }
  }

  /// Delete entry (admin).
  Future<bool> deleteEntry(String id) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      await TimeRecordRepo.instance.delete(id);
      invalidateCachedDtrData();
      await loadTimeRecordsForAdmin(
        startDate: _filterStart,
        endDate: _filterEnd,
        userId: _filterUserId,
        departmentId: _filterDepartmentId,
        forceRefresh: true,
      );
      await loadSummary(forceRefresh: true);
      _loading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      _loading = false;
      notifyListeners();
      return false;
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
