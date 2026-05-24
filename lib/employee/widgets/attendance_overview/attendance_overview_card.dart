import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../dtr/dtr_provider.dart';
import '../../../landingpage/constants/app_theme.dart';
import 'attendance_overview_data.dart';
import 'attendance_overview_kpi_tile.dart';
import 'monthly_category_bar_chart.dart';
import '../employee_dash_ui.dart';
import '../employee_dashboard_skeletons.dart';

/// Production-style monthly attendance overview: optional top summary strip
/// (e.g. clock, attendance, leave, payslip) + KPI grid + category bar chart.
class EmployeeAttendanceOverviewCard extends StatefulWidget {
  const EmployeeAttendanceOverviewCard({
    super.key,
    this.onViewMore,
    this.summaryCards,
    this.upcomingLeave,
  });

  /// Typically switches the employee shell to **My Attendance**.
  final VoidCallback? onViewMore;

  /// Placed at the **top** of this card (same white container), above the
  /// monthly attendance header and analytics.
  final Widget? summaryCards;

  /// Placed **below** the monthly attendance block (same white container).
  final Widget? upcomingLeave;

  @override
  State<EmployeeAttendanceOverviewCard> createState() =>
      _EmployeeAttendanceOverviewCardState();
}

class _EmployeeAttendanceOverviewCardState
    extends State<EmployeeAttendanceOverviewCard> {
  late int _year;
  late int _month;
  StreamSubscription<DtrUpdateEvent>? _dtrUpdateSub;

  /// True until the first awaited [loadTimeRecordsForUser] for this month
  /// finishes (also true while switching months). Without this, the first
  /// frame has `dtr.loading == false` and empty data, so the UI would flash
  /// the empty state instead of the skeleton.
  bool _monthLoadInFlight = true;

  DateTime get _now => DateTime.now();

  bool get _isViewingCurrentMonth => _year == _now.year && _month == _now.month;

  @override
  void initState() {
    super.initState();
    final n = DateTime.now();
    _year = n.year;
    _month = n.month;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadMonth();
      _subscribeToDtrUpdates();
    });
  }

  @override
  void dispose() {
    _dtrUpdateSub?.cancel();
    super.dispose();
  }

  void _subscribeToDtrUpdates() {
    _dtrUpdateSub?.cancel();
    _dtrUpdateSub = context.read<DtrProvider>().onDtrEvent.listen((event) {
      if (!mounted) return;
      if (!_isViewingCurrentMonth) return;
      final dtr = context.read<DtrProvider>();
      if (dtr.loading) return;
      if (!event.affectsUser(dtr.userId)) return;
      final start = DateTime(_year, _month, 1);
      final end = DateTime(_year, _month + 1, 0);
      if (!event.affectsDateRange(start, end)) return;
      _loadMonth(showSkeleton: false);
    });
  }

  /// Loads DTR rows for the selected month. [showSkeleton] is false for
  /// background refresh so the KPI/chart do not flash to skeleton every 30s.
  Future<void> _loadMonth({bool showSkeleton = true}) async {
    final start = DateTime(_year, _month, 1);
    final end = DateTime(_year, _month + 1, 0);
    if (showSkeleton && mounted) {
      setState(() => _monthLoadInFlight = true);
    }
    try {
      await context.read<DtrProvider>().loadTimeRecordsForUser(
        startDate: start,
        endDate: end,
      );
    } finally {
      if (mounted && showSkeleton) {
        setState(() => _monthLoadInFlight = false);
      }
    }
  }

  void _goPrevMonth() {
    final floorY = _now.year - 3;
    if (_year == floorY && _month == 1) return;
    setState(() {
      if (_month == 1) {
        _year--;
        _month = 12;
      } else {
        _month--;
      }
    });
    _loadMonth();
  }

  void _goNextMonth() {
    final cur = DateTime(_now.year, _now.month, 1);
    final sel = DateTime(_year, _month, 1);
    if (!sel.isBefore(cur)) return;
    setState(() {
      if (_month == 12) {
        _year++;
        _month = 1;
      } else {
        _month++;
      }
    });
    _loadMonth();
  }

  bool _canGoNext() {
    final sel = DateTime(_year, _month, 1);
    final cur = DateTime(_now.year, _now.month, 1);
    return sel.isBefore(cur);
  }

  String _footnote(MonthlyAttendanceSummary s) {
    final parts = <String>[];
    if (s.daysSkippedHoliday > 0) {
      parts.add(
        '${s.daysSkippedHoliday} holiday day${s.daysSkippedHoliday == 1 ? '' : 's'} excluded',
      );
    }
    if (s.daysSkippedWeekendNoPunch > 0) {
      parts.add(
        '${s.daysSkippedWeekendNoPunch} weekend day${s.daysSkippedWeekendNoPunch == 1 ? '' : 's'} (no punch) excluded',
      );
    }
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final narrow = w < 560;
    final pad = narrow ? 14.0 : 18.0;
    final monthTitle = attendanceOverviewMonthTitle(_year, _month);
    final summaryStrip = widget.summaryCards;
    final leaveSection = widget.upcomingLeave;

    return Container(
      padding: EdgeInsets.all(pad),
      decoration: EmployeeDashUi.elevatedPanel(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (summaryStrip != null) ...[
            summaryStrip,
            SizedBox(height: narrow ? 14 : 18),
            Divider(
              height: 1,
              thickness: 1,
              color: AppTheme.dashHairlineOf(context),
            ),
            SizedBox(height: narrow ? 14 : 18),
          ],
          _AttendanceOverviewHeader(
            narrow: narrow,
            monthTitle: monthTitle,
            canGoNext: _canGoNext(),
            onPrev: _goPrevMonth,
            onNext: _goNextMonth,
            onViewMore: widget.onViewMore,
          ),
          SizedBox(height: narrow ? 10 : 12),
          Consumer<DtrProvider>(
            builder: (context, dtr, _) {
              final monthRecords = filterRecordsToMonth(
                dtr.timeRecords,
                _year,
                _month,
              );

              final showSkeleton =
                  monthRecords.isEmpty && (dtr.loading || _monthLoadInFlight);
              if (showSkeleton) {
                return const AttendanceOverviewLoadingBody();
              }

              if (monthRecords.isEmpty) {
                return _EmptyBody(monthTitle: monthTitle);
              }

              final summary = aggregateMonthlyAttendance(
                records: dtr.timeRecords,
                year: _year,
                month: _month,
                now: _now,
              );
              final barData = summaryToBarData(summary);

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AttendanceOverviewKpiGrid(
                    present: summary.present,
                    late: summary.late,
                    absent: summary.absent,
                    undertime: summary.undertime,
                    onLeave: summary.onLeave,
                  ),
                  SizedBox(height: narrow ? 10 : 12),
                  _DistributionPanel(
                    narrow: narrow,
                    summary: summary,
                    barData: barData,
                  ),
                  if (summary.daysSkippedHoliday > 0 ||
                      summary.daysSkippedWeekendNoPunch > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        _footnote(summary),
                        style: TextStyle(
                          fontSize: 10.5,
                          height: 1.35,
                          color: AppTheme.dashTextSecondaryOf(context)
                              .withValues(alpha: 0.85),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          if (leaveSection != null) ...[
            SizedBox(height: narrow ? 14 : 18),
            Divider(
              height: 1,
              thickness: 1,
              color: AppTheme.dashHairlineOf(context),
            ),
            SizedBox(height: narrow ? 12 : 14),
            leaveSection,
          ],
        ],
      ),
    );
  }
}

class _AttendanceOverviewHeader extends StatelessWidget {
  const _AttendanceOverviewHeader({
    required this.narrow,
    required this.monthTitle,
    required this.canGoNext,
    required this.onPrev,
    required this.onNext,
    this.onViewMore,
  });

  final bool narrow;
  final String monthTitle;
  final bool canGoNext;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback? onViewMore;

  @override
  Widget build(BuildContext context) {
    final titleStyle = TextStyle(
      color: AppTheme.dashTextPrimaryOf(context),
      fontWeight: FontWeight.w800,
      fontSize: narrow ? 16 : 17,
      letterSpacing: -0.3,
    );
    final subtitleStyle = TextStyle(
      color: AppTheme.dashTextSecondaryOf(context).withValues(alpha: 0.92),
      fontSize: narrow ? 11.5 : 12,
      fontWeight: FontWeight.w500,
      height: 1.25,
    );

    final nav = _MonthNavPill(
      monthTitle: monthTitle,
      canGoNext: canGoNext,
      onPrev: onPrev,
      onNext: onNext,
    );

    final viewMore = onViewMore != null
        ? TextButton(
            onPressed: onViewMore,
            style: EmployeeDashUi.ghostAction(context),
            child: const Text('View more'),
          )
        : null;

    if (narrow) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Attendance Overview', style: titleStyle),
          const SizedBox(height: 3),
          Text('Monthly summary · $monthTitle', style: subtitleStyle),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: nav),
              if (viewMore != null) viewMore,
            ],
          ),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Attendance Overview', style: titleStyle),
              const SizedBox(height: 3),
              Text('Monthly summary · $monthTitle', style: subtitleStyle),
            ],
          ),
        ),
        nav,
        if (viewMore != null) ...[const SizedBox(width: 4), viewMore],
      ],
    );
  }
}

class _MonthNavPill extends StatelessWidget {
  const _MonthNavPill({
    required this.monthTitle,
    required this.canGoNext,
    required this.onPrev,
    required this.onNext,
  });

  final String monthTitle;
  final bool canGoNext;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.dashMutedSurfaceOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppTheme.primaryNavy.withValues(alpha: 0.12),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: onPrev,
            borderRadius: const BorderRadius.horizontal(
              left: Radius.circular(10),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              child: Icon(
                Icons.chevron_left_rounded,
                size: 22,
                color: AppTheme.dashTextPrimaryOf(context),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              monthTitle,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: AppTheme.dashTextPrimaryOf(context),
              ),
            ),
          ),
          InkWell(
            onTap: canGoNext ? onNext : null,
            borderRadius: const BorderRadius.horizontal(
              right: Radius.circular(10),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              child: Icon(
                Icons.chevron_right_rounded,
                size: 22,
                color: canGoNext
                    ? AppTheme.dashTextPrimaryOf(context)
                    : AppTheme.dashTextSecondaryOf(context)
                        .withValues(alpha: 0.35),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DistributionPanel extends StatelessWidget {
  const _DistributionPanel({
    required this.narrow,
    required this.summary,
    required this.barData,
  });

  final bool narrow;
  final MonthlyAttendanceSummary summary;
  final List<MonthlyCategoryBarDatum> barData;

  String _throughLine() {
    final d = summary.lastStatsDay;
    final m = kAttendanceOverviewMonthNames[d.month - 1];
    return 'Data through $m ${d.day}, ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        narrow ? 12 : 14,
        narrow ? 10 : 12,
        narrow ? 12 : 14,
        narrow ? 10 : 12,
      ),
      decoration: BoxDecoration(
        color: AppTheme.dashMutedSurfaceOf(context).withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                'Distribution',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: narrow ? 12.5 : 13,
                  color: AppTheme.dashTextPrimaryOf(context),
                ),
              ),
              const Spacer(),
              Text(
                '${summary.totalCategorized} days',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.dashTextSecondaryOf(context)
                      .withValues(alpha: 0.9),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            _throughLine(),
            style: TextStyle(
              fontSize: 10.5,
              color: AppTheme.dashTextSecondaryOf(context)
                  .withValues(alpha: 0.78),
            ),
          ),
          SizedBox(height: narrow ? 8 : 10),
          MonthlyCategoryBarChart(
            data: barData,
            maxBarHeight: narrow ? 82 : 92,
          ),
        ],
      ),
    );
  }
}

class _EmptyBody extends StatelessWidget {
  const _EmptyBody({required this.monthTitle});

  final String monthTitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 14),
      decoration: BoxDecoration(
        color: AppTheme.dashMutedSurfaceOf(context).withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
      ),
      child: Column(
        children: [
          Icon(
            Icons.inbox_outlined,
            size: 36,
            color: AppTheme.dashTextSecondaryOf(context).withValues(alpha: 0.45),
          ),
          const SizedBox(height: 10),
          Text(
            'No attendance data',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: AppTheme.dashTextPrimaryOf(context),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            'No time records for $monthTitle. Data will appear after '
            'clock events or approved imports.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              color: AppTheme.dashTextSecondaryOf(context)
                  .withValues(alpha: 0.92),
            ),
          ),
        ],
      ),
    );
  }
}
