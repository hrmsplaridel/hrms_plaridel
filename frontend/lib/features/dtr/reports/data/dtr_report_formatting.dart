import 'package:hrms_plaridel/features/dtr/attendance/models/time_record.dart';
import 'package:hrms_plaridel/features/dtr/attendance/presentation/widgets/attendance_display.dart';
import 'package:hrms_plaridel/features/dtr/reports/data/official_time.dart';

/// Cell text for one punch column: the official time, the locator slip label
/// when an approved slip covers that segment, or an em dash.
String dtrCellDisplayForSegment({
  required TimeRecord record,
  required DateTime? timeValue,
  required String segment,
}) {
  if (timeValue != null) {
    return formatOfficialPhilippineTime(
      timeValue,
      attendanceDate: record.recordDate,
    );
  }
  final segs = record.locatorSlipSegments ?? const <String>[];
  if (segs.any((s) => s.toUpperCase() == segment)) {
    return record.locatorSlipSlotLabel;
  }
  return '—';
}

const List<String> _shortWeekdays = [
  'Mon',
  'Tue',
  'Wed',
  'Thu',
  'Fri',
  'Sat',
  'Sun',
];

/// Day-of-month with short weekday, e.g. `3 Wed`.
String formatDtrReportDate(DateTime d) {
  final weekday = _shortWeekdays[d.weekday - 1];
  return '${d.day} $weekday';
}

String formatDtrMinutes(int? mins) {
  if (mins == null || mins <= 0) return '—';
  return '$mins min';
}

String _getRemarks(TimeRecord r) {
  if (r.status != null && r.status!.isNotEmpty) {
    switch (r.status!) {
      case 'not_tracked':
        return 'Not tracked';
      case 'late':
        return 'Late';
      case 'absent':
        return 'Absent';
      case 'on_leave':
        return r.leaveTypeName ?? r.attendanceRemark ?? 'On Leave';
      case 'holiday':
        return r.holidayName ?? 'Holiday';
      case 'on_field':
        return r.locatorSlipDisplayLabel;
      default:
        return 'On Time';
    }
  }
  if (r.timeIn == null) return 'Absent';
  final official = toOfficialPhilippineTime(r.timeIn!);
  final punchMinute = (official.hour * 60) + official.minute;
  if (punchMinute > 8 * 60) return 'Late';
  return 'On Time';
}

/// Remarks column text for a report row.
String dtrReportRowRemark({
  required TimeRecord? record,
  required bool isQuietPlaceholder,
  required bool isMissingScheduledWorkDay,
}) {
  if (isQuietPlaceholder) return '—';
  if (isMissingScheduledWorkDay) return 'Absent';
  final rec = record;
  if (rec == null) return '';
  final attendanceRemark = rec.attendanceRemark?.trim();
  if (attendanceRemark != null && attendanceRemark.isNotEmpty) {
    return _normalizeAttendanceRemark(attendanceRemark);
  }
  return _getRemarks(rec);
}

String _normalizeAttendanceRemark(String remark) {
  return compactLocatorRemark(normalizeAttendanceRemark(remark));
}

/// Minutes shown as minutes or hours, following the report's unit toggle.
String formatDtrMinutesOrHours(int minutes, {required bool showMinutes}) {
  if (minutes <= 0) return showMinutes ? '0 min' : '0 hrs';
  if (showMinutes) return '$minutes min';
  final hours = minutes / 60;
  return hours == hours.roundToDouble()
      ? '${hours.toInt()} hrs'
      : '${hours.toStringAsFixed(2)} hrs';
}

/// Equivalent-day value with trailing zeros trimmed (e.g. `0.125`, `1`).
String formatDtrEquivalentDay(double value) {
  return value
      .toStringAsFixed(3)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}
