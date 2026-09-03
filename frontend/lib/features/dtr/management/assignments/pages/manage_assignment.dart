import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/dtr/management/assignments/data/assignment_request_guard.dart';

part '../models/assignment_models.dart';
part '../widgets/assignment_drawers.dart';
part '../widgets/assignment_page_sections.dart';
part '../widgets/assignment_forms.dart';

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

DateTime? _assignmentDateFromApi(dynamic value) {
  final text = value?.toString().trim() ?? '';
  if (text.isEmpty) return null;
  return DateTime.tryParse(text);
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
  String _assignmentStatusFilter = 'Current';
  String? _selectedEmployeeId;
  String? _selectedEmployeeName;
  DateTime? _officialHrmsDate;
  DateTime? _assignmentPickerFirstDate;
  DateTime? _assignmentPickerLastDate;
  List<_EmployeeSummary> _employees = [];
  bool _loadingEmployees = false;
  int _pageIndex = 0;
  int _pageSize = 25;
  int _totalEmployeeCount = 0;
  String _searchQuery = '';
  Timer? _searchDebounceTimer;
  final _employeeListRequestGuard = AssignmentRequestGuard();
  final _lookupRequestGuard = AssignmentRequestGuard();
  final _assignmentRequestGuard = AssignmentRequestGuard();
  final _designationRequestGuard = AssignmentRequestGuard();
  final _prefillRequestGuard = AssignmentRequestGuard();

  List<_AssignmentRecord> _assignments = [];
  bool _loadingAssignments = false;
  List<_PolicyAssignmentRecord> _policyAssignments = [];
  bool _loadingPolicyAssignments = false;
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
  String? _policyPeriodPolicyId;
  DateTime? _policyPeriodEffectiveFrom;
  DateTime? _policyPeriodEffectiveTo;
  _PolicyAssignmentRecord? _selectedPolicyPeriod;
  StateSetter? _policyDrawerSetState;
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

  void _updatePolicyFormState(VoidCallback update) {
    if (mounted) setState(update);
    final drawerSetState = _policyDrawerSetState;
    if (!mounted || drawerSetState == null) return;
    try {
      drawerSetState(() {});
    } catch (_) {
      _policyDrawerSetState = null;
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
    _employeeListRequestGuard.invalidate();
    _lookupRequestGuard.invalidate();
    _assignmentRequestGuard.invalidate();
    _designationRequestGuard.invalidate();
    _prefillRequestGuard.invalidate();
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
      'sort': 'employee_number',
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

  Map<String, dynamic> _employeeListPageQuery() => <String, dynamic>{
    ..._employeeListQueryBase(),
    'limit': _pageSize,
    'offset': _pageIndex * _pageSize,
  };

  Map<String, dynamic> _assignmentQueryContext() => <String, dynamic>{
    'employee_id': _selectedEmployeeId,
    'status': _assignmentStatusFilter,
  };

  Map<String, dynamic> _designationQueryContext() => <String, dynamic>{
    'employee_id': _selectedEmployeeId,
    'status': _assignmentStatusFilter,
  };

  Future<void> _loadEmployees({bool clampPage = true}) async {
    if (!mounted) return;
    final query = Map<String, dynamic>.unmodifiable(_employeeListPageQuery());
    final request = _employeeListRequestGuard.begin(query);
    setState(() => _loadingEmployees = true);
    try {
      final res = await ApiClient.instance.get<dynamic>(
        '/api/employees',
        queryParameters: query,
      );
      if (!mounted ||
          !_employeeListRequestGuard.accepts(
            request,
            _employeeListPageQuery(),
          )) {
        return;
      }
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
        setState(() {
          _pageIndex = pageIdx;
          _loadingEmployees = false;
        });
        await _loadEmployees(clampPage: false);
        return;
      }

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
    } catch (e) {
      debugPrint('Load employees failed: $e');
      if (!mounted ||
          !_employeeListRequestGuard.accepts(
            request,
            _employeeListPageQuery(),
          )) {
        return;
      }
      setState(() {
        _employees = [];
        _totalEmployeeCount = 0;
        _loadingEmployees = false;
      });
    }
    if (mounted &&
        _employeeListRequestGuard.accepts(request, _employeeListPageQuery()) &&
        !_initialPrefillApplied &&
        widget.initialEmployeeId != null) {
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
      await _selectEmployee(employee, invalidatePrefill: false);
      widget.onInitialEmployeeConsumed?.call();
      return;
    }

    final context = <String, dynamic>{'employee_id': id};
    final request = _prefillRequestGuard.begin(context);
    try {
      final res = await ApiClient.instance.get<Map<String, dynamic>>(
        '/api/employees/$id',
      );
      final data = res.data;
      if (data != null &&
          mounted &&
          _selectedEmployeeId == null &&
          _prefillRequestGuard.accepts(request, context)) {
        final employeeNumber = data['employee_number'];
        await _selectEmployee(
          _EmployeeSummary(
            id: id,
            fullName: data['full_name'] as String? ?? 'Unknown',
            employeeNumber: employeeNumber is int
                ? employeeNumber
                : (employeeNumber != null
                      ? int.tryParse(employeeNumber.toString())
                      : null),
          ),
          invalidatePrefill: false,
        );
      }
    } catch (e) {
      debugPrint('Initial employee prefill failed: $e');
    }
    widget.onInitialEmployeeConsumed?.call();
  }

  Future<void> _loadLookups() async {
    if (!mounted) return;
    const context = <String, dynamic>{'status': 'Active'};
    final request = _lookupRequestGuard.begin(context);
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

      if (!mounted || !_lookupRequestGuard.accepts(request, context)) return;

      final departments = (deptRes.data ?? []).map((e) {
        final m = e as Map<String, dynamic>;
        return {'id': m['id'], 'name': m['name'] as String? ?? ''};
      }).toList();
      final positions = (posRes.data ?? []).map((e) {
        final m = e as Map<String, dynamic>;
        return {
          'id': m['id'],
          'name': m['name'] as String? ?? '',
          'department_id': m['department_id'],
        };
      }).toList();
      final shifts = (shiftRes.data ?? []).map((e) {
        final m = e as Map<String, dynamic>;
        return {'id': m['id'], 'name': m['name'] as String? ?? ''};
      }).toList();
      final attendancePolicies = (policyRes.data ?? []).map((e) {
        final m = e as Map<String, dynamic>;
        final name =
            (m['policy_name'] as String?) ?? (m['name'] as String?) ?? '';
        return {'id': m['id'], 'name': name};
      }).toList();
      _updateAssignmentFormState(() {
        _departments = departments;
        _positions = positions;
        _shifts = shifts;
        _attendancePolicies = attendancePolicies;
        if (_employeeDepartmentFilterId != null &&
            !_departments.any(
              (d) => d['id']?.toString() == _employeeDepartmentFilterId,
            )) {
          _employeeDepartmentFilterId = null;
        }
        if (!_positionBelongsToDepartment(
          _selectedPositionId,
          _selectedDeptId,
        )) {
          _selectedPositionId = null;
        }
        _loadingLookups = false;
      });
    } catch (e) {
      debugPrint('Load lookups failed: $e');
      if (!mounted || !_lookupRequestGuard.accepts(request, context)) return;
      _updateAssignmentFormState(() {
        _departments = [];
        _positions = [];
        _shifts = [];
        _attendancePolicies = [];
        _loadingLookups = false;
      });
    }
  }

  Future<void> _loadAssignments() async {
    final employeeId = _selectedEmployeeId;
    if (employeeId == null) {
      _assignmentRequestGuard.invalidate();
      _updateAssignmentFormState(() {
        _assignments = [];
        _policyAssignments = [];
        _loadingAssignments = false;
        _loadingPolicyAssignments = false;
      });
      return;
    }
    final context = Map<String, dynamic>.unmodifiable(
      _assignmentQueryContext(),
    );
    final request = _assignmentRequestGuard.begin(context);
    _updateAssignmentFormState(() {
      _loadingAssignments = true;
      _loadingPolicyAssignments = true;
    });
    try {
      final contextRes = await ApiClient.instance.get<Map<String, dynamic>>(
        '/api/assignments/context',
        queryParameters: {'employee_id': employeeId},
      );
      if (!mounted ||
          !_assignmentRequestGuard.accepts(
            request,
            _assignmentQueryContext(),
          )) {
        return;
      }
      final assignmentContext = contextRes.data ?? const <String, dynamic>{};
      final officialDate = _assignmentDateFromApi(
        assignmentContext['official_date'],
      );
      final pickerFirstDate = _assignmentDateFromApi(
        assignmentContext['first_date'],
      );
      final pickerLastDate = _assignmentDateFromApi(
        assignmentContext['last_date'],
      );
      if (officialDate == null ||
          pickerFirstDate == null ||
          pickerLastDate == null) {
        throw const FormatException('Invalid assignment date context');
      }

      final policyRes = await ApiClient.instance.get<List<dynamic>>(
        '/api/policy-assignments',
        queryParameters: {
          'employee_id': employeeId,
          'status': context['status'],
        },
      );
      if (!mounted ||
          !_assignmentRequestGuard.accepts(
            request,
            _assignmentQueryContext(),
          )) {
        return;
      }
      final policyRows = (policyRes.data ?? [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      final policyAssignments = policyRows.map((m) {
        final fromDate = m['effective_from'];
        final toDate = m['effective_to'];
        return _PolicyAssignmentRecord(
          id: m['id'].toString(),
          policyId: m['attendance_policy_id'].toString(),
          policyName: m['policy_name']?.toString() ?? 'Attendance policy',
          effectiveFrom: DateTime.parse(fromDate.toString()),
          effectiveTo: toDate != null && toDate.toString().isNotEmpty
              ? DateTime.tryParse(toDate.toString())
              : null,
          isActive: m['is_active'] as bool? ?? true,
          computedStatus: m['computed_status']?.toString() ?? 'Current',
        );
      }).toList();

      final res = await ApiClient.instance.get<List<dynamic>>(
        '/api/assignments',
        queryParameters: {
          'employee_id': employeeId,
          'status': context['status'],
        },
      );
      if (!mounted ||
          !_assignmentRequestGuard.accepts(
            request,
            _assignmentQueryContext(),
          )) {
        return;
      }
      final data = res.data ?? [];
      final assignments = data.map((e) {
        final m = e as Map<String, dynamic>;
        final st = m['start_time'] ?? m['override_start_time'];
        final et = m['end_time'] ?? m['override_end_time'];
        final fromDate = m['effective_from'] ?? m['date_assigned'];
        final toDate = m['effective_to'];
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
          isActive: m['is_active'] as bool? ?? true,
          computedStatus: m['computed_status']?.toString() ?? 'Current',
          canPermanentlyDelete: m['can_permanently_delete'] as bool? ?? false,
          remarks: m['remarks'] as String?,
        );
      }).toList();
      _updateAssignmentFormState(() {
        _assignments = assignments;
        _policyAssignments = policyAssignments;
        _loadingAssignments = false;
        _loadingPolicyAssignments = false;
        _selectedAssignment = null;
        _officialHrmsDate = officialDate;
        _assignmentPickerFirstDate = pickerFirstDate;
        _assignmentPickerLastDate = pickerLastDate;
      });
    } catch (e) {
      debugPrint('Load assignments failed: $e');
      if (!mounted ||
          !_assignmentRequestGuard.accepts(
            request,
            _assignmentQueryContext(),
          )) {
        return;
      }
      _updateAssignmentFormState(() {
        _assignments = [];
        _policyAssignments = [];
        _loadingAssignments = false;
        _loadingPolicyAssignments = false;
        _selectedAssignment = null;
      });
    }
  }

  Future<void> _loadDesignations() async {
    final employeeId = _selectedEmployeeId;
    if (employeeId == null) {
      _designationRequestGuard.invalidate();
      _updateDesignationFormState(() {
        _designations = [];
        _loadingDesignations = false;
      });
      return;
    }
    final context = Map<String, dynamic>.unmodifiable(
      _designationQueryContext(),
    );
    final request = _designationRequestGuard.begin(context);
    _updateDesignationFormState(() => _loadingDesignations = true);
    try {
      final res = await ApiClient.instance.get<List<dynamic>>(
        '/api/employee-other-positions',
        queryParameters: {
          'employee_id': employeeId,
          'status': context['status'],
        },
      );
      if (!mounted ||
          !_designationRequestGuard.accepts(
            request,
            _designationQueryContext(),
          )) {
        return;
      }
      final data = res.data ?? [];
      final designations = data.map((e) {
        final m = e as Map<String, dynamic>;
        final fromDate = m['effective_from'];
        final toDate = m['effective_to'];
        return _DesignationRecord(
          id: m['id'] as String,
          employeeId: m['employee_id'] as String? ?? employeeId,
          departmentId: m['department_id'] as String?,
          positionId: m['position_id'] as String?,
          effectiveFrom: fromDate != null
              ? DateTime.parse(fromDate.toString())
              : DateTime.now(),
          effectiveTo: toDate != null && toDate.toString().isNotEmpty
              ? DateTime.tryParse(toDate.toString())
              : null,
          isActive: m['is_active'] as bool? ?? true,
          computedStatus: m['computed_status']?.toString() ?? 'Current',
          canPermanentlyDelete: m['can_permanently_delete'] as bool? ?? false,
          remarks: m['remarks'] as String?,
          departmentName: m['department_name'] as String?,
          positionName: m['position_name'] as String?,
        );
      }).toList();
      _updateDesignationFormState(() {
        _designations = designations;
        _loadingDesignations = false;
        _selectedDesignation = null;
      });
    } catch (e) {
      debugPrint('Load designations failed: $e');
      if (!mounted ||
          !_designationRequestGuard.accepts(
            request,
            _designationQueryContext(),
          )) {
        return;
      }
      _updateDesignationFormState(() {
        _designations = [];
        _loadingDesignations = false;
        _selectedDesignation = null;
      });
    }
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

  String _policyEffectivePeriodStr(_PolicyAssignmentRecord policy) {
    final from = _dateStr(policy.effectiveFrom);
    final to = policy.effectiveTo;
    return to == null ? '$from onward' : '$from → ${_dateStr(to)}';
  }

  String _policyPeriodStatus(_PolicyAssignmentRecord policy) {
    return policy.computedStatus;
  }

  String _designationTitle(_DesignationRecord designation) {
    final position = designation.positionName?.trim();
    if (position != null && position.isNotEmpty) return position;
    return '—';
  }

  String _designationStatus(_DesignationRecord designation) {
    return designation.computedStatus;
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

  Future<void> _selectEmployee(
    _EmployeeSummary employee, {
    bool invalidatePrefill = true,
  }) async {
    if (!mounted) return;
    if (invalidatePrefill) _prefillRequestGuard.invalidate();
    _assignmentRequestGuard.invalidate();
    _designationRequestGuard.invalidate();
    _updateAssignmentFormState(() {
      _selectedEmployeeId = employee.id;
      _selectedEmployeeName = employee.fullName;
      _officialHrmsDate = null;
      _assignmentPickerFirstDate = null;
      _assignmentPickerLastDate = null;
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
    await Future.wait([_loadAssignments(), _loadDesignations()]);
  }

  void _clearEmployeeSelection() {
    _prefillRequestGuard.invalidate();
    _assignmentRequestGuard.invalidate();
    _designationRequestGuard.invalidate();
    _selectedEmployeeId = null;
    _selectedEmployeeName = null;
    _officialHrmsDate = null;
    _assignmentPickerFirstDate = null;
    _assignmentPickerLastDate = null;
    _assignments = [];
    _policyAssignments = [];
    _designations = [];
    _loadingAssignments = false;
    _loadingPolicyAssignments = false;
    _loadingDesignations = false;
    _selectedAssignment = null;
    _selectedDesignation = null;
    _selectedDeptId = null;
    _selectedPositionId = null;
    _selectedShiftId = null;
    _selectedPolicyId = null;
    _policyPeriodPolicyId = null;
    _policyPeriodEffectiveFrom = null;
    _policyPeriodEffectiveTo = null;
    _selectedPolicyPeriod = null;
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
      _selectedPolicyId = null;
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

  String _saveMessageWithReconciliation(
    String baseMessage,
    Map<String, dynamic>? payload,
  ) {
    final raw = payload?['reconciliation'];
    if (raw is! Map) return baseMessage;
    final reconciliation = Map<String, dynamic>.from(raw);
    final warning = reconciliation['warning']?.toString().trim();
    if (warning != null && warning.isNotEmpty) {
      return '$baseMessage $warning';
    }
    final months = reconciliation['queued_months'];
    final queuedCount = months is List ? months.length : 0;
    if (reconciliation['required'] == true && queuedCount > 0) {
      final noun = queuedCount == 1 ? 'month' : 'months';
      return '$baseMessage $queuedCount completed $noun queued for DTR reconciliation.';
    }
    return baseMessage;
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
        if (_selectedPolicyId != null)
          'attendance_policy_id': _selectedPolicyId,
        'remarks': _remarksController.text.trim().isEmpty
            ? null
            : _remarksController.text.trim(),
      };
      final response = await ApiClient.instance.post<Map<String, dynamic>>(
        '/api/assignments',
        data: data,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _saveMessageWithReconciliation(
                'Assignment added.',
                response.data,
              ),
            ),
          ),
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

  void _clearPolicyPeriodForm() {
    _updatePolicyFormState(() {
      _selectedPolicyPeriod = null;
      _policyPeriodPolicyId = null;
      _policyPeriodEffectiveFrom = null;
      _policyPeriodEffectiveTo = null;
    });
  }

  void _selectPolicyPeriod(_PolicyAssignmentRecord policy) {
    _updatePolicyFormState(() {
      _selectedPolicyPeriod = policy;
      _policyPeriodPolicyId = policy.policyId;
      _policyPeriodEffectiveFrom = policy.effectiveFrom;
      _policyPeriodEffectiveTo = policy.effectiveTo;
    });
  }

  Future<bool> _savePolicyPeriod() async {
    if (_selectedEmployeeId == null || _policyPeriodEffectiveFrom == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select an employee and effective date.')),
      );
      return false;
    }
    if (!_isEffectiveRangeValid(
      _policyPeriodEffectiveFrom!,
      _policyPeriodEffectiveTo,
    )) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Effective to must be on or after effective from.'),
        ),
      );
      return false;
    }

    try {
      final response = await ApiClient.instance.post<Map<String, dynamic>>(
        '/api/policy-assignments/employee-upsert',
        data: {
          'employee_id': _selectedEmployeeId,
          'attendance_policy_id': _policyPeriodPolicyId,
          'effective_from': _dateStr(_policyPeriodEffectiveFrom!),
          'effective_to': _policyPeriodEffectiveTo == null
              ? null
              : _dateStr(_policyPeriodEffectiveTo!),
          'is_active': true,
        },
      );
      if (mounted) {
        final message = _policyPeriodPolicyId == null
            ? 'Employee policy removed for the selected period.'
            : 'Attendance policy period saved.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _saveMessageWithReconciliation(message, response.data),
            ),
          ),
        );
        _clearPolicyPeriodForm();
        await _loadAssignments();
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
      final response = await ApiClient.instance.put<Map<String, dynamic>>(
        '/api/assignments/${a.id}',
        data: data,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _saveMessageWithReconciliation(
                'Assignment updated.',
                response.data,
              ),
            ),
          ),
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

  Future<String?> _requestDeactivationReason({
    required String title,
    required String description,
    String actionLabel = 'Deactivate',
    String hintText = 'Why is this assignment being deactivated?',
  }) async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(description),
              const SizedBox(height: 16),
              TextFormField(
                controller: controller,
                autofocus: true,
                maxLength: 1000,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: 'Reason',
                  hintText: hintText,
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Reason is required'
                    : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() != true) return;
              Navigator.of(ctx).pop(controller.text.trim());
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: Text(actionLabel),
          ),
        ],
      ),
    );
    controller.dispose();
    return reason;
  }

  Future<bool> _deactivateAssignment() async {
    final a = _selectedAssignment;
    if (a == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select an assignment to deactivate.')),
      );
      return false;
    }
    final reason = await _requestDeactivationReason(
      title: 'Deactivate assignment?',
      description:
          'This keeps the assignment history and removes it from active assignments.',
    );
    if (reason == null || !mounted) return false;
    try {
      final response = await ApiClient.instance.put<Map<String, dynamic>>(
        '/api/assignments/${a.id}',
        data: {'is_active': false, 'change_reason': reason},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _saveMessageWithReconciliation(
                'Assignment deactivated.',
                response.data,
              ),
            ),
          ),
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

  Future<bool> _deleteMistakenAssignment() async {
    final assignment = _selectedAssignment;
    if (assignment == null || !assignment.canPermanentlyDelete) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'This assignment is no longer eligible for permanent deletion.',
          ),
        ),
      );
      return false;
    }
    final reason = await _requestDeactivationReason(
      title: 'Delete mistaken assignment?',
      description:
          'This permanently removes the unused future assignment. Its deletion is still recorded in the audit log.',
      actionLabel: 'Delete permanently',
      hintText: 'Why was this assignment created by mistake?',
    );
    if (reason == null || !mounted) return false;
    try {
      await ApiClient.instance.delete(
        '/api/assignments/${assignment.id}/permanent',
        data: {'reason': reason},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Mistaken assignment deleted.')),
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
    final reason = await _requestDeactivationReason(
      title: 'Deactivate other position?',
      description:
          'This keeps the position history and removes it from active other positions.',
    );
    if (reason == null || !mounted) return false;
    try {
      await ApiClient.instance.put(
        '/api/employee-other-positions/${designation.id}',
        data: {'is_active': false, 'change_reason': reason},
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

  Future<bool> _deleteMistakenDesignation() async {
    final designation = _selectedDesignation;
    if (designation == null || !designation.canPermanentlyDelete) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'This additional position is no longer eligible for permanent deletion.',
          ),
        ),
      );
      return false;
    }
    final reason = await _requestDeactivationReason(
      title: 'Delete mistaken other position?',
      description:
          'This permanently removes the unused future position. Its deletion is still recorded in the audit log.',
      actionLabel: 'Delete permanently',
      hintText: 'Why was this position created by mistake?',
    );
    if (reason == null || !mounted) return false;
    try {
      await ApiClient.instance.delete(
        '/api/employee-other-positions/${designation.id}/permanent',
        data: {'reason': reason},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Mistaken other position deleted.')),
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

  Future<void> _openPolicyPeriodDrawer({
    _PolicyAssignmentRecord? policyPeriod,
  }) async {
    _policyDrawerSetState = null;
    if (_selectedEmployeeId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select an employee first.')),
      );
      return;
    }

    if (policyPeriod == null) {
      _clearPolicyPeriodForm();
    } else {
      _selectPolicyPeriod(policyPeriod);
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
          final drawerWidth = screenWidth < 760 ? screenWidth : 560.0;
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
                    _policyDrawerSetState = drawerSetState;
                    return _buildPolicyPeriodDrawer(dialogContext);
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
      _policyDrawerSetState = null;
    }
  }

  void _setAssignmentStatusFilter(String? value) {
    setState(() => _assignmentStatusFilter = value ?? 'Current');
    _loadAssignments();
    _loadDesignations();
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
}
