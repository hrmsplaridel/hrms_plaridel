import 'package:flutter/material.dart';

import '../../../landingpage/constants/app_theme.dart';
import 'attendance_overview_data.dart';

/// Compact KPI cell for attendance category totals (HRMS dashboard style).
class AttendanceOverviewKpiTile extends StatelessWidget {
  const AttendanceOverviewKpiTile({
    super.key,
    required this.label,
    required this.value,
    required this.accentColor,
    required this.icon,
  });

  final String label;
  final int value;
  final Color accentColor;
  final IconData icon;

  static Color _tintBackground(Color c) => Color.alphaBlend(
        c.withValues(alpha: 0.11),
        Colors.white,
      );

  static Color _tintBorder(Color c) => c.withValues(alpha: 0.28);

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _tintBackground(accentColor),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _tintBorder(accentColor), width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 9),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: accentColor),
            const SizedBox(height: 6),
            Text(
              '$value',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                height: 1.05,
                letterSpacing: -0.5,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                height: 1.2,
                color: AppTheme.textSecondary.withValues(alpha: 0.92),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Responsive grid of [AttendanceOverviewKpiTile] for the five attendance categories.
class AttendanceOverviewKpiGrid extends StatelessWidget {
  const AttendanceOverviewKpiGrid({
    super.key,
    required this.present,
    required this.late,
    required this.absent,
    required this.undertime,
    required this.onLeave,
  });

  final int present;
  final int late;
  final int absent;
  final int undertime;
  final int onLeave;

  @override
  Widget build(BuildContext context) {
    final tiles = <(String, int, Color, IconData)>[
      (
        'Present',
        present,
        AttendanceOverviewColors.present,
        Icons.check_circle_outline_rounded,
      ),
      (
        'Late',
        late,
        AttendanceOverviewColors.late,
        Icons.schedule_rounded,
      ),
      (
        'Absent',
        absent,
        AttendanceOverviewColors.absent,
        Icons.person_off_outlined,
      ),
      (
        'Undertime',
        undertime,
        AttendanceOverviewColors.undertime,
        Icons.trending_down_rounded,
      ),
      (
        'On leave',
        onLeave,
        AttendanceOverviewColors.onLeave,
        Icons.event_available_outlined,
      ),
    ];

    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final crossAxisCount = w >= 720
            ? 5
            : w >= 440
                ? 3
                : 2;
        const spacing = 8.0;
        const ratio = 1.38;

        return GridView.count(
          crossAxisCount: crossAxisCount,
          mainAxisSpacing: spacing,
          crossAxisSpacing: spacing,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: ratio,
          children: tiles
              .map(
                (t) => AttendanceOverviewKpiTile(
                  label: t.$1,
                  value: t.$2,
                  accentColor: t.$3,
                  icon: t.$4,
                ),
              )
              .toList(),
        );
      },
    );
  }
}
