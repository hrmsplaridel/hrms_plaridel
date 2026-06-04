import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/docutracker/data/styles/docutracker_styles.dart';
import 'package:hrms_plaridel/features/docutracker/theme/docutracker_tokens.dart';
import 'package:hrms_plaridel/features/docutracker/models/workflow_step.dart';

/// Picker-backed step editor for [DocuTrackerWorkflowEditorScreen].
///
/// Pops with [WorkflowStep] on save, or `null` on cancel.
class WorkflowStepEditorPanel extends StatefulWidget {
  const WorkflowStepEditorPanel({
    super.key,
    required this.title,
    required this.initial,
  });

  final String title;
  final WorkflowStep initial;

  @override
  State<WorkflowStepEditorPanel> createState() =>
      _WorkflowStepEditorPanelState();
}

class _DeptRow {
  const _DeptRow({required this.id, required this.name});
  final String id;
  final String name;
}

class _EmpRow {
  const _EmpRow({required this.id, required this.name});
  final String id;
  final String name;
}

class _WorkflowStepEditorPanelState extends State<WorkflowStepEditorPanel> {
  late bool _enabled;
  String? _dialogError;

  final _labelController = TextEditingController();
  final _usersManualController = TextEditingController();
  final _deadlineController = TextEditingController();
  final _empSearchController = TextEditingController();

  List<_DeptRow> _departments = [];
  String? _departmentDropdownValue;
  final _departmentManualController = TextEditingController();
  bool _departmentsLoading = false;

  List<_EmpRow> _employeeHits = [];
  bool _employeesLoading = false;
  Timer? _empSearchDebounce;

  /// First user in the saved list is treated as the primary reviewer; the rest are backups.
  String? _primaryUserId;
  final List<String> _backupUserIds = [];
  final Map<String, String> _userIdToName = {};
  List<_EmpRow> _departmentRoster = [];
  bool _rosterLoading = false;

  @override
  void initState() {
    super.initState();
    final s = widget.initial;
    _enabled = s.enabled;

    _labelController.text = s.label ?? '';
    _deadlineController.text = s.deadlineHours?.toString() ?? '';
    final rawIds = (s.userIds ?? const [])
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (rawIds.isNotEmpty) {
      _primaryUserId = rawIds.first;
      if (rawIds.length > 1) {
        _backupUserIds.addAll(rawIds.sublist(1));
      }
    }
    _usersManualController.text = rawIds.join(', ');

    final did = (s.departmentId ?? '').trim();
    _departmentDropdownValue = did.isEmpty ? null : did;
    _departmentManualController.text = did;

    _loadDepartments();
    _fetchEmployees();
    _empSearchController.addListener(_scheduleEmpSearch);
    Future<void>.microtask(() => _loadDepartmentRoster());
  }

  @override
  void dispose() {
    _empSearchDebounce?.cancel();
    _empSearchController.removeListener(_scheduleEmpSearch);
    _labelController.dispose();
    _usersManualController.dispose();
    _deadlineController.dispose();
    _empSearchController.dispose();
    _departmentManualController.dispose();
    super.dispose();
  }

  void _scheduleEmpSearch() {
    _empSearchDebounce?.cancel();
    _empSearchDebounce = Timer(
      const Duration(milliseconds: 350),
      _fetchEmployees,
    );
  }

  Future<void> _loadDepartments() async {
    setState(() => _departmentsLoading = true);
    try {
      final res = await ApiClient.instance.get<List<dynamic>>(
        '/api/departments',
      );
      final data = res.data ?? [];
      final rows = <_DeptRow>[];
      for (final e in data) {
        final m = e as Map<String, dynamic>;
        final id = m['id']?.toString();
        if (id == null || id.isEmpty) continue;
        final name = m['name']?.toString() ?? '—';
        rows.add(_DeptRow(id: id, name: name));
      }
      rows.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      if (mounted) {
        setState(() {
          _departments = rows;
          _ensureDepartmentValueValid();
        });
      }
      if (mounted) {
        await _loadDepartmentRoster();
      }
    } on DioException catch (_) {
      if (mounted) setState(() => _departments = []);
    } catch (_) {
      if (mounted) setState(() => _departments = []);
    } finally {
      if (mounted) setState(() => _departmentsLoading = false);
    }
  }

  void _ensureDepartmentValueValid() {
    final v = _departmentDropdownValue;
    if (v == null || v.isEmpty) return;
    if (_departments.any((d) => d.id == v)) return;
    _departments = [
      _DeptRow(id: v, name: 'Current id (not in list)'),
      ..._departments,
    ];
  }

  Future<void> _fetchEmployees() async {
    setState(() => _employeesLoading = true);
    try {
      final q = _empSearchController.text.trim();
      final dept = (_departmentDropdownValue ?? '').trim();
      final res = await ApiClient.instance.get<dynamic>(
        '/api/employees',
        queryParameters: <String, dynamic>{
          'status': 'Active',
          'role': 'All',
          'limit': 100,
          'offset': 0,
          if (q.isNotEmpty) 'q': q,
          if (dept.isNotEmpty) 'department_id': dept,
          'sort': 'full_name',
          'order': 'asc',
        },
      );
      final data = res.data;
      List<dynamic> list;
      if (data is Map && data['employees'] is List) {
        list = data['employees'] as List<dynamic>;
      } else if (data is List) {
        list = data;
      } else {
        list = [];
      }
      final rows = <_EmpRow>[];
      for (final e in list) {
        final m = e as Map<String, dynamic>;
        final id = m['id']?.toString();
        if (id == null || id.isEmpty) continue;
        final name = m['full_name']?.toString() ?? 'Unknown';
        rows.add(_EmpRow(id: id, name: name));
      }
      if (mounted) setState(() => _employeeHits = rows);
    } catch (_) {
      if (mounted) setState(() => _employeeHits = []);
    } finally {
      if (mounted) setState(() => _employeesLoading = false);
    }
  }

  Future<void> _loadDepartmentRoster() async {
    final dept = (_departmentDropdownValue ?? _departmentManualController.text)
        .trim();
    if (dept.isEmpty) {
      if (mounted) setState(() => _departmentRoster = []);
      return;
    }
    if (!mounted) return;
    setState(() => _rosterLoading = true);
    try {
      final res = await ApiClient.instance.get<dynamic>(
        '/api/employees',
        queryParameters: <String, dynamic>{
          'status': 'Active',
          'role': 'All',
          'limit': 500,
          'offset': 0,
          'department_id': dept,
          'sort': 'full_name',
          'order': 'asc',
        },
      );
      final data = res.data;
      List<dynamic> list;
      if (data is Map && data['employees'] is List) {
        list = data['employees'] as List<dynamic>;
      } else if (data is List) {
        list = data;
      } else {
        list = [];
      }
      final rows = <_EmpRow>[];
      for (final e in list) {
        final m = e as Map<String, dynamic>;
        final id = m['id']?.toString();
        if (id == null || id.isEmpty) continue;
        final name = m['full_name']?.toString() ?? 'Unknown';
        rows.add(_EmpRow(id: id, name: name));
        _userIdToName[id] = name;
      }
      rows.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      if (mounted) {
        setState(() {
          _departmentRoster = rows;
          _pruneAssignmentsAgainstRoster();
        });
      }
    } catch (_) {
      if (mounted) setState(() => _departmentRoster = []);
    } finally {
      if (mounted) setState(() => _rosterLoading = false);
    }
  }

  void _pruneAssignmentsAgainstRoster() {
    if (_departmentRoster.isEmpty) return;
    final allowed = _departmentRoster.map((e) => e.id).toSet();
    if (_primaryUserId != null && !allowed.contains(_primaryUserId)) {
      _primaryUserId = null;
    }
    _backupUserIds.removeWhere((id) => !allowed.contains(id));
  }

  List<String> get _orderedUserIds {
    final out = <String>[];
    final p = _primaryUserId?.trim();
    if (p != null && p.isNotEmpty) out.add(p);
    for (final id in _backupUserIds) {
      final t = id.trim();
      if (t.isEmpty || t == p) continue;
      if (out.contains(t)) continue;
      out.add(t);
    }
    return out;
  }

  String? _lookupRosterName(String id) {
    for (final e in _departmentRoster) {
      if (e.id == id) return e.name;
    }
    return null;
  }

  void _refreshManualUserLine() {
    _usersManualController.text = _orderedUserIds.join(', ');
  }

  String? _validateDraft() {
    final deadlineRaw = _deadlineController.text.trim();
    if (deadlineRaw.isNotEmpty) {
      final h = int.tryParse(deadlineRaw);
      if (h == null) return 'Deadline hours must be a whole number.';
      if (h <= 0) return 'Deadline hours must be greater than zero.';
    }
    if (!_enabled) return null;
    final dept = _departments.isNotEmpty
        ? (_departmentDropdownValue ?? '').trim()
        : _departmentManualController.text.trim();
    if (dept.isEmpty) {
      return 'Choose which department this step belongs to, or disable this step.';
    }
    if ((_primaryUserId ?? '').trim().isEmpty) {
      return 'Choose a primary reviewer from the department list, or disable this step.';
    }
    return null;
  }

  void _syncPrimaryBackupsFromManual() {
    final parts = _usersManualController.text
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    _primaryUserId = parts.isNotEmpty ? parts.first : null;
    _backupUserIds
      ..clear()
      ..addAll(parts.length > 1 ? parts.sublist(1) : const []);
  }

  void _submit() {
    final err = _validateDraft();
    if (err != null) {
      setState(() => _dialogError = err);
      return;
    }
    final label = _labelController.text.trim();
    final deadlineRaw = _deadlineController.text.trim();
    final deadlineHours = deadlineRaw.isEmpty
        ? null
        : int.tryParse(deadlineRaw);
    final dept = _departments.isNotEmpty
        ? (_departmentDropdownValue ?? '').trim()
        : _departmentManualController.text.trim();

    Navigator.of(context).pop(
      WorkflowStep(
        stepOrder: widget.initial.stepOrder,
        assigneeType: 'user',
        label: label.isEmpty ? null : label,
        enabled: _enabled,
        departmentId: dept.isEmpty ? null : dept,
        userIds: _orderedUserIds,
        deadlineHours: deadlineHours,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: _enabled
                          ? DocuTrackerTokens.brand.withValues(alpha: 0.04)
                          : Colors.grey.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _enabled
                            ? DocuTrackerTokens.brand.withValues(alpha: 0.2)
                            : Colors.black.withValues(alpha: 0.08),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Step enabled',
                                  style: TextStyle(
                                    color: AppTheme.textPrimary,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Assignee and deadlines apply only while the step is enabled.',
                                  style: TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontSize: 12,
                                    height: 1.25,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: _enabled,
                            onChanged: (v) => setState(() {
                              _enabled = v;
                              _dialogError = null;
                            }),
                            activeTrackColor: DocuTrackerTokens.brand
                                .withValues(alpha: 0.8),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _labelController,
                    decoration: DocuTrackerStyles.inputDecoration(
                      context,
                      'Step label (shown in the flow)',
                      Icons.label_rounded,
                    ),
                    onChanged: (_) => setState(() => _dialogError = null),
                  ),
                  const SizedBox(height: 12),
                  _WorkflowStepSectionLabel(
                    stepNumber: 1,
                    title: 'Department',
                    subtitle:
                        'Pick the department this step belongs to. Only people from this '
                        'list can be assigned.',
                  ),
                  const SizedBox(height: 8),
                  if (_departmentsLoading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  else if (_departments.isNotEmpty)
                    DropdownButtonFormField<String>(
                      key: ValueKey<String>(
                        'user-dept-$_departmentDropdownValue',
                      ),
                      initialValue: _departmentDropdownValue,
                      decoration: DocuTrackerStyles.dropdownDecoration(
                        context,
                        'Department',
                      ),
                      hint: const Text('Select department'),
                      isExpanded: true,
                      items: _departments
                          .map(
                            (d) => DropdownMenuItem(
                              value: d.id,
                              child: Text(
                                d.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        setState(() {
                          _departmentDropdownValue = v;
                          if (v != null) _departmentManualController.text = v;
                          _dialogError = null;
                        });
                        _fetchEmployees();
                        _loadDepartmentRoster();
                      },
                    )
                  else
                    TextField(
                      controller: _departmentManualController,
                      decoration: DocuTrackerStyles.inputDecoration(
                        context,
                        'Department id (UUID)',
                        Icons.apartment_rounded,
                      ),
                      onChanged: (_) {
                        setState(() => _dialogError = null);
                        _loadDepartmentRoster();
                        _fetchEmployees();
                      },
                    ),
                  const SizedBox(height: 16),
                  _WorkflowStepSectionLabel(
                    stepNumber: 2,
                    title: 'Primary reviewer',
                    subtitle:
                        'One person is responsible for moving the document forward.',
                  ),
                  const SizedBox(height: 8),
                  if (_rosterLoading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  else if (!_rosterLoading &&
                      (_departmentDropdownValue ??
                              _departmentManualController.text)
                          .trim()
                          .isEmpty)
                    Text(
                      'Select a department in step 1 to load people.',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                      ),
                    )
                  else if (!_rosterLoading && _departmentRoster.isEmpty)
                    Text(
                      'No active employees found for this department.',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                      ),
                    )
                  else
                    DropdownButtonFormField<String>(
                      key: ValueKey<String>(
                        'primary-$_departmentDropdownValue-$_primaryUserId',
                      ),
                      initialValue: _primaryUserId,
                      decoration: DocuTrackerStyles.dropdownDecoration(
                        context,
                        'Primary reviewer',
                      ),
                      hint: const Text('Choose a person'),
                      isExpanded: true,
                      items: [
                        if (_primaryUserId != null &&
                            !_departmentRoster.any(
                              (e) => e.id == _primaryUserId,
                            ))
                          DropdownMenuItem(
                            value: _primaryUserId,
                            child: Text(
                              'Current: ${_userIdToName[_primaryUserId!] ?? _primaryUserId}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        for (final e in _departmentRoster)
                          DropdownMenuItem(
                            value: e.id,
                            child: Text(
                              e.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (v) {
                        setState(() {
                          _primaryUserId = v;
                          if (v != null) {
                            _userIdToName[v] =
                                _lookupRosterName(v) ?? _userIdToName[v] ?? '';
                            _backupUserIds.remove(v);
                          }
                          _refreshManualUserLine();
                          _dialogError = null;
                        });
                      },
                    ),
                  const SizedBox(height: 16),
                  _WorkflowStepSectionLabel(
                    stepNumber: 3,
                    title: 'Backup reviewers (optional)',
                    subtitle:
                        'If the primary is unavailable, these people can help — '
                        'you finalize who can approve in “Manage step assignees”.',
                  ),
                  const SizedBox(height: 8),
                  if (_departmentRoster.isNotEmpty) ...[
                    if (_departmentRoster.any(
                      (e) =>
                          e.id != _primaryUserId &&
                          !_backupUserIds.contains(e.id),
                    ))
                      DropdownButtonFormField<String>(
                        key: ValueKey<String>(
                          'add-backup-${_backupUserIds.length}',
                        ),
                        initialValue: null,
                        decoration: DocuTrackerStyles.dropdownDecoration(
                          context,
                          'Add backup',
                        ),
                        hint: const Text('Choose someone to add'),
                        isExpanded: true,
                        items: [
                          for (final e in _departmentRoster)
                            if (e.id != _primaryUserId &&
                                !_backupUserIds.contains(e.id))
                              DropdownMenuItem(
                                value: e.id,
                                child: Text(
                                  e.name,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() {
                            _userIdToName[v] = _lookupRosterName(v) ?? '';
                            if (!_backupUserIds.contains(v)) {
                              _backupUserIds.add(v);
                            }
                            _refreshManualUserLine();
                            _dialogError = null;
                          });
                        },
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Text(
                          'Everyone in this department is already listed on this step.',
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                  if (_backupUserIds.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final id in _backupUserIds)
                          InputChip(
                            label: Text(
                              _userIdToName[id] ??
                                  (id.length > 12
                                      ? '${id.substring(0, 8)}…'
                                      : id),
                              style: const TextStyle(fontSize: 12),
                            ),
                            onDeleted: () => setState(() {
                              _backupUserIds.remove(id);
                              _refreshManualUserLine();
                              _dialogError = null;
                            }),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    'Total: ${_orderedUserIds.length} reviewer(s) · '
                    'Primary first, then backups in order.',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 11,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _WorkflowStepSectionLabel(
                    stepNumber: 4,
                    title: 'Find by name (optional)',
                    subtitle: 'Use search if the dropdown list is long.',
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _empSearchController,
                    decoration: DocuTrackerStyles.inputDecoration(
                      context,
                      'Search employees (name)',
                      Icons.search_rounded,
                    ),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 160,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Colors.black.withValues(alpha: 0.08),
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: _employeesLoading
                          ? const Center(
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : ListView.builder(
                              itemCount: _employeeHits.length,
                              itemBuilder: (ctx, i) {
                                final e = _employeeHits[i];
                                final isPrimary = _primaryUserId == e.id;
                                final isBackup = _backupUserIds.contains(e.id);
                                return ListTile(
                                  dense: true,
                                  title: Text(
                                    e.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Text(
                                    isPrimary
                                        ? 'Primary'
                                        : isBackup
                                        ? 'Backup'
                                        : 'Tap to add as backup',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: AppTheme.textSecondary.withValues(
                                        alpha: 0.95,
                                      ),
                                    ),
                                  ),
                                  trailing: isPrimary
                                      ? Icon(
                                          Icons.star_rounded,
                                          color: DocuTrackerTokens.brand,
                                          size: 20,
                                        )
                                      : isBackup
                                      ? Icon(
                                          Icons.check_circle_outline_rounded,
                                          color: Colors.green.shade700,
                                          size: 20,
                                        )
                                      : IconButton(
                                          icon: const Icon(
                                            Icons.add_circle_outline_rounded,
                                          ),
                                          onPressed: () {
                                            if (_primaryUserId == null) {
                                              setState(() {
                                                _primaryUserId = e.id;
                                                _userIdToName[e.id] = e.name;
                                                _refreshManualUserLine();
                                              });
                                            } else if (!_backupUserIds.contains(
                                                  e.id,
                                                ) &&
                                                e.id != _primaryUserId) {
                                              setState(() {
                                                _backupUserIds.add(e.id);
                                                _userIdToName[e.id] = e.name;
                                                _refreshManualUserLine();
                                              });
                                            }
                                          },
                                        ),
                                  onTap: () {
                                    if (isPrimary) return;
                                    if (_primaryUserId == null) {
                                      setState(() {
                                        _primaryUserId = e.id;
                                        _userIdToName[e.id] = e.name;
                                        _refreshManualUserLine();
                                      });
                                    } else if (!isBackup &&
                                        e.id != _primaryUserId) {
                                      setState(() {
                                        _backupUserIds.add(e.id);
                                        _userIdToName[e.id] = e.name;
                                        _refreshManualUserLine();
                                      });
                                    }
                                  },
                                );
                              },
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ExpansionTile(
                    title: Text(
                      'Advanced: paste IDs',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: TextField(
                          controller: _usersManualController,
                          maxLines: 2,
                          decoration: DocuTrackerStyles.inputDecoration(
                            context,
                            'User IDs — first = primary, rest = backups (comma-separated)',
                            Icons.edit_note_rounded,
                          ),
                          onChanged: (_) => setState(() {
                            _syncPrimaryBackupsFromManual();
                            _dialogError = null;
                          }),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _deadlineController,
                    keyboardType: TextInputType.number,
                    decoration: DocuTrackerStyles.inputDecoration(
                      context,
                      'Deadline for this step (hours, optional)',
                      Icons.timer_rounded,
                    ),
                    onChanged: (_) => setState(() => _dialogError = null),
                  ),
                  if (_dialogError != null) ...[
                    const SizedBox(height: 12),
                    Material(
                      color: const Color(0xFFFFEBEE),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.error_outline_rounded,
                              size: 20,
                              color: Colors.red.shade800,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _dialogError!,
                                style: TextStyle(
                                  color: Colors.red.shade900,
                                  fontSize: 13,
                                  height: 1.3,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: _submit,
                  child: const Text('Save step'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkflowStepSectionLabel extends StatelessWidget {
  const _WorkflowStepSectionLabel({
    required this.stepNumber,
    required this.title,
    required this.subtitle,
  });

  final int stepNumber;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: DocuTrackerTokens.brand.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '$stepNumber',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 13,
              color: DocuTrackerTokens.brand,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 11,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Opens the step editor in a bottom sheet (narrow) or dialog (wide).
Future<WorkflowStep?> showWorkflowStepEditor(
  BuildContext context, {
  required String title,
  required WorkflowStep initial,
}) async {
  final width = MediaQuery.sizeOf(context).width;
  final useSheet = width < 720;

  if (useSheet) {
    return showModalBottomSheet<WorkflowStep>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (ctx) {
        final viewInsets = MediaQuery.viewInsetsOf(ctx).bottom;
        final h = MediaQuery.sizeOf(ctx).height * 0.9;
        return Padding(
          padding: EdgeInsets.only(bottom: viewInsets),
          child: SizedBox(
            height: h,
            child: WorkflowStepEditorPanel(title: title, initial: initial),
          ),
        );
      },
    );
  }

  return showDialog<WorkflowStep>(
    context: context,
    builder: (ctx) => Dialog(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: SizedBox(
        width: 520,
        height: MediaQuery.sizeOf(ctx).height * 0.78,
        child: WorkflowStepEditorPanel(title: title, initial: initial),
      ),
    ),
  );
}
