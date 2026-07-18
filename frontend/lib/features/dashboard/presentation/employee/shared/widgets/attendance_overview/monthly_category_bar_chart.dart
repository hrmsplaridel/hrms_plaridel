import 'package:flutter/material.dart';

import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'attendance_overview_data.dart';

class MonthlyCategoryBarDatum {
  const MonthlyCategoryBarDatum({
    required this.label,
    required this.shortLabel,
    required this.count,
    required this.color,
  });

  final String label;
  final String shortLabel;
  final int count;
  final Color color;
}

/// Vertical bars keyed by category (x-axis labels). Supports all-zero months gracefully.
class MonthlyCategoryBarChart extends StatelessWidget {
  const MonthlyCategoryBarChart({
    super.key,
    required this.data,
    this.maxBarHeight = 96,
  });

  final List<MonthlyCategoryBarDatum> data;
  final double maxBarHeight;

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return const SizedBox.shrink();

    final maxVal = data.map((e) => e.count).reduce((a, b) => a > b ? a : b);
    final allZero = maxVal == 0;
    final scaleMax = maxVal <= 0 ? 1 : maxVal;

    return LayoutBuilder(
      builder: (context, c) {
        final narrow = c.maxWidth < 400;
        const padTop = 4.0;
        const labelGap = 4.0;

        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: data.map((d) {
            final double barH;
            final Color fill;
            if (allZero) {
              barH = 10;
              fill = d.color.withValues(alpha: 0.22);
            } else if (d.count == 0) {
              barH = 4;
              fill = Colors.black.withValues(alpha: 0.08);
            } else {
              barH = (maxBarHeight * d.count / scaleMax).clamp(
                12.0,
                maxBarHeight,
              );
              fill = d.color;
            }

            return Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: narrow ? 3 : 5),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${d.count}',
                      style: TextStyle(
                        fontSize: narrow ? 11.5 : 12.5,
                        fontWeight: FontWeight.w800,
                        color: allZero || d.count == 0
                            ? Colors.black.withValues(alpha: 0.38)
                            : AppTheme.textPrimary,
                      ),
                    ),
                    SizedBox(height: padTop),
                    SizedBox(
                      height: maxBarHeight,
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 240),
                          curve: Curves.easeOutCubic,
                          width: narrow ? double.infinity : 26,
                          height: barH,
                          decoration: BoxDecoration(
                            color: fill,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(5),
                            ),
                            border: Border.all(
                              color: allZero
                                  ? d.color.withValues(alpha: 0.35)
                                  : Colors.transparent,
                              width: 1,
                            ),
                            boxShadow: !allZero && d.count > 0
                                ? [
                                    BoxShadow(
                                      color: d.color.withValues(alpha: 0.22),
                                      blurRadius: 5,
                                      offset: const Offset(0, 2),
                                    ),
                                  ]
                                : null,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: labelGap),
                    Text(
                      narrow ? d.shortLabel : d.label,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: narrow ? 9.5 : 10,
                        fontWeight: FontWeight.w600,
                        color: Colors.black.withValues(alpha: 0.52),
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

List<MonthlyCategoryBarDatum> summaryToBarData(MonthlyAttendanceSummary s) {
  return [
    MonthlyCategoryBarDatum(
      label: 'On time',
      shortLabel: 'On time',
      count: s.present,
      color: AttendanceOverviewColors.present,
    ),
    MonthlyCategoryBarDatum(
      label: 'Late',
      shortLabel: 'Late',
      count: s.late,
      color: AttendanceOverviewColors.late,
    ),
    MonthlyCategoryBarDatum(
      label: 'Absent',
      shortLabel: 'Absent',
      count: s.absent,
      color: AttendanceOverviewColors.absent,
    ),
    MonthlyCategoryBarDatum(
      label: 'Undertime',
      shortLabel: 'Under',
      count: s.undertime,
      color: AttendanceOverviewColors.undertime,
    ),
    MonthlyCategoryBarDatum(
      label: 'On leave',
      shortLabel: 'Leave',
      count: s.onLeave,
      color: AttendanceOverviewColors.onLeave,
    ),
  ];
}
