import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hrms_plaridel/shared/widgets/workforce_loading_skeleton.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/core/api/user_facing_api_error.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';

class ManageWeeklySchedule extends StatefulWidget {
  const ManageWeeklySchedule({super.key});

  @override
  State<ManageWeeklySchedule> createState() => _ManageWeeklyScheduleState();
}

class _ManageWeeklyScheduleState extends State<ManageWeeklySchedule> {
  static const _dayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _pageSize = 25;
  int _page = 0;
  int _loadSerial = 0;

  int get _pageCount => (_employees.length / _pageSize).ceil();
  Iterable<_WeeklyEmployee> get _pageEmployees =>
      _employees.skip(_page * _pageSize).take(_pageSize);

  final _searchController = TextEditingController();
  DateTime _weekStart = _mondayOf(DateTime.now());
  List<Map<String, dynamic>> _departments = [];
  List<_WeeklyEmployee> _employees = [];
  String? _departmentId;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  Timer? _searchTimer;

  static DateTime _mondayOf(DateTime value) {
    final date = DateTime(value.year, value.month, value.day);
    return date.subtract(Duration(days: date.weekday - DateTime.monday));
  }

  String _apiDate(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  String _shortDate(DateTime value) {
    const months = [
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
    return '${months[value.month - 1]} ${value.day}';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadDepartments();
      await _loadSchedule();
    });
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadDepartments() async {
    try {
      final response = await ApiClient.instance.get<List<dynamic>>(
        '/api/departments',
        queryParameters: {'status': 'Active'},
      );
      if (!mounted) return;
      setState(() {
        _departments = (response.data ?? const [])
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
      });
    } catch (_) {
      // The schedule request still provides department names per employee.
    }
  }

  Future<void> _loadSchedule({bool preservePage = false}) async {
    if (!mounted) return;
    final serial = ++_loadSerial;
    final requestedWeek = _apiDate(_weekStart);
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await ApiClient.instance.get<Map<String, dynamic>>(
        '/api/weekly-schedules',
        queryParameters: {
          'week_start': requestedWeek,
          if (_departmentId != null) 'department_id': _departmentId,
          if (_searchController.text.trim().isNotEmpty)
            'q': _searchController.text.trim(),
        },
      );
      final raw = response.data?['employees'];
      final employees = raw is List
          ? raw
                .whereType<Map>()
                .map(
                  (item) =>
                      _WeeklyEmployee.fromJson(Map<String, dynamic>.from(item)),
                )
                .toList()
          : <_WeeklyEmployee>[];
      if (!mounted || serial != _loadSerial) return;
      setState(() {
        _employees = employees;
        _page = preservePage && _pageCount > 0
            ? _page.clamp(0, _pageCount - 1)
            : 0;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || serial != _loadSerial) return;
      setState(() {
        _loading = false;
        _error = userFacingApiError(error);
      });
    }
  }

  void _changeWeek(int days) {
    if (_saving) return;
    setState(() => _weekStart = _weekStart.add(Duration(days: days)));
    _loadSchedule();
  }

  Future<void> _pickWeek() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _weekStart,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    setState(() => _weekStart = _mondayOf(picked));
    _loadSchedule();
  }

  void _toggleDay(_WeeklyEmployee employee, int dayIndex) {
    if (_saving) return;
    setState(() => employee.days[dayIndex].toggle());
  }

  int get _dirtyEmployeeCount =>
      _employees.where((employee) => employee.isDirty).length;

  void _discardChanges() {
    if (!_saving) _loadSchedule(preservePage: true);
  }

  Future<void> _saveChanges() async {
    final dirty = _employees.where((employee) => employee.isDirty).toList();
    if (dirty.isEmpty || _saving) return;
    setState(() => _saving = true);
    try {
      for (final employee in dirty) {
        await ApiClient.instance.put<Map<String, dynamic>>(
          '/api/weekly-schedules/${employee.id}/${_apiDate(_weekStart)}',
          data: {
            'days': employee.days
                .map(
                  (day) => {
                    'date': day.date,
                    'is_working_day': day.overrideIsWorking,
                  },
                )
                .toList(),
          },
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${dirty.length} employee schedule(s) saved.')),
      );
      await _loadSchedule(preservePage: true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(userFacingApiError(error))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final weekEnd = _weekStart.add(const Duration(days: 6));
    final textColor = AppTheme.dashTextPrimaryOf(context);
    final mutedColor = AppTheme.dashTextSecondaryOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 12,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Weekly Schedule',
                  style: TextStyle(
                    color: textColor,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'Assign employee work and rest-day exceptions for a specific week.',
                  style: TextStyle(color: mutedColor, fontSize: 14),
                ),
              ],
            ),
            Wrap(
              spacing: 10,
              children: [
                if (_dirtyEmployeeCount > 0)
                  OutlinedButton.icon(
                    onPressed: _saving ? null : _discardChanges,
                    icon: const Icon(Icons.undo_rounded, size: 18),
                    label: const Text('Discard changes'),
                  ),
                FilledButton.icon(
                  onPressed: _dirtyEmployeeCount == 0 || _saving
                      ? null
                      : _saveChanges,
                  icon: _saving
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_rounded, size: 18),
                  label: Text(
                    _dirtyEmployeeCount == 0
                        ? 'No changes'
                        : 'Save $_dirtyEmployeeCount employee${_dirtyEmployeeCount == 1 ? '' : 's'}',
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 18),
        _buildToolbar(weekEnd),
        const SizedBox(height: 14),
        _buildLegend(),
        const SizedBox(height: 14),
        if (_loading)
          const WeeklyScheduleSkeleton()
        else if (_error != null)
          _buildError()
        else if (_employees.isEmpty)
          _buildEmpty()
        else ...[
          _buildRoster(),
          _buildPagination(),
          const SizedBox(height: 14),
          _buildSummary(),
        ],
      ],
    );
  }

  Widget _buildToolbar(DateTime weekEnd) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.dashSurfaceCard(context, radius: 8),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 220,
            child: TextField(
              controller: _searchController,
              enabled: _dirtyEmployeeCount == 0 && !_saving,
              decoration: AppTheme.dashInputDecoration(
                context,
                hintText: 'Search employee',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
              ),
              onChanged: (_) {
                _searchTimer?.cancel();
                _searchTimer = Timer(
                  const Duration(milliseconds: 350),
                  _loadSchedule,
                );
              },
            ),
          ),
          SizedBox(
            width: 220,
            child: DropdownButtonFormField<String?>(
              initialValue: _departmentId,
              isExpanded: true,
              decoration: AppTheme.dashInputDecoration(
                context,
                hintText: 'Department',
              ),
              dropdownColor: AppTheme.dashPanelOf(context),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('All departments'),
                ),
                ..._departments.map(
                  (department) => DropdownMenuItem<String?>(
                    value: department['id']?.toString(),
                    child: Text(
                      department['name']?.toString() ?? 'Department',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
              onChanged: _dirtyEmployeeCount > 0 || _saving
                  ? null
                  : (value) {
                      setState(() => _departmentId = value);
                      _loadSchedule();
                    },
            ),
          ),
          IconButton.outlined(
            tooltip: 'Previous week',
            onPressed: _saving || _dirtyEmployeeCount > 0
                ? null
                : () => _changeWeek(-7),
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          OutlinedButton.icon(
            onPressed: _saving || _dirtyEmployeeCount > 0 ? null : _pickWeek,
            icon: const Icon(Icons.calendar_month_rounded, size: 18),
            label: Text(
              '${_shortDate(_weekStart)} - ${_shortDate(weekEnd)}, ${weekEnd.year}',
            ),
          ),
          IconButton.outlined(
            tooltip: 'Next week',
            onPressed: _saving || _dirtyEmployeeCount > 0
                ? null
                : () => _changeWeek(7),
            icon: const Icon(Icons.chevron_right_rounded),
          ),
          TextButton(
            onPressed: _saving || _dirtyEmployeeCount > 0
                ? null
                : () {
                    setState(() => _weekStart = _mondayOf(DateTime.now()));
                    _loadSchedule();
                  },
            child: const Text('Current week'),
          ),
        ],
      ),
    );
  }

  Widget _buildLegend() {
    return Wrap(
      spacing: 18,
      runSpacing: 8,
      children: const [
        _Legend(color: Color(0xFF3D73DD), label: 'Work day'),
        _Legend(color: Color(0xFF2E9D57), label: 'Rest day'),
        _Legend(color: Color(0xFFE85D04), label: 'Weekly override'),
        _Legend(color: Color(0xFFD7373F), label: 'No rest day'),
      ],
    );
  }

  Widget _buildRoster() {
    const employeeWidth = 220.0;
    const dayWidth = 112.0;
    final border = AppTheme.dashHairlineOf(context);
    return Container(
      decoration: AppTheme.dashSurfaceCard(context, radius: 8),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: employeeWidth + dayWidth * 7,
          child: Column(
            children: [
              Container(
                color: AppTheme.dashMutedSurfaceOf(context),
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: [
                    SizedBox(
                      width: employeeWidth,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text('Employee', style: _headerStyle()),
                      ),
                    ),
                    for (var index = 0; index < 7; index++)
                      SizedBox(
                        width: dayWidth,
                        child: Column(
                          children: [
                            Text(_dayLabels[index], style: _headerStyle()),
                            const SizedBox(height: 2),
                            Text(
                              _shortDate(_weekStart.add(Duration(days: index))),
                              style: TextStyle(
                                fontSize: 11,
                                color: AppTheme.dashTextSecondaryOf(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              for (final employee in _pageEmployees)
                Container(
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: border)),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      SizedBox(
                        width: employeeWidth,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                employee.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: AppTheme.dashTextPrimaryOf(context),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                employee.departmentName ?? 'No department',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: AppTheme.dashTextSecondaryOf(context),
                                  fontSize: 11,
                                ),
                              ),
                              if (employee.days.every(
                                (day) => day.isWorking,
                              )) ...[
                                const SizedBox(height: 3),
                                const Row(
                                  children: [
                                    Icon(
                                      Icons.warning_amber_rounded,
                                      size: 13,
                                      color: Color(0xFFD7373F),
                                    ),
                                    SizedBox(width: 3),
                                    Text(
                                      'No rest day',
                                      style: TextStyle(
                                        color: Color(0xFFD7373F),
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      for (var index = 0; index < employee.days.length; index++)
                        SizedBox(
                          width: dayWidth,
                          child: _buildDayCell(employee, index),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDayCell(_WeeklyEmployee employee, int index) {
    final day = employee.days[index];
    final isWork = day.isWorking;
    final color = isWork ? const Color(0xFF3D73DD) : const Color(0xFF2E9D57);
    final shiftText = day.shiftName == null
        ? 'No shift'
        : (isWork ? _clockRange(day.startTime, day.endTime) : 'REST');
    return Tooltip(
      message: day.hasOverride
          ? 'Weekly override. Tap to use the shift default.'
          : 'Using shift default. Tap to change this day.',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5),
        child: Material(
          color: color,
          borderRadius: BorderRadius.circular(6),
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: day.shiftName == null
                ? null
                : () => _toggleDay(employee, index),
            child: Container(
              height: 58,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: day.hasOverride
                    ? Border.all(color: AppTheme.primaryNavyLight, width: 3)
                    : null,
              ),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    shiftText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (day.hasOverride)
                    const Text(
                      'Override',
                      style: TextStyle(color: Colors.white, fontSize: 9),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _clockRange(String? start, String? end) {
    String clock(String? value) {
      if (value == null || value.length < 5) return '--';
      final hour = int.tryParse(value.substring(0, 2));
      if (hour == null) return value.substring(0, 5);
      final minute = value.substring(3, 5);
      final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
      return '$displayHour:$minute${hour >= 12 ? 'p' : 'a'}';
    }

    return '${clock(start)}-${clock(end)}';
  }

  TextStyle _headerStyle() => TextStyle(
    color: AppTheme.dashTextPrimaryOf(context),
    fontSize: 12,
    fontWeight: FontWeight.w700,
  );

  Widget _buildPagination() {
    final locked = _loading || _saving || _dirtyEmployeeCount > 0;
    final end = ((_page + 1) * _pageSize).clamp(0, _employees.length);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Wrap(
        spacing: 16,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            'Showing ${_page * _pageSize + 1}-$end of ${_employees.length} employees',
          ),
          const Text('25 per page'),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Previous employee page',
                onPressed: locked || _page == 0
                    ? null
                    : () => setState(() => _page--),
                icon: const Icon(Icons.chevron_left),
              ),
              Text('Page ${_page + 1} of $_pageCount'),
              IconButton(
                tooltip: 'Next employee page',
                onPressed: locked || _page + 1 >= _pageCount
                    ? null
                    : () => setState(() => _page++),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummary() {
    final restDays = _employees.fold<int>(
      0,
      (total, employee) =>
          total + employee.days.where((day) => !day.isWorking).length,
    );
    final overrides = _employees.fold<int>(
      0,
      (total, employee) =>
          total + employee.days.where((day) => day.hasOverride).length,
    );
    final conflicts = _employees
        .where((employee) => employee.days.every((day) => day.isWorking))
        .length;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: AppTheme.dashSurfaceCard(context, radius: 8),
      child: Wrap(
        spacing: 42,
        runSpacing: 12,
        children: [
          _Summary(label: 'Employees', value: '${_employees.length}'),
          _Summary(label: 'Rest days', value: '$restDays'),
          _Summary(label: 'Weekly overrides', value: '$overrides'),
          _Summary(
            label: 'No-rest alerts',
            value: '$conflicts',
            warning: conflicts > 0,
          ),
        ],
      ),
    );
  }

  Widget _buildError() => Container(
    padding: const EdgeInsets.all(20),
    decoration: AppTheme.dashSurfaceCard(context, radius: 8),
    child: Row(
      children: [
        const Icon(Icons.error_outline_rounded, color: Colors.red),
        const SizedBox(width: 10),
        Expanded(child: Text(_error!)),
        IconButton(
          tooltip: 'Retry',
          onPressed: _loadSchedule,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    ),
  );

  Widget _buildEmpty() => Container(
    height: 220,
    alignment: Alignment.center,
    decoration: AppTheme.dashSurfaceCard(context, radius: 8),
    child: Text(
      'No employees with effective assignments for this week.',
      style: TextStyle(color: AppTheme.dashTextSecondaryOf(context)),
    ),
  );
}

class _WeeklyEmployee {
  _WeeklyEmployee({
    required this.id,
    required this.name,
    required this.departmentName,
    required this.days,
  });

  factory _WeeklyEmployee.fromJson(Map<String, dynamic> json) {
    final rawDays = json['days'];
    return _WeeklyEmployee(
      id: json['employee_id']?.toString() ?? '',
      name: json['employee_name']?.toString() ?? 'Employee',
      departmentName: json['department_name']?.toString(),
      days: rawDays is List
          ? rawDays
                .whereType<Map>()
                .map(
                  (day) => _WeeklyDay.fromJson(Map<String, dynamic>.from(day)),
                )
                .toList()
          : <_WeeklyDay>[],
    );
  }

  final String id;
  final String name;
  final String? departmentName;
  final List<_WeeklyDay> days;

  bool get isDirty => days.any((day) => day.isDirty);
}

class _WeeklyDay {
  _WeeklyDay({
    required this.date,
    required this.shiftName,
    required this.startTime,
    required this.endTime,
    required this.defaultIsWorking,
    required this.savedOverride,
  }) : overrideIsWorking = savedOverride;

  factory _WeeklyDay.fromJson(Map<String, dynamic> json) => _WeeklyDay(
    date: json['date']?.toString() ?? '',
    shiftName: json['shift_name']?.toString(),
    startTime: json['start_time']?.toString(),
    endTime: json['end_time']?.toString(),
    defaultIsWorking: json['default_is_working_day'] == true,
    savedOverride: json['override_is_working_day'] is bool
        ? json['override_is_working_day'] as bool
        : null,
  );

  final String date;
  final String? shiftName;
  final String? startTime;
  final String? endTime;
  final bool defaultIsWorking;
  final bool? savedOverride;
  bool? overrideIsWorking;

  bool get isWorking => overrideIsWorking ?? defaultIsWorking;
  bool get hasOverride => overrideIsWorking != null;
  bool get isDirty => overrideIsWorking != savedOverride;

  void toggle() {
    overrideIsWorking = hasOverride ? null : !defaultIsWorking;
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 6),
      Text(
        label,
        style: TextStyle(
          color: AppTheme.dashTextSecondaryOf(context),
          fontSize: 12,
        ),
      ),
    ],
  );
}

class _Summary extends StatelessWidget {
  const _Summary({
    required this.label,
    required this.value,
    this.warning = false,
  });

  final String label;
  final String value;
  final bool warning;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 150,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: AppTheme.dashTextSecondaryOf(context),
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: TextStyle(
            color: warning ? Colors.red : AppTheme.dashTextPrimaryOf(context),
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );
}
