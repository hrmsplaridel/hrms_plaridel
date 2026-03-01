import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/time_record.dart';

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
  const EmployeeOption({required this.id, required this.fullName});
  final String id;
  final String fullName;
}

/// DTR state and operations. Used by admin DTR module and employee clock in/attendance.
class DtrProvider extends ChangeNotifier {
  DtrProvider() {
    _user = Supabase.instance.client.auth.currentUser;
    Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      _user = data.session?.user;
      _todayRecord = null;
      notifyListeners();
    });
  }

  User? _user;
  User? get user => _user;

  List<TimeRecord> _timeRecords = [];
  List<TimeRecord> get timeRecords => List.unmodifiable(_timeRecords);

  DtrSummary _summary = const DtrSummary();
  DtrSummary get summary => _summary;

  List<EmployeeOption> _employees = [];
  List<EmployeeOption> get employees => List.unmodifiable(_employees);

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

  /// Today's record for current user (for clock in/out UI).
  TimeRecord? _todayRecord;
  TimeRecord? get todayRecord => _todayRecord;

  /// Set current user (e.g. after auth change).
  void setUser(User? u) {
    _user = u;
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
  Future<void> loadTimeRecordsForAdmin({
    DateTime? startDate,
    DateTime? endDate,
    String? userId,
    int? limit,
  }) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _tableMissing = false;
      _filterStart = startDate;
      _filterEnd = endDate;
      _filterUserId = userId;
      final list = await TimeRecordRepo.instance.listForAdmin(
        startDate: startDate,
        endDate: endDate,
        userId: userId,
        limit: limit,
      );
      _timeRecords = list;
      _loading = false;
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
      _loading = false;
      notifyListeners();
    }
  }

  /// Load time records for current user (employee).
  Future<void> loadTimeRecordsForUser({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final uid = _user?.id;
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
    final uid = _user?.id;
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

  /// Load employee list for admin filter.
  Future<void> loadEmployees() async {
    try {
      final res = await Supabase.instance.client
          .from('profiles')
          .select('id, full_name')
          .eq('role', 'employee')
          .order('full_name');
      _employees = (res as List)
          .map(
            (e) => EmployeeOption(
              id: (e as Map)['id'] as String,
              fullName: (e['full_name'] as String? ?? 'Unknown'),
            ),
          )
          .toList();
      notifyListeners();
    } catch (_) {
      _employees = [];
      notifyListeners();
    }
  }

  /// Clock in for current user.
  Future<bool> clockIn() async {
    final uid = _user?.id;
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
    } catch (e) {
      _error = e.toString();
      _loading = false;
      notifyListeners();
      return false;
    }
  }

  /// Clock out for current user.
  Future<bool> clockOut() async {
    final uid = _user?.id;
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
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final now = DateTime.now();
      double? hours;
      if (existing.timeIn != null) {
        hours = now.difference(existing.timeIn!).inMinutes / 60.0;
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
