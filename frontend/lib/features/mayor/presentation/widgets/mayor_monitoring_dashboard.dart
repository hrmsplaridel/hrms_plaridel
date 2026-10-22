import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';

/// Compact list row used by Phase 4 monitoring panels.
class MayorDashListItem {
  const MayorDashListItem({
    required this.id,
    required this.applicantName,
    required this.subtitle,
    required this.statusLabel,
    this.referenceNumber,
    this.meetingRequestStatus = 'none',
    this.raw = const {},
  });

  final String id;
  final String applicantName;
  final String subtitle;
  final String statusLabel;
  final String? referenceNumber;
  final String meetingRequestStatus;
  final Map<String, dynamic> raw;
}

class MayorMonitoringSummary {
  const MayorMonitoringSummary({
    required this.totalRequests,
    required this.pendingCount,
    required this.endorsedCount,
    required this.rejectedCount,
    required this.endorsedToday,
    required this.endorsedThisWeek,
    required this.endorsedThisMonth,
    required this.pendingMeetingApprovals,
    required this.pendingFinalDecisions,
    required this.pendingAttendance,
    required this.rescheduleRequestedCount,
    required this.approvedMeetingsCount,
    required this.completedMeetingsCount,
    required this.meetingsToday,
    required this.upcomingMeetingsCount,
    required this.legacyScheduledWithoutMeetingApproval,
    this.requestsToday = 0,
    this.requestsThisWeek = 0,
    this.requestsThisMonth = 0,
    this.rejectedToday = 0,
    this.rejectedThisWeek = 0,
    this.rejectedThisMonth = 0,
    this.meetingsOnToday = 0,
    this.meetingsThisWeek = 0,
    this.meetingsThisMonth = 0,
  });

  final int totalRequests;
  final int pendingCount;
  final int endorsedCount;
  final int rejectedCount;
  final int endorsedToday;
  final int endorsedThisWeek;
  final int endorsedThisMonth;
  final int pendingMeetingApprovals;
  final int pendingFinalDecisions;
  final int pendingAttendance;
  final int rescheduleRequestedCount;
  final int approvedMeetingsCount;
  final int completedMeetingsCount;
  final int meetingsToday;
  final int upcomingMeetingsCount;
  final int legacyScheduledWithoutMeetingApproval;
  final int requestsToday;
  final int requestsThisWeek;
  final int requestsThisMonth;
  final int rejectedToday;
  final int rejectedThisWeek;
  final int rejectedThisMonth;
  final int meetingsOnToday;
  final int meetingsThisWeek;
  final int meetingsThisMonth;
}

class MayorMonthTrend {
  const MayorMonthTrend({required this.month, required this.endorsedCount});
  final String month;
  final int endorsedCount;
}

class MayorOfficeShare {
  const MayorOfficeShare({required this.officeName, required this.total});
  final String officeName;
  final int total;
}

/// Phase 4 role-aware monitoring dashboard body.
class MayorMonitoringDashboard extends StatelessWidget {
  const MayorMonitoringDashboard({
    super.key,
    required this.summary,
    required this.isMayor,
    required this.monthlyTrends,
    required this.officeStatistics,
    required this.pendingMayorActions,
    required this.recentEndorsements,
    required this.meetingQueue,
    required this.upcomingMeetings,
    required this.onRefresh,
    required this.onOpenRequest,
    required this.onOpenMeetings,
    required this.onOpenDecisions,
    required this.onOpenRequests,
    required this.onOpenHistory,
  });

  final MayorMonitoringSummary summary;
  final bool isMayor;
  final List<MayorMonthTrend> monthlyTrends;
  final List<MayorOfficeShare> officeStatistics;
  final List<MayorDashListItem> pendingMayorActions;
  final List<MayorDashListItem> recentEndorsements;
  final List<MayorDashListItem> meetingQueue;
  final List<MayorDashListItem> upcomingMeetings;
  final Future<void> Function() onRefresh;
  final ValueChanged<MayorDashListItem> onOpenRequest;
  final VoidCallback onOpenMeetings;
  final VoidCallback onOpenDecisions;
  final VoidCallback onOpenRequests;
  final VoidCallback onOpenHistory;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final narrow = width < 700;
    final s = summary;

    // Parent shell already scrolls; use a Column to avoid nested ListView height errors.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  isMayor
                      ? 'Mayor Monitoring Overview'
                      : "Mayor's Office Operations",
                  style: TextStyle(
                    color: AppTheme.dashTextPrimaryOf(context),
                    fontSize: narrow ? 20 : 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            isMayor
                ? 'Endorsement activity, meetings, and pending Mayor actions (Asia/Manila).'
                : 'Daily intake, scheduling, and attendance workload (Asia/Manila).',
            style: TextStyle(
              color: AppTheme.dashTextSecondaryOf(context),
              fontSize: 13,
            ),
          ),
          if (s.legacyScheduledWithoutMeetingApproval > 0) ...[
            const SizedBox(height: 10),
            _InfoBanner(
              icon: Icons.info_outline_rounded,
              text:
                  '${s.legacyScheduledWithoutMeetingApproval} pre-Phase-3 schedule(s) exist without a Mayor meeting approval. Staff should submit a meeting request before recording attendance. Historical approvals were not fabricated.',
            ),
          ],
          const SizedBox(height: 14),
          _PeriodOverview(
            summary: s,
            isMayor: isMayor,
            narrow: narrow,
            onOpenHistory: onOpenHistory,
            onOpenRequests: onOpenRequests,
            onOpenMeetings: onOpenMeetings,
            onOpenDecisions: onOpenDecisions,
          ),
          const SizedBox(height: 16),
          if (isMayor) ...[
            LayoutBuilder(
              builder: (context, c) {
                final sideBySide = c.maxWidth >= 900;
                final trend = _TrendCard(trends: monthlyTrends);
                final offices = _OfficeCard(offices: officeStatistics);
                if (!sideBySide) {
                  return Column(
                    children: [trend, const SizedBox(height: 12), offices],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 6, child: trend),
                    const SizedBox(width: 12),
                    Expanded(flex: 4, child: offices),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            _RequestListCard(
              title: 'Pending Mayor Actions',
              empty: 'No pending Mayor actions.',
              items: pendingMayorActions,
              onOpen: onOpenRequest,
            ),
            const SizedBox(height: 12),
            _RequestListCard(
              title: 'Recent Endorsements',
              empty: 'No endorsements yet for the official monitoring set.',
              items: recentEndorsements,
              onOpen: onOpenRequest,
            ),
          ] else ...[
            _RequestListCard(
              title: 'Recent Requests',
              empty: 'No recent requests.',
              items: pendingMayorActions,
              onOpen: onOpenRequest,
            ),
            const SizedBox(height: 12),
            _RequestListCard(
              title: 'Upcoming / Pending Meetings',
              empty: 'No upcoming meetings.',
              items: [
                ...upcomingMeetings,
                ...meetingQueue.where(
                  (e) =>
                      e.meetingRequestStatus == 'submitted' ||
                      e.meetingRequestStatus == 'reschedule_requested',
                ),
              ],
              onOpen: onOpenRequest,
            ),
            if (s.rescheduleRequestedCount > 0) ...[
              const SizedBox(height: 12),
              _InfoBanner(
                icon: Icons.event_repeat_rounded,
                text:
                    '${s.rescheduleRequestedCount} meeting request(s) need a revised schedule from Staff.',
              ),
            ],
          ],
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => onRefresh(),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Refresh metrics'),
            ),
          ),
          const SizedBox(height: 12),
      ],
    );
  }
}

enum _DashPeriod { today, week, month, all }

class _PeriodOverview extends StatefulWidget {
  const _PeriodOverview({
    required this.summary,
    required this.isMayor,
    required this.narrow,
    required this.onOpenHistory,
    required this.onOpenRequests,
    required this.onOpenMeetings,
    required this.onOpenDecisions,
  });

  final MayorMonitoringSummary summary;
  final bool isMayor;
  final bool narrow;
  final VoidCallback onOpenHistory;
  final VoidCallback onOpenRequests;
  final VoidCallback onOpenMeetings;
  final VoidCallback onOpenDecisions;

  @override
  State<_PeriodOverview> createState() => _PeriodOverviewState();
}

class _PeriodOverviewState extends State<_PeriodOverview> {
  _DashPeriod _period = _DashPeriod.all;

  @override
  Widget build(BuildContext context) {
    final s = widget.summary;
    final (requests, endorsed, rejected, meetings) = switch (_period) {
      _DashPeriod.today => (
          s.requestsToday,
          s.endorsedToday,
          s.rejectedToday,
          s.meetingsOnToday,
        ),
      _DashPeriod.week => (
          s.requestsThisWeek,
          s.endorsedThisWeek,
          s.rejectedThisWeek,
          s.meetingsThisWeek,
        ),
      _DashPeriod.month => (
          s.requestsThisMonth,
          s.endorsedThisMonth,
          s.rejectedThisMonth,
          s.meetingsThisMonth,
        ),
      _DashPeriod.all => (
          s.totalRequests,
          s.endorsedCount,
          s.rejectedCount,
          s.completedMeetingsCount,
        ),
    };

    final tiles = [
      _PeriodTile('Requests', requests, widget.onOpenRequests),
      _PeriodTile('Endorsed', endorsed, widget.onOpenHistory),
      _PeriodTile('Rejected', rejected, widget.onOpenHistory),
      _PeriodTile('Meetings', meetings, widget.onOpenMeetings),
    ];

    final queue = widget.isMayor
        ? [
            _QueueChip('Pending', s.pendingCount, widget.onOpenRequests),
            _QueueChip(
              'Meeting approvals',
              s.pendingMeetingApprovals,
              widget.onOpenMeetings,
            ),
            _QueueChip(
              'Final decisions',
              s.pendingFinalDecisions,
              widget.onOpenDecisions,
            ),
          ]
        : [
            _QueueChip('Pending', s.pendingCount, widget.onOpenRequests),
            _QueueChip(
              'Awaiting Mayor',
              s.pendingMeetingApprovals,
              widget.onOpenMeetings,
            ),
            _QueueChip(
              'Attendance',
              s.pendingAttendance,
              widget.onOpenMeetings,
            ),
          ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppTheme.dashPanelOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Overview',
                style: TextStyle(
                  color: AppTheme.dashTextPrimaryOf(context),
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
              _PeriodPicker(
                period: _period,
                onChanged: (v) => setState(() => _period = v),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (widget.narrow)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in tiles)
                  SizedBox(width: 150, child: t),
              ],
            )
          else
            Row(
              children: [
                for (var i = 0; i < tiles.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(child: tiles[i]),
                ],
              ],
            ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Now',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.dashTextSecondaryOf(context),
                ),
              ),
              ...queue,
            ],
          ),
        ],
      ),
    );
  }
}

class _PeriodTile extends StatelessWidget {
  const _PeriodTile(this.label, this.value, this.onTap);
  final String label;
  final int value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.dashCanvasOf(context),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$value',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  height: 1,
                  color: AppTheme.dashTextPrimaryOf(context),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.dashTextSecondaryOf(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QueueChip extends StatelessWidget {
  const _QueueChip(this.label, this.value, this.onTap);
  final String label;
  final int value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.dashHairlineOf(context)),
        ),
        child: Text(
          '$label  $value',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppTheme.dashTextPrimaryOf(context),
          ),
        ),
      ),
    );
  }
}

class _PeriodPicker extends StatelessWidget {
  const _PeriodPicker({required this.period, required this.onChanged});
  final _DashPeriod period;
  final ValueChanged<_DashPeriod> onChanged;

  @override
  Widget build(BuildContext context) {
    const options = [
      (_DashPeriod.today, 'Today'),
      (_DashPeriod.week, 'Week'),
      (_DashPeriod.month, 'Month'),
      (_DashPeriod.all, 'All'),
    ];
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppTheme.dashCanvasOf(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (value, label) in options)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: Material(
                color: period == value
                    ? AppTheme.primaryNavy
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  onTap: () => onChanged(value),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: period == value
                            ? Colors.white
                            : AppTheme.dashTextSecondaryOf(context),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.primaryNavy.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.primaryNavy.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppTheme.primaryNavy),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12.5,
                color: AppTheme.dashTextPrimaryOf(context),
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrendCard extends StatelessWidget {
  const _TrendCard({required this.trends});
  final List<MayorMonthTrend> trends;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: 'Monthly Endorsement Trends',
      child: trends.isEmpty
          ? const _Empty('No endorsement trend data yet.')
          : SizedBox(
              height: 180,
              child: BarChart(
                BarChartData(
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    leftTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (v, _) {
                          final i = v.toInt();
                          if (i < 0 || i >= trends.length) {
                            return const SizedBox.shrink();
                          }
                          final m = trends[i].month;
                          final label = m.length >= 7 ? m.substring(5) : m;
                          return Text(label, style: const TextStyle(fontSize: 10));
                        },
                      ),
                    ),
                  ),
                  barGroups: [
                    for (var i = 0; i < trends.length; i++)
                      BarChartGroupData(
                        x: i,
                        barRods: [
                          BarChartRodData(
                            toY: trends[i].endorsedCount.toDouble(),
                            color: AppTheme.primaryNavy,
                            width: 12,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _OfficeCard extends StatelessWidget {
  const _OfficeCard({required this.offices});
  final List<MayorOfficeShare> offices;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: 'Endorsements by Destination Office',
      child: offices.isEmpty
          ? const _Empty('No office endorsement totals yet.')
          : Column(
              children: [
                for (final o in offices.take(8))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            o.officeName,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: AppTheme.dashTextPrimaryOf(context),
                            ),
                          ),
                        ),
                        Text(
                          '${o.total}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: AppTheme.primaryNavy,
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

class _RequestListCard extends StatelessWidget {
  const _RequestListCard({
    required this.title,
    required this.empty,
    required this.items,
    required this.onOpen,
  });

  final String title;
  final String empty;
  final List<MayorDashListItem> items;
  final ValueChanged<MayorDashListItem> onOpen;

  @override
  Widget build(BuildContext context) {
    final deduped = <String, MayorDashListItem>{};
    for (final i in items) {
      if (i.id.isNotEmpty) deduped[i.id] = i;
    }
    final list = deduped.values.toList();
    return _Panel(
      title: title,
      child: list.isEmpty
          ? _Empty(empty)
          : Column(
              children: [
                for (final item in list.take(8))
                  Material(
                    color: Colors.transparent,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(
                        item.applicantName.isEmpty
                            ? 'Applicant'
                            : item.applicantName,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        [
                          if ((item.referenceNumber ?? '').isNotEmpty)
                            item.referenceNumber!,
                          item.subtitle,
                          item.statusLabel,
                        ].join(' · '),
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.dashTextSecondaryOf(context),
                        ),
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => onOpen(item),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.child});
  final String title;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.dashPanelOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: AppTheme.dashTextPrimaryOf(context),
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(
        text,
        style: TextStyle(
          color: AppTheme.dashTextSecondaryOf(context),
          fontSize: 13,
        ),
      ),
    );
  }
}
