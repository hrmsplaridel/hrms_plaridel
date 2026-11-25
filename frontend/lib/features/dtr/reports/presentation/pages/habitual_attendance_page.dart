import 'package:flutter/material.dart';
import 'package:hrms_plaridel/core/api/user_facing_api_error.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/dtr/dtr_provider.dart';
import 'package:hrms_plaridel/features/dtr/reports/data/habitual_attendance_report.dart';
import 'package:hrms_plaridel/shared/widgets/skeleton_bone.dart';

const _monthLabels = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// Habitual tardiness and undertime (CSC rule: 10+ instances a month in two
/// months of a semester, or two consecutive months).
class HabitualAttendancePage extends StatefulWidget {
  const HabitualAttendancePage({
    super.key,
    this.loader = fetchHabitualAttendanceReport,
    this.departments = const [],
    this.initialYear,
  });

  final HabitualAttendanceLoader loader;
  final List<DepartmentOption> departments;
  final int? initialYear;

  @override
  State<HabitualAttendancePage> createState() => _HabitualAttendancePageState();
}

class _HabitualAttendancePageState extends State<HabitualAttendancePage> {
  late final int _currentYear = DateTime.now().year;
  late int _year = widget.initialYear ?? _currentYear;
  String? _departmentId;
  HabitualAttendanceReport? _report;
  Object? _error;
  bool _loading = true;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final requestId = ++_requestId;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final report = await widget.loader(_year, _departmentId);
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _report = report;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.dashCanvasOf(context),
      appBar: AppBar(title: const Text('Habitual tardiness & undertime')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Flags employees with 10 or more late or undertime days in a month, '
            'in two months of the same semester or two consecutive months '
            '(CSC MC 04 s.1991, MC 16 s.2010). Days covered by approved leave, '
            'locator slips, or policy exemptions are not counted.',
            style: TextStyle(
              color: AppTheme.dashTextSecondaryOf(context),
              fontSize: AppTheme.smallSize,
            ),
          ),
          const SizedBox(height: 16),
          _buildFilters(context),
          const SizedBox(height: 16),
          ..._buildBody(context),
        ],
      ),
    );
  }

  Widget _buildFilters(BuildContext context) {
    final years = [for (var y = _currentYear; y >= _currentYear - 5; y--) y];
    if (!years.contains(_year)) years.add(_year);
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        SizedBox(
          width: 160,
          child: DropdownButtonFormField<int>(
            initialValue: _year,
            decoration: AppTheme.dashInputDecoration(
              context,
              labelText: 'Year',
              radius: 8,
            ),
            items: [
              for (final y in years)
                DropdownMenuItem(value: y, child: Text('$y')),
            ],
            onChanged: _loading
                ? null
                : (v) {
                    if (v == null || v == _year) return;
                    _year = v;
                    _load();
                  },
          ),
        ),
        SizedBox(
          width: 260,
          child: DropdownButtonFormField<String?>(
            initialValue: _departmentId,
            isExpanded: true,
            decoration: AppTheme.dashInputDecoration(
              context,
              labelText: 'Department',
              radius: 8,
            ),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('All departments'),
              ),
              for (final d in widget.departments)
                DropdownMenuItem<String?>(
                  value: d.id,
                  child: Text(d.name, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: _loading
                ? null
                : (v) {
                    _departmentId = v;
                    _load();
                  },
          ),
        ),
      ],
    );
  }

  List<Widget> _buildBody(BuildContext context) {
    if (_loading) {
      return [
        for (var i = 0; i < 3; i++) ...[
          const SkeletonBone(height: 132, borderRadius: 12),
          const SizedBox(height: 12),
        ],
      ];
    }
    if (_error != null) {
      return [
        Text(
          userFacingApiError(_error!),
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Retry'),
          ),
        ),
      ];
    }
    final report = _report!;
    final subtitle = Text(
      'Data through ${report.through}',
      style: TextStyle(
        color: AppTheme.dashTextSecondaryOf(context),
        fontSize: AppTheme.smallSize,
      ),
    );
    if (report.employees.isEmpty) {
      return [
        subtitle,
        const SizedBox(height: 24),
        Center(
          child: Text(
            'No employee reached ${report.threshold} instances in any month of '
            '${report.year}. Try another year or department.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.dashTextSecondaryOf(context)),
          ),
        ),
      ];
    }
    return [
      subtitle,
      const SizedBox(height: 12),
      for (final employee in report.employees) ...[
        _EmployeeCard(employee: employee, threshold: report.threshold),
        const SizedBox(height: 12),
      ],
    ];
  }
}

class _EmployeeCard extends StatelessWidget {
  const _EmployeeCard({required this.employee, required this.threshold});

  final HabitualAttendanceEmployee employee;
  final int threshold;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.dashSurfaceCard(context, radius: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            employee.employeeName,
            style: TextStyle(
              color: AppTheme.dashTextPrimaryOf(context),
              fontSize: AppTheme.bodySize,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ..._badges(context, 'tardiness', employee.tardiness),
              ..._badges(context, 'undertime', employee.undertime),
            ],
          ),
          if (employee.tardiness.qualifyingMonths.isNotEmpty)
            _MonthRow(
              label: 'Late',
              metric: employee.tardiness,
              threshold: threshold,
            ),
          if (employee.undertime.qualifyingMonths.isNotEmpty)
            _MonthRow(
              label: 'Undertime',
              metric: employee.undertime,
              threshold: threshold,
            ),
        ],
      ),
    );
  }

  List<Widget> _badges(BuildContext context, String kind, HabitualMetric m) {
    if (m.qualifyingMonths.isEmpty) return const [];
    final count = m.qualifyingMonths.length;
    final label = m.habitual
        ? 'Habitual $kind'
        : 'Warning: $count month${count == 1 ? '' : 's'}';
    final scheme = Theme.of(context).colorScheme;
    return [
      Chip(
        label: Text(label),
        visualDensity: VisualDensity.compact,
        backgroundColor: m.habitual
            ? scheme.errorContainer
            : scheme.secondaryContainer,
        labelStyle: TextStyle(
          color: m.habitual
              ? scheme.onErrorContainer
              : scheme.onSecondaryContainer,
          fontWeight: FontWeight.w600,
        ),
      ),
    ];
  }
}

class _MonthRow extends StatelessWidget {
  const _MonthRow({
    required this.label,
    required this.metric,
    required this.threshold,
  });

  final String label;
  final HabitualMetric metric;
  final int threshold;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label days per month',
            style: TextStyle(
              color: AppTheme.dashTextSecondaryOf(context),
              fontSize: AppTheme.smallSize,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var i = 0; i < 12; i++)
                Semantics(
                  label: '${_monthLabels[i]}: ${metric.monthly[i]}',
                  child: Container(
                    width: 52,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                      color: metric.monthly[i] >= threshold
                          ? scheme.errorContainer
                          : AppTheme.dashMutedSurfaceOf(context),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ExcludeSemantics(
                      child: Column(
                        children: [
                          Text(
                            _monthLabels[i],
                            style: TextStyle(
                              fontSize: 11,
                              color: metric.monthly[i] >= threshold
                                  ? scheme.onErrorContainer
                                  : AppTheme.dashTextSecondaryOf(context),
                            ),
                          ),
                          Text(
                            '${metric.monthly[i]}',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: metric.monthly[i] >= threshold
                                  ? scheme.onErrorContainer
                                  : AppTheme.dashTextPrimaryOf(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
