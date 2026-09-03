import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/dtr/dtr_provider.dart';

class EmployeeSetupSelection {
  const EmployeeSetupSelection({
    this.departmentId,
    this.positionId,
    this.shiftId,
    this.policyId,
  });

  final String? departmentId;
  final String? positionId;
  final String? shiftId;
  final String? policyId;

  bool get hasAssignmentChoice =>
      departmentId != null || positionId != null || shiftId != null;

  bool get hasCompleteAssignment =>
      departmentId != null && positionId != null && shiftId != null;

  bool sameAssignmentAs(EmployeeSetupSelection other) =>
      departmentId == other.departmentId &&
      positionId == other.positionId &&
      shiftId == other.shiftId;

  bool samePolicyAs(EmployeeSetupSelection other) => policyId == other.policyId;
}

class EmployeeSetupSection extends StatefulWidget {
  const EmployeeSetupSection({
    super.key,
    required this.title,
    required this.subtitle,
    required this.validationMessage,
    this.employeeId,
    this.loadCurrentSetup = false,
    this.showTopDivider = false,
    this.boxed = false,
  });

  final String title;
  final String subtitle;
  final String validationMessage;
  final String? employeeId;
  final bool loadCurrentSetup;
  final bool showTopDivider;
  final bool boxed;

  @override
  State<EmployeeSetupSection> createState() => EmployeeSetupSectionState();
}

class EmployeeSetupSectionState extends State<EmployeeSetupSection> {
  bool _loading = false;
  List<Map<String, dynamic>> _departments = [];
  List<Map<String, dynamic>> _positions = [];
  List<Map<String, dynamic>> _shifts = [];
  List<Map<String, dynamic>> _policies = [];

  String? _selectedDepartmentId;
  String? _selectedPositionId;
  String? _selectedShiftId;
  String? _selectedPolicyId;

  EmployeeSetupSelection _original = const EmployeeSetupSelection();

  EmployeeSetupSelection get selection => EmployeeSetupSelection(
    departmentId: _selectedDepartmentId,
    positionId: _selectedPositionId,
    shiftId: _selectedShiftId,
    policyId: _selectedPolicyId,
  );

  EmployeeSetupSelection get originalSelection => _original;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadLookups(loadCurrentSetup: widget.loadCurrentSetup);
    });
  }

  bool validateAssignmentSelection() {
    final current = selection;
    if (current.hasAssignmentChoice && !current.hasCompleteAssignment) {
      _showSnackBar(widget.validationMessage);
      return false;
    }
    return true;
  }

  void clearSelection() {
    setState(() {
      _selectedDepartmentId = null;
      _selectedPositionId = null;
      _selectedShiftId = null;
      _selectedPolicyId = null;
    });
  }

  Map<String, dynamic>? buildAtomicSetupPayload({
    required DateTime effectiveFrom,
    DateTime? effectiveTo,
    bool isActive = true,
    bool changedOnly = false,
  }) {
    final current = selection;
    final assignmentChanged = !current.sameAssignmentAs(_original);
    final policyChanged = !current.samePolicyAs(_original);
    final includeAssignment = changedOnly
        ? assignmentChanged
        : current.hasCompleteAssignment;
    final includePolicy = changedOnly
        ? policyChanged
        : current.policyId != null;
    if (!includeAssignment && !includePolicy) return null;

    final payload = <String, dynamic>{
      'effective_from': _dateOnly(effectiveFrom),
      'effective_to': effectiveTo == null ? null : _dateOnly(effectiveTo),
      'is_active': isActive,
    };

    if (includeAssignment) {
      payload['assignment'] = current.hasCompleteAssignment
          ? <String, dynamic>{
              'department_id': current.departmentId,
              'position_id': current.positionId,
              'shift_id': current.shiftId,
            }
          : null;
    }

    if (includePolicy) {
      payload['policy_assignment'] = current.policyId == null
          ? null
          : <String, dynamic>{'attendance_policy_id': current.policyId};
    }
    return payload;
  }

  static String _dateOnly(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String _timeOnly(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:00';

  static String _formatTimeOfDay(TimeOfDay? t) {
    if (t == null) return 'Not set';
    final hour = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final minute = t.minute.toString().padLeft(2, '0');
    final period = t.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }

  static List<Map<String, dynamic>> _sortOptions(
    List<Map<String, dynamic>> items,
  ) {
    final sorted = List<Map<String, dynamic>>.from(items);
    sorted.sort(
      (a, b) => (a['name']?.toString() ?? '').toLowerCase().compareTo(
        (b['name']?.toString() ?? '').toLowerCase(),
      ),
    );
    return sorted;
  }

  static String? _safeValue(String? value, List<Map<String, dynamic>> items) {
    if (value == null) return null;
    return items.any((item) => item['id']?.toString() == value) ? value : null;
  }

  static String? _cleanString(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  static void _ensureOption(
    List<Map<String, dynamic>> items, {
    required String? id,
    required String? name,
    Map<String, dynamic> extra = const {},
  }) {
    final cleanId = _cleanString(id);
    if (cleanId == null) return;
    if (items.any((item) => item['id']?.toString() == cleanId)) return;
    items.add({
      'id': cleanId,
      'name': _cleanString(name) ?? 'Current item',
      ...extra,
    });
  }

  static bool _positionBelongsToDepartment(
    List<Map<String, dynamic>> positions,
    String? positionId,
    String? departmentId,
  ) {
    if (positionId == null || departmentId == null) return false;
    return positions.any(
      (p) =>
          p['id']?.toString() == positionId &&
          p['department_id']?.toString() == departmentId,
    );
  }

  List<Map<String, dynamic>> get _positionsForSelectedDepartment {
    final departmentId = _selectedDepartmentId;
    if (departmentId == null) return const [];
    return _positions
        .where((p) => p['department_id']?.toString() == departmentId)
        .toList();
  }

  void _setDepartment(String? departmentId) {
    setState(() {
      _selectedDepartmentId = departmentId;
      if (!_positionBelongsToDepartment(
        _positions,
        _selectedPositionId,
        departmentId,
      )) {
        _selectedPositionId = null;
      }
    });
  }

  Map<String, dynamic>? _effectiveTodayRow(List<dynamic> rows) {
    final today = _dateOnly(DateTime.now());
    final maps = rows
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .where((m) => m['is_active'] != false)
        .toList();
    if (maps.isEmpty) return null;

    String cleanDate(Object? value) {
      if (value == null) return '';
      return value.toString().split('T').first;
    }

    for (final row in maps) {
      final from = cleanDate(row['effective_from']);
      final to = cleanDate(row['effective_to']);
      final startsOk = from.isEmpty || from.compareTo(today) <= 0;
      final endsOk = to.isEmpty || to.compareTo(today) >= 0;
      if (startsOk && endsOk) return row;
    }
    return maps.first;
  }

  Future<void> _loadLookups({
    String? selectDepartmentId,
    String? selectPositionId,
    String? selectShiftId,
    String? selectPolicyId,
    bool loadCurrentSetup = false,
  }) async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final deptRes = await ApiClient.instance.get<List<dynamic>>(
        '/api/departments',
        queryParameters: {'status': 'Active'},
      );
      final posRes = await ApiClient.instance.get<List<dynamic>>(
        '/api/positions',
        queryParameters: {'status': 'Active'},
      );
      final shiftRes = await ApiClient.instance.get<List<dynamic>>(
        '/api/shifts',
        queryParameters: {'status': 'Active'},
      );
      final policyRes = await ApiClient.instance.get<List<dynamic>>(
        '/api/attendance-policies',
        queryParameters: {'status': 'Active'},
      );

      Map<String, dynamic>? assignment;
      Map<String, dynamic>? policyAssignment;
      if (loadCurrentSetup && widget.employeeId != null) {
        final assignmentRes = await ApiClient.instance.get<List<dynamic>>(
          '/api/assignments',
          queryParameters: {
            'employee_id': widget.employeeId,
            'status': 'Active',
          },
        );
        assignment = _effectiveTodayRow(assignmentRes.data ?? const []);

        final policyAssignmentRes = await ApiClient.instance.get<List<dynamic>>(
          '/api/policy-assignments',
          queryParameters: {
            'employee_id': widget.employeeId,
            'status': 'Active',
          },
        );
        policyAssignment = _effectiveTodayRow(
          policyAssignmentRes.data ?? const [],
        );
      }

      final departments = _sortOptions(
        (deptRes.data ?? const [])
            .whereType<Map>()
            .map((m) => Map<String, dynamic>.from(m))
            .map(
              (m) => {
                'id': m['id']?.toString(),
                'name': m['name']?.toString() ?? '',
              },
            )
            .where((m) => (m['id']?.toString() ?? '').isNotEmpty)
            .toList(),
      );
      final positions = _sortOptions(
        (posRes.data ?? const [])
            .whereType<Map>()
            .map((m) => Map<String, dynamic>.from(m))
            .map(
              (m) => {
                'id': m['id']?.toString(),
                'name': m['name']?.toString() ?? '',
                'department_id': m['department_id']?.toString(),
              },
            )
            .where((m) => (m['id']?.toString() ?? '').isNotEmpty)
            .toList(),
      );
      final shifts = _sortOptions(
        (shiftRes.data ?? const [])
            .whereType<Map>()
            .map((m) => Map<String, dynamic>.from(m))
            .map(
              (m) => {
                'id': m['id']?.toString(),
                'name': m['name']?.toString() ?? '',
              },
            )
            .where((m) => (m['id']?.toString() ?? '').isNotEmpty)
            .toList(),
      );
      final policies = _sortOptions(
        (policyRes.data ?? const [])
            .whereType<Map>()
            .map((m) => Map<String, dynamic>.from(m))
            .map(
              (m) => {
                'id': m['id']?.toString(),
                'name':
                    m['policy_name']?.toString() ?? m['name']?.toString() ?? '',
              },
            )
            .where((m) => (m['id']?.toString() ?? '').isNotEmpty)
            .toList(),
      );

      final currentDepartmentId = assignment?['department_id']?.toString();
      final currentPositionId = assignment?['position_id']?.toString();
      final currentShiftId = assignment?['shift_id']?.toString();
      final currentPolicyId = policyAssignment?['attendance_policy_id']
          ?.toString();

      if (loadCurrentSetup) {
        _ensureOption(
          departments,
          id: currentDepartmentId,
          name: assignment?['department_name'],
        );
        _ensureOption(
          positions,
          id: currentPositionId,
          name: assignment?['position_name'],
          extra: {'department_id': currentDepartmentId},
        );
        _ensureOption(
          shifts,
          id: currentShiftId,
          name: assignment?['shift_name'],
        );
        _ensureOption(
          policies,
          id: currentPolicyId,
          name: policyAssignment?['policy_name'],
        );
      }

      if (!mounted) return;
      setState(() {
        _departments = departments;
        _positions = positions;
        _shifts = shifts;
        _policies = policies;

        if (loadCurrentSetup) {
          final resolvedDepartmentId = _safeValue(
            currentDepartmentId,
            departments,
          );

          _original = EmployeeSetupSelection(
            departmentId: resolvedDepartmentId,
            positionId:
                _positionBelongsToDepartment(
                  positions,
                  currentPositionId,
                  resolvedDepartmentId,
                )
                ? currentPositionId
                : null,
            shiftId: _safeValue(currentShiftId, shifts),
            policyId: _safeValue(currentPolicyId, policies),
          );

          _selectedDepartmentId = _original.departmentId;
          _selectedPositionId = _original.positionId;
          _selectedShiftId = _original.shiftId;
          _selectedPolicyId = _original.policyId;
        } else {
          _selectedDepartmentId =
              selectDepartmentId ??
              _safeValue(_selectedDepartmentId, departments);
          _selectedPositionId =
              selectPositionId ??
              (_positionBelongsToDepartment(
                    positions,
                    _selectedPositionId,
                    _selectedDepartmentId,
                  )
                  ? _selectedPositionId
                  : null);
          _selectedShiftId =
              selectShiftId ?? _safeValue(_selectedShiftId, shifts);
          _selectedPolicyId =
              selectPolicyId ?? _safeValue(_selectedPolicyId, policies);
        }
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showSnackBar(
        _apiErrorMessage(e, fallback: 'Could not load setup options.'),
      );
    }
  }

  Future<Map<String, dynamic>?> _showNameDescriptionDialog({
    required String title,
    required String nameLabel,
    required String submitLabel,
    required Future<Map<String, dynamic>> Function(
      String name,
      String? description,
    )
    onSubmit,
  }) async {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();
    var saving = false;
    final created = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(title),
          content: Form(
            key: formKey,
            child: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameController,
                    autofocus: true,
                    decoration: InputDecoration(labelText: nameLabel),
                    textCapitalization: TextCapitalization.words,
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: descriptionController,
                    decoration: const InputDecoration(
                      labelText: 'Description (optional)',
                    ),
                    maxLines: 2,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving
                  ? null
                  : () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      if (!(formKey.currentState?.validate() ?? false)) return;
                      setDialogState(() => saving = true);
                      try {
                        final result = await onSubmit(
                          nameController.text.trim(),
                          descriptionController.text.trim().isEmpty
                              ? null
                              : descriptionController.text.trim(),
                        );
                        if (dialogContext.mounted) {
                          Navigator.of(dialogContext).pop(result);
                        }
                      } catch (e) {
                        _showSnackBar(
                          _apiErrorMessage(e, fallback: 'Could not save.'),
                        );
                        if (dialogContext.mounted) {
                          setDialogState(() => saving = false);
                        }
                      }
                    },
              child: saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(submitLabel),
            ),
          ],
        ),
      ),
    );
    nameController.dispose();
    descriptionController.dispose();
    return created;
  }

  Future<void> _quickAddDepartment() async {
    final created = await _showNameDescriptionDialog(
      title: 'Add Department',
      nameLabel: 'Department name',
      submitLabel: 'Add Department',
      onSubmit: (name, description) async {
        final res = await ApiClient.instance.post<Map<String, dynamic>>(
          '/api/departments',
          data: {'name': name, 'description': description, 'is_active': true},
        );
        final data = res.data ?? const {};
        return {
          'id': data['id']?.toString(),
          'name': data['name']?.toString() ?? name,
        };
      },
    );
    final id = created?['id']?.toString();
    if (id == null || id.isEmpty || !mounted) return;
    await _loadLookups(selectDepartmentId: id);
    _invalidateReferenceCaches();
    _showSnackBar('Department added.');
  }

  Future<void> _quickAddPosition() async {
    final departmentId = _selectedDepartmentId;
    if (departmentId == null || departmentId.isEmpty) {
      _showSnackBar('Select or add a department first.');
      return;
    }
    final created = await _showNameDescriptionDialog(
      title: 'Add Position',
      nameLabel: 'Position title',
      submitLabel: 'Add Position',
      onSubmit: (name, description) async {
        final res = await ApiClient.instance.post<Map<String, dynamic>>(
          '/api/positions',
          data: {
            'name': name,
            'description': description,
            'department_id': departmentId,
            'is_active': true,
          },
        );
        final data = res.data ?? const {};
        return {
          'id': data['id']?.toString(),
          'name': data['name']?.toString() ?? name,
          'department_id': departmentId,
        };
      },
    );
    final id = created?['id']?.toString();
    if (id == null || id.isEmpty || !mounted) return;
    await _loadLookups(selectDepartmentId: departmentId, selectPositionId: id);
    _invalidateReferenceCaches();
    _showSnackBar('Position added.');
  }

  Future<void> _quickAddShift() async {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController();
    final graceController = TextEditingController(text: '0');
    TimeOfDay? startTime = const TimeOfDay(hour: 8, minute: 0);
    TimeOfDay? endTime = const TimeOfDay(hour: 17, minute: 0);
    TimeOfDay? breakEndTime = const TimeOfDay(hour: 13, minute: 0);
    var saving = false;

    final created = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          Future<void> pickTime(
            TimeOfDay? current,
            ValueChanged<TimeOfDay> apply,
          ) async {
            final picked = await showTimePicker(
              context: dialogContext,
              initialTime: current ?? TimeOfDay.now(),
            );
            if (picked != null && dialogContext.mounted) {
              setDialogState(() => apply(picked));
            }
          }

          Widget timeTile({
            required String label,
            required TimeOfDay? value,
            required VoidCallback onTap,
            VoidCallback? onClear,
          }) {
            return InkWell(
              onTap: saving ? null : onTap,
              borderRadius: BorderRadius.circular(8),
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: label,
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (onClear != null)
                        IconButton(
                          tooltip: 'Clear',
                          icon: const Icon(Icons.close_rounded, size: 18),
                          onPressed: saving ? null : onClear,
                        ),
                      const Icon(Icons.access_time_rounded, size: 18),
                      const SizedBox(width: 12),
                    ],
                  ),
                ),
                child: Text(_formatTimeOfDay(value)),
              ),
            );
          }

          return AlertDialog(
            title: const Text('Add Shift'),
            content: Form(
              key: formKey,
              child: SizedBox(
                width: 460,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: nameController,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Shift name',
                      ),
                      textCapitalization: TextCapitalization.words,
                      validator: (v) =>
                          v == null || v.trim().isEmpty ? 'Required' : null,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: timeTile(
                            label: 'Start',
                            value: startTime,
                            onTap: () =>
                                pickTime(startTime, (t) => startTime = t),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: timeTile(
                            label: 'End',
                            value: endTime,
                            onTap: () => pickTime(endTime, (t) => endTime = t),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    timeTile(
                      label: 'PM Start (optional)',
                      value: breakEndTime,
                      onTap: () =>
                          pickTime(breakEndTime, (t) => breakEndTime = t),
                      onClear: () => setDialogState(() => breakEndTime = null),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: graceController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Grace period minutes',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving
                    ? null
                    : () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: saving
                    ? null
                    : () async {
                        if (!(formKey.currentState?.validate() ?? false)) {
                          return;
                        }
                        if (startTime == null || endTime == null) {
                          _showSnackBar('Start and end time are required.');
                          return;
                        }
                        setDialogState(() => saving = true);
                        try {
                          final res = await ApiClient.instance
                              .post<Map<String, dynamic>>(
                                '/api/shifts',
                                data: {
                                  'name': nameController.text.trim(),
                                  'start_time': _timeOnly(startTime!),
                                  'end_time': _timeOnly(endTime!),
                                  if (breakEndTime != null)
                                    'break_end': _timeOnly(breakEndTime!),
                                  'punch_mode': 'auto',
                                  'grace_period_minutes':
                                      int.tryParse(
                                        graceController.text.trim(),
                                      ) ??
                                      0,
                                  'working_days': const [1, 2, 3, 4, 5],
                                  'is_active': true,
                                },
                              );
                          final data = res.data ?? const {};
                          if (dialogContext.mounted) {
                            Navigator.of(dialogContext).pop({
                              'id': data['id']?.toString(),
                              'name':
                                  data['name']?.toString() ??
                                  nameController.text.trim(),
                            });
                          }
                        } catch (e) {
                          _showSnackBar(
                            _apiErrorMessage(
                              e,
                              fallback: 'Could not save shift.',
                            ),
                          );
                          if (dialogContext.mounted) {
                            setDialogState(() => saving = false);
                          }
                        }
                      },
                child: saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Add Shift'),
              ),
            ],
          );
        },
      ),
    );

    nameController.dispose();
    graceController.dispose();
    final id = created?['id']?.toString();
    if (id == null || id.isEmpty || !mounted) return;
    await _loadLookups(selectShiftId: id);
    _invalidateReferenceCaches();
    _showSnackBar('Shift added.');
  }

  Future<void> _quickAddPolicy() async {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController();
    final workHoursController = TextEditingController(text: '8');
    var deductLate = true;
    var deductUndertime = true;
    var combineLateAndUndertime = false;
    var saving = false;

    final created = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Add Attendance Policy'),
          content: Form(
            key: formKey,
            child: SizedBox(
              width: 460,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameController,
                    autofocus: true,
                    decoration: const InputDecoration(labelText: 'Policy name'),
                    textCapitalization: TextCapitalization.words,
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: workHoursController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Work hours per day',
                    ),
                    validator: (v) {
                      final value = double.tryParse(v?.trim() ?? '');
                      return value == null || value <= 0
                          ? 'Enter valid hours'
                          : null;
                    },
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Count late minutes'),
                    value: deductLate,
                    onChanged: saving
                        ? null
                        : (v) => setDialogState(() => deductLate = v),
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Count undertime minutes'),
                    value: deductUndertime,
                    onChanged: saving
                        ? null
                        : (v) => setDialogState(() => deductUndertime = v),
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Combine late into undertime'),
                    value: combineLateAndUndertime,
                    onChanged: saving
                        ? null
                        : (v) =>
                              setDialogState(() => combineLateAndUndertime = v),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving
                  ? null
                  : () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      if (!(formKey.currentState?.validate() ?? false)) return;
                      setDialogState(() => saving = true);
                      try {
                        final res = await ApiClient.instance
                            .post<Map<String, dynamic>>(
                              '/api/attendance-policies',
                              data: {
                                'policy_name': nameController.text.trim(),
                                'work_hours_per_day':
                                    double.tryParse(
                                      workHoursController.text.trim(),
                                    ) ??
                                    8,
                                'deduct_late': deductLate,
                                'deduct_undertime': deductUndertime,
                                'combine_late_and_undertime':
                                    combineLateAndUndertime,
                                'convert_late_to_equivalent_day': true,
                                'convert_undertime_to_equivalent_day': true,
                                'absent_equals_full_day_deduction': true,
                                'deduction_multiplier': 1.0,
                                'is_active': true,
                              },
                            );
                        final data = res.data ?? const {};
                        if (dialogContext.mounted) {
                          Navigator.of(dialogContext).pop({
                            'id': data['id']?.toString(),
                            'name':
                                data['policy_name']?.toString() ??
                                data['name']?.toString() ??
                                nameController.text.trim(),
                          });
                        }
                      } catch (e) {
                        _showSnackBar(
                          _apiErrorMessage(
                            e,
                            fallback: 'Could not save policy.',
                          ),
                        );
                        if (dialogContext.mounted) {
                          setDialogState(() => saving = false);
                        }
                      }
                    },
              child: saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Add Policy'),
            ),
          ],
        ),
      ),
    );

    nameController.dispose();
    workHoursController.dispose();
    final id = created?['id']?.toString();
    if (id == null || id.isEmpty || !mounted) return;
    await _loadLookups(selectPolicyId: id);
    _invalidateReferenceCaches();
    _showSnackBar('Attendance policy added.');
  }

  Widget _buildDropdown({
    required String label,
    required String? value,
    required List<Map<String, dynamic>> items,
    required ValueChanged<String?> onChanged,
    required VoidCallback onAdd,
    required String addTooltip,
    bool enabled = true,
    String emptyLabel = 'None',
  }) {
    final safeValue = _safeValue(value, items);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: DropdownButtonFormField<String?>(
            key: ValueKey(
              'employee_setup_${label}_${safeValue}_${items.length}_$enabled',
            ),
            initialValue: safeValue,
            isExpanded: true,
            decoration: AppTheme.dashInputDecoration(context, hintText: label),
            hint: Text(enabled ? 'Select' : emptyLabel),
            items: [
              DropdownMenuItem<String?>(
                value: null,
                child: Text(emptyLabel, overflow: TextOverflow.ellipsis),
              ),
              ...items.map(
                (item) => DropdownMenuItem<String?>(
                  value: item['id']?.toString(),
                  child: Text(
                    item['name']?.toString() ?? 'Unnamed',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
            onChanged: enabled ? onChanged : null,
          ),
        ),
        const SizedBox(width: 8),
        Tooltip(
          message: addTooltip,
          child: IconButton.filledTonal(
            onPressed: onAdd,
            icon: const Icon(Icons.add_rounded),
          ),
        ),
      ],
    );
  }

  Widget _content() {
    final filteredPositions = _positionsForSelectedDepartment;
    final hasDepartment = _selectedDepartmentId != null;
    final canSelectPosition = hasDepartment && filteredPositions.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.title,
          style: TextStyle(
            color: AppTheme.dashTextPrimaryOf(context),
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          widget.subtitle,
          style: TextStyle(
            color: AppTheme.dashTextSecondaryOf(context),
            fontSize: 12,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 12),
        if (_loading)
          const LinearProgressIndicator(minHeight: 2)
        else ...[
          _buildDropdown(
            label: 'Department',
            value: _selectedDepartmentId,
            items: _departments,
            onChanged: _setDepartment,
            onAdd: _quickAddDepartment,
            addTooltip: 'Add department',
            emptyLabel: 'No department',
          ),
          const SizedBox(height: 12),
          _buildDropdown(
            label: 'Position',
            value: _selectedPositionId,
            items: filteredPositions,
            onChanged: (v) => setState(() => _selectedPositionId = v),
            onAdd: _quickAddPosition,
            addTooltip: 'Add position',
            enabled: canSelectPosition,
            emptyLabel: !hasDepartment
                ? 'Select department first'
                : 'No position',
          ),
          const SizedBox(height: 12),
          _buildDropdown(
            label: 'Shift',
            value: _selectedShiftId,
            items: _shifts,
            onChanged: (v) => setState(() => _selectedShiftId = v),
            onAdd: _quickAddShift,
            addTooltip: 'Add shift',
            emptyLabel: 'No shift',
          ),
          const SizedBox(height: 12),
          _buildDropdown(
            label: 'Attendance policy',
            value: _selectedPolicyId,
            items: _policies,
            onChanged: (v) => setState(() => _selectedPolicyId = v),
            onAdd: _quickAddPolicy,
            addTooltip: 'Add attendance policy',
            emptyLabel: widget.loadCurrentSetup
                ? 'Use inherited/default policy'
                : 'Use default policy',
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = widget.boxed
        ? Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.dashMutedSurfaceOf(context),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.dashHairlineOf(context)),
            ),
            child: _content(),
          )
        : _content();

    if (!widget.showTopDivider) return body;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        Divider(color: AppTheme.dashHairlineOf(context)),
        const SizedBox(height: 18),
        body,
      ],
    );
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _invalidateReferenceCaches() {
    try {
      final dtr = context.read<DtrProvider>();
      dtr.invalidateCachedDtrData(includeReferenceData: true);
      dtr.loadDepartments(forceRefresh: true);
      dtr.loadEmployees(forceRefresh: true);
    } catch (_) {}
  }
}

String _apiErrorMessage(Object e, {required String fallback}) {
  if (e is DioException) {
    final data = e.response?.data;
    if (data is Map && data['error'] != null) {
      return data['error'].toString();
    }
    if (e.message != null && e.message!.isNotEmpty) return e.message!;
  }
  return fallback;
}
