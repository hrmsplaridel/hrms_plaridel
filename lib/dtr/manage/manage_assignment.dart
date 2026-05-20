import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../api/client.dart';
import '../../landingpage/constants/app_theme.dart';

/// Backend JSON often uses `{ "error": "..." }`; avoid showing raw [DioException] in UI.
String _userFacingApiError(Object e) {
  if (e is DioException) {
    final data = e.response?.data;
    if (data is Map && data['error'] != null) {
      return data['error'].toString();
    }
    if (e.message != null && e.message!.isNotEmpty) {
      return e.message!;
    }
    return 'Request failed';
  }
  return e.toString();
}

/// Employee summary for assignment list.
class _EmployeeSummary {
  const _EmployeeSummary({
    required this.id,
    required this.fullName,
    this.employeeNumber,
  });
  final String id;
  final String fullName;
  final int? employeeNumber;

  String get displayEmployeeNo => employeeNumber != null
      ? 'EMP-${employeeNumber!.toString().padLeft(3, '0')}'
      : '—';
}

/// Assignment record for display/CRUD (Schema v2: effective_from/to, override times).
class _AssignmentRecord {
  const _AssignmentRecord({
    required this.id,
    required this.departmentId,
    required this.positionId,
    required this.shiftId,
    required this.departmentName,
    required this.positionName,
    required this.shiftName,
    required this.startTime,
    required this.endTime,
    required this.effectiveFrom,
    this.effectiveTo,
    this.policyId,
    this.policyName,
    required this.isActive,
    this.remarks,
  });
  final String id;
  final String? departmentId;
  final String? positionId;
  final String? shiftId;
  final String departmentName;
  final String positionName;
  final String shiftName;
  final TimeOfDay startTime;
  final TimeOfDay endTime;
  final DateTime effectiveFrom;
  final DateTime? effectiveTo;
  final String? policyId;
  final String? policyName;
  final bool isActive;
  final String? remarks;
}

/// Assignment management screen: employee list + assignment CRUD.
class ManageAssignment extends StatefulWidget {
  const ManageAssignment({
    super.key,
    this.initialEmployeeId,
    this.onInitialEmployeeConsumed,
  });

  /// Pre-select after first employee load (e.g. deep-link from Employees).
  final String? initialEmployeeId;
  final VoidCallback? onInitialEmployeeConsumed;

  @override
  State<ManageAssignment> createState() => _ManageAssignmentState();
}

class _ManageAssignmentState extends State<ManageAssignment> {
  final _searchController = TextEditingController();
  String _employeeStatusFilter = 'All';
  String _assignmentStatusFilter = 'Active';
  String? _selectedEmployeeId;
  List<_EmployeeSummary> _employees = [];
  bool _loadingEmployees = false;

  List<_AssignmentRecord> _assignments = [];
  bool _loadingAssignments = false;

  List<Map<String, dynamic>> _departments = [];
  List<Map<String, dynamic>> _positions = [];
  List<Map<String, dynamic>> _shifts = [];
  List<Map<String, dynamic>> _attendancePolicies = [];
  bool _loadingLookups = false;

  String? _selectedDeptId;
  String? _selectedPositionId;
  String? _selectedShiftId;
  String? _selectedPolicyId;
  DateTime? _effectiveFrom;
  DateTime? _effectiveTo;
  final _remarksController = TextEditingController();
  _AssignmentRecord? _selectedAssignment;

  bool _initialPrefillApplied = false;

  @override
  void initState() {
    super.initState();
    final pre = widget.initialEmployeeId?.trim();
    if (pre != null && pre.isNotEmpty) {
      _employeeStatusFilter = 'All';
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadEmployees();
      _loadLookups();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _remarksController.dispose();
    super.dispose();
  }

  Future<void> _loadEmployees() async {
    setState(() => _loadingEmployees = true);
    try {
      final status = _employeeStatusFilter == 'Active'
          ? 'Active'
          : _employeeStatusFilter == 'Inactive'
          ? 'Inactive'
          : 'All';
      final res = await ApiClient.instance.get<List<dynamic>>(
        '/api/employees',
        queryParameters: {'status': status, 'role': 'All'},
      );
      final data = res.data ?? [];
      _employees = data.map((e) {
        final m = e as Map<String, dynamic>;
        final empNum = m['employee_number'];
        return _EmployeeSummary(
          id: m['id'] as String,
          fullName: m['full_name'] as String? ?? 'Unknown',
          employeeNumber: empNum is int
              ? empNum
              : (empNum != null ? int.tryParse(empNum.toString()) : null),
        );
      }).toList();
    } catch (e) {
      debugPrint('Load employees failed: $e');
      _employees = [];
    }
    if (mounted) setState(() => _loadingEmployees = false);
    if (!_initialPrefillApplied && widget.initialEmployeeId != null) {
      _initialPrefillApplied = true;
      await _applyInitialEmployeePrefill();
    }
  }

  Future<void> _applyInitialEmployeePrefill() async {
    final id = widget.initialEmployeeId?.trim();
    if (id == null || id.isEmpty) {
      widget.onInitialEmployeeConsumed?.call();
      return;
    }
    if (!_employees.any((e) => e.id == id)) {
      widget.onInitialEmployeeConsumed?.call();
      return;
    }
    if (!mounted) return;
    setState(() => _selectedEmployeeId = id);
    await _loadAssignments();
    widget.onInitialEmployeeConsumed?.call();
  }

  Future<void> _loadLookups() async {
    setState(() => _loadingLookups = true);
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

      _departments = (deptRes.data ?? []).map((e) {
        final m = e as Map<String, dynamic>;
        return {'id': m['id'], 'name': m['name'] as String? ?? ''};
      }).toList();
      _positions = (posRes.data ?? []).map((e) {
        final m = e as Map<String, dynamic>;
        return {'id': m['id'], 'name': m['name'] as String? ?? ''};
      }).toList();
      _shifts = (shiftRes.data ?? []).map((e) {
        final m = e as Map<String, dynamic>;
        return {'id': m['id'], 'name': m['name'] as String? ?? ''};
      }).toList();
      _attendancePolicies = (policyRes.data ?? []).map((e) {
        final m = e as Map<String, dynamic>;
        final name =
            (m['policy_name'] as String?) ?? (m['name'] as String?) ?? '';
        return {'id': m['id'], 'name': name};
      }).toList();
    } catch (e) {
      debugPrint('Load lookups failed: $e');
      _departments = [];
      _positions = [];
      _shifts = [];
      _attendancePolicies = [];
    }
    if (mounted) setState(() => _loadingLookups = false);
  }

  Future<void> _loadAssignments() async {
    if (_selectedEmployeeId == null) {
      _assignments = [];
      setState(() {});
      return;
    }
    setState(() => _loadingAssignments = true);
    try {
      final policyRes = await ApiClient.instance.get<List<dynamic>>(
        '/api/policy-assignments',
        queryParameters: {
          'employee_id': _selectedEmployeeId!,
          'status': 'Active',
        },
      );
      final policyRows = (policyRes.data ?? [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      final res = await ApiClient.instance.get<List<dynamic>>(
        '/api/assignments',
        queryParameters: {
          'employee_id': _selectedEmployeeId!,
          'status': _assignmentStatusFilter,
        },
      );
      final data = res.data ?? [];
      _assignments = data.map((e) {
        final m = e as Map<String, dynamic>;
        final st = m['start_time'] ?? m['override_start_time'];
        final et = m['end_time'] ?? m['override_end_time'];
        final fromDate = m['effective_from'] ?? m['date_assigned'];
        final toDate = m['effective_to'];
        final resolvedPolicy = _resolvePolicyForAssignmentRange(
          policyRows,
          fromDate?.toString(),
          toDate?.toString(),
        );
        return _AssignmentRecord(
          id: m['id'] as String,
          departmentId: m['department_id'] as String?,
          positionId: m['position_id'] as String?,
          shiftId: m['shift_id'] as String?,
          departmentName: m['department_name'] as String? ?? '—',
          positionName: m['position_name'] as String? ?? '—',
          shiftName: m['shift_name'] as String? ?? '—',
          startTime: _parseTime(st) ?? const TimeOfDay(hour: 0, minute: 0),
          endTime: _parseTime(et) ?? const TimeOfDay(hour: 0, minute: 0),
          effectiveFrom: fromDate != null
              ? DateTime.parse(fromDate.toString())
              : DateTime.now(),
          effectiveTo: toDate != null && toDate.toString().isNotEmpty
              ? DateTime.tryParse(toDate.toString())
              : null,
          policyId: resolvedPolicy?['attendance_policy_id']?.toString(),
          policyName: resolvedPolicy?['policy_name']?.toString(),
          isActive: m['is_active'] as bool? ?? true,
          remarks: m['remarks'] as String?,
        );
      }).toList();
    } catch (e) {
      debugPrint('Load assignments failed: $e');
      _assignments = [];
    }
    if (mounted) {
      setState(() {
        _loadingAssignments = false;
        _selectedAssignment = null;
      });
    }
  }

  Map<String, dynamic>? _resolvePolicyForAssignmentRange(
    List<Map<String, dynamic>> policies,
    String? assignmentFromRaw,
    String? assignmentToRaw,
  ) {
    if (assignmentFromRaw == null) return null;
    final assignmentFrom = DateTime.tryParse(assignmentFromRaw.toString());
    if (assignmentFrom == null) return null;
    final assignmentTo =
        assignmentToRaw != null && assignmentToRaw.toString().trim().isNotEmpty
        ? DateTime.tryParse(assignmentToRaw.toString())
        : null;

    for (final p in policies) {
      final pFrom = DateTime.tryParse((p['effective_from'] ?? '').toString());
      if (pFrom == null) continue;
      final pToRaw = p['effective_to'];
      final pTo = pToRaw != null && pToRaw.toString().trim().isNotEmpty
          ? DateTime.tryParse(pToRaw.toString())
          : null;
      final overlap =
          !pFrom.isAfter(assignmentTo ?? DateTime(9999, 12, 31)) &&
          !(pTo ?? DateTime(9999, 12, 31)).isBefore(assignmentFrom);
      if (overlap) return p;
    }
    return null;
  }

  TimeOfDay? _parseTime(dynamic v) {
    if (v == null) return null;
    final s = v.toString();
    if (s.length >= 5) {
      final parts = s.substring(0, 5).split(':');
      if (parts.length >= 2) {
        final h = int.tryParse(parts[0]) ?? 0;
        final m = int.tryParse(parts[1]) ?? 0;
        return TimeOfDay(hour: h.clamp(0, 23), minute: m.clamp(0, 59));
      }
    }
    return null;
  }

  String _timeStr(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  String _dateStr(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _effectivePeriodStr(_AssignmentRecord assignment) {
    final from = _dateStr(assignment.effectiveFrom);
    final to = assignment.effectiveTo;
    return to == null ? from : '$from → ${_dateStr(to)}';
  }

  /// Calendar-day comparison (ignores time) so picker values stay valid across timezones.
  bool _isEffectiveRangeValid(DateTime from, DateTime? to) {
    if (to == null) return true;
    final a = DateTime(from.year, from.month, from.day);
    final b = DateTime(to.year, to.month, to.day);
    return !b.isBefore(a);
  }

  void _selectAssignment(_AssignmentRecord a) {
    setState(() {
      _selectedAssignment = a;
      _selectedDeptId = a.departmentId;
      _selectedPositionId = a.positionId;
      _selectedShiftId = a.shiftId;
      _selectedPolicyId = a.policyId;
      _effectiveFrom = a.effectiveFrom;
      _effectiveTo = a.effectiveTo;
      _remarksController.text = a.remarks ?? '';
    });
  }

  void _clearForm() {
    setState(() {
      _selectedAssignment = null;
      _selectedDeptId = null;
      _selectedPositionId = null;
      _selectedShiftId = null;
      _selectedPolicyId = null;
      _effectiveFrom = null;
      _effectiveTo = null;
      _remarksController.clear();
    });
  }

  Future<void> _addAssignment() async {
    if (_selectedEmployeeId == null) return;
    if (_selectedDeptId == null ||
        _selectedPositionId == null ||
        _selectedShiftId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select Department, Position, and Shift.'),
        ),
      );
      return;
    }
    if (_effectiveFrom == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please set Effective From date.')),
      );
      return;
    }
    if (!_isEffectiveRangeValid(_effectiveFrom!, _effectiveTo)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Effective to must be on or after effective from.'),
        ),
      );
      return;
    }
    try {
      final data = <String, dynamic>{
        'employee_id': _selectedEmployeeId,
        'department_id': _selectedDeptId,
        'position_id': _selectedPositionId,
        'shift_id': _selectedShiftId,
        'effective_from': _effectiveFrom!.toIso8601String().split('T')[0],
        if (_effectiveTo != null)
          'effective_to': _effectiveTo!.toIso8601String().split('T')[0],
        'is_active': true,
        'remarks': _remarksController.text.trim().isEmpty
            ? null
            : _remarksController.text.trim(),
      };
      await ApiClient.instance.post('/api/assignments', data: data);
      await _upsertEmployeePolicyAssignment();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Assignment added.')));
        _clearForm();
        _loadAssignments();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_userFacingApiError(e))));
      }
    }
  }

  Future<void> _updateAssignment() async {
    final a = _selectedAssignment;
    if (a == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select an assignment to update.')),
      );
      return;
    }
    if (_selectedDeptId == null ||
        _selectedPositionId == null ||
        _selectedShiftId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select Department, Position, and Shift.'),
        ),
      );
      return;
    }
    if (_effectiveFrom == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please set Effective From date.')),
      );
      return;
    }
    if (!_isEffectiveRangeValid(_effectiveFrom!, _effectiveTo)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Effective to must be on or after effective from.'),
        ),
      );
      return;
    }
    try {
      final data = <String, dynamic>{
        'department_id': _selectedDeptId,
        'position_id': _selectedPositionId,
        'shift_id': _selectedShiftId,
        'effective_from': _effectiveFrom!.toIso8601String().split('T')[0],
        'effective_to': _effectiveTo != null
            ? _effectiveTo!.toIso8601String().split('T')[0]
            : null,
        'remarks': _remarksController.text.trim().isEmpty
            ? null
            : _remarksController.text.trim(),
      };
      await ApiClient.instance.put('/api/assignments/${a.id}', data: data);
      await _upsertEmployeePolicyAssignment();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Assignment updated.')));
        _clearForm();
        _loadAssignments();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_userFacingApiError(e))));
      }
    }
  }

  Future<void> _upsertEmployeePolicyAssignment() async {
    if (_selectedEmployeeId == null || _effectiveFrom == null) return;
    await ApiClient.instance.post(
      '/api/policy-assignments/employee-upsert',
      data: {
        'employee_id': _selectedEmployeeId,
        'attendance_policy_id': _selectedPolicyId,
        'effective_from': _effectiveFrom!.toIso8601String().split('T')[0],
        'effective_to': _effectiveTo != null
            ? _effectiveTo!.toIso8601String().split('T')[0]
            : null,
        'is_active': true,
      },
    );
  }

  Future<void> _deactivateAssignment() async {
    final a = _selectedAssignment;
    if (a == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select an assignment to deactivate.')),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Deactivate assignment?'),
        content: const Text(
          'This will deactivate the selected assignment. You can reactivate it later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Deactivate'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ApiClient.instance.put(
        '/api/assignments/${a.id}',
        data: {'is_active': false},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Assignment deactivated.')),
        );
        _clearForm();
        _loadAssignments();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_userFacingApiError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final isNarrow = w < 700;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Assignment',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 24,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 20),
        isNarrow ? _buildNarrowLayout() : _buildWideLayout(),
      ],
    );
  }

  Widget _buildWideLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 1, child: _buildLeftPanel()),
        const SizedBox(width: 24),
        Expanded(flex: 2, child: _buildRightPanel()),
      ],
    );
  }

  Widget _buildNarrowLayout() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildLeftPanel(),
        const SizedBox(height: 24),
        _buildRightPanel(),
      ],
    );
  }

  Widget _buildLeftPanel() {
    final search = _searchController.text.toLowerCase();
    final filtered = search.isEmpty
        ? _employees
        : _employees
              .where((e) => e.fullName.toLowerCase().contains(search))
              .toList();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(width: 180, child: _buildSearchField()),
              _buildFilterDropdown(),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: AppTheme.lightGray.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 88,
                  child: Text(
                    'No.',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    'Name',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (_loadingEmployees)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (filtered.isEmpty)
            Container(
              constraints: const BoxConstraints(minHeight: 120),
              alignment: Alignment.center,
              child: Text(
                'No employees',
                style: TextStyle(
                  color: AppTheme.textSecondary.withValues(alpha: 0.8),
                  fontSize: 14,
                ),
              ),
            )
          else
            ...filtered.map((e) {
              final isSelected = _selectedEmployeeId == e.id;
              return Material(
                color: isSelected
                    ? AppTheme.primaryNavy.withValues(alpha: 0.08)
                    : Colors.transparent,
                child: InkWell(
                  onTap: () {
                    setState(() {
                      _selectedEmployeeId = e.id;
                      _clearForm();
                    });
                    _loadAssignments();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 88,
                          child: Text(
                            e.displayEmployeeNo,
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.textSecondary,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            e.fullName,
                            style: TextStyle(
                              fontSize: 13,
                              color: AppTheme.textPrimary,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    return TextField(
      controller: _searchController,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        hintText: 'Search',
        hintStyle: TextStyle(
          color: AppTheme.textSecondary.withValues(alpha: 0.8),
          fontSize: 14,
        ),
        prefixIcon: Icon(
          Icons.search_rounded,
          size: 20,
          color: AppTheme.textSecondary.withValues(alpha: 0.7),
        ),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        filled: true,
        fillColor: AppTheme.lightGray.withValues(alpha: 0.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _buildFilterDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.lightGray.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.transparent),
      ),
      child: DropdownButton<String>(
        value: _employeeStatusFilter,
        underline: const SizedBox.shrink(),
        isDense: true,
        items: [
          'All',
          'Active',
          'Inactive',
        ].map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
        onChanged: (v) {
          setState(() => _employeeStatusFilter = v ?? 'All');
          _loadEmployees();
        },
      ),
    );
  }

  Widget _buildRightPanel() {
    _EmployeeSummary? sel;
    if (_selectedEmployeeId != null) {
      try {
        sel = _employees.firstWhere((e) => e.id == _selectedEmployeeId);
      } catch (_) {}
    }
    final hasSelection = sel != null;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: AppTheme.lightGray,
                  child: Icon(
                    Icons.person_rounded,
                    size: 28,
                    color: AppTheme.textSecondary.withValues(alpha: 0.5),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Manage Assignments for ${hasSelection ? sel.fullName : 'Select an employee'}',
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 16,
                      fontWeight: hasSelection
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                  ),
                ),
                _buildStatusDropdown(),
              ],
            ),
            const SizedBox(height: 24),
            _buildAssignmentsTable(hasSelection),
            const SizedBox(height: 24),
            if (hasSelection) _buildAssignmentForm(),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.lightGray.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.transparent),
      ),
      child: DropdownButton<String>(
        value: _assignmentStatusFilter,
        underline: const SizedBox.shrink(),
        isDense: true,
        items: [
          'Active',
          'Inactive',
          'All',
        ].map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
        onChanged: (v) {
          setState(() => _assignmentStatusFilter = v ?? 'Active');
          _loadAssignments();
        },
      ),
    );
  }

  Widget _buildAssignmentsTable(bool hasSelection) {
    if (!hasSelection) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.lightGray.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: AppTheme.lightGray.withValues(alpha: 0.4),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(8),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Text('Department', style: _tableHeaderStyle),
                ),
                Expanded(
                  flex: 2,
                  child: Text('Position', style: _tableHeaderStyle),
                ),
                Expanded(
                  flex: 1,
                  child: Text('Shift', style: _tableHeaderStyle),
                ),
                Expanded(
                  flex: 2,
                  child: Text('Policy', style: _tableHeaderStyle),
                ),
                Expanded(
                  flex: 1,
                  child: Text('Time', style: _tableHeaderStyle),
                ),
                Expanded(
                  flex: 1,
                  child: Text('Effective period', style: _tableHeaderStyle),
                ),
              ],
            ),
          ),
          if (_loadingAssignments)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_assignments.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(child: Text('No content in table')),
            )
          else
            ..._assignments.map((a) {
              final isSelected = _selectedAssignment?.id == a.id;
              return Material(
                color: isSelected
                    ? AppTheme.primaryNavy.withValues(alpha: 0.08)
                    : Colors.transparent,
                child: InkWell(
                  onTap: () => _selectAssignment(a),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: Text(a.departmentName, style: _tableCellStyle),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(a.positionName, style: _tableCellStyle),
                        ),
                        Expanded(
                          flex: 1,
                          child: Text(a.shiftName, style: _tableCellStyle),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            (a.policyName != null &&
                                    a.policyName!.trim().isNotEmpty)
                                ? a.policyName!
                                : 'Default policy',
                            style: _tableCellStyle,
                          ),
                        ),
                        Expanded(
                          flex: 1,
                          child: Text(
                            '${_timeStr(a.startTime)} - ${_timeStr(a.endTime)}',
                            style: _tableCellStyle,
                          ),
                        ),
                        Expanded(
                          flex: 1,
                          child: Text(
                            _effectivePeriodStr(a),
                            style: _tableCellStyle,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  TextStyle get _tableHeaderStyle => TextStyle(
    fontWeight: FontWeight.w700,
    fontSize: 13,
    color: AppTheme.textPrimary,
  );

  TextStyle get _tableCellStyle =>
      TextStyle(fontSize: 13, color: AppTheme.textPrimary);

  Widget _buildAssignmentForm() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.lightGray.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final useRow = constraints.maxWidth >= 600;
              if (useRow) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 1,
                      child: _buildFormDropdown(
                        'Department',
                        _selectedDeptId,
                        _departments,
                        (v) => setState(() => _selectedDeptId = v),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 1,
                      child: _buildFormDropdown(
                        'Position',
                        _selectedPositionId,
                        _positions,
                        (v) => setState(() => _selectedPositionId = v),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 1,
                      child: _buildFormDropdown(
                        'Shift',
                        _selectedShiftId,
                        _shifts,
                        (v) => setState(() => _selectedShiftId = v),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 1,
                      child: _buildFormDropdown(
                        'Attendance Policy (opt)',
                        _selectedPolicyId,
                        _attendancePolicies,
                        (v) => setState(() => _selectedPolicyId = v),
                      ),
                    ),
                  ],
                );
              }
              return Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  _buildFormDropdown(
                    'Department',
                    _selectedDeptId,
                    _departments,
                    (v) => setState(() => _selectedDeptId = v),
                  ),
                  _buildFormDropdown(
                    'Position',
                    _selectedPositionId,
                    _positions,
                    (v) => setState(() => _selectedPositionId = v),
                  ),
                  _buildFormDropdown(
                    'Shift',
                    _selectedShiftId,
                    _shifts,
                    (v) => setState(() => _selectedShiftId = v),
                  ),
                  _buildFormDropdown(
                    'Attendance Policy (opt)',
                    _selectedPolicyId,
                    _attendancePolicies,
                    (v) => setState(() => _selectedPolicyId = v),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final useRow = constraints.maxWidth >= 520;
              if (useRow) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _buildDatePicker(
                        'Effective from',
                        _effectiveFrom,
                        (d) => setState(() => _effectiveFrom = d),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildDatePicker(
                        'Effective to (opt)',
                        _effectiveTo,
                        (d) => setState(() => _effectiveTo = d),
                      ),
                    ),
                  ],
                );
              }
              return Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  _buildDatePicker(
                    'Effective from',
                    _effectiveFrom,
                    (d) => setState(() => _effectiveFrom = d),
                  ),
                  _buildDatePicker(
                    'Effective to (opt)',
                    _effectiveTo,
                    (d) => setState(() => _effectiveTo = d),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          Text(
            'Remarks (optional)',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: _remarksController,
            decoration: InputDecoration(
              hintText: 'Notes about this assignment',
              filled: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            maxLines: 2,
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              FilledButton.icon(
                onPressed: _loadingLookups ? null : _addAssignment,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add Assignment'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF4CAF50),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: 0,
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: _selectedAssignment != null
                    ? _updateAssignment
                    : null,
                icon: const Icon(Icons.edit_rounded, size: 18),
                label: const Text('Update'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF4CAF50),
                  side: const BorderSide(color: Color(0xFF4CAF50)),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: _selectedAssignment != null
                    ? _deactivateAssignment
                    : null,
                icon: const Icon(Icons.person_off_rounded, size: 18),
                label: const Text('Deactivate'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFE53935),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: 0,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFormDropdown(
    String label,
    String? value,
    List<Map<String, dynamic>> items,
    ValueChanged<String?> onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppTheme.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          initialValue: value,
          decoration: _inputDecoration('Select'),
          hint: const Text('Select'),
          isExpanded: true,
          items: [
            const DropdownMenuItem(value: null, child: Text('Select')),
            ...items.map(
              (e) => DropdownMenuItem(
                value: e['id'] as String?,
                child: Text(
                  e['name'] as String? ?? '',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _buildDatePicker(
    String label,
    DateTime? value,
    ValueChanged<DateTime> onChanged,
  ) {
    return SizedBox(
      width: 160,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          InkWell(
            onTap: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: value ?? DateTime.now(),
                firstDate: DateTime(2020),
                lastDate: DateTime(2030),
              );
              if (d != null) onChanged(d);
            },
            borderRadius: BorderRadius.circular(8),
            child: InputDecorator(
              decoration: _inputDecoration('Select date').copyWith(
                suffixIcon: Icon(
                  Icons.calendar_today_rounded,
                  size: 20,
                  color: AppTheme.textSecondary,
                ),
              ),
              child: Text(
                value != null
                    ? '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}'
                    : '',
                style: TextStyle(
                  fontSize: 14,
                  color: value != null
                      ? AppTheme.textPrimary
                      : AppTheme.textSecondary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(
      color: AppTheme.textSecondary.withValues(alpha: 0.7),
      fontSize: 14,
    ),
    filled: true,
    fillColor: AppTheme.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: AppTheme.lightGray),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: AppTheme.lightGray),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: Color(0xFF4CAF50), width: 1.5),
    ),
  );
}
