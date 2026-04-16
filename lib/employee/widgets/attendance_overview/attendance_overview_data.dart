import 'package:flutter/material.dart';

import '../../../data/time_record.dart';
import '../../../dtr/widgets/attendance_display.dart';

const List<String> kAttendanceOverviewMonthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// HRMS analytics palette: strong accents for values/bars; use with light tints on cards.
abstract final class AttendanceOverviewColors {
  static const Color present = Color(0xFF2E7D32);
  static const Color late = Color(0xFFF57C00);
  static const Color absent = Color(0xFFC62828);
  static const Color undertime = Color(0xFF00897B);
  static const Color onLeave = Color(0xFF6A1B9A);
}

/// Single primary category per calendar day (mutually exclusive buckets).
enum MonthlyAttendanceBucket {
  present,
  late,
  absent,
  undertime,
  onLeave,
}

/// Aggregated counts for one calendar month (elapsed days only for current month).
class MonthlyAttendanceSummary {
  const MonthlyAttendanceSummary({
    required this.year,
    required this.month,
    required this.present,
    required this.late,
    required this.absent,
    required this.undertime,
    required this.onLeave,
    required this.daysSkippedHoliday,
    required this.daysSkippedWeekendNoPunch,
    required this.lastStatsDay,
  });

  final int year;
  final int month;
  final int present;
  final int late;
  final int absent;
  final int undertime;
  final int onLeave;

  /// Holiday rows excluded from category totals (still in API data).
  final int daysSkippedHoliday;

  /// Weekend days with no record (non-work days).
  final int daysSkippedWeekendNoPunch;

  /// Last calendar date included in aggregation (inclusive).
  final DateTime lastStatsDay;

  int get totalCategorized =>
      present + late + absent + undertime + onLeave;

  int get maxCount {
    final m = [
      present,
      late,
      absent,
      undertime,
      onLeave,
    ].reduce((a, b) => a > b ? a : b);
    return m;
  }
}

String attendanceOverviewMonthTitle(int year, int month) {
  final m = kAttendanceOverviewMonthNames[month - 1];
  return '$m $year';
}

bool _isWeekend(DateTime d) =>
    d.weekday == DateTime.saturday || d.weekday == DateTime.sunday;

String _dateOnlyKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Maps [TimeRecord] list to [MonthlyAttendanceBucket] using the same rules as
/// [getAttendanceRemark], with **one** primary outcome per day.
MonthlyAttendanceBucket? _bucketForDay(TimeRecord? rec) {
  if (rec != null &&
      (rec.status == 'holiday' || rec.holidayId != null)) {
    return null;
  }
  if (rec != null &&
      (rec.status == 'on_leave' || rec.leaveRequestId != null)) {
    return MonthlyAttendanceBucket.onLeave;
  }

  if (rec == null) {
    return MonthlyAttendanceBucket.absent;
  }

  final remark = getAttendanceRemark(rec);

  if (remark == 'Holiday' ||
      (rec.holidayName != null && remark.contains('Holiday'))) {
    return null;
  }

  if (remark.toLowerCase().contains('leave')) {
    return MonthlyAttendanceBucket.onLeave;
  }

  switch (remark) {
    case 'Absent':
    case 'Incomplete':
    case 'Invalid Log':
      return MonthlyAttendanceBucket.absent;
    case 'Late':
    case 'Late + Undertime':
      return MonthlyAttendanceBucket.late;
    case 'Undertime':
      return MonthlyAttendanceBucket.undertime;
    case 'On Time':
      return MonthlyAttendanceBucket.present;
    default:
      if (remark.contains('Late')) return MonthlyAttendanceBucket.late;
      return MonthlyAttendanceBucket.absent;
  }
}

/// Filters [records] to [year]/[month], builds per-day map, aggregates by bucket.
MonthlyAttendanceSummary aggregateMonthlyAttendance({
  required List<TimeRecord> records,
  required int year,
  required int month,
  DateTime? now,
}) {
  final clock = now ?? DateTime.now();
  final lastDay = DateTime(year, month + 1, 0).day;
  final monthEnd = DateTime(year, month, lastDay);
  final today = DateTime(clock.year, clock.month, clock.day);
  final statsEnd = (year == today.year && month == today.month)
      ? (today.isBefore(monthEnd) ? today : monthEnd)
      : monthEnd;

  final byDate = <String, TimeRecord>{};
  for (final r in records) {
    if (r.recordDate.year != year || r.recordDate.month != month) continue;
    byDate[_dateOnlyKey(r.recordDate)] ??= r;
  }

  var present = 0;
  var late = 0;
  var absent = 0;
  var undertime = 0;
  var onLeave = 0;
  var skippedHoliday = 0;
  var skippedWeekend = 0;

  for (var day = 1; day <= lastDay; day++) {
    final dt = DateTime(year, month, day);
    if (dt.isAfter(statsEnd)) break;

    final key = _dateOnlyKey(dt);
    final rec = byDate[key];

    if (rec == null && _isWeekend(dt)) {
      skippedWeekend++;
      continue;
    }

    final bucket = _bucketForDay(rec);
    if (bucket == null) {
      skippedHoliday++;
      continue;
    }

    switch (bucket) {
      case MonthlyAttendanceBucket.present:
        present++;
        break;
      case MonthlyAttendanceBucket.late:
        late++;
        break;
      case MonthlyAttendanceBucket.absent:
        absent++;
        break;
      case MonthlyAttendanceBucket.undertime:
        undertime++;
        break;
      case MonthlyAttendanceBucket.onLeave:
        onLeave++;
        break;
    }
  }

  return MonthlyAttendanceSummary(
    year: year,
    month: month,
    present: present,
    late: late,
    absent: absent,
    undertime: undertime,
    onLeave: onLeave,
    daysSkippedHoliday: skippedHoliday,
    daysSkippedWeekendNoPunch: skippedWeekend,
    lastStatsDay: statsEnd,
  );
}

/// Records belonging to [year]/[month] (calendar), for empty-state checks.
List<TimeRecord> filterRecordsToMonth(
  List<TimeRecord> records,
  int year,
  int month,
) {
  return records
      .where((r) => r.recordDate.year == year && r.recordDate.month == month)
      .toList();
}
