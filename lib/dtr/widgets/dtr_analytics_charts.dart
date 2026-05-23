import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../landingpage/constants/app_theme.dart';

// --- Public chart widgets (data-driven) ---------------------------------------------------------

/// Line chart: Present, Late, Undertime, Absent (30 points: oldest → newest day).
class AttendanceTrendLineChart extends StatelessWidget {
  const AttendanceTrendLineChart({
    super.key,
    required this.presentByDay,
    required this.lateByDay,
    required this.undertimeByDay,
    required this.absentByDay,
    this.height = 240,
    this.loading = false,
  });

  final List<int> presentByDay;
  final List<int> lateByDay;
  final List<int> undertimeByDay;
  final List<int> absentByDay;
  final double height;
  final bool loading;

  static const _present = Color(0xFF2E7D32);
  static const _late = Color(0xFFE85D04);
  static const _undertime = Color(0xFF1565C0);
  static const _absent = Color(0xFF616161);

  static List<int> _len30(List<int> v) =>
      v.length == 30 ? v : List<int>.filled(30, 0);

  @override
  Widget build(BuildContext context) {
    if (loading && presentByDay.isEmpty) {
      return SizedBox(
        height: height,
        child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    final p = _len30(presentByDay);
    final l = _len30(lateByDay);
    final u = _len30(undertimeByDay);
    final a = _len30(absentByDay);

    var maxVal = 0;
    for (var i = 0; i < 30; i++) {
      final m = [p[i], l[i], u[i], a[i]].reduce((x, y) => x > y ? x : y);
      if (m > maxVal) maxVal = m;
    }
    final maxY = (maxVal + 5).clamp(5, 200).toDouble();

    List<FlSpot> toSpots(List<int> series) => List<FlSpot>.generate(
      30,
      (i) => FlSpot((i + 1).toDouble(), series[i].toDouble()),
    );

    final seriesColors = [_present, _late, _undertime, _absent];
    final seriesLabels = ['Present', 'Late', 'Undertime', 'Absent'];

    LineChartBarData lineBar(
      List<FlSpot> spotList,
      Color color, {
      double dotR = 2.5,
      double fillTop = 0.14,
    }) {
      return LineChartBarData(
        spots: spotList,
        isCurved: true,
        curveSmoothness: 0.22,
        color: color,
        barWidth: 2,
        isStrokeCapRound: true,
        dotData: FlDotData(
          show: true,
          getDotPainter: (s, p, b, i) => FlDotCirclePainter(
            radius: dotR,
            color: color,
            strokeWidth: 1,
            strokeColor: Colors.white,
          ),
        ),
        belowBarData: BarAreaData(
          show: true,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              color.withValues(alpha: fillTop),
              color.withValues(alpha: 0.02),
            ],
          ),
        ),
      );
    }

    final gridColor = AppTheme.dashIsDark(context)
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.06);
    final borderColor = AppTheme.dashIsDark(context)
        ? Colors.white.withValues(alpha: 0.12)
        : Colors.black.withValues(alpha: 0.12);
    final axisLabelColor = AppTheme.dashTextSecondaryOf(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ChartLegend(
          items: [
            _LegendItem(color: _present, label: 'Present'),
            _LegendItem(color: _late, label: 'Late'),
            _LegendItem(color: _undertime, label: 'Undertime'),
            _LegendItem(color: _absent, label: 'Absent'),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: height,
          width: double.infinity,
          child: LineChart(
            LineChartData(
              minX: 1,
              maxX: 30,
              minY: 0,
              maxY: maxY,
              clipData: const FlClipData.all(),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: maxY > 20 ? 5 : (maxY / 5).ceilToDouble(),
                getDrawingHorizontalLine: (v) =>
                    FlLine(color: gridColor, strokeWidth: 1),
              ),
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
                    reservedSize: 32,
                    interval: maxY > 20 ? 5 : 1,
                    getTitlesWidget: (v, m) => Text(
                      v.toInt().toString(),
                      style: TextStyle(fontSize: 10, color: axisLabelColor),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 22,
                    interval: 5,
                    getTitlesWidget: (v, m) {
                      final n = v.toInt();
                      if (n == 1 || n == 10 || n == 20 || n == 30) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            '$n',
                            style: TextStyle(
                              fontSize: 10,
                              color: axisLabelColor,
                            ),
                          ),
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                ),
              ),
              borderData: FlBorderData(
                show: true,
                border: Border(
                  bottom: BorderSide(color: borderColor),
                  left: BorderSide(color: borderColor),
                ),
              ),
              lineTouchData: LineTouchData(
                enabled: true,
                touchTooltipData: LineTouchTooltipData(
                  tooltipRoundedRadius: 8,
                  tooltipPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  maxContentWidth: 220,
                  // Default fl_chart tooltip is dark; series colors (esp. grey/blue) fail contrast.
                  getTooltipColor: (_) => AppTheme.dashPanelOf(context),
                  tooltipBorder: BorderSide(
                    color: AppTheme.dashHairlineOf(context),
                  ),
                  getTooltipItems: (touched) {
                    return touched.map((s) {
                      final idx = s.barIndex.clamp(0, 3);
                      final color = seriesColors[idx];
                      final label = seriesLabels[idx];
                      return LineTooltipItem(
                        '$label: ${s.y.toStringAsFixed(0)}',
                        TextStyle(
                          color: color,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          height: 1.25,
                        ),
                      );
                    }).toList();
                  },
                ),
              ),
              lineBarsData: [
                lineBar(toSpots(p), _present, fillTop: 0.18),
                lineBar(toSpots(l), _late, fillTop: 0.15),
                lineBar(toSpots(u), _undertime, dotR: 2, fillTop: 0.12),
                lineBar(toSpots(a), _absent, dotR: 2, fillTop: 0.1),
              ],
            ),
            duration: Duration.zero,
          ),
        ),
      ],
    );
  }
}

/// Late or undertime distinct employee-days by department (column chart).
class DepartmentIssueBarChart extends StatelessWidget {
  const DepartmentIssueBarChart({
    super.key,
    required this.countsByDepartment,
    required this.legendLabel,
    required this.emptyMessage,
    this.height = 200,
    this.loading = false,
  });

  final Map<String, int> countsByDepartment;
  final String legendLabel;
  final String emptyMessage;
  final double height;
  final bool loading;

  static final _barColors = [
    const Color(0xFFE85D04),
    const Color(0xFFFB923C),
    const Color(0xFFF59E0B),
    const Color(0xFFEA580C),
    const Color(0xFFCA8A04),
    const Color(0xFFC2410C),
    const Color(0xFF9A3412),
    const Color(0xFF7C2D12),
  ];

  @override
  Widget build(BuildContext context) {
    if (loading && countsByDepartment.isEmpty) {
      return SizedBox(
        height: height,
        child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    final entries = countsByDepartment.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = entries.take(8).toList();
    if (top.isEmpty) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(
            emptyMessage,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: AppTheme.dashTextSecondaryOf(context),
            ),
          ),
        ),
      );
    }

    final gridColor = AppTheme.dashIsDark(context)
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.06);
    final borderColor = AppTheme.dashIsDark(context)
        ? Colors.white.withValues(alpha: 0.12)
        : Colors.black.withValues(alpha: 0.12);
    final axisLabelColor = AppTheme.dashTextSecondaryOf(context);
    final axisPrimaryColor = AppTheme.dashTextPrimaryOf(context);

    final maxY =
        ((top.map((e) => e.value).reduce((a, b) => a > b ? a : b) * 1.15)
                .ceilToDouble()
                .clamp(3, 500))
            .toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ChartLegend(
          items: [
            _LegendItem(
              color: AppTheme.primaryNavy.withValues(alpha: 0.9),
              label: legendLabel,
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: height,
          width: double.infinity,
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: maxY,
              minY: 0,
              groupsSpace: 12,
              barTouchData: BarTouchData(
                enabled: true,
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (_) => AppTheme.dashPanelOf(context),
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    final name = top[group.x.toInt()].key;
                    return BarTooltipItem(
                      '$name\n',
                      TextStyle(
                        color: axisPrimaryColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                      children: [
                        TextSpan(
                          text: rod.toY.toStringAsFixed(0),
                          style: TextStyle(
                            color: axisPrimaryColor,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
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
                    interval: maxY > 10 ? 5 : 1,
                    getTitlesWidget: (v, m) => Text(
                      v.toInt().toString(),
                      style: TextStyle(fontSize: 10, color: axisLabelColor),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 36,
                    interval: 1,
                    getTitlesWidget: (v, m) {
                      final i = v.toInt();
                      if (i >= 0 && i < top.length) {
                        final label = top[i].key;
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            label.length > 10
                                ? '${label.substring(0, 9)}…'
                                : label,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              color: axisPrimaryColor,
                            ),
                          ),
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                ),
              ),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: maxY > 15 ? 5 : 2,
                getDrawingHorizontalLine: (v) =>
                    FlLine(color: gridColor, strokeWidth: 1),
              ),
              borderData: FlBorderData(
                show: true,
                border: Border(
                  bottom: BorderSide(color: borderColor),
                  left: BorderSide(color: borderColor),
                ),
              ),
              barGroups: List<BarChartGroupData>.generate(top.length, (i) {
                final c = _barColors[i % _barColors.length];
                return BarChartGroupData(
                  x: i,
                  barRods: [
                    BarChartRodData(
                      toY: top[i].value.toDouble(),
                      width: 18,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(4),
                        topRight: Radius.circular(4),
                      ),
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [c.withValues(alpha: 0.75), c],
                      ),
                    ),
                  ],
                );
              }),
            ),
            duration: Duration.zero,
          ),
        ),
      ],
    );
  }
}

/// Donut chart for leave type distribution.
class LeaveDistributionPieChart extends StatelessWidget {
  const LeaveDistributionPieChart({
    super.key,
    required this.leaveByType,
    required this.leaveDataAvailable,
    this.height = 200,
    this.loading = false,
  });

  final Map<String, double> leaveByType;
  final bool leaveDataAvailable;
  final double height;
  final bool loading;

  static final _palette = [
    const Color(0xFF2E7D32),
    const Color(0xFFC62828),
    const Color(0xFFE65100),
    const Color(0xFF1565C0),
    const Color(0xFF6A1B9A),
    const Color(0xFF00838F),
    const Color(0xFF827717),
    const Color(0xFF37474F),
  ];

  @override
  Widget build(BuildContext context) {
    if (loading && leaveByType.isEmpty) {
      return SizedBox(
        height: height,
        child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    if (!leaveDataAvailable) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(
            'Leave data unavailable (check connection or permissions).',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: AppTheme.dashTextSecondaryOf(context),
            ),
          ),
        ),
      );
    }

    final entries = leaveByType.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (entries.isEmpty) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(
            'No approved leave in this period.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: AppTheme.dashTextSecondaryOf(context),
            ),
          ),
        ),
      );
    }

    final total = entries.fold<double>(0, (s, e) => s + e.value);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ChartLegend(
          items: List<_LegendItem>.generate(entries.length, (i) {
            final e = entries[i];
            final pct = total > 0 ? (e.value / total * 100) : 0.0;
            return _LegendItem(
              color: _palette[i % _palette.length],
              label: '${e.key} (${pct.toStringAsFixed(1)}%)',
            );
          }),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: height,
          width: double.infinity,
          child: PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 52,
              sections: List<PieChartSectionData>.generate(entries.length, (i) {
                final e = entries[i];
                final pct = total > 0 ? (e.value / total * 100) : 0.0;
                final col = _palette[i % _palette.length];
                return PieChartSectionData(
                  color: col,
                  value: e.value,
                  title: '${pct.toStringAsFixed(0)}%',
                  radius: 58,
                  titleStyle: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    shadows: [Shadow(blurRadius: 2, color: Colors.black26)],
                  ),
                  titlePositionPercentageOffset: 0.62,
                );
              }),
              pieTouchData: PieTouchData(enabled: true),
            ),
            duration: Duration.zero,
          ),
        ),
      ],
    );
  }
}

// --- Shared legend ------------------------------------------------------------------------------

class _LegendItem {
  const _LegendItem({required this.color, required this.label});

  final Color color;
  final String label;
}

class _ChartLegend extends StatelessWidget {
  const _ChartLegend({required this.items});

  final List<_LegendItem> items;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 16,
      runSpacing: 8,
      children: items
          .map(
            (e) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: e.color,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  e.label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.dashTextSecondaryOf(context),
                  ),
                ),
              ],
            ),
          )
          .toList(),
    );
  }
}
