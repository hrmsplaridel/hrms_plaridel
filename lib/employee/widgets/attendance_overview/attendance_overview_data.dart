import 'package:flutter/material.dart';

import '../../../data/time_record.dart';
import '../../../dtr/widgets/attendance_display.dart';

/// Default window: last ~16 calendar days, clamped to current month start and today.
class AttendanceOverviewDateRange {
  const AttendanceOverviewDateRange({
    required this.startDate,
    required this.endDate,
  });

  final DateTime startDate;
  final DateTime endDate;
}

AttendanceOverviewDateRange computeAttendanceOverviewDateRange([DateTime? now]) {
  final n = now ?? DateTime.now();
  final monthStart = DateTime(n.year, n.month, 1);
  final monthEnd = DateTime(n.year, n.month + 1, 0);
  final today = DateTime(n.year, n.month, n.day);
  final clampedEnd = today.isAfter(monthEnd) ? monthEnd : today;
  final startCandidate = clampedEnd.subtract(const Duration(days: 15));
  final startDate =
      startCandidate.isBefore(monthStart) ? monthStart : startCandidate;
  return AttendanceOverviewDateRange(startDate: startDate, endDate: clampedEnd);
}

String attendanceOverviewRangeLabel(DateTime startDate, DateTime endDate) {
  final startMonth = _monthNames[startDate.month - 1];
  final endMonth = _monthNames[endDate.month - 1];
  return 'Attendance chart ($startMonth ${startDate.day} – $endMonth ${endDate.day})';
}

const List<String> _monthNames = [
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

/// One bar per day: color encodes Present / Absent / Late.
class AttendanceOverviewDay {
  const AttendanceOverviewDay({
    required this.dayOfMonth,
    required this.barColor,
  });

  final int dayOfMonth;
  final Color barColor;
}

List<AttendanceOverviewDay> buildAttendanceOverviewDays({
  required List<TimeRecord> timeRecords,
  required DateTime startDate,
  required DateTime endDate,
}) {
  const presentColor = Color(0xFFE85D04);
  const absentColor = Color(0xFF81C784);
  const lateColor = Color(0xFFFFB74D);

  final byDate = <String, TimeRecord>{};
  for (final r in timeRecords) {
    byDate[_dateOnlyKey(r.recordDate)] ??= r;
  }

  final out = <AttendanceOverviewDay>[];
  var d = startDate;
  while (!d.isAfter(endDate)) {
    final rec = byDate[_dateOnlyKey(d)];
    final remark = rec != null ? getAttendanceRemark(rec) : 'Absent';

    final isLate = remark.contains('Late');
    final isPresent = remark == 'On Time' || remark == 'Undertime';

    final color =
        isLate ? lateColor : (isPresent ? presentColor : absentColor);

    out.add(AttendanceOverviewDay(dayOfMonth: d.day, barColor: color));
    d = DateTime(d.year, d.month, d.day + 1);
  }
  return out;
}

String _dateOnlyKey(DateTime d) {
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
