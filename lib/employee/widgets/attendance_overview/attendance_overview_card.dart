import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../dtr/dtr_provider.dart';
import '../../../landingpage/constants/app_theme.dart';
import 'attendance_overview_bar_chart.dart';
import 'attendance_overview_data.dart';

const _legendPresent = Color(0xFFE85D04);
const _legendAbsent = Color(0xFF81C784);
const _legendLate = Color(0xFFFFB74D);

/// Employee dashboard card: attendance bar chart + legend + date range label.
class EmployeeAttendanceOverviewCard extends StatelessWidget {
  const EmployeeAttendanceOverviewCard({super.key, this.onViewMore});

  /// Typically switches the employee shell to **My Attendance**.
  final VoidCallback? onViewMore;

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 600;
    final pad = narrow ? 16.0 : 24.0;
    final chartBoxHeight = narrow ? 172.0 : 200.0;
    final barChartHeight = narrow ? 96.0 : 108.0;

    Widget titleText() {
      return Text(
        'Attendance Overview',
        style: TextStyle(
          color: AppTheme.textPrimary,
          fontWeight: FontWeight.w700,
          fontSize: 17,
        ),
        overflow: TextOverflow.ellipsis,
      );
    }

    return LayoutBuilder(
      builder: (context, c) {
        final stackHeader = c.maxWidth < 400;
        return Container(
          padding: EdgeInsets.all(pad),
          decoration: BoxDecoration(
            color: AppTheme.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (stackHeader) ...[
                titleText(),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: onViewMore,
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.primaryNavy,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                    ),
                    child: const Text('View More >'),
                  ),
                ),
              ] else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: titleText()),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: onViewMore,
                      style: TextButton.styleFrom(
                        foregroundColor: AppTheme.primaryNavy,
                      ),
                      child: const Text('View More >'),
                    ),
                  ],
                ),
              SizedBox(height: narrow ? 16 : 20),
              Container(
                height: chartBoxHeight,
                padding: EdgeInsets.symmetric(
                  horizontal: narrow ? 8 : 12,
                  vertical: narrow ? 10 : 14,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.offWhite.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.black.withValues(alpha: 0.06),
                  ),
                ),
                child: Consumer<DtrProvider>(
                  builder: (context, dtr, _) {
                    final range = computeAttendanceOverviewDateRange();
                    final rangeLabel = attendanceOverviewRangeLabel(
                      range.startDate,
                      range.endDate,
                    );

                    if (dtr.loading && dtr.timeRecords.isEmpty) {
                      return _ChartBody(
                        narrow: narrow,
                        rangeLabel: rangeLabel,
                        child: const SizedBox(
                          height: 40,
                          width: 40,
                          child: CircularProgressIndicator(strokeWidth: 3),
                        ),
                      );
                    }

                    final days = buildAttendanceOverviewDays(
                      timeRecords: dtr.timeRecords,
                      startDate: range.startDate,
                      endDate: range.endDate,
                    );

                    return _ChartBody(
                      narrow: narrow,
                      rangeLabel: rangeLabel,
                      child: SizedBox(
                        height: barChartHeight,
                        width: double.infinity,
                        child: AttendanceOverviewBarChart(days: days),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ChartBody extends StatelessWidget {
  const _ChartBody({
    required this.rangeLabel,
    required this.child,
    this.narrow = false,
  });

  final String rangeLabel;
  final Widget child;
  final bool narrow;

  @override
  Widget build(BuildContext context) {
    final legend = narrow
        ? Wrap(
            spacing: 14,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: const [
              _LegendItem(color: _legendPresent, label: 'Present'),
              _LegendItem(color: _legendAbsent, label: 'Absent'),
              _LegendItem(color: _legendLate, label: 'Late'),
            ],
          )
        : Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _LegendItem(color: _legendPresent, label: 'Present'),
              const SizedBox(width: 20),
              _LegendItem(color: _legendAbsent, label: 'Absent'),
              const SizedBox(width: 20),
              _LegendItem(color: _legendLate, label: 'Late'),
            ],
          );

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        child,
        SizedBox(height: narrow ? 8 : 10),
        Text(
          rangeLabel,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppTheme.textSecondary,
            fontSize: narrow ? 13 : 14,
          ),
        ),
        SizedBox(height: narrow ? 10 : 14),
        legend,
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
        ),
      ],
    );
  }
}
