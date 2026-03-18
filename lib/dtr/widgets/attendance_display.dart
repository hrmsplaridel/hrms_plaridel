import 'package:flutter/material.dart';

import '../../data/time_record.dart';
import '../../landingpage/constants/app_theme.dart';

/// Attendance display helpers shared by admin DTR Time Logs and employee My Attendance.

/// Single attendance remark. Prefer record.attendanceRemark (backend); fallback for hardcoded/preview.
/// For holidays, uses holiday name when available.
String getAttendanceRemark(TimeRecord r) {
  if (r.attendanceRemark != null && r.attendanceRemark!.isNotEmpty) return r.attendanceRemark!;
  if (r.status == 'holiday' || r.holidayId != null) return r.holidayName ?? 'Holiday';
  if (r.status == 'on_leave' || r.leaveRequestId != null) return 'Leave';
  final hasAnyLog = r.timeIn != null || r.breakOut != null || r.breakIn != null || r.timeOut != null;
  if (!hasAnyLog) return 'Absent';
  if (r.status == 'invalid') return 'Invalid Log';
  final hasAllFour = r.timeIn != null && r.breakOut != null && r.breakIn != null && r.timeOut != null;
  if (!hasAllFour) return 'Incomplete';
  final late = (r.lateMinutes ?? 0) > 0;
  final under = (r.undertimeMinutes ?? 0) > 0;
  if (late && under) return 'Late + Undertime';
  if (late) return 'Late';
  if (under) return 'Undertime';
  return 'On Time';
}

/// Display late minutes: "X min", "0 min", or "—" for holiday/leave.
String formatLateMinutes(TimeRecord r) {
  if (r.status == 'holiday' || r.holidayId != null || r.status == 'on_leave' || r.leaveRequestId != null) return '—';
  final m = r.lateMinutes ?? 0;
  return m == 0 ? '0 min' : '$m min';
}

/// Display undertime minutes: "X min", "0 min", or "—" for holiday/leave.
String formatUndertimeMinutes(TimeRecord r) {
  if (r.status == 'holiday' || r.holidayId != null || r.status == 'on_leave' || r.leaveRequestId != null) return '—';
  final m = r.undertimeMinutes ?? 0;
  return m == 0 ? '0 min' : '$m min';
}

/// Badge/chip for attendance remark. Government-style clean styling.
class AttendanceRemarksChip extends StatelessWidget {
  const AttendanceRemarksChip({
    super.key,
    required this.remark,
    this.isHoliday = false,
  });

  final String remark;
  final bool isHoliday;

  @override
  Widget build(BuildContext context) {
    final (color, bg) = _colorsForRemark(remark, isHoliday: isHoliday);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.5), width: 1),
      ),
      child: Text(
        remark,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  static (Color color, Color bg) _colorsForRemark(String r, {bool isHoliday = false}) {
    if (isHoliday) return (Colors.purple.shade700, Colors.purple.shade50);
    switch (r) {
      case 'On Time':
        return (Colors.green.shade800, Colors.green.shade50);
      case 'Late':
        return (Colors.red.shade800, Colors.red.shade50);
      case 'Undertime':
        return (Colors.orange.shade800, Colors.orange.shade50);
      case 'Late + Undertime':
        return (Colors.deepOrange.shade800, Colors.deepOrange.shade50);
      case 'Absent':
        return (Colors.orange.shade700, Colors.orange.shade50);
      case 'Holiday':
        return (Colors.purple.shade700, Colors.purple.shade50);
      case 'Leave':
        return (Colors.blue.shade700, Colors.blue.shade50);
      case 'Incomplete':
        return (Colors.amber.shade800, Colors.amber.shade50);
      case 'Invalid Log':
        return (Colors.red.shade900, Colors.red.shade100);
      default:
        return (AppTheme.textPrimary, AppTheme.lightGray.withOpacity(0.5));
    }
  }
}
