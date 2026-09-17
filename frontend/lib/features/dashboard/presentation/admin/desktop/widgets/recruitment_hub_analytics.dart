import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/dashboard/presentation/admin/desktop/widgets/recruitment_monitoring_stats.dart';
import 'package:hrms_plaridel/features/recruitment/models/recruitment_application.dart';

/// RSP monitoring content for the admin dashboard home.
class RecruitmentHubAnalyticsPanel extends StatelessWidget {
  const RecruitmentHubAnalyticsPanel({
    super.key,
    required this.stats,
    required this.activeApplications,
    required this.dateLabel,
    this.hiringOpen,
    this.listedPositionCount,
  });

  final RecruitmentMonitoringStats stats;
  final List<RecruitmentApplication> activeApplications;
  final String Function(DateTime?) dateLabel;
  final bool? hiringOpen;
  final int? listedPositionCount;

  static const _pending = Color(0xFFD97706);
  static const _progress = Color(0xFF1565C0);
  static const _hired = Color(0xFF2E7D32);
  static const _attention = Color(0xFFC62828);

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isDesktop = width >= 960;
    final isMobile = width < 720;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _KpiGrid(
          stats: stats,
          hiringOpen: hiringOpen,
          listedPositionCount: listedPositionCount,
        ),
        const SizedBox(height: 14),
        _SectionCard(
          title: 'Recruitment Pipeline',
          subtitle: 'Where applicants currently are in the hiring process',
          child: _PipelineTracker(stages: stats.pipeline),
        ),
        const SizedBox(height: 14),
        if (isDesktop)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 6,
                child: _SectionCard(
                  title: 'Application Trend',
                  subtitle: 'Applications received over the last 6 months',
                  child: _ApplicationTrendChart(
                    months: stats.monthlySubmissions,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                flex: 4,
                child: Column(
                  children: [
                    _SectionCard(
                      title: 'Status Breakdown',
                      subtitle: 'Applicants by current recruitment status',
                      child: _StatusBreakdownList(items: stats.statusBreakdown),
                    ),
                    const SizedBox(height: 14),
                    _RequiresAttentionCard(items: stats.attention),
                  ],
                ),
              ),
            ],
          )
        else ...[
          _SectionCard(
            title: 'Application Trend',
            subtitle: 'Applications received over the last 6 months',
            child: _ApplicationTrendChart(months: stats.monthlySubmissions),
          ),
          const SizedBox(height: 14),
          _SectionCard(
            title: 'Status Breakdown',
            subtitle: 'Applicants by current recruitment status',
            child: _StatusBreakdownList(items: stats.statusBreakdown),
          ),
          const SizedBox(height: 14),
          _RequiresAttentionCard(items: stats.attention),
        ],
        const SizedBox(height: 14),
        _SectionCard(
          title: 'Active Applications',
          subtitle: 'Latest applicants and their current recruitment stage',
          child: isMobile
              ? _ActiveApplicationCards(
                  applications: activeApplications,
                  dateLabel: dateLabel,
                )
              : _ActiveApplicationTable(
                  applications: activeApplications,
                  dateLabel: dateLabel,
                ),
        ),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
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
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: AppTheme.dashPanelOf(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: AppTheme.dashIsDark(context) ? 0.22 : 0.04,
            ),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: AppTheme.dashTextPrimaryOf(context),
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(
              color: AppTheme.dashTextSecondaryOf(context),
              fontSize: 12,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _KpiGrid extends StatelessWidget {
  const _KpiGrid({
    required this.stats,
    required this.hiringOpen,
    required this.listedPositionCount,
  });

  final RecruitmentMonitoringStats stats;
  final bool? hiringOpen;
  final int? listedPositionCount;

  @override
  Widget build(BuildContext context) {
    final vacancyValue = hiringOpen == null
        ? '—'
        : (hiringOpen! ? 'Open' : 'Closed');
    String vacancyHint;
    if (hiringOpen == null) {
      vacancyHint = 'Unable to load';
    } else if (hiringOpen! && (listedPositionCount ?? 0) > 0) {
      final n = listedPositionCount!;
      vacancyHint = n == 1 ? '1 posted position' : '$n posted positions';
    } else if (hiringOpen!) {
      vacancyHint = 'Hiring active';
    } else {
      vacancyHint = 'Hiring inactive';
    }

    final cards = [
      _KpiCard(
        label: 'Total Applicants',
        value: '${stats.total}',
        icon: Icons.groups_rounded,
        accent: AppTheme.primaryNavy,
      ),
      _KpiCard(
        label: 'Pending Review',
        value: '${stats.pending}',
        icon: Icons.hourglass_top_rounded,
        accent: RecruitmentHubAnalyticsPanel._pending,
      ),
      _KpiCard(
        label: 'Active Recruitment',
        value: '${stats.inProgress}',
        icon: Icons.timelapse_rounded,
        accent: RecruitmentHubAnalyticsPanel._progress,
        hint: 'In progress',
      ),
      _KpiCard(
        label: 'Job Vacancies',
        value: vacancyValue,
        icon: Icons.work_outline_rounded,
        accent: hiringOpen == true
            ? RecruitmentHubAnalyticsPanel._hired
            : AppTheme.primaryNavy,
        hint: vacancyHint,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final columns = w >= 960 ? 4 : (w >= 420 ? 2 : 1);
        const gap = 12.0;
        final itemWidth = columns == 1
            ? w
            : (w - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final card in cards) SizedBox(width: itemWidth, child: card),
          ],
        );
      },
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
    this.hint,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color accent;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 92),
      decoration: BoxDecoration(
        color: AppTheme.dashPanelOf(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: AppTheme.dashIsDark(context) ? 0.2 : 0.035,
            ),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          Container(width: 4, color: accent),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, size: 18, color: accent),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppTheme.dashTextPrimaryOf(context),
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            height: 1.1,
                            letterSpacing: -0.4,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppTheme.dashTextSecondaryOf(context),
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (hint != null) ...[
                          const SizedBox(height: 1),
                          Text(
                            hint!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppTheme.dashTextSecondaryOf(
                                context,
                              ).withValues(alpha: 0.9),
                              fontSize: 10.5,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PipelineTracker extends StatelessWidget {
  const _PipelineTracker({required this.stages});

  final List<RecruitmentPipelineStage> stages;

  @override
  Widget build(BuildContext context) {
    if (stages.every((s) => s.count == 0)) {
      return Text(
        'Pipeline counts appear once applications are recorded.',
        style: TextStyle(
          color: AppTheme.dashTextSecondaryOf(context),
          fontSize: 13,
          height: 1.4,
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 760;
        if (compact) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < stages.length; i++) ...[
                  SizedBox(
                    width: 108,
                    child: _PipelineStageChip(stage: stages[i]),
                  ),
                  if (i < stages.length - 1) const _PipelineConnector(),
                ],
              ],
            ),
          );
        }
        return Row(
          children: [
            for (var i = 0; i < stages.length; i++) ...[
              Expanded(child: _PipelineStageChip(stage: stages[i])),
              if (i < stages.length - 1) const _PipelineConnector(),
            ],
          ],
        );
      },
    );
  }
}

class _PipelineConnector extends StatelessWidget {
  const _PipelineConnector();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Icon(
        Icons.chevron_right_rounded,
        size: 16,
        color: AppTheme.dashTextSecondaryOf(context).withValues(alpha: 0.55),
      ),
    );
  }
}

class _PipelineStageChip extends StatelessWidget {
  const _PipelineStageChip({required this.stage});

  final RecruitmentPipelineStage stage;

  @override
  Widget build(BuildContext context) {
    final active = stage.count > 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: active
            ? AppTheme.primaryNavy.withValues(alpha: 0.06)
            : AppTheme.dashMutedSurfaceOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: active
              ? AppTheme.primaryNavy.withValues(alpha: 0.22)
              : AppTheme.dashHairlineOf(context),
        ),
      ),
      child: Column(
        children: [
          Text(
            '${stage.count}',
            style: TextStyle(
              color: active
                  ? AppTheme.dashTextPrimaryOf(context)
                  : AppTheme.dashTextSecondaryOf(context),
              fontSize: 20,
              fontWeight: FontWeight.w800,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            stage.label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: AppTheme.dashTextSecondaryOf(context),
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _ApplicationTrendChart extends StatelessWidget {
  const _ApplicationTrendChart({required this.months});

  final List<RecruitmentMonthCount> months;

  @override
  Widget build(BuildContext context) {
    final maxVal = months.fold<int>(0, (m, e) => e.count > m ? e.count : m);
    final maxY = (maxVal + 1).clamp(2, 20).toDouble();
    final barColor = AppTheme.primaryNavy;
    final hasData = maxVal > 0;

    return SizedBox(
      height: 168,
      child: BarChart(
        BarChartData(
          maxY: maxY,
          barTouchData: BarTouchData(
            enabled: true,
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => const Color(0xFF1F2937),
              tooltipPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 8,
              ),
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                if (group.x < 0 || group.x >= months.length) return null;
                final n = rod.toY.toInt();
                return BarTooltipItem(
                  '${months[group.x].label}\n$n ${n == 1 ? 'application' : 'applications'}',
                  const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                );
              },
            ),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: 1,
            getDrawingHorizontalLine: (v) =>
                FlLine(color: AppTheme.dashHairlineOf(context), strokeWidth: 1),
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
                reservedSize: 26,
                interval: 1,
                getTitlesWidget: (v, meta) {
                  if (v % 1 != 0) return const SizedBox.shrink();
                  return Text(
                    v.toInt().toString(),
                    style: TextStyle(
                      fontSize: 10,
                      color: AppTheme.dashTextSecondaryOf(context),
                    ),
                  );
                },
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
                  width: 16,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(5),
                  ),
                  color: hasData ? barColor : barColor.withValues(alpha: 0.28),
                ),
              ],
            );
          }),
        ),
        duration: const Duration(milliseconds: 280),
      ),
    );
  }
}

class _StatusBreakdownList extends StatelessWidget {
  const _StatusBreakdownList({required this.items});

  final List<RecruitmentStatusCount> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Text(
        'Status counts appear once applications are recorded.',
        style: TextStyle(
          color: AppTheme.dashTextSecondaryOf(context),
          fontSize: 13,
          height: 1.4,
        ),
      );
    }

    final maxVal = items.first.count.toDouble();
    return Column(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _StatusRow(label: items[i].label, value: items[i].count, max: maxVal),
        ],
      ],
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.label,
    required this.value,
    required this.max,
  });

  final String label;
  final int value;
  final double max;

  @override
  Widget build(BuildContext context) {
    final fraction = max <= 0 ? 0.0 : (value / max).clamp(0.0, 1.0);
    return Row(
      children: [
        Expanded(
          flex: 4,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTheme.dashTextSecondaryOf(context),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 5,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: SizedBox(
              height: 7,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(color: AppTheme.dashHairlineOf(context)),
                  FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: fraction,
                    child: const ColoredBox(color: AppTheme.primaryNavy),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 24,
          child: Text(
            '$value',
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: AppTheme.dashTextPrimaryOf(context),
            ),
          ),
        ),
      ],
    );
  }
}

class _RequiresAttentionCard extends StatelessWidget {
  const _RequiresAttentionCard({required this.items});

  final List<RecruitmentAttentionItem> items;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Requires Attention',
      subtitle: 'Existing statuses that currently need HR action',
      child: items.isEmpty
          ? Text(
              'No recruitment items currently require immediate action.',
              style: TextStyle(
                color: AppTheme.dashTextSecondaryOf(context),
                fontSize: 13,
                height: 1.4,
              ),
            )
          : Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final item in items)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: RecruitmentHubAnalyticsPanel._attention.withValues(
                        alpha: 0.06,
                      ),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: RecruitmentHubAnalyticsPanel._attention
                            .withValues(alpha: 0.18),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${item.count}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                            color: RecruitmentHubAnalyticsPanel._attention,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          item.label,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.dashTextPrimaryOf(context),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

class _ActiveApplicationTable extends StatelessWidget {
  const _ActiveApplicationTable({
    required this.applications,
    required this.dateLabel,
  });

  final List<RecruitmentApplication> applications;
  final String Function(DateTime?) dateLabel;

  @override
  Widget build(BuildContext context) {
    if (applications.isEmpty) {
      return Text(
        'No active applications',
        style: TextStyle(
          color: AppTheme.dashTextSecondaryOf(context),
          fontSize: 13,
          height: 1.4,
        ),
      );
    }

    return Column(
      children: [
        _TableHeaderRow(),
        const Divider(height: 1),
        for (var i = 0; i < applications.length; i++) ...[
          _ApplicantTableRow(
            application: applications[i],
            dateLabel: dateLabel,
          ),
          if (i < applications.length - 1) const Divider(height: 1),
        ],
      ],
    );
  }
}

class _TableHeaderRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontWeight: FontWeight.w700,
      fontSize: 11,
      letterSpacing: 0.4,
      color: AppTheme.dashTextSecondaryOf(context),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
      child: Row(
        children: [
          Expanded(flex: 3, child: Text('APPLICANT', style: style)),
          Expanded(flex: 2, child: Text('POSITION', style: style)),
          Expanded(flex: 2, child: Text('APPLIED DATE', style: style)),
          Expanded(flex: 2, child: Text('CURRENT STAGE', style: style)),
        ],
      ),
    );
  }
}

class _ApplicantTableRow extends StatefulWidget {
  const _ApplicantTableRow({
    required this.application,
    required this.dateLabel,
  });

  final RecruitmentApplication application;
  final String Function(DateTime?) dateLabel;

  @override
  State<_ApplicantTableRow> createState() => _ApplicantTableRowState();
}

class _ApplicantTableRowState extends State<_ApplicantTableRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final a = widget.application;
    final name = a.fullName.trim().isEmpty
        ? '(Unnamed applicant)'
        : a.fullName.trim();
    final position = (a.positionAppliedFor?.trim().isNotEmpty ?? false)
        ? a.positionAppliedFor!.trim()
        : 'Recruitment';
    final hoverColor = AppTheme.dashMutedSurfaceOf(context);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        color: _hovered ? hoverColor : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Row(
                children: [
                  _ApplicantAvatar(name: name),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppTheme.dashTextPrimaryOf(context),
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          a.email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppTheme.dashTextSecondaryOf(context),
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                position,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  color: AppTheme.dashTextSecondaryOf(context),
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                widget.dateLabel(a.createdAt),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  color: AppTheme.dashTextSecondaryOf(context),
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Align(
                alignment: Alignment.centerLeft,
                child: _StageBadge(
                  label: RecruitmentMonitoringStats.detailedStageLabel(a),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActiveApplicationCards extends StatelessWidget {
  const _ActiveApplicationCards({
    required this.applications,
    required this.dateLabel,
  });

  final List<RecruitmentApplication> applications;
  final String Function(DateTime?) dateLabel;

  @override
  Widget build(BuildContext context) {
    if (applications.isEmpty) {
      return Text(
        'No active applications',
        style: TextStyle(
          color: AppTheme.dashTextSecondaryOf(context),
          fontSize: 13,
          height: 1.4,
        ),
      );
    }

    return Column(
      children: [
        for (var i = 0; i < applications.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _ApplicantMobileCard(
            application: applications[i],
            dateLabel: dateLabel,
          ),
        ],
      ],
    );
  }
}

class _ApplicantMobileCard extends StatelessWidget {
  const _ApplicantMobileCard({
    required this.application,
    required this.dateLabel,
  });

  final RecruitmentApplication application;
  final String Function(DateTime?) dateLabel;

  @override
  Widget build(BuildContext context) {
    final a = application;
    final name = a.fullName.trim().isEmpty
        ? '(Unnamed applicant)'
        : a.fullName.trim();
    final position = (a.positionAppliedFor?.trim().isNotEmpty ?? false)
        ? a.positionAppliedFor!.trim()
        : 'Recruitment';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.dashMutedSurfaceOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _ApplicantAvatar(name: name),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppTheme.dashTextPrimaryOf(context),
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      position,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppTheme.dashTextSecondaryOf(context),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Applied: ${dateLabel(a.createdAt)}',
            style: TextStyle(
              color: AppTheme.dashTextSecondaryOf(context),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          _StageBadge(label: RecruitmentMonitoringStats.detailedStageLabel(a)),
        ],
      ),
    );
  }
}

class _ApplicantAvatar extends StatelessWidget {
  const _ApplicantAvatar({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 15,
      backgroundColor: AppTheme.primaryNavy.withValues(alpha: 0.12),
      child: Text(
        _initials(name),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: AppTheme.primaryNavy,
        ),
      ),
    );
  }
}

class _StageBadge extends StatelessWidget {
  const _StageBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.primaryNavy.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppTheme.primaryNavy.withValues(alpha: 0.22)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppTheme.primaryNavy,
        ),
      ),
    );
  }
}

String _initials(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((p) => p.isNotEmpty && p != '(' && !p.startsWith('('))
      .toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) {
    final s = parts.first;
    return s.substring(0, s.length >= 2 ? 2 : 1).toUpperCase();
  }
  return (parts.first[0] + parts.last[0]).toUpperCase();
}
