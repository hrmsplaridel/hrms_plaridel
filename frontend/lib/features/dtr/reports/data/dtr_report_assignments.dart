import 'package:hrms_plaridel/features/dtr/attendance/models/time_record.dart';
import 'dtr_report_official_hours.dart';

// Historical schedule parsing and validation shared by individual and bulk reports.
List<DtrReportAssignment> assignmentsOverlappingDtrRange(
  List<DtrReportAssignment> timeline,
  DateTime start,
  DateTime end,
) {
  return timeline
      .where((assignment) {
        final from = assignment.effectiveFrom;
        final to = assignment.effectiveTo;
        return (from == null || !from.isAfter(end)) &&
            (to == null || !to.isBefore(start));
      })
      .toList(growable: false);
}

bool hasVerifiedDtrPolicyCoverage({
  required List<TimeRecord> records,
  required List<DtrReportAssignment> timeline,
  required int year,
  required int month,
  int startDay = 1,
  int? endDay,
  DateTime? reportableThrough,
}) {
  final recordsByDate = <DateTime, TimeRecord>{
    for (final record in records)
      DateTime(
        record.recordDate.year,
        record.recordDate.month,
        record.recordDate.day,
      ): record,
  };
  final lastDay = DateTime(year, month + 1, 0).day;
  final reportStart = DateTime(year, month, startDay.clamp(1, lastDay).toInt());
  final reportEnd = DateTime(
    year,
    month,
    (endDay ?? lastDay).clamp(reportStart.day, lastDay).toInt(),
  );
  final authoritativeEnd = reportableThrough == null
      ? reportStart.subtract(const Duration(days: 1))
      : DateTime(
          reportableThrough.year,
          reportableThrough.month,
          reportableThrough.day,
        );
  final validationEnd = reportEnd.isAfter(authoritativeEnd)
      ? authoritativeEnd
      : reportEnd;
  if (validationEnd.isBefore(reportStart)) return true;

  for (var day = reportStart.day; day <= validationEnd.day; day++) {
    final date = DateTime(year, month, day);
    if (!isDtrScheduledWorkDay(date, timeline)) continue;
    final record = recordsByDate[date];
    if (record?.attendancePolicy == null || record?.reportDeduction == null) {
      return false;
    }
  }
  return true;
}

bool hasCompleteDtrAssignments(List<DtrReportAssignment> assignments) {
  return assignments.every(
    (assignment) =>
        assignment.officialHours?.trim().isNotEmpty == true &&
        (assignment.workHoursPerDay ?? 0) > 0 &&
        assignment.workingDays?.isNotEmpty == true,
  );
}

String _formatOfficialHours(String start, String end) {
  String toAmPm(String t) {
    final parts = t.trim().split(RegExp(r'[:.\s]'));
    if (parts.isEmpty) return t;
    final h = int.tryParse(parts[0]) ?? 0;
    final m = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
    final isPm = h >= 12;
    final h12 = h > 12 ? h - 12 : (h == 0 ? 12 : h);
    return '${h12.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}${isPm ? 'PM' : 'AM'}';
  }

  final crossesMidnight =
      (_parseShiftClockMinutes(end) ?? 1440) <
      (_parseShiftClockMinutes(start) ?? 0);
  return '${toAmPm(start)}-${toAmPm(end)}${crossesMidnight ? ' (+1 day)' : ''}';
}

List<DtrReportAssignment> parseDtrAssignmentTimeline(
  List<dynamic> list, {
  required int year,
  required int month,
}) {
  final monthStart = DateTime(year, month, 1);
  final monthEnd = DateTime(year, month + 1, 0);
  final assignments = <DtrReportAssignment>[];
  for (final a in list) {
    final m = a as Map<String, dynamic>;
    final from = m['effective_from'] != null
        ? DateTime.tryParse(m['effective_from'].toString())
        : null;
    final to =
        m['effective_to'] != null &&
            m['effective_to'].toString().trim().isNotEmpty
        ? DateTime.tryParse(m['effective_to'].toString())
        : null;
    if (from == null) continue;
    if (from.isAfter(monthEnd)) continue;
    if (to != null && to.isBefore(monthStart)) continue;
    final wd = m['working_days'];
    List<int>? days;
    if (wd is List) {
      days = wd
          .map((x) => x is int ? x : int.tryParse(x.toString()))
          .whereType<int>()
          .where((x) => x >= 1 && x <= 7)
          .toList();
    }
    final scheduleOverrides = <String, bool>{};
    final rawOverrides = m['schedule_overrides'];
    if (rawOverrides is List) {
      for (final rawOverride in rawOverrides.whereType<Map>()) {
        final date = rawOverride['date']?.toString().trim() ?? '';
        final value = rawOverride['is_working_day'];
        if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date) && value is bool) {
          scheduleOverrides[date] = value;
        }
      }
    }
    final st = m['start_time'];
    final et = m['end_time'];
    final be = m['break_end'];
    final officialHours = reportOfficialHours(
      startTime: st,
      endTime: et,
      scheduleOverrides: rawOverrides,
      format: _formatOfficialHours,
    );
    final startMinutes = _parseShiftClockMinutes(st);
    final endMinutes = _parseShiftClockMinutes(et);
    final breakEndMinutes = _parseShiftClockMinutes(be);
    final punchMode = _resolveReportPunchMode(
      m['punch_mode']?.toString(),
      startMinutes: startMinutes,
      endMinutes: endMinutes,
      breakEndMinutes: breakEndMinutes,
    );
    assignments.add(
      DtrReportAssignment(
        workingDays: (days != null && days.isNotEmpty) ? days : null,
        scheduleOverrides: scheduleOverrides,
        officialHours: officialHours,
        overnight:
            startMinutes != null &&
            endMinutes != null &&
            endMinutes < startMinutes,
        shiftEndMinutes: endMinutes,
        workHoursPerDay: _reportShiftWorkHours(
          startMinutes: startMinutes,
          endMinutes: endMinutes,
          breakEndMinutes: breakEndMinutes,
          punchMode: punchMode,
          breakStartMinutes: _parseShiftClockMinutes(m['break_start']),
        ),
        punchMode: punchMode,
        effectiveFrom: DateTime(from.year, from.month, from.day),
        effectiveTo: to != null ? DateTime(to.year, to.month, to.day) : null,
        department: m['department_name']?.toString().trim(),
        position: m['position_name']?.toString().trim(),
      ),
    );
  }
  assignments.sort((a, b) {
    final aFrom = a.effectiveFrom ?? DateTime(1900);
    final bFrom = b.effectiveFrom ?? DateTime(1900);
    return aFrom.compareTo(bFrom);
  });
  return assignments;
}

DtrReportAssignment? _assignmentForDate(
  DateTime date,
  List<DtrReportAssignment> timeline,
) {
  final assignments = timeline;
  for (final assignment in assignments.reversed) {
    final from = assignment.effectiveFrom;
    final to = assignment.effectiveTo;
    if (from != null && date.isBefore(from)) continue;
    if (to != null && date.isAfter(to)) continue;
    return assignment;
  }
  return null;
}

bool isDtrScheduledWorkDay(DateTime dt, List<DtrReportAssignment> timeline) {
  final assignment = _assignmentForDate(dt, timeline);
  if (assignment == null) return false;
  final override = assignment.scheduleOverrides[dtrReportDateKey(dt)];
  if (override != null) return override;
  final shiftWd =
      assignment.workingDays != null && assignment.workingDays!.isNotEmpty
      ? assignment.workingDays!.toSet()
      : {1, 2, 3, 4, 5};
  return shiftWd.contains(dt.weekday);
}

/// Holiday rows from the API are omitted when they are not meaningful for tardiness:
/// no assignment overlapping the month, or the date is not a scheduled work day for this employee.
Map<DateTime, TimeRecord> filterDtrReportRecords(
  Map<DateTime, TimeRecord> raw,
  List<DtrReportAssignment> timeline,
) {
  final hasAssignment = timeline.isNotEmpty;
  final out = <DateTime, TimeRecord>{};
  for (final e in raw.entries) {
    final dt = e.key;
    final r = e.value;
    final isHoliday = r.status == 'holiday' || (r.holidayId != null);
    if (isHoliday) {
      if (!hasAssignment) continue;
      if (!isDtrScheduledWorkDay(dt, timeline)) continue;
    }
    out[dt] = r;
  }
  return out;
}

String? _nonEmpty(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

String? dtrAssignmentHeaderValue(
  Iterable<String?> values, {
  required String multipleLabel,
}) {
  final distinct = values.map(_nonEmpty).whereType<String>().toSet();
  if (distinct.isEmpty) return null;
  return distinct.length == 1 ? distinct.first : multipleLabel;
}

int? _parseShiftClockMinutes(dynamic value) {
  if (value == null) return null;
  final match = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(value.toString());
  if (match == null) return null;
  final hour = int.tryParse(match.group(1)!);
  final minute = int.tryParse(match.group(2)!);
  if (hour == null ||
      minute == null ||
      hour < 0 ||
      hour > 23 ||
      minute < 0 ||
      minute > 59) {
    return null;
  }
  return hour * 60 + minute;
}

String _resolveReportPunchMode(
  String? value, {
  required int? startMinutes,
  required int? endMinutes,
  required int? breakEndMinutes,
}) {
  final mode = value?.trim().toLowerCase() ?? 'auto';
  if (const {
    'full_day',
    'am_only',
    'pm_only',
    'single_session',
  }.contains(mode)) {
    return mode;
  }
  if (startMinutes == null) return 'auto';
  if (endMinutes != null && endMinutes < startMinutes) return 'single_session';
  if (startMinutes >= 12 * 60) return 'pm_only';
  if (breakEndMinutes == null && endMinutes != null && endMinutes <= 13 * 60) {
    return 'am_only';
  }
  return 'full_day';
}

double? _reportShiftWorkHours({
  required int? startMinutes,
  required int? endMinutes,
  required int? breakEndMinutes,
  required String punchMode,
  int? breakStartMinutes,
}) {
  if (startMinutes == null || endMinutes == null) return null;
  var spanMinutes = endMinutes - startMinutes;
  if (spanMinutes <= 0) spanMinutes += 24 * 60;
  if (punchMode == 'full_day' && endMinutes < startMinutes) {
    int normalize(int value) => value < startMinutes ? value + 1440 : value;
    final duration =
        normalize(breakEndMinutes ?? 13 * 60) -
        normalize(breakStartMinutes ?? 12 * 60);
    return (spanMinutes - duration).clamp(0, 1440) / 60;
  }
  if (punchMode == 'full_day') {
    final lunchMinutes = breakEndMinutes == null
        ? 60
        : (breakEndMinutes - 12 * 60).clamp(0, 24 * 60).toInt();
    spanMinutes = (spanMinutes - lunchMinutes).clamp(0, 24 * 60).toInt();
  }
  return spanMinutes / 60;
}

class DtrReportAssignment {
  const DtrReportAssignment({
    this.workingDays,
    this.scheduleOverrides = const {},
    this.officialHours,
    this.workHoursPerDay,
    this.punchMode,
    this.overnight = false,
    this.shiftEndMinutes,
    this.effectiveFrom,
    this.effectiveTo,
    this.department,
    this.position,
  });

  final List<int>? workingDays;
  final Map<String, bool> scheduleOverrides;
  final String? officialHours;
  final double? workHoursPerDay;
  final String? punchMode;
  final bool overnight;
  final int? shiftEndMinutes;
  final DateTime? effectiveFrom;
  final DateTime? effectiveTo;
  final String? department;
  final String? position;
}

String dtrReportDateKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';
