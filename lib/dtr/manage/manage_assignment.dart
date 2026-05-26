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
  String? _employeeDepartmentFilterId;
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
  StateSetter? _drawerSetState;

  bool _initialPrefillApplied = false;

  bool _isDark(BuildContext context) => AppTheme.dashIsDark(context);

  Color _headingColor(BuildContext context) =>
      AppTheme.dashTextPrimaryOf(context);

  Color _mutedColor(BuildContext context) =>
      AppTheme.dashTextSecondaryOf(context);

  BoxDecoration _filterDecoration(BuildContext context) => BoxDecoration(
    color: _isDark(context)
        ? AppTheme.dashMutedSurfaceOf(context)
        : AppTheme.lightGray.withValues(alpha: 0.5),
    borderRadius: BorderRadius.circular(10),
    border: Border.all(
      color: _isDark(context)
          ? AppTheme.dashHairlineOf(context)
          : Colors.transparent,
    ),
  );

  void _updateAssignmentFormState(VoidCallback update) {
    if (mounted) setState(update);
    final drawerSetState = _drawerSetState;
    if (!mounted || drawerSetState == null) return;
    try {
      drawerSetState(() {});
    } catch (_) {
      _drawerSetState = null;
    }
  }

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
      final queryParameters = <String, dynamic>{
        'status': status,
        'role': 'All',
      };
      final departmentId = _employeeDepartmentFilterId?.trim();
      if (departmentId != null && departmentId.isNotEmpty) {
        queryParameters['department_id'] = departmentId;
      }
      final res = await ApiClient.instance.get<List<dynamic>>(
        '/api/employees',
        queryParameters: queryParameters,
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
      if (_selectedEmployeeId != null &&
          !_employees.any((e) => e.id == _selectedEmployeeId)) {
        _clearEmployeeSelection();
      }
    } catch (e) {
      debugPrint('Load employees failed: $e');
      _employees = [];
      _clearEmployeeSelection();
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
      if (_employeeDepartmentFilterId != null &&
          !_departments.any(
            (d) => d['id']?.toString() == _employeeDepartmentFilterId,
          )) {
        _employeeDepartmentFilterId = null;
      }
      _positions = (posRes.data ?? []).map((e) {
        final m = e as Map<String, dynamic>;
        return {
          'id': m['id'],
          'name': m['name'] as String? ?? '',
          'department_id': m['department_id'],
        };
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
      if (!_positionBelongsToDepartment(_selectedPositionId, _selectedDeptId)) {
        _selectedPositionId = null;
      }
    } catch (e) {
      debugPrint('Load lookups failed: $e');
      _departments = [];
      _positions = [];
      _shifts = [];
      _attendancePolicies = [];
    }
    _updateAssignmentFormState(() => _loadingLookups = false);
  }

  Future<void> _loadAssignments() async {
    if (_selectedEmployeeId == null) {
      _assignments = [];
      _updateAssignmentFormState(() {});
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
      _updateAssignmentFormState(() {
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

  List<Map<String, dynamic>> get _positionsForSelectedDepartment {
    final deptId = _selectedDeptId;
    if (deptId == null || deptId.isEmpty) return const [];
    return _positions
        .where((p) => p['department_id']?.toString() == deptId)
        .toList();
  }

  bool _positionBelongsToDepartment(String? positionId, String? departmentId) {
    if (positionId == null || departmentId == null) return false;
    for (final position in _positions) {
      if (position['id']?.toString() == positionId) {
        return position['department_id']?.toString() == departmentId;
      }
    }
    return false;
  }

  void _setDepartment(String? departmentId) {
    _updateAssignmentFormState(() {
      _selectedDeptId = departmentId;
      if (!_positionBelongsToDepartment(_selectedPositionId, departmentId)) {
        _selectedPositionId = null;
      }
    });
  }

  void _clearEmployeeSelection() {
    _selectedEmployeeId = null;
    _assignments = [];
    _selectedAssignment = null;
    _selectedDeptId = null;
    _selectedPositionId = null;
    _selectedShiftId = null;
    _selectedPolicyId = null;
    _effectiveFrom = null;
    _effectiveTo = null;
    _remarksController.clear();
  }

  /// Calendar-day comparison (ignores time) so picker values stay valid across timezones.
  bool _isEffectiveRangeValid(DateTime from, DateTime? to) {
    if (to == null) return true;
    final a = DateTime(from.year, from.month, from.day);
    final b = DateTime(to.year, to.month, to.day);
    return !b.isBefore(a);
  }

  void _selectAssignment(_AssignmentRecord a) {
    _updateAssignmentFormState(() {
      _selectedAssignment = a;
      _selectedDeptId = a.departmentId;
      _selectedPositionId =
          _positionBelongsToDepartment(a.positionId, a.departmentId)
          ? a.positionId
          : null;
      _selectedShiftId = a.shiftId;
      _selectedPolicyId = a.policyId;
      _effectiveFrom = a.effectiveFrom;
      _effectiveTo = a.effectiveTo;
      _remarksController.text = a.remarks ?? '';
    });
  }

  void _clearForm() {
    _updateAssignmentFormState(() {
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

  Future<bool> _addAssignment() async {
    if (_selectedEmployeeId == null) return false;
    if (_selectedDeptId == null ||
        _selectedPositionId == null ||
        _selectedShiftId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select Department, Position, and Shift.'),
        ),
      );
      return false;
    }
    if (_effectiveFrom == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please set Effective From date.')),
      );
      return false;
    }
    if (!_isEffectiveRangeValid(_effectiveFrom!, _effectiveTo)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Effective to must be on or after effective from.'),
        ),
      );
      return false;
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
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_userFacingApiError(e))));
      }
      return false;
    }
  }

  Future<bool> _updateAssignment() async {
    final a = _selectedAssignment;
    if (a == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select an assignment to update.')),
      );
      return false;
    }
    if (_selectedDeptId == null ||
        _selectedPositionId == null ||
        _selectedShiftId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select Department, Position, and Shift.'),
        ),
      );
      return false;
    }
    if (_effectiveFrom == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please set Effective From date.')),
      );
      return false;
    }
    if (!_isEffectiveRangeValid(_effectiveFrom!, _effectiveTo)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Effective to must be on or after effective from.'),
        ),
      );
      return false;
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
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_userFacingApiError(e))));
      }
      return false;
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

  Future<bool> _deactivateAssignment() async {
    final a = _selectedAssignment;
    if (a == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select an assignment to deactivate.')),
      );
      return false;
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
    if (ok != true || !mounted) return false;
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
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_userFacingApiError(e))));
      }
      return false;
    }
  }

  Future<void> _openAssignmentDrawer({_AssignmentRecord? assignment}) async {
    _drawerSetState = null;
    if (_selectedEmployeeId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select an employee first.')),
      );
      return;
    }

    if (assignment == null) {
      _clearForm();
    } else {
      _selectAssignment(assignment);
    }

    try {
      await showGeneralDialog<void>(
        context: context,
        barrierDismissible: true,
        barrierLabel: MaterialLocalizations.of(
          context,
        ).modalBarrierDismissLabel,
        barrierColor: Colors.black.withValues(alpha: 0.32),
        transitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (dialogContext, _, __) {
          final screenWidth = MediaQuery.of(dialogContext).size.width;
          final drawerWidth = screenWidth < 760 ? screenWidth : 620.0;
          return Align(
            alignment: Alignment.centerRight,
            child: SizedBox(
              width: drawerWidth,
              height: double.infinity,
              child: Material(
                color: AppTheme.dashPanelOf(dialogContext),
                elevation: 18,
                child: StatefulBuilder(
                  builder: (context, drawerSetState) {
                    _drawerSetState = drawerSetState;
                    return _buildAssignmentDrawer(dialogContext);
                  },
                ),
              ),
            ),
          );
        },
        transitionBuilder: (context, animation, _, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(1, 0),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          );
        },
      );
    } finally {
      _drawerSetState = null;
    }
  }

  Widget _buildAssignmentDrawer(BuildContext drawerContext) {
    final isEditing = _selectedAssignment != null;
    return SafeArea(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: AppTheme.dashHairlineOf(context)),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    isEditing ? 'Edit Assignment' : 'Add Assignment',
                    style: TextStyle(
                      color: _headingColor(context),
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(drawerContext).pop(),
                  icon: Icon(Icons.close_rounded, color: _mutedColor(context)),
                  tooltip: 'Close',
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              child: _buildAssignmentForm(framed: false, showActions: false),
            ),
          ),
          _buildDrawerFooter(drawerContext),
        ],
      ),
    );
  }

  Widget _buildDrawerFooter(BuildContext drawerContext) {
    final isEditing = _selectedAssignment != null;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.dashPanelOf(context),
        border: Border(
          top: BorderSide(color: AppTheme.dashHairlineOf(context)),
        ),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        alignment: WrapAlignment.end,
        children: [
          TextButton(
            onPressed: () => Navigator.of(drawerContext).pop(),
            child: const Text('Cancel'),
          ),
          if (isEditing)
            OutlinedButton.icon(
              onPressed: () async {
                final ok = await _deactivateAssignment();
                if (ok && drawerContext.mounted) {
                  Navigator.of(drawerContext).pop();
                }
              },
              icon: const Icon(Icons.person_off_rounded, size: 18),
              label: const Text('Deactivate'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: const BorderSide(color: Colors.red),
              ),
            ),
          FilledButton.icon(
            onPressed: _loadingLookups
                ? null
                : () async {
                    final ok = isEditing
                        ? await _updateAssignment()
                        : await _addAssignment();
                    if (ok && drawerContext.mounted) {
                      Navigator.of(drawerContext).pop();
                    }
                  },
            icon: Icon(
              isEditing ? Icons.edit_rounded : Icons.add_rounded,
              size: 18,
            ),
            label: Text(isEditing ? 'Update' : 'Add Assignment'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFE85D04),
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
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
            color: _headingColor(context),
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
    final dark = _isDark(context);
    final search = _searchController.text.toLowerCase();
    final filtered = search.isEmpty
        ? _employees
        : _employees
              .where((e) => e.fullName.toLowerCase().contains(search))
              .toList();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppTheme.dashSurfaceCard(context, radius: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(width: 180, child: _buildSearchField()),
              _buildDepartmentFilterDropdown(),
              _buildEmployeeStatusDropdown(),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: AppTheme.dashMutedSurfaceOf(context),
              borderRadius: BorderRadius.circular(8),
              border: Border(
                bottom: BorderSide(color: AppTheme.dashHairlineOf(context)),
              ),
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
                      color: _headingColor(context),
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    'Name',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: _headingColor(context),
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
                  color: _mutedColor(context).withValues(alpha: 0.8),
                  fontSize: 14,
                ),
              ),
            )
          else
            ...filtered.map((e) {
              final isSelected = _selectedEmployeeId == e.id;
              return Material(
                color: isSelected
                    ? (dark
                          ? AppTheme.primaryNavy.withValues(alpha: 0.35)
                          : AppTheme.primaryNavy.withValues(alpha: 0.08))
                    : Colors.transparent,
                child: InkWell(
                  onTap: () {
                    _updateAssignmentFormState(() {
                      _selectedEmployeeId = e.id;
                      _selectedAssignment = null;
                      _selectedDeptId = null;
                      _selectedPositionId = null;
                      _selectedShiftId = null;
                      _selectedPolicyId = null;
                      _effectiveFrom = null;
                      _effectiveTo = null;
                      _remarksController.clear();
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
                              color: _mutedColor(context),
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
                              color: _headingColor(context),
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
      style: AppTheme.dashFieldTextStyle(context),
      decoration: AppTheme.dashInputDecoration(
        context,
        hintText: 'Search',
        prefixIcon: Icon(
          Icons.search_rounded,
          size: 20,
          color: _mutedColor(context).withValues(alpha: 0.7),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        radius: 10,
      ),
    );
  }

  Widget _buildDepartmentFilterDropdown() {
    final safeValue =
        _employeeDepartmentFilterId != null &&
            _departments.any(
              (d) => d['id']?.toString() == _employeeDepartmentFilterId,
            )
        ? _employeeDepartmentFilterId
        : null;

    return SizedBox(
      width: 180,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: _filterDecoration(context),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String?>(
            value: safeValue,
            dropdownColor: AppTheme.dashPanelOf(context),
            style: AppTheme.dashFieldTextStyle(context),
            icon: Icon(
              Icons.arrow_drop_down_rounded,
              color: _mutedColor(context),
            ),
            hint: Text(
              'All departments',
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: AppTheme.dashFieldHintStyle(context),
            ),
            isExpanded: true,
            isDense: true,
            items: [
              DropdownMenuItem<String?>(
                value: null,
                child: Text(
                  'All departments',
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: AppTheme.dashFieldTextStyle(context),
                ),
              ),
              ..._departments.map(
                (d) => DropdownMenuItem<String?>(
                  value: d['id']?.toString(),
                  child: Text(
                    d['name']?.toString() ?? '',
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: AppTheme.dashFieldTextStyle(context),
                  ),
                ),
              ),
            ],
            onChanged: (v) {
              setState(() => _employeeDepartmentFilterId = v);
              _loadEmployees();
            },
          ),
        ),
      ),
    );
  }

  Widget _buildEmployeeStatusDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: _filterDecoration(context),
      child: DropdownButton<String>(
        value: _employeeStatusFilter,
        dropdownColor: AppTheme.dashPanelOf(context),
        style: AppTheme.dashFieldTextStyle(context),
        underline: const SizedBox.shrink(),
        isDense: true,
        items: ['All', 'Active', 'Inactive']
            .map(
              (o) => DropdownMenuItem(
                value: o,
                child: Text(o, style: AppTheme.dashFieldTextStyle(context)),
              ),
            )
            .toList(),
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
      decoration: AppTheme.dashSurfaceCard(context, radius: 12),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: AppTheme.dashMutedSurfaceOf(context),
                  child: Icon(
                    Icons.person_rounded,
                    size: 28,
                    color: _mutedColor(context).withValues(alpha: 0.5),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Manage Assignments for ${hasSelection ? sel.fullName : 'Select an employee'}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _headingColor(context),
                      fontSize: 16,
                      fontWeight: hasSelection
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                  ),
                ),
                if (hasSelection) ...[
                  FilledButton.icon(
                    onPressed: _loadingLookups
                        ? null
                        : () => _openAssignmentDrawer(),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Add Assignment'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFE85D04),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                _buildStatusDropdown(),
              ],
            ),
            const SizedBox(height: 24),
            _buildAssignmentsTable(hasSelection),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: _filterDecoration(context),
      child: DropdownButton<String>(
        value: _assignmentStatusFilter,
        dropdownColor: AppTheme.dashPanelOf(context),
        style: AppTheme.dashFieldTextStyle(context),
        underline: const SizedBox.shrink(),
        isDense: true,
        items: ['Active', 'Inactive', 'All']
            .map(
              (o) => DropdownMenuItem(
                value: o,
                child: Text(o, style: AppTheme.dashFieldTextStyle(context)),
              ),
            )
            .toList(),
        onChanged: (v) {
          setState(() => _assignmentStatusFilter = v ?? 'Active');
          _loadAssignments();
        },
      ),
    );
  }

  Widget _buildAssignmentsTable(bool hasSelection) {
    if (!hasSelection) return const SizedBox.shrink();
    final dark = _isDark(context);

    return Container(
      decoration: BoxDecoration(
        color: dark
            ? AppTheme.dashMutedSurfaceOf(context).withValues(alpha: 0.65)
            : AppTheme.lightGray.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: AppTheme.dashMutedSurfaceOf(context),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(8),
              ),
              border: Border(
                bottom: BorderSide(color: AppTheme.dashHairlineOf(context)),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Text('Department', style: _tableHeaderStyle(context)),
                ),
                Expanded(
                  flex: 2,
                  child: Text('Position', style: _tableHeaderStyle(context)),
                ),
                Expanded(
                  flex: 1,
                  child: Text('Shift', style: _tableHeaderStyle(context)),
                ),
                Expanded(
                  flex: 2,
                  child: Text('Policy', style: _tableHeaderStyle(context)),
                ),
                Expanded(
                  flex: 1,
                  child: Text('Time', style: _tableHeaderStyle(context)),
                ),
                Expanded(
                  flex: 1,
                  child: Text(
                    'Effective period',
                    style: _tableHeaderStyle(context),
                  ),
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
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Center(
                child: Text(
                  'No content in table',
                  style: TextStyle(color: _mutedColor(context)),
                ),
              ),
            )
          else
            ..._assignments.map((a) {
              final isSelected = _selectedAssignment?.id == a.id;
              return Material(
                color: isSelected
                    ? (dark
                          ? AppTheme.primaryNavy.withValues(alpha: 0.35)
                          : AppTheme.primaryNavy.withValues(alpha: 0.08))
                    : Colors.transparent,
                child: InkWell(
                  onTap: () => _openAssignmentDrawer(assignment: a),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: Text(
                            a.departmentName,
                            style: _tableCellStyle(context),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            a.positionName,
                            style: _tableCellStyle(context),
                          ),
                        ),
                        Expanded(
                          flex: 1,
                          child: Text(
                            a.shiftName,
                            style: _tableCellStyle(context),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            (a.policyName != null &&
                                    a.policyName!.trim().isNotEmpty)
                                ? a.policyName!
                                : 'Default policy',
                            style: _tableCellStyle(context),
                          ),
                        ),
                        Expanded(
                          flex: 1,
                          child: Text(
                            '${_timeStr(a.startTime)} - ${_timeStr(a.endTime)}',
                            style: _tableCellStyle(context),
                          ),
                        ),
                        Expanded(
                          flex: 1,
                          child: Text(
                            _effectivePeriodStr(a),
                            style: _tableCellStyle(context),
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

  TextStyle _tableHeaderStyle(BuildContext context) => TextStyle(
    fontWeight: FontWeight.w700,
    fontSize: 13,
    color: _headingColor(context),
  );

  TextStyle _tableCellStyle(BuildContext context) =>
      TextStyle(fontSize: 13, color: _headingColor(context));

  Widget _buildAssignmentForm({bool framed = true, bool showActions = true}) {
    String? safeValue(String? value, List<Map<String, dynamic>> items) {
      if (value == null) return null;
      return items.any((item) => item['id']?.toString() == value)
          ? value
          : null;
    }

    final selectedDeptValue = safeValue(_selectedDeptId, _departments);
    final selectedShiftValue = safeValue(_selectedShiftId, _shifts);
    final selectedPolicyValue = safeValue(
      _selectedPolicyId,
      _attendancePolicies,
    );
    final filteredPositions = _positionsForSelectedDepartment;
    final hasDepartment = selectedDeptValue != null;
    final canSelectPosition = hasDepartment && filteredPositions.isNotEmpty;
    final positionSelectLabel = !hasDepartment
        ? 'Select department first'
        : filteredPositions.isEmpty
        ? 'No positions'
        : 'Select';
    final selectedPositionValue =
        filteredPositions.any(
          (position) => position['id']?.toString() == _selectedPositionId,
        )
        ? _selectedPositionId
        : null;

    final content = Column(
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
                      selectedDeptValue,
                      _departments,
                      _setDepartment,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 1,
                    child: _buildFormDropdown(
                      'Position',
                      selectedPositionValue,
                      filteredPositions,
                      (v) => _updateAssignmentFormState(
                        () => _selectedPositionId = v,
                      ),
                      enabled: canSelectPosition,
                      selectLabel: positionSelectLabel,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 1,
                    child: _buildFormDropdown(
                      'Shift',
                      selectedShiftValue,
                      _shifts,
                      (v) => _updateAssignmentFormState(
                        () => _selectedShiftId = v,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 1,
                    child: _buildFormDropdown(
                      'Attendance Policy (opt)',
                      selectedPolicyValue,
                      _attendancePolicies,
                      (v) => _updateAssignmentFormState(
                        () => _selectedPolicyId = v,
                      ),
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
                  selectedDeptValue,
                  _departments,
                  _setDepartment,
                ),
                _buildFormDropdown(
                  'Position',
                  selectedPositionValue,
                  filteredPositions,
                  (v) =>
                      _updateAssignmentFormState(() => _selectedPositionId = v),
                  enabled: canSelectPosition,
                  selectLabel: positionSelectLabel,
                ),
                _buildFormDropdown(
                  'Shift',
                  selectedShiftValue,
                  _shifts,
                  (v) => _updateAssignmentFormState(() => _selectedShiftId = v),
                ),
                _buildFormDropdown(
                  'Attendance Policy (opt)',
                  selectedPolicyValue,
                  _attendancePolicies,
                  (v) =>
                      _updateAssignmentFormState(() => _selectedPolicyId = v),
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
                      (d) =>
                          _updateAssignmentFormState(() => _effectiveFrom = d),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildDatePicker(
                      'Effective to (opt)',
                      _effectiveTo,
                      (d) => _updateAssignmentFormState(() => _effectiveTo = d),
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
                  (d) => _updateAssignmentFormState(() => _effectiveFrom = d),
                ),
                _buildDatePicker(
                  'Effective to (opt)',
                  _effectiveTo,
                  (d) => _updateAssignmentFormState(() => _effectiveTo = d),
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
            color: _mutedColor(context),
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: _remarksController,
          style: AppTheme.dashFieldTextStyle(context),
          decoration: AppTheme.dashInputDecoration(
            context,
            hintText: 'Notes about this assignment',
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            radius: 8,
          ),
          maxLines: 2,
        ),
        if (showActions) ...[
          const SizedBox(height: 24),
          Row(
            children: [
              FilledButton.icon(
                onPressed: _loadingLookups ? null : () => _addAssignment(),
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
                    ? () => _updateAssignment()
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
                    ? () => _deactivateAssignment()
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
      ],
    );

    if (!framed) {
      return Padding(padding: const EdgeInsets.all(24), child: content);
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _isDark(context)
            ? AppTheme.dashMutedSurfaceOf(context)
            : AppTheme.lightGray.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
      ),
      child: content,
    );
  }

  Widget _buildFormDropdown(
    String label,
    String? value,
    List<Map<String, dynamic>> items,
    ValueChanged<String?> onChanged, {
    bool enabled = true,
    String selectLabel = 'Select',
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: _mutedColor(context),
          ),
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          key: ValueKey('$label-${value ?? ''}-${items.length}-$enabled'),
          initialValue: value,
          dropdownColor: AppTheme.dashPanelOf(context),
          style: AppTheme.dashFieldTextStyle(context),
          decoration: _inputDecoration(selectLabel),
          hint: Text(
            selectLabel,
            style: TextStyle(color: _mutedColor(context)),
            overflow: TextOverflow.ellipsis,
          ),
          isExpanded: true,
          items: [
            DropdownMenuItem(
              value: null,
              child: Text(
                selectLabel,
                style: AppTheme.dashFieldTextStyle(context),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            ...items.map(
              (e) => DropdownMenuItem(
                value: e['id'] as String?,
                child: Text(
                  e['name'] as String? ?? '',
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.dashFieldTextStyle(context),
                ),
              ),
            ),
          ],
          onChanged: enabled ? onChanged : null,
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
              color: _mutedColor(context),
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
                  color: _mutedColor(context),
                ),
              ),
              child: Text(
                value != null
                    ? '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}'
                    : '',
                style: TextStyle(
                  fontSize: 14,
                  color: value != null
                      ? _headingColor(context)
                      : _mutedColor(context),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) => AppTheme.dashInputDecoration(
    context,
    hintText: hint,
    radius: 8,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
  );
}
