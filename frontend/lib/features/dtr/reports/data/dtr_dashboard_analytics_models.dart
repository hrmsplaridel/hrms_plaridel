import 'package:flutter/foundation.dart';

/// Precomputed dashboard analytics for charts and recent table (last ~30 days window).
@immutable
class DtrDashboardAnalyticsSnapshot {
  const DtrDashboardAnalyticsSnapshot({
    required this.windowStart,
    required this.windowEnd,
    required this.presentByDay,
    required this.lateByDay,
    required this.undertimeByDay,
    required this.absentByDay,
    required this.lateCountByDepartment,
    required this.undertimeCountByDepartment,
    required this.leaveDaysByType,
    required this.recentRows,
    this.leaveDataAvailable = true,
  });

  /// Inclusive calendar start (oldest of the 30 days).
  final DateTime windowStart;

  /// Inclusive calendar end (usually today).
  final DateTime windowEnd;

  /// Length 30: present (non-late) headcount per day, oldest → newest.
  final List<int> presentByDay;

  /// Length 30: late headcount per day, oldest → newest.
  final List<int> lateByDay;

  /// Length 30: undertime employee-days per day (see aggregation rules).
  final List<int> undertimeByDay;

  /// Length 30: explicit `status == absent` rows per day (no inference from missing rows).
  final List<int> absentByDay;

  /// Department display name → distinct late employee-days in window (after filters).
  final Map<String, int> lateCountByDepartment;

  /// Department display name → distinct undertime employee-days in window (after filters).
  final Map<String, int> undertimeCountByDepartment;

  /// Leave type label → total working days in window (approved, overlapping).
  final Map<String, double> leaveDaysByType;

  final List<DtrRecentActivityRow> recentRows;

  /// False when leave API failed or returned nothing usable.
  final bool leaveDataAvailable;
}

@immutable
class DtrRecentActivityRow {
  const DtrRecentActivityRow({
    required this.employeeName,
    required this.department,
    required this.timeIn,
    required this.status,
    required this.method,
  });

  final String employeeName;
  final String department;
  final String timeIn;
  final String status;
  final String method;
}
