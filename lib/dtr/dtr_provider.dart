import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../api/client.dart';
import '../data/time_record.dart';

// Previously used Supabase for auth; now use setUserFromApi(userId) from AuthProvider.

/// Summary counts for DTR dashboard.
class DtrSummary {
  const DtrSummary({
    this.presentToday = 0,
    this.lateToday = 0,
    this.onLeaveToday,
    this.pendingApproval,
  });

  final int presentToday;
  final int lateToday;
  final int? onLeaveToday;
  final int? pendingApproval;
}

/// Simple employee profile for admin filters.
class EmployeeOption {
  const EmployeeOption({
    required this.id,
    required this.fullName,
    this.employeeNumber,
  });
  final String id;
  final String fullName;

  /// Human-friendly number (1, 2, 3...) for display.
  final int? employeeNumber;

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
  DtrProvider();

  /// Current user id (from API auth). Set via setUserFromApi(auth.user?.id) when using API login.
  String? _userId;
  String? get userId => _userId;

  /// For compatibility: code that checked user != null can use userId != null.
  bool get hasUser => _userId != null;

  List<TimeRecord> _timeRecords = [];
  List<TimeRecord> get timeRecords => List.unmodifiable(_timeRecords);

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

  /// True if current time is past shift end (PM In would be blocked).
  bool get isPmInPastShiftEnd {
    if (_myShiftEndMinutes == null) return false;
    final now = DateTime.now();
    return now.hour * 60 + now.minute > _myShiftEndMinutes!;
  }

  /// Format shift start as "H:MM AM/PM" for display.
  String? get myShiftStartFormatted {
    if (_myShiftStartMinutes == null) return null;
    final h = _myShiftStartMinutes! ~/ 60;
    final m = _myShiftStartMinutes! % 60;
    final isPm = h >= 12;
    final h12 = h > 12 ? h - 12 : (h == 0 ? 12 : h);
    return '${h12}:${m.toString().padLeft(2, '0')} ${isPm ? 'PM' : 'AM'}';
  }

  /// Format shift end as "H:MM AM/PM" for display.
  String? get myShiftEndFormatted {
    if (_myShiftEndMinutes == null) return null;
    final h = _myShiftEndMinutes! ~/ 60;
    final m = _myShiftEndMinutes! % 60;
    final isPm = h >= 12;
    final h12 = h > 12 ? h - 12 : (h == 0 ? 12 : h);
    return '${h12}:${m.toString().padLeft(2, '0')} ${isPm ? 'PM' : 'AM'}';
  }

  /// Set current user id from API auth (e.g. AuthProvider.user?.id). Call after login or when restoring session.
  void setUserFromApi(String? id) {
    if (_userId == id) return;
    _userId = id;
    _todayRecord = null;
    notifyListeners();
  }

  /// Load summary for admin dashboard (present, late, etc.).
  Future<void> loadSummary() async {
    try {
      _error = null;
      _tableMissing = false;
      final present = await TimeRecordRepo.instance.countPresentToday();
      final late = await TimeRecordRepo.instance.countLateToday();
      _summary = DtrSummary(
        presentToday: present,
        lateToday: late,
        onLeaveToday: null, // placeholder until leave module exists
        pendingApproval: null, // placeholder until approval workflow exists
      );
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

  /// Load time records for admin (with optional filters). [limit] caps results for dashboard.
  /// When [silent] is true, does not set [loading] so existing data stays visible during refresh.
  Future<void> loadTimeRecordsForAdmin({
    DateTime? startDate,
    DateTime? endDate,
    String? userId,
    String? departmentId,
    int? limit,
    bool silent = false,
  }) async {
    if (!silent) {
      _loading = true;
      _error = null;
      notifyListeners();
    }
    try {
      _tableMissing = false;
      _filterStart = startDate;
      _filterEnd = endDate;
      _filterUserId = userId;
      _filterDepartmentId = departmentId;
      final list = await TimeRecordRepo.instance.listForAdmin(
        startDate: startDate,
        endDate: endDate,
        userId: userId,
        departmentId: departmentId,
        limit: limit,
      );
      _timeRecords = list;
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

  /// Load time records for current user (employee).
  Future<void> loadTimeRecordsForUser({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final uid = _userId;
    if (uid == null) return;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final list = await TimeRecordRepo.instance.listForUser(
        userId: uid,
        startDate: startDate,
        endDate: endDate,
      );
      _timeRecords = list;
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

  /// Load employee list for admin filter. Optional [departmentId] filters to employees in that department.
  Future<void> loadEmployees({String? departmentId}) async {
    try {
      final params = <String, dynamic>{'role': 'User', 'status': 'Active'};
      if (departmentId != null && departmentId.isNotEmpty) {
        params['department_id'] = departmentId;
      }
      final res = await ApiClient.instance.get<List<dynamic>>(
        '/api/employees',
        queryParameters: params,
      );
      final data = res.data ?? [];
      _employees = data.map((e) {
        final m = e as Map;
        final empNum = m['employee_number'];
        return EmployeeOption(
          id: m['id'] as String,
          fullName: (m['full_name'] as String? ?? 'Unknown'),
          employeeNumber: empNum is int
              ? empNum
              : (empNum != null ? int.tryParse(empNum.toString()) : null),
        );
      }).toList();
      notifyListeners();
    } catch (_) {
      _employees = [];
      notifyListeners();
    }
  }

  /// Load department list for admin filter.
  Future<void> loadDepartments() async {
    try {
      final res = await ApiClient.instance.get<List<dynamic>>(
        '/api/departments',
      );
      final data = res.data ?? [];
      _departments = data
          .map((e) {
            final m = e as Map;
            final id = m['id']?.toString();
            final name = m['name']?.toString() ?? '—';
            return id != null ? DepartmentOption(id: id, name: name) : null;
          })
          .whereType<DepartmentOption>()
          .toList();
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
      await loadTodayRecord();
      if (_filterUserId == null && _filterStart == null) {
        await loadTimeRecordsForAdmin();
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
      _error = e.toString();
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
      await loadTodayRecord();
      await loadTimeRecordsForUser();
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
      await loadTodayRecord();
      if (_filterUserId == null && _filterStart == null) {
        await loadTimeRecordsForAdmin();
      }
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
      await loadTodayRecord();
      await loadTimeRecordsForUser();
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
      _error = e.toString();
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
      await loadTodayRecord();
      await loadTimeRecordsForUser();
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

  /// Add manual entry (admin).
  Future<bool> addManualEntry(TimeRecord record) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      await TimeRecordRepo.instance.upsert(record);
      await loadTimeRecordsForAdmin(
        startDate: _filterStart,
        endDate: _filterEnd,
        userId: _filterUserId,
      );
      await loadSummary();
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

  /// Update entry (admin).
  Future<bool> updateEntry(TimeRecord record) async {
    if (record.id == null) return false;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      await TimeRecordRepo.instance.update(record);
      await loadTimeRecordsForAdmin(
        startDate: _filterStart,
        endDate: _filterEnd,
        userId: _filterUserId,
      );
      await loadSummary();
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

  /// Delete entry (admin).
  Future<bool> deleteEntry(String id) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      await TimeRecordRepo.instance.delete(id);
      await loadTimeRecordsForAdmin(
        startDate: _filterStart,
        endDate: _filterEnd,
        userId: _filterUserId,
      );
      await loadSummary();
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
