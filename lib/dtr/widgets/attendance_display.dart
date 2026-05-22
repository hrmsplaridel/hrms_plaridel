import 'package:flutter/material.dart';

import '../../data/time_record.dart';
import '../../landingpage/constants/app_theme.dart';

/// Attendance display helpers shared by admin DTR Time Logs and employee My Attendance.

/// Single attendance remark. Prefer record.attendanceRemark (backend); fallback for hardcoded/preview.
/// For holidays, uses holiday name when available.
String getAttendanceRemark(TimeRecord r) {
  if (r.attendanceRemark != null && r.attendanceRemark!.isNotEmpty) {
    return r.attendanceRemark!;
  }
  if (r.status == 'holiday' || r.holidayId != null) {
    return r.holidayName ?? 'Holiday';
  }
  if (r.status == 'on_leave' || r.leaveRequestId != null) {
    return r.leaveTypeName ?? 'Leave';
  }
  if (r.status == 'on_field' || r.locatorSlipId != null) {
    return r.locatorSlipDisplayLabel;
  }
  final hasAnyLog =
      r.timeIn != null ||
      r.breakOut != null ||
      r.breakIn != null ||
      r.timeOut != null;
  if (!hasAnyLog) return 'Absent';
  if (r.status == 'invalid') return 'Invalid Log';
  final hasAllFour =
      r.timeIn != null &&
      r.breakOut != null &&
      r.breakIn != null &&
      r.timeOut != null;
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
  if (r.status == 'holiday' ||
      r.holidayId != null ||
      r.status == 'on_leave' ||
      r.leaveRequestId != null) {
    return '—';
  }
  final m = r.lateMinutes ?? 0;
  return m == 0 ? '0 min' : '$m min';
}

/// Text color for an attendance remark (for plain text display, e.g. DTR reports table).
Color colorForRemarkText(
  BuildContext context,
  String remark, {
  bool isHoliday = false,
}) {
  final (color, _) = AttendanceRemarksChip.colorsForRemark(
    remark,
    isHoliday: isHoliday,
    dark: AppTheme.dashIsDark(context),
  );
  return color;
}

/// Display undertime minutes: "X min", "0 min", or "—" for holiday/leave.
String formatUndertimeMinutes(TimeRecord r) {
  if (r.status == 'holiday' ||
      r.holidayId != null ||
      r.status == 'on_leave' ||
      r.leaveRequestId != null) {
    return '—';
  }
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
    final dark = AppTheme.dashIsDark(context);
    final (color, bg) = colorsForRemark(
      remark,
      isHoliday: isHoliday,
      dark: dark,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.5), width: 1),
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

  static (Color color, Color bg) _chipPair(
    Color fg,
    Color lightBg, {
    required bool dark,
  }) => dark
      ? (fg.withValues(alpha: 0.92), fg.withValues(alpha: 0.24))
      : (fg, lightBg);

  static (Color color, Color bg) colorsForRemark(
    String r, {
    bool isHoliday = false,
    bool dark = false,
  }) {
    if (isHoliday) {
      return _chipPair(
        Colors.purple.shade700,
        Colors.purple.shade50,
        dark: dark,
      );
    }
    switch (r) {
      case 'On Time':
        return _chipPair(
          Colors.green.shade800,
          Colors.green.shade50,
          dark: dark,
        );
      case 'Late':
        return _chipPair(Colors.red.shade800, Colors.red.shade50, dark: dark);
      case 'Undertime':
        return _chipPair(
          Colors.orange.shade800,
          Colors.orange.shade50,
          dark: dark,
        );
      case 'Late + Undertime':
        return _chipPair(
          Colors.deepOrange.shade800,
          Colors.deepOrange.shade50,
          dark: dark,
        );
      case 'Absent':
        return _chipPair(
          Colors.orange.shade700,
          Colors.orange.shade50,
          dark: dark,
        );
      case 'Holiday':
        return _chipPair(
          Colors.purple.shade700,
          Colors.purple.shade50,
          dark: dark,
        );
      case 'Leave':
        return _chipPair(Colors.blue.shade700, Colors.blue.shade50, dark: dark);
      case 'Locator / Official Business':
      case 'On Field':
      case 'Pass Slip':
      case 'Work From Home':
      case 'WFH':
        return _chipPair(Colors.teal.shade700, Colors.teal.shade50, dark: dark);
      case 'Incomplete':
        return _chipPair(
          Colors.amber.shade800,
          Colors.amber.shade50,
          dark: dark,
        );
      case 'Invalid Log':
        return _chipPair(Colors.red.shade900, Colors.red.shade100, dark: dark);
      default:
        if (r.toLowerCase().contains('leave')) {
          return _chipPair(
            Colors.blue.shade700,
            Colors.blue.shade50,
            dark: dark,
          );
        }
        return dark
            ? (const Color(0xFFB0B8C4), const Color(0xFF343B4A))
            : (AppTheme.textPrimary, AppTheme.lightGray.withValues(alpha: 0.5));
    }
  }
}
