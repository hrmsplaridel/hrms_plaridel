import 'package:hrms_plaridel/features/dtr/attendance/models/time_record.dart';
import 'package:hrms_plaridel/features/dtr/reports/data/dtr_dashboard_analytics_models.dart';

/// Calendar day key YYYY-MM-DD (local).
String _dayKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

bool _isLate(TimeRecord r) {
  final s = (r.status ?? '').toLowerCase();
  if (s == 'late') return true;
  if ((r.pmStatus ?? '').toLowerCase() == 'late') return true;
  if ((r.lateMinutes ?? 0) > 0) return true;
  final ar = (r.attendanceRemark ?? '').toLowerCase();
  if (ar.contains('late')) return true;
  return false;
}

bool _isExplicitAbsent(TimeRecord r) =>
    (r.status ?? '').toLowerCase() == 'absent';

/// Undertime for trend: backend `undertime_minutes` and/or remark (aligned with [TimeRecord] docs).
bool _hasUndertime(TimeRecord r) {
  if ((r.status ?? '').toLowerCase() == 'on_leave') return false;
  if ((r.undertimeMinutes ?? 0) > 0) return true;
  final ar = (r.attendanceRemark ?? '').toLowerCase();
  return ar.contains('undertime');
}

bool _hasAttendanceActivity(TimeRecord r) {
  return r.timeIn != null ||
      r.breakOut != null ||
      r.breakIn != null ||
      r.timeOut != null;
}

DateTime? _latestAttendanceActivityAt(TimeRecord r) {
  DateTime? latest;
  for (final value in [r.timeIn, r.breakOut, r.breakIn, r.timeOut]) {
    if (value == null) continue;
    if (latest == null || value.isAfter(latest)) latest = value;
  }
  return latest;
}

DateTime? _displayAttendanceActivityAt(TimeRecord r) {
  return r.timeIn ?? r.breakIn ?? r.breakOut ?? r.timeOut;
}

/// Build 30 consecutive calendar days ending at [windowEnd] (inclusive).
List<DateTime> _daysWindow(DateTime windowEnd) {
  final end = _dateOnly(windowEnd);
  return List<DateTime>.generate(30, (i) {
    return end.subtract(Duration(days: 29 - i));
  });
}

/// Filter records to [departmentName] == null for all, else employee's department must match.
List<TimeRecord> _filterByDepartment(
  List<TimeRecord> records,
  Map<String, String> userIdToDepartment,
  String? departmentName,
) {
  if (departmentName == null || departmentName == 'All departments') {
    return records;
  }
  return records.where((r) {
    final d = userIdToDepartment[r.userId]?.trim() ?? '';
    return d == departmentName;
  }).toList();
}

/// One count per (employee, calendar day) per issue category, grouped by department label.
Map<String, int> _distinctIssueDaysByDepartment({
  required List<TimeRecord> filtered,
  required Map<String, String> userIdToDepartment,
  required bool Function(TimeRecord r) qualifies,
}) {
  final perDept = <String, Set<String>>{};
  for (final r in filtered) {
    if (!qualifies(r)) continue;
    final dept = userIdToDepartment[r.userId]?.trim();
    final label = (dept != null && dept.isNotEmpty) ? dept : 'Unassigned';
    final dayKey = _dayKey(_dateOnly(r.recordDate));
    final issueKey = '${r.userId}|$dayKey';
    perDept.putIfAbsent(label, () => <String>{}).add(issueKey);
  }
  return {for (final e in perDept.entries) e.key: e.value.length};
}

DtrDashboardAnalyticsSnapshot computeDashboardAnalytics({
  required List<TimeRecord> records,
  required Map<String, String> userIdToDepartment,
  required DateTime windowEnd,
  String? departmentFilter,
  Map<String, double> leaveDaysByType = const {},
  bool leaveDataAvailable = true,
}) {
  final days = _daysWindow(windowEnd);
  final windowStart = days.first;
  final filtered = _filterByDepartment(
    records,
    userIdToDepartment,
    departmentFilter,
  );

  final byDay = <String, List<TimeRecord>>{};
  for (final r in filtered) {
    final k = _dayKey(_dateOnly(r.recordDate));
    byDay.putIfAbsent(k, () => []).add(r);
  }

  final presentByDay = List<int>.filled(30, 0);
  final lateByDay = List<int>.filled(30, 0);
  final undertimeByDay = List<int>.filled(30, 0);
  final absentByDay = List<int>.filled(30, 0);

  for (var i = 0; i < 30; i++) {
    final k = _dayKey(days[i]);
    final list = byDay[k] ?? const [];
    for (final r in list) {
      final st = (r.status ?? '').toLowerCase();
      if (_isExplicitAbsent(r)) {
        absentByDay[i]++;
      } else if (_isLate(r)) {
        lateByDay[i]++;
      } else if (r.timeIn != null && st != 'on_leave') {
        presentByDay[i]++;
      }
      if (!_isExplicitAbsent(r) && _hasUndertime(r)) {
        undertimeByDay[i]++;
      }
    }
  }

  final lateByDept = _distinctIssueDaysByDepartment(
    filtered: filtered,
    userIdToDepartment: userIdToDepartment,
    qualifies: _isLate,
  );
  final undertimeByDept = _distinctIssueDaysByDepartment(
    filtered: filtered,
    userIdToDepartment: userIdToDepartment,
    qualifies: (r) => !_isExplicitAbsent(r) && _hasUndertime(r),
  );

  final sortedRecent = filtered.where(_hasAttendanceActivity).toList()
    ..sort((a, b) {
      final ad = _dateOnly(a.recordDate);
      final bd = _dateOnly(b.recordDate);
      final c = bd.compareTo(ad);
      if (c != 0) return c;
      final at = _latestAttendanceActivityAt(a);
      final bt = _latestAttendanceActivityAt(b);
      if (at == null && bt == null) return 0;
      if (at == null) return 1;
      if (bt == null) return -1;
      return bt.compareTo(at);
    });

  final recentRows = <DtrRecentActivityRow>[];
  for (final r in sortedRecent.take(20)) {
    recentRows.add(
      DtrRecentActivityRow(
        employeeName: (r.employeeName ?? '—').trim().isEmpty
            ? '—'
            : r.employeeName!.trim(),
        department: userIdToDepartment[r.userId]?.trim() ?? '—',
        timeIn: _formatTime(_displayAttendanceActivityAt(r)),
        status: _statusLabel(r),
        method: _sourceLabel(r.source),
      ),
    );
  }

  return DtrDashboardAnalyticsSnapshot(
    windowStart: windowStart,
    windowEnd: _dateOnly(windowEnd),
    presentByDay: presentByDay,
    lateByDay: lateByDay,
    undertimeByDay: undertimeByDay,
    absentByDay: absentByDay,
    lateCountByDepartment: lateByDept,
    undertimeCountByDepartment: undertimeByDept,
    leaveDaysByType: leaveDaysByType,
    recentRows: recentRows,
    leaveDataAvailable: leaveDataAvailable,
  );
}

String _formatTime(DateTime? dt) {
  if (dt == null) return '—';
  final local = dt.toLocal();
  final h = local.hour;
  final m = local.minute;
  final isPm = h >= 12;
  final h12 = h > 12 ? h - 12 : (h == 0 ? 12 : h);
  return '$h12:${m.toString().padLeft(2, '0')} ${isPm ? 'PM' : 'AM'}';
}

String _sourceLabel(String? source) {
  switch ((source ?? '').toLowerCase()) {
    case 'system':
      return 'Biometric';
    case 'manual':
      return 'Manual';
    case 'adjusted':
      return 'Adjusted';
    default:
      return source == null || source.isEmpty ? '—' : source;
  }
}

String _statusLabel(TimeRecord r) {
  final s = (r.status ?? '').toLowerCase();
  if (s == 'on_leave') {
    return r.leaveTypeName != null && r.leaveTypeName!.isNotEmpty
        ? r.leaveTypeName!
        : 'On Leave';
  }
  if (s == 'holiday') return r.holidayName ?? 'Holiday';
  if (s == 'late' || _isLate(r)) return 'Late';
  if (r.timeIn == null) {
    if (s == 'absent') return 'Absent';
    return '—';
  }
  if (r.attendanceRemark != null && r.attendanceRemark!.trim().isNotEmpty) {
    return r.attendanceRemark!.trim();
  }
  return 'Present';
}
