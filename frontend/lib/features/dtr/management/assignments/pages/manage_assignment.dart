import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';

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

/// Extra role/designation record that can coexist with the primary assignment.
class _DesignationRecord {
  const _DesignationRecord({
    required this.id,
    required this.employeeId,
    this.departmentId,
    this.positionId,
    required this.effectiveFrom,
    this.effectiveTo,
    required this.isActive,
    this.remarks,
    this.departmentName,
    this.positionName,
  });

  final String id;
  final String employeeId;
  final String? departmentId;
  final String? positionId;
  final DateTime effectiveFrom;
  final DateTime? effectiveTo;
  final bool isActive;
  final String? remarks;
  final String? departmentName;
  final String? positionName;
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
  static const _kPageSizes = [10, 25, 50];

  final _searchController = TextEditingController();
  String _employeeStatusFilter = 'All';
  String? _employeeDepartmentFilterId;
  String _assignmentStatusFilter = 'Active';
  String? _selectedEmployeeId;
  String? _selectedEmployeeName;
  List<_EmployeeSummary> _employees = [];
  bool _loadingEmployees = false;
  int _pageIndex = 0;
  int _pageSize = 25;
  int _totalEmployeeCount = 0;
  String _searchQuery = '';
  Timer? _searchDebounceTimer;

  List<_AssignmentRecord> _assignments = [];
  bool _loadingAssignments = false;
  List<_DesignationRecord> _designations = [];
  bool _loadingDesignations = false;

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
  String? _designationDeptId;
  String? _designationPositionId;
  DateTime? _designationEffectiveFrom;
  DateTime? _designationEffectiveTo;
  bool _designationIsActive = true;
  final _designationRemarksController = TextEditingController();
  _DesignationRecord? _selectedDesignation;
  StateSetter? _designationDrawerSetState;

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

  void _updateDesignationFormState(VoidCallback update) {
    if (mounted) setState(update);
    final drawerSetState = _designationDrawerSetState;
    if (!mounted || drawerSetState == null) return;
    try {
      drawerSetState(() {});
    } catch (_) {
      _designationDrawerSetState = null;
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
    _searchDebounceTimer?.cancel();
    _searchController.dispose();
    _remarksController.dispose();
    _designationRemarksController.dispose();
    super.dispose();
  }

  Map<String, dynamic> _employeeListQueryBase() {
    final status = _employeeStatusFilter == 'Active'
        ? 'Active'
        : _employeeStatusFilter == 'Inactive'
        ? 'Inactive'
        : 'All';
    final query = <String, dynamic>{
      'status': status,
      'role': 'All',
      'sort': 'full_name',
      'order': 'asc',
    };
    final departmentId = _employeeDepartmentFilterId?.trim();
    if (departmentId != null && departmentId.isNotEmpty) {
      query['department_id'] = departmentId;
    }
    final sq = _searchQuery.trim();
    if (sq.isNotEmpty) {
      query['q'] = sq;
    }
    return query;
  }

  Future<void> _loadEmployees({bool clampPage = true}) async {
    setState(() => _loadingEmployees = true);
    try {
      final query = <String, dynamic>{
        ..._employeeListQueryBase(),
        'limit': _pageSize,
        'offset': _pageIndex * _pageSize,
      };
      final res = await ApiClient.instance.get<dynamic>(
        '/api/employees',
        queryParameters: query,
      );
      final data = res.data;
      List<_EmployeeSummary> next;
      int total;
      if (data is Map) {
        final list = data['employees'] as List<dynamic>? ?? [];
        total = (data['total'] as num?)?.toInt() ?? 0;
        next = list.map((e) {
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
      } else if (data is List) {
        next = data.map((e) {
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
        total = next.length;
      } else {
        next = [];
        total = 0;
      }

      var pageIdx = _pageIndex;
      if (clampPage && total > 0 && _pageSize > 0) {
        final maxPage = (total - 1) ~/ _pageSize;
        if (pageIdx > maxPage) {
          pageIdx = maxPage;
        }
      }

      if (clampPage && pageIdx != _pageIndex) {
        if (mounted) {
          setState(() {
            _pageIndex = pageIdx;
            _loadingEmployees = false;
          });
          await _loadEmployees(clampPage: false);
          return;
        }
      }

      if (mounted) {
        setState(() {
          _employees = next;
          _totalEmployeeCount = total;
          _loadingEmployees = false;
          final selectedId = _selectedEmployeeId;
          if (selectedId != null) {
            final match = next.where((e) => e.id == selectedId);
            if (match.isNotEmpty) {
              _selectedEmployeeName = match.first.fullName;
            }
          }
        });
      }
    } catch (e) {
      debugPrint('Load employees failed: $e');
      if (mounted) {
        setState(() {
          _employees = [];
          _totalEmployeeCount = 0;
          _loadingEmployees = false;
        });
      }
    }
    if (!_initialPrefillApplied && widget.initialEmployeeId != null) {
      _initialPrefillApplied = true;
      await _applyInitialEmployeePrefill();
    }
  }

  void _onSearchChanged() {
    _searchDebounceTimer?.cancel();
    _searchDebounceTimer = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      final next = _searchController.text.trim();
      if (next == _searchQuery) return;
      setState(() {
        _searchQuery = next;
        _pageIndex = 0;
        _clearEmployeeSelection();
      });
      _loadEmployees();
    });
  }

  void _goToEmployeePage(int index) {
    final maxPage = _totalEmployeeCount > 0
        ? (_totalEmployeeCount - 1) ~/ _pageSize
        : 0;
    if (index < 0 || index > maxPage || index == _pageIndex) return;
    setState(() => _pageIndex = index);
    _loadEmployees();
  }

  void _setEmployeePageSize(int size) {
    if (!_kPageSizes.contains(size)) return;
    setState(() {
      _pageSize = size;
      _pageIndex = 0;
    });
    _loadEmployees();
  }

  void _resetEmployeeFiltersAndReload(VoidCallback updateFilters) {
    setState(() {
      updateFilters();
      _pageIndex = 0;
      _clearEmployeeSelection();
    });
    _loadEmployees();
  }

  Future<void> _applyInitialEmployeePrefill() async {
    final id = widget.initialEmployeeId?.trim();
    if (id == null || id.isEmpty) {
      widget.onInitialEmployeeConsumed?.call();
      return;
    }

    if (_employees.any((e) => e.id == id)) {
      if (!mounted) return;
      final employee = _employees.firstWhere((e) => e.id == id);
      setState(() {
        _selectedEmployeeId = id;
        _selectedEmployeeName = employee.fullName;
      });
      await Future.wait([_loadAssignments(), _loadDesignations()]);
      widget.onInitialEmployeeConsumed?.call();
      return;
    }

    try {
      final res = await ApiClient.instance.get<Map<String, dynamic>>(
        '/api/employees/$id',
      );
      final data = res.data;
      if (data != null && mounted) {
        setState(() {
          _selectedEmployeeId = id;
          _selectedEmployeeName = data['full_name'] as String? ?? 'Unknown';
        });
        await Future.wait([_loadAssignments(), _loadDesignations()]);
      }
    } catch (e) {
      debugPrint('Initial employee prefill failed: $e');
    }
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

  Future<void> _loadDesignations() async {
    if (_selectedEmployeeId == null) {
      _designations = [];
      _updateDesignationFormState(() {});
      return;
    }
    setState(() => _loadingDesignations = true);
    try {
      final res = await ApiClient.instance.get<List<dynamic>>(
        '/api/employee-other-positions',
        queryParameters: {'employee_id': _selectedEmployeeId!, 'status': 'All'},
      );
      final data = res.data ?? [];
      _designations = data.map((e) {
        final m = e as Map<String, dynamic>;
        final fromDate = m['effective_from'];
        final toDate = m['effective_to'];
        return _DesignationRecord(
          id: m['id'] as String,
          employeeId: m['employee_id'] as String? ?? _selectedEmployeeId!,
          departmentId: m['department_id'] as String?,
          positionId: m['position_id'] as String?,
          effectiveFrom: fromDate != null
              ? DateTime.parse(fromDate.toString())
              : DateTime.now(),
          effectiveTo: toDate != null && toDate.toString().isNotEmpty
              ? DateTime.tryParse(toDate.toString())
              : null,
          isActive: m['is_active'] as bool? ?? true,
          remarks: m['remarks'] as String?,
          departmentName: m['department_name'] as String?,
          positionName: m['position_name'] as String?,
        );
      }).toList();
    } catch (e) {
      debugPrint('Load designations failed: $e');
      _designations = [];
    }
    if (mounted) {
      _updateDesignationFormState(() {
        _loadingDesignations = false;
        _selectedDesignation = null;
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

  String _designationEffectivePeriodStr(_DesignationRecord designation) {
    final from = _dateStr(designation.effectiveFrom);
    final to = designation.effectiveTo;
    return to == null ? from : '$from → ${_dateStr(to)}';
  }

  String _designationTitle(_DesignationRecord designation) {
    final position = designation.positionName?.trim();
    if (position != null && position.isNotEmpty) return position;
    return '—';
  }

  String _designationStatus(_DesignationRecord designation) {
    if (!designation.isActive) return 'Inactive';
    final today = DateTime.now();
    final currentDay = DateTime(today.year, today.month, today.day);
    final from = DateTime(
      designation.effectiveFrom.year,
      designation.effectiveFrom.month,
      designation.effectiveFrom.day,
    );
    final to = designation.effectiveTo == null
        ? null
        : DateTime(
            designation.effectiveTo!.year,
            designation.effectiveTo!.month,
            designation.effectiveTo!.day,
          );
    if (from.isAfter(currentDay)) return 'Upcoming';
    if (to != null && to.isBefore(currentDay)) return 'Expired';
    return 'Active';
  }

  List<Map<String, dynamic>> get _positionsForSelectedDepartment {
    final deptId = _selectedDeptId;
    if (deptId == null || deptId.isEmpty) return const [];
    return _positions
        .where((p) => p['department_id']?.toString() == deptId)
        .toList();
  }

  List<Map<String, dynamic>> get _positionsForDesignationDepartment {
    final deptId = _designationDeptId;
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

  bool _designationPositionBelongsToDepartment(
    String? positionId,
    String? departmentId,
  ) {
    if (positionId == null) return false;
    if (departmentId == null || departmentId.isEmpty) return false;
    return _positionBelongsToDepartment(positionId, departmentId);
  }

  void _setDepartment(String? departmentId) {
    _updateAssignmentFormState(() {
      _selectedDeptId = departmentId;
      if (!_positionBelongsToDepartment(_selectedPositionId, departmentId)) {
        _selectedPositionId = null;
      }
    });
  }

  void _setDesignationDepartment(String? departmentId) {
    _updateDesignationFormState(() {
      _designationDeptId = departmentId;
      if (!_designationPositionBelongsToDepartment(
        _designationPositionId,
        departmentId,
      )) {
        _designationPositionId = null;
      }
    });
  }

  void _clearEmployeeSelection() {
    _selectedEmployeeId = null;
    _selectedEmployeeName = null;
    _assignments = [];
    _designations = [];
    _selectedAssignment = null;
    _selectedDesignation = null;
    _selectedDeptId = null;
    _selectedPositionId = null;
    _selectedShiftId = null;
    _selectedPolicyId = null;
    _effectiveFrom = null;
    _effectiveTo = null;
    _designationDeptId = null;
    _designationPositionId = null;
    _designationEffectiveFrom = null;
    _designationEffectiveTo = null;
    _designationIsActive = true;
    _remarksController.clear();
    _designationRemarksController.clear();
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

  void _selectDesignation(_DesignationRecord designation) {
    _updateDesignationFormState(() {
      _selectedDesignation = designation;
      _designationDeptId = designation.departmentId;
      _designationPositionId =
          _designationPositionBelongsToDepartment(
            designation.positionId,
            designation.departmentId,
          )
          ? designation.positionId
          : null;
      _designationEffectiveFrom = designation.effectiveFrom;
      _designationEffectiveTo = designation.effectiveTo;
      _designationIsActive = designation.isActive;
      _designationRemarksController.text = designation.remarks ?? '';
    });
  }

  void _clearDesignationForm() {
    _updateDesignationFormState(() {
      _selectedDesignation = null;
      _designationDeptId = null;
      _designationPositionId = null;
      _designationEffectiveFrom = null;
      _designationEffectiveTo = null;
      _designationIsActive = true;
      _designationRemarksController.clear();
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

  Map<String, dynamic>? _designationPayload() {
    if (_selectedEmployeeId == null) return null;
    if (_designationPositionId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a position.')),
      );
      return null;
    }
    if (_designationEffectiveFrom == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please set Effective From date.')),
      );
      return null;
    }
    if (!_isEffectiveRangeValid(
      _designationEffectiveFrom!,
      _designationEffectiveTo,
    )) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Effective to must be on or after effective from.'),
        ),
      );
      return null;
    }
    return {
      'employee_id': _selectedEmployeeId,
      'department_id': _designationDeptId,
      'position_id': _designationPositionId,
      'effective_from': _designationEffectiveFrom!.toIso8601String().split(
        'T',
      )[0],
      'effective_to': _designationEffectiveTo != null
          ? _designationEffectiveTo!.toIso8601String().split('T')[0]
          : null,
      'is_active': _designationIsActive,
      'remarks': _designationRemarksController.text.trim().isEmpty
          ? null
          : _designationRemarksController.text.trim(),
    };
  }

  Future<bool> _addDesignation() async {
    final data = _designationPayload();
    if (data == null) return false;
    try {
      await ApiClient.instance.post(
        '/api/employee-other-positions',
        data: data,
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Other position added.')));
        _clearDesignationForm();
        _loadDesignations();
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

  Future<bool> _updateDesignation() async {
    final designation = _selectedDesignation;
    if (designation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select another position to update.')),
      );
      return false;
    }
    final data = _designationPayload();
    if (data == null) return false;
    data.remove('employee_id');
    try {
      await ApiClient.instance.put(
        '/api/employee-other-positions/${designation.id}',
        data: data,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Other position updated.')),
        );
        _clearDesignationForm();
        _loadDesignations();
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

  Future<bool> _deactivateDesignation() async {
    final designation = _selectedDesignation;
    if (designation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select another position to deactivate.')),
      );
      return false;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Deactivate other position?'),
        content: const Text(
          'This keeps the history but removes it from active other positions.',
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
        '/api/employee-other-positions/${designation.id}',
        data: {'is_active': false},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Other position deactivated.')),
        );
        _clearDesignationForm();
        _loadDesignations();
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

  Future<void> _openDesignationDrawer({_DesignationRecord? designation}) async {
    _designationDrawerSetState = null;
    if (_selectedEmployeeId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select an employee first.')),
      );
      return;
    }

    if (designation == null) {
      _clearDesignationForm();
    } else {
      _selectDesignation(designation);
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
                    _designationDrawerSetState = drawerSetState;
                    return _buildDesignationDrawer(dialogContext);
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
      _designationDrawerSetState = null;
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
                    isEditing
                        ? 'Edit Primary Assignment'
                        : 'Add Primary Assignment',
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
            label: Text(isEditing ? 'Update' : 'Add Primary Assignment'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFE85D04),
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesignationDrawer(BuildContext drawerContext) {
    final isEditing = _selectedDesignation != null;
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
                    isEditing ? 'Edit Other Position' : 'Add Other Position',
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
              child: _buildDesignationForm(framed: false),
            ),
          ),
          _buildDesignationDrawerFooter(drawerContext),
        ],
      ),
    );
  }

  Widget _buildDesignationDrawerFooter(BuildContext drawerContext) {
    final isEditing = _selectedDesignation != null;
    final canDeactivate =
        isEditing && (_selectedDesignation?.isActive ?? false);
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
          if (canDeactivate)
            OutlinedButton.icon(
              onPressed: () async {
                final ok = await _deactivateDesignation();
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
                        ? await _updateDesignation()
                        : await _addDesignation();
                    if (ok && drawerContext.mounted) {
                      Navigator.of(drawerContext).pop();
                    }
                  },
            icon: Icon(
              isEditing ? Icons.edit_rounded : Icons.add_rounded,
              size: 18,
            ),
            label: Text(isEditing ? 'Update' : 'Add Other Position'),
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
          else if (_employees.isEmpty)
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
            ..._employees.map((e) {
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
                      _selectedEmployeeName = e.fullName;
                      _selectedAssignment = null;
                      _selectedDeptId = null;
                      _selectedPositionId = null;
                      _selectedShiftId = null;
                      _selectedPolicyId = null;
                      _effectiveFrom = null;
                      _effectiveTo = null;
                      _selectedDesignation = null;
                      _designationDeptId = null;
                      _designationPositionId = null;
                      _designationEffectiveFrom = null;
                      _designationEffectiveTo = null;
                      _designationIsActive = true;
                      _remarksController.clear();
                      _designationRemarksController.clear();
                    });
                    _loadAssignments();
                    _loadDesignations();
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
          if (!_loadingEmployees && _totalEmployeeCount > 0)
            _buildEmployeePaginationBar(),
        ],
      ),
    );
  }

  Widget _buildEmployeePaginationBar() {
    final total = _totalEmployeeCount;
    final maxPage = total <= 0 ? 0 : (total - 1) ~/ _pageSize;
    final start = total == 0 ? 0 : _pageIndex * _pageSize + 1;
    final end = total == 0
        ? 0
        : (_pageIndex * _pageSize + _employees.length).clamp(0, total);

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Wrap(
        spacing: 12,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            total == 0 ? 'No results' : 'Showing $start–$end of $total',
            style: TextStyle(
              fontSize: 12,
              color: _mutedColor(context).withValues(alpha: 0.9),
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Rows',
                style: TextStyle(
                  fontSize: 12,
                  color: _mutedColor(context).withValues(alpha: 0.85),
                ),
              ),
              const SizedBox(width: 8),
              DropdownButton<int>(
                value: _pageSize,
                dropdownColor: AppTheme.dashPanelOf(context),
                style: AppTheme.dashFieldTextStyle(context),
                underline: const SizedBox.shrink(),
                isDense: true,
                items: _kPageSizes
                    .map(
                      (s) => DropdownMenuItem(
                        value: s,
                        child: Text(
                          '$s / page',
                          style: AppTheme.dashFieldTextStyle(context),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v != null) _setEmployeePageSize(v);
                },
              ),
            ],
          ),
          IconButton(
            tooltip: 'Previous page',
            icon: const Icon(Icons.chevron_left_rounded),
            onPressed: _pageIndex > 0
                ? () => _goToEmployeePage(_pageIndex - 1)
                : null,
          ),
          Text(
            'Page ${_pageIndex + 1} / ${maxPage + 1}',
            style: TextStyle(
              fontSize: 12,
              color: _headingColor(context),
              fontWeight: FontWeight.w500,
            ),
          ),
          IconButton(
            tooltip: 'Next page',
            icon: const Icon(Icons.chevron_right_rounded),
            onPressed: _pageIndex < maxPage
                ? () => _goToEmployeePage(_pageIndex + 1)
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    return TextField(
      controller: _searchController,
      onChanged: (_) => _onSearchChanged(),
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
              _resetEmployeeFiltersAndReload(() {
                _employeeDepartmentFilterId = v;
              });
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
          _resetEmployeeFiltersAndReload(() {
            _employeeStatusFilter = v ?? 'All';
          });
        },
      ),
    );
  }

  Widget _buildRightPanel() {
    final hasSelection = _selectedEmployeeId != null;
    final employeeLabel = _selectedEmployeeName ?? 'Select an employee';

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
                    'Assignments for ${hasSelection ? employeeLabel : 'Select an employee'}',
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
                    label: const Text('Add Primary'),
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
            if (hasSelection) ...[
              const SizedBox(height: 24),
              _buildDesignationsSection(),
            ],
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
                Icon(
                  Icons.assignment_ind_rounded,
                  size: 18,
                  color: _mutedColor(context),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Primary Assignment',
                    style: _tableHeaderStyle(context),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
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
                  'No primary assignment yet',
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

  Widget _buildDesignationsSection() {
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
                Icon(
                  Icons.badge_rounded,
                  size: 18,
                  color: _mutedColor(context),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Other Positions',
                    style: _tableHeaderStyle(context),
                  ),
                ),
                TextButton.icon(
                  onPressed: _loadingLookups
                      ? null
                      : () => _openDesignationDrawer(),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Add Other'),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFE85D04),
                  ),
                ),
              ],
            ),
          ),
          if (_loadingDesignations)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_designations.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text(
                  'No other positions yet',
                  style: TextStyle(color: _mutedColor(context)),
                ),
              ),
            )
          else ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: AppTheme.dashHairlineOf(context)),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Text(
                      'Department',
                      style: _tableHeaderStyle(context),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text('Position', style: _tableHeaderStyle(context)),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      'Effective period',
                      style: _tableHeaderStyle(context),
                    ),
                  ),
                  SizedBox(
                    width: 92,
                    child: Text('Status', style: _tableHeaderStyle(context)),
                  ),
                ],
              ),
            ),
            ..._designations.map((designation) {
              final isSelected = _selectedDesignation?.id == designation.id;
              final status = _designationStatus(designation);
              return Material(
                color: isSelected
                    ? (dark
                          ? AppTheme.primaryNavy.withValues(alpha: 0.35)
                          : AppTheme.primaryNavy.withValues(alpha: 0.08))
                    : Colors.transparent,
                child: InkWell(
                  onTap: () => _openDesignationDrawer(designation: designation),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: AppTheme.dashHairlineOf(
                            context,
                          ).withValues(alpha: 0.55),
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: Text(
                            designation.departmentName ?? '—',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: _tableCellStyle(context),
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(
                            _designationTitle(designation),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: _tableCellStyle(context),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            _designationEffectivePeriodStr(designation),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: _tableCellStyle(context),
                          ),
                        ),
                        SizedBox(
                          width: 92,
                          child: _buildDesignationStatusBadge(status),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildDesignationStatusBadge(String status) {
    final Color color = switch (status) {
      'Active' => const Color(0xFF2E7D32),
      'Upcoming' => const Color(0xFF1565C0),
      'Expired' => const Color(0xFF6B7280),
      _ => const Color(0xFFC62828),
    };
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: _isDark(context) ? 0.18 : 0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.55)),
        ),
        child: Text(
          status,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: _isDark(context) ? color.withValues(alpha: 0.9) : color,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
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
                label: const Text('Add Primary Assignment'),
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

  Widget _buildDesignationForm({bool framed = true}) {
    String? safeValue(String? value, List<Map<String, dynamic>> items) {
      if (value == null) return null;
      return items.any((item) => item['id']?.toString() == value)
          ? value
          : null;
    }

    final selectedDeptValue = safeValue(_designationDeptId, _departments);
    final filteredPositions = _positionsForDesignationDepartment;
    final hasDepartment = selectedDeptValue != null;
    final canSelectPosition = hasDepartment && filteredPositions.isNotEmpty;
    final positionSelectLabel = !hasDepartment
        ? 'Select department first'
        : filteredPositions.isEmpty
        ? 'No positions'
        : 'Select';
    final selectedPositionValue =
        filteredPositions.any(
          (position) => position['id']?.toString() == _designationPositionId,
        )
        ? _designationPositionId
        : null;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final useRow = constraints.maxWidth >= 560;
            if (useRow) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _buildFormDropdown(
                      'Department',
                      selectedDeptValue,
                      _departments,
                      _setDesignationDepartment,
                      selectLabel: 'Select department',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildFormDropdown(
                      'Position',
                      selectedPositionValue,
                      filteredPositions,
                      (v) => _updateDesignationFormState(
                        () => _designationPositionId = v,
                      ),
                      enabled: canSelectPosition,
                      selectLabel: positionSelectLabel,
                    ),
                  ),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildFormDropdown(
                  'Department',
                  selectedDeptValue,
                  _departments,
                  _setDesignationDepartment,
                  selectLabel: 'Select department',
                ),
                const SizedBox(height: 16),
                _buildFormDropdown(
                  'Position',
                  selectedPositionValue,
                  filteredPositions,
                  (v) => _updateDesignationFormState(
                    () => _designationPositionId = v,
                  ),
                  enabled: canSelectPosition,
                  selectLabel: positionSelectLabel,
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
                      _designationEffectiveFrom,
                      (d) => _updateDesignationFormState(
                        () => _designationEffectiveFrom = d,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildDatePicker(
                      'Effective to (opt)',
                      _designationEffectiveTo,
                      (d) => _updateDesignationFormState(
                        () => _designationEffectiveTo = d,
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
                _buildDatePicker(
                  'Effective from',
                  _designationEffectiveFrom,
                  (d) => _updateDesignationFormState(
                    () => _designationEffectiveFrom = d,
                  ),
                ),
                _buildDatePicker(
                  'Effective to (opt)',
                  _designationEffectiveTo,
                  (d) => _updateDesignationFormState(
                    () => _designationEffectiveTo = d,
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            color: _isDark(context)
                ? AppTheme.dashMutedSurfaceOf(context)
                : AppTheme.lightGray.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.dashHairlineOf(context)),
          ),
          child: SwitchListTile(
            value: _designationIsActive,
            onChanged: (value) =>
                _updateDesignationFormState(() => _designationIsActive = value),
            title: Text(
              'Active other position',
              style: TextStyle(
                color: _headingColor(context),
                fontWeight: FontWeight.w700,
              ),
            ),
            activeThumbColor: const Color(0xFFE85D04),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          ),
        ),
        const SizedBox(height: 16),
        _buildTextField(
          label: 'Remarks (optional)',
          controller: _designationRemarksController,
          hintText: 'Notes about this other position',
          maxLines: 2,
        ),
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

  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    required String hintText,
    int maxLines = 1,
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
        TextFormField(
          controller: controller,
          style: AppTheme.dashFieldTextStyle(context),
          decoration: AppTheme.dashInputDecoration(
            context,
            hintText: hintText,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            radius: 8,
          ),
          maxLines: maxLines,
        ),
      ],
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
