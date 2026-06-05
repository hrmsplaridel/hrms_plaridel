import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/recruitment/models/recruitment_application.dart';

/// Analytics charts for the admin dashboard recruitment hub.
class RecruitmentHubAnalyticsPanel extends StatelessWidget {
  const RecruitmentHubAnalyticsPanel({
    super.key,
    required this.applications,
    required this.pending,
    required this.inProgress,
    required this.hired,
    required this.closed,
    required this.total,
  });

  final List<RecruitmentApplication> applications;
  final int pending;
  final int inProgress;
  final int hired;
  final int closed;
  final int total;

  static const _pendingColor = AppTheme.primaryNavy;
  static const _progressColor = Color(0xFF1565C0);
  static const _hiredColor = Color(0xFF2E7D32);
  static const _closedColor = Color(0xFF6A1B9A);

  int get _thisMonthCount {
    final now = DateTime.now();
    return applications.where((a) {
      final dt = a.createdAt?.toLocal();
      return dt != null && dt.year == now.year && dt.month == now.month;
    }).length;
  }

  double get _hireRate => total == 0 ? 0 : (hired / total) * 100;

  List<({String label, int count})> get _monthlySubmissions {
    final now = DateTime.now();
    final months = <DateTime>[];
    for (var i = 5; i >= 0; i--) {
      var y = now.year;
      var m = now.month - i;
      while (m < 1) {
        m += 12;
        y -= 1;
      }
      months.add(DateTime(y, m, 1));
    }

    final counts = {for (final d in months) d: 0};
    for (final app in applications) {
      final dt = app.createdAt?.toLocal();
      if (dt == null) continue;
      final key = DateTime(dt.year, dt.month, 1);
      if (counts.containsKey(key)) counts[key] = counts[key]! + 1;
    }

    const shortMonths = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return months
        .map(
          (d) => (
            label: shortMonths[d.month - 1],
            count: counts[d] ?? 0,
          ),
        )
        .toList();
  }

  Map<String, int> get _statusBreakdown {
    final map = <String, int>{};
    for (final app in applications) {
      final label = _statusLabel(app.status);
      map[label] = (map[label] ?? 0) + 1;
    }
    return map;
  }

  static String _statusLabel(String status) {
    switch (status) {
      case 'submitted':
        return 'Pending review';
      case 'document_approved':
        return 'Docs approved';
      case 'document_declined':
        return 'Docs declined';
      case 'exam_taken':
        return 'Exam taken';
      case 'passed':
        return 'Passed exam';
      case 'failed':
        return 'Failed exam';
      case 'registered':
        return 'Hired';
      default:
        return status.replaceAll('_', ' ');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (total == 0) {
      return _RecruitmentAnalyticsEmptyState(
        monthlyLabels: _monthlySubmissions.map((e) => e.label).toList(),
      );
    }

    final isWide = MediaQuery.sizeOf(context).width > 720;
    final pipelineSegments = [
      if (pending > 0) (label: 'Pending', count: pending, color: _pendingColor),
      if (inProgress > 0)
        (label: 'In progress', count: inProgress, color: _progressColor),
      if (hired > 0) (label: 'Hired', count: hired, color: _hiredColor),
      if (closed > 0) (label: 'Closed', count: closed, color: _closedColor),
    ];

    final charts = isWide
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _AnalyticsChartCard(
                  title: 'Pipeline distribution',
                  subtitle: 'Share of applicants by stage',
                  child: _PipelineDonutChart(
                    segments: pipelineSegments,
                    total: total,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _AnalyticsChartCard(
                  title: 'Submissions trend',
                  subtitle: 'New applications (last 6 months)',
                  child: _SubmissionsBarChart(months: _monthlySubmissions),
                ),
              ),
            ],
          )
        : Column(
            children: [
              _AnalyticsChartCard(
                title: 'Pipeline distribution',
                subtitle: 'Share of applicants by stage',
                child: _PipelineDonutChart(
                  segments: pipelineSegments,
                  total: total,
                ),
              ),
              const SizedBox(height: 14),
              _AnalyticsChartCard(
                title: 'Submissions trend',
                subtitle: 'New applications (last 6 months)',
                child: _SubmissionsBarChart(months: _monthlySubmissions),
              ),
            ],
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _InsightChip(
              label: 'Hire rate',
              value: '${_hireRate.toStringAsFixed(0)}%',
              icon: Icons.trending_up_rounded,
              color: _hiredColor,
            ),
            _InsightChip(
              label: 'This month',
              value: '$_thisMonthCount',
              icon: Icons.calendar_month_rounded,
              color: _pendingColor,
            ),
            _InsightChip(
              label: 'In pipeline',
              value: '${pending + inProgress}',
              icon: Icons.sync_rounded,
              color: _progressColor,
            ),
            _InsightChip(
              label: 'Closed out',
              value: '$closed',
              icon: Icons.archive_outlined,
              color: _closedColor,
            ),
          ],
        ),
        const SizedBox(height: 16),
        charts,
        const SizedBox(height: 14),
        _AnalyticsChartCard(
          title: 'Status breakdown',
          subtitle: 'Applicants by current recruitment status',
          child: _StatusBreakdownChart(breakdown: _statusBreakdown),
        ),
      ],
    );
  }
}

class _RecruitmentAnalyticsEmptyState extends StatelessWidget {
  const _RecruitmentAnalyticsEmptyState({required this.monthlyLabels});

  final List<String> monthlyLabels;

  @override
  Widget build(BuildContext context) {
    final secondary = AppTheme.dashTextSecondaryOf(context);
    final zeroMonths = monthlyLabels
        .map((label) => (label: label, count: 0))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _AnalyticsChartCard(
          title: 'Submissions trend',
          subtitle: 'New applications (last 6 months)',
          child: Column(
            children: [
              _SubmissionsBarChart(months: zeroMonths, muted: true),
              const SizedBox(height: 12),
              Text(
                'Charts will populate when applicants submit recruitment forms.',
                textAlign: TextAlign.center,
                style: TextStyle(color: secondary, fontSize: 13, height: 1.4),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
          decoration: BoxDecoration(
            color: AppTheme.dashMutedSurfaceOf(context),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.dashHairlineOf(context)),
          ),
          child: Column(
            children: [
              Icon(
                Icons.pie_chart_outline_rounded,
                size: 36,
                color: AppTheme.primaryNavy.withValues(alpha: 0.45),
              ),
              const SizedBox(height: 10),
              Text(
                'No pipeline data yet',
                style: TextStyle(
                  color: AppTheme.dashTextPrimaryOf(context),
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Pipeline donut and status charts appear once applications are recorded.',
                textAlign: TextAlign.center,
                style: TextStyle(color: secondary, fontSize: 13, height: 1.4),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AnalyticsChartCard extends StatelessWidget {
  const _AnalyticsChartCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.dashMutedSurfaceOf(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: AppTheme.dashTextPrimaryOf(context),
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              color: AppTheme.dashTextSecondaryOf(context),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _InsightChip extends StatelessWidget {
  const _InsightChip({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: AppTheme.dashTextSecondaryOf(context),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _PipelineDonutChart extends StatelessWidget {
  const _PipelineDonutChart({
    required this.segments,
    required this.total,
  });

  final List<({String label, int count, Color color})> segments;
  final int total;

  @override
  Widget build(BuildContext context) {
    if (segments.isEmpty || total == 0) {
      return const SizedBox(
        height: 200,
        child: Center(child: Text('No pipeline data')),
      );
    }

    return SizedBox(
      height: 220,
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: PieChart(
              PieChartData(
                sectionsSpace: 2,
                centerSpaceRadius: 42,
                sections: [
                  for (final s in segments)
                    PieChartSectionData(
                      color: s.color,
                      value: s.count.toDouble(),
                      title:
                          '${(s.count / total * 100).toStringAsFixed(0)}%',
                      radius: 52,
                      titleStyle: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                      titlePositionPercentageOffset: 0.58,
                    ),
                ],
              ),
              duration: const Duration(milliseconds: 350),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final s in segments) ...[
                  Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: s.color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${s.label} (${s.count})',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.dashTextSecondaryOf(context),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SubmissionsBarChart extends StatelessWidget {
  const _SubmissionsBarChart({
    required this.months,
    this.muted = false,
  });

  final List<({String label, int count})> months;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final maxVal = months.fold<int>(0, (m, e) => e.count > m ? e.count : m);
    final maxY = (maxVal + 1).clamp(2, 20).toDouble();
    final barColor = muted
        ? AppTheme.dashTextSecondaryOf(context).withValues(alpha: 0.35)
        : AppTheme.primaryNavy;

    return SizedBox(
      height: 200,
      child: BarChart(
        BarChartData(
          maxY: maxY,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: 1,
            getDrawingHorizontalLine: (v) => FlLine(
              color: AppTheme.dashHairlineOf(context),
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                getTitlesWidget: (v, meta) => Text(
                  v.toInt().toString(),
                  style: TextStyle(
                    fontSize: 10,
                    color: AppTheme.dashTextSecondaryOf(context),
                  ),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (v, meta) {
                  final i = v.toInt();
                  if (i < 0 || i >= months.length) return const SizedBox();
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      months[i].label,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.dashTextSecondaryOf(context),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          barGroups: List.generate(months.length, (i) {
            final count = months[i].count;
            return BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: count.toDouble(),
                  width: 18,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(6),
                  ),
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      barColor.withValues(alpha: 0.55),
                      barColor,
                    ],
                  ),
                ),
              ],
            );
          }),
        ),
        duration: const Duration(milliseconds: 350),
      ),
    );
  }
}

class _StatusBreakdownChart extends StatelessWidget {
  const _StatusBreakdownChart({required this.breakdown});

  final Map<String, int> breakdown;

  static const _colors = [
    AppTheme.primaryNavy,
    Color(0xFF1565C0),
    Color(0xFF2E7D32),
    Color(0xFF6A1B9A),
    Color(0xFFC62828),
    Color(0xFFE65100),
    Color(0xFF00838F),
  ];

  @override
  Widget build(BuildContext context) {
    final entries = breakdown.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (entries.isEmpty) {
      return const SizedBox(
        height: 80,
        child: Center(child: Text('No status data')),
      );
    }

    final maxVal = entries.first.value.toDouble();

    return Column(
      children: [
        for (var i = 0; i < entries.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          _HorizontalBarRow(
            label: entries[i].key,
            value: entries[i].value,
            max: maxVal,
            color: _colors[i % _colors.length],
          ),
        ],
      ],
    );
  }
}

class _HorizontalBarRow extends StatelessWidget {
  const _HorizontalBarRow({
    required this.label,
    required this.value,
    required this.max,
    required this.color,
  });

  final String label;
  final int value;
  final double max;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final fraction = max <= 0 ? 0.0 : (value / max).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.dashTextSecondaryOf(context),
                ),
              ),
            ),
            Text(
              '$value',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: AppTheme.dashTextPrimaryOf(context),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: SizedBox(
            height: 10,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(color: AppTheme.dashHairlineOf(context)),
                FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: fraction,
                  child: ColoredBox(color: color),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
