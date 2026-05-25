import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../landingpage/constants/app_theme.dart';
import '../dtr_dashboard_analytics_models.dart';
import '../dtr_provider.dart';
import 'dtr_analytics_charts.dart';

/// Analytics block for the DTR admin dashboard (data from [DtrProvider.analyticsSnapshot]).
class DtrAttendanceAnalyticsSection extends StatelessWidget {
  const DtrAttendanceAnalyticsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final dtr = context.watch<DtrProvider>();
    final snap = dtr.analyticsSnapshot;
    final loading = dtr.dashboardAnalyticsLoading;

    final deptItems = <String>[
      DtrProvider.analyticsAllDepartmentsLabel,
      ...dtr.departments.map((d) => d.name),
    ];
    final selectedDept =
        dtr.analyticsDepartmentName ?? DtrProvider.analyticsAllDepartmentsLabel;

    final w = MediaQuery.of(context).size.width;
    final isDesktop = w >= 900;

    final present = snap?.presentByDay ?? List<int>.filled(30, 0);
    final late = snap?.lateByDay ?? List<int>.filled(30, 0);
    final undertime = snap?.undertimeByDay ?? List<int>.filled(30, 0);
    final absent = snap?.absentByDay ?? List<int>.filled(30, 0);
    final lateDept = snap?.lateCountByDepartment ?? {};
    final undertimeDept = snap?.undertimeCountByDepartment ?? {};
    final leaveMap = snap?.leaveDaysByType ?? {};
    final leaveOk = snap?.leaveDataAvailable ?? false;
    final recent = snap?.recentRows ?? const <DtrRecentActivityRow>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 28),
        _AnalyticsHeader(
          department: selectedDept,
          departments: deptItems,
          onDepartmentChanged: (v) {
            context.read<DtrProvider>().setAnalyticsDepartmentFilter(v);
          },
        ),
        const SizedBox(height: 20),
        _AnalyticsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Attendance Trend',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.dashTextPrimaryOf(context),
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Present, Late, Undertime, Absent — last 30 days (by calendar day)',
                style: TextStyle(
                  fontSize: 13,
                  color: AppTheme.dashTextSecondaryOf(context),
                ),
              ),
              const SizedBox(height: 16),
              AttendanceTrendLineChart(
                presentByDay: present,
                lateByDay: late,
                undertimeByDay: undertime,
                absentByDay: absent,
                height: 240,
                loading: loading && snap == null,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (isDesktop)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _AnalyticsCard(
                  child: _AttendanceIssuesByDepartmentCard(
                    lateByDepartment: lateDept,
                    undertimeByDepartment: undertimeDept,
                    loading: loading && snap == null,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _AnalyticsCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _cardSectionTitle(context, 'Leave Distribution'),
                      const SizedBox(height: 16),
                      LeaveDistributionPieChart(
                        leaveByType: leaveMap,
                        leaveDataAvailable: leaveOk,
                        height: 200,
                        loading: loading && snap == null,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          )
        else
          Column(
            children: [
              _AnalyticsCard(
                child: _AttendanceIssuesByDepartmentCard(
                  lateByDepartment: lateDept,
                  undertimeByDepartment: undertimeDept,
                  loading: loading && snap == null,
                ),
              ),
              const SizedBox(height: 16),
              _AnalyticsCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _cardSectionTitle(context, 'Leave Distribution'),
                    const SizedBox(height: 16),
                    LeaveDistributionPieChart(
                      leaveByType: leaveMap,
                      leaveDataAvailable: leaveOk,
                      height: 200,
                      loading: loading && snap == null,
                    ),
                  ],
                ),
              ),
            ],
          ),
        const SizedBox(height: 16),
        _AnalyticsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Recent Attendance Activity',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.dashTextPrimaryOf(context),
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 16),
              _RecentAttendanceTable(
                rows: recent,
                loading: loading && recent.isEmpty,
              ),
            ],
          ),
        ),
      ],
    );
  }

  static Widget _cardSectionTitle(BuildContext context, String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: AppTheme.dashTextPrimaryOf(context),
      ),
    );
  }
}

enum _DeptIssueKind { late, undertime }

/// Late / Undertime toggle with shared department bar chart (same slot as former “Late by Department”).
class _AttendanceIssuesByDepartmentCard extends StatefulWidget {
  const _AttendanceIssuesByDepartmentCard({
    required this.lateByDepartment,
    required this.undertimeByDepartment,
    required this.loading,
  });

  final Map<String, int> lateByDepartment;
  final Map<String, int> undertimeByDepartment;
  final bool loading;

  @override
  State<_AttendanceIssuesByDepartmentCard> createState() =>
      _AttendanceIssuesByDepartmentCardState();
}

class _AttendanceIssuesByDepartmentCardState
    extends State<_AttendanceIssuesByDepartmentCard> {
  _DeptIssueKind _kind = _DeptIssueKind.late;

  @override
  Widget build(BuildContext context) {
    final counts = _kind == _DeptIssueKind.late
        ? widget.lateByDepartment
        : widget.undertimeByDepartment;
    final title = _kind == _DeptIssueKind.late
        ? 'Late by Department'
        : 'Undertime by Department';
    const emptyLate = 'No late records in this period for the selected filter.';
    const emptyUt =
        'No undertime records in this period for the selected filter.';
    final empty = _kind == _DeptIssueKind.late ? emptyLate : emptyUt;
    final legend = _kind == _DeptIssueKind.late
        ? 'Late employee-days by department'
        : 'Undertime employee-days by department';

    final titleStyle = TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w600,
      color: AppTheme.textPrimary,
    );

    final filter = SegmentedButton<_DeptIssueKind>(
      segments: const [
        ButtonSegment<_DeptIssueKind>(
          value: _DeptIssueKind.late,
          label: Text('Late'),
        ),
        ButtonSegment<_DeptIssueKind>(
          value: _DeptIssueKind.undertime,
          label: Text('Undertime'),
        ),
      ],
      selected: {_kind},
      onSelectionChanged: (Set<_DeptIssueKind> next) {
        if (next.isEmpty) return;
        setState(() => _kind = next.single);
      },
      showSelectedIcon: false,
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 340) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: titleStyle),
                  const SizedBox(height: 10),
                  filter,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: Text(title, style: titleStyle)),
                filter,
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        DepartmentIssueBarChart(
          countsByDepartment: counts,
          legendLabel: legend,
          emptyMessage: empty,
          height: 200,
          loading: widget.loading,
        ),
      ],
    );
  }
}

class _AnalyticsHeader extends StatelessWidget {
  const _AnalyticsHeader({
    required this.department,
    required this.departments,
    required this.onDepartmentChanged,
  });

  final String department;
  final List<String> departments;
  final ValueChanged<String> onDepartmentChanged;

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.of(context).size.width < 520;
    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Attendance Analytics',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppTheme.dashTextPrimaryOf(context),
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Last 30 days',
          style: TextStyle(
            fontSize: 13,
            color: AppTheme.dashTextSecondaryOf(context),
          ),
        ),
      ],
    );

    final dropdown = _DepartmentDropdown(
      value: department,
      items: departments,
      onChanged: onDepartmentChanged,
    );

    if (narrow) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          titleBlock,
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: dropdown,
          ),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: titleBlock),
        const SizedBox(width: 16),
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 180, maxWidth: 260),
          child: dropdown,
        ),
      ],
    );
  }
}

class _DepartmentDropdown extends StatelessWidget {
  const _DepartmentDropdown({
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String value;
  final List<String> items;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final fieldStyle = AppTheme.dashFieldTextStyle(
      context,
    ).copyWith(fontSize: 14, fontWeight: FontWeight.w500);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppTheme.dashInputFillOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.dashInputBorderOf(context)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: items.contains(value)
              ? value
              : DtrProvider.analyticsAllDepartmentsLabel,
          isExpanded: true,
          dropdownColor: AppTheme.dashPanelOf(context),
          icon: Icon(
            Icons.keyboard_arrow_down_rounded,
            color: AppTheme.dashTextSecondaryOf(context),
          ),
          style: fieldStyle,
          items: items
              .map(
                (e) => DropdownMenuItem<String>(
                  value: e,
                  child: Text(e, style: fieldStyle),
                ),
              )
              .toList(),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}

class _AnalyticsCard extends StatelessWidget {
  const _AnalyticsCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppTheme.dashSurfaceCard(context),
      child: child,
    );
  }
}

class _RecentAttendanceTable extends StatelessWidget {
  const _RecentAttendanceTable({required this.rows, this.loading = false});

  final List<DtrRecentActivityRow> rows;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final headerStyle = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: AppTheme.dashTextSecondaryOf(context),
    );
    final cellStyle = TextStyle(
      fontSize: 13,
      color: AppTheme.dashTextPrimaryOf(context),
    );

    if (loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(
            'No recent attendance activity for the selected filter.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: AppTheme.dashHairlineOf(context)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: constraints.maxWidth),
                child: Table(
                  columnWidths: const {
                    0: FlexColumnWidth(2),
                    1: FlexColumnWidth(1.2),
                    2: FlexColumnWidth(1),
                    3: FlexColumnWidth(1),
                    4: FlexColumnWidth(1.1),
                  },
                  defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                  children: [
                    TableRow(
                      decoration: BoxDecoration(
                        color: AppTheme.dashMutedSurfaceOf(context),
                      ),
                      children: [
                        _TableHeaderCell('Employee Name', style: headerStyle),
                        _TableHeaderCell('Department', style: headerStyle),
                        _TableHeaderCell('Time In', style: headerStyle),
                        _TableHeaderCell('Status', style: headerStyle),
                        _TableHeaderCell('Method', style: headerStyle),
                      ],
                    ),
                    for (var i = 0; i < rows.length; i++)
                      TableRow(
                        decoration: BoxDecoration(
                          color: i.isEven
                              ? AppTheme.dashPanelOf(context)
                              : AppTheme.dashMutedSurfaceOf(context),
                          border: Border(
                            top: BorderSide(
                              color: AppTheme.dashHairlineOf(context),
                            ),
                          ),
                        ),
                        children: [
                          _TableBodyCell(
                            rows[i].employeeName,
                            style: cellStyle,
                          ),
                          _TableBodyCell(rows[i].department, style: cellStyle),
                          _TableBodyCell(rows[i].timeIn, style: cellStyle),
                          _TableBodyCell(rows[i].status, style: cellStyle),
                          _TableBodyCell(rows[i].method, style: cellStyle),
                        ],
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _TableHeaderCell extends StatelessWidget {
  const _TableHeaderCell(this.text, {required this.style});

  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(text, style: style),
      ),
    );
  }
}

class _TableBodyCell extends StatelessWidget {
  const _TableBodyCell(this.text, {required this.style});

  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(text, style: style),
      ),
    );
  }
}
