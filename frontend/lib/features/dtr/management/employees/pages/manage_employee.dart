import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';

import 'package:hrms_plaridel/core/api/avatar_url.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/core/utils/responsive_right_side_panel.dart';
import 'package:hrms_plaridel/features/recruitment/models/recruitment_application.dart';
import 'package:hrms_plaridel/features/recruitment/data/recruitment_hire_prefill.dart';
import 'package:hrms_plaridel/shared/widgets/structured_address_fields.dart';
import 'package:hrms_plaridel/features/dtr/dtr_provider.dart';
import 'package:hrms_plaridel/features/dtr/attendance/data/repositories/biometric_import_repository.dart';
import 'package:hrms_plaridel/features/dtr/management/employees/data/employee_list_request_guard.dart';
import 'package:hrms_plaridel/features/dtr/management/employees/widgets/employee_setup_section.dart';
import 'package:hrms_plaridel/features/dtr/reports/data/dtr_share.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';

part '../widgets/edit_employee_dialog.dart';
part '../widgets/add_employee_form.dart';
part '../widgets/biometric_employee_dialogs.dart';

const Set<String> _separationEmploymentStatuses = {
  'resigned',
  'retired',
  'terminated',
};

bool _requiresSeparationDate(String? status) =>
    _separationEmploymentStatuses.contains(status);

String _employeeDateText(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

/// Employee profile for Manage screen (full data from profiles).
class _EmployeeProfile {
  const _EmployeeProfile({
    required this.id,
    required this.fullName,
    required this.role,
    this.employeeNumber,
    this.email,
    this.isActive = true,
    this.avatarPath,
    this.firstName,
    this.middleName,
    this.lastName,
    this.suffix,
    this.sex,
    this.dateOfBirth,
    this.contactNumber,
    this.address,
    this.employmentType,
    this.salaryGrade,
    this.dateHired,
    this.separationDate,
    this.leaveCreditEligibleUntil,
    this.employmentStatus,
    this.leaveCreditEligible = true,
    this.biometricUserId,
    this.departmentName,
    this.positionName,
  });
  final String id;
  final String fullName;
  final String role;

  /// Human-friendly number (1, 2, 3...) for display and ad-hoc queries.
  final int? employeeNumber;
  final String? email;
  final bool isActive;
  final String? avatarPath;
  final String? firstName;
  final String? middleName;
  final String? lastName;
  final String? suffix;
  final String? sex;
  final DateTime? dateOfBirth;
  final String? contactNumber;
  final String? address;
  final String? employmentType;
  final String? salaryGrade;
  final DateTime? dateHired;
  final DateTime? separationDate;
  final DateTime? leaveCreditEligibleUntil;
  final String? employmentStatus;
  final bool leaveCreditEligible;
  final String? biometricUserId;
  final String? departmentName;
  final String? positionName;

  String get roleDisplay => role == 'admin' ? 'Admin' : 'Employee';

  /// Current assignment from API (department · position), or em dash if none.
  String get assignmentDisplay {
    final d = departmentName?.trim();
    final p = positionName?.trim();
    final hasD = d != null && d.isNotEmpty;
    final hasP = p != null && p.isNotEmpty;
    if (!hasD && !hasP) return '—';
    if (d != null && d.isNotEmpty && p != null && p.isNotEmpty) {
      return '$d · $p';
    }
    if (d != null && d.isNotEmpty) return d;
    if (p != null && p.isNotEmpty) return p;
    return '—';
  }

  String get displayEmployeeNo {
    if (employeeNumber == null) return '—';
    return 'EMP-${employeeNumber!.toString().padLeft(3, '0')}';
  }

  String get compactEmployeeNo =>
      employeeNumber != null ? employeeNumber!.toString().padLeft(3, '0') : '—';
}

/// Default initial passwords for legacy import / recruitment helper dialogs.
const String kDefaultAdminPassword = kDefaultAdminAccountPassword;
const String kDefaultEmployeePassword = kDefaultEmployeeAccountPassword;

String defaultPasswordForRoleKey(String role) =>
    role == 'admin' ? kDefaultAdminPassword : kDefaultEmployeePassword;

String generateTemporaryAccountPassword({int length = 12}) {
  final random = Random.secure();
  const lower = 'abcdefghijkmnopqrstuvwxyz';
  const upper = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
  const numbers = '23456789';
  const symbols = '!@#%';
  const all = '$lower$upper$numbers$symbols';
  final chars = <String>[
    lower[random.nextInt(lower.length)],
    upper[random.nextInt(upper.length)],
    numbers[random.nextInt(numbers.length)],
    symbols[random.nextInt(symbols.length)],
  ];
  while (chars.length < length) {
    chars.add(all[random.nextInt(all.length)]);
  }
  for (var i = chars.length - 1; i > 0; i--) {
    final j = random.nextInt(i + 1);
    final tmp = chars[i];
    chars[i] = chars[j];
    chars[j] = tmp;
  }
  return chars.join();
}

/// Create Account form. Use inline in Dashboard. Single place for adding employees.
/// Prefer JSON `error` from API responses (Dio), then Dio message.
String _apiErrorMessageFromDio(Object e, {required String fallback}) {
  if (e is DioException) {
    final data = e.response?.data;
    if (data is Map && data['error'] != null) {
      return data['error'].toString();
    }
    if (e.message != null && e.message!.isNotEmpty) return e.message!;
  }
  return fallback;
}

String _messageForEmployeesLoadError(Object e) {
  if (e is DioException) {
    return _apiErrorMessageFromDio(
      e,
      fallback:
          'Could not load employees. Check your connection and try again.',
    );
  }
  return 'Could not load employees.';
}

String _titleCaseUnderscores(String raw) {
  return raw
      .split('_')
      .map(
        (w) => w.isEmpty
            ? w
            : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}',
      )
      .join(' ');
}

_EmployeeProfile _employeeProfileFromJson(Map<String, dynamic> m) {
  final dob = m['date_of_birth'];
  final empNum = m['employee_number'];
  final dateHiredRaw = m['date_hired'];
  final separationDateRaw = m['separation_date'];
  final leaveCreditEligibleUntilRaw = m['leave_credit_eligible_until'];
  return _EmployeeProfile(
    id: m['id'] as String,
    fullName: m['full_name'] as String? ?? 'Unknown',
    role: m['role'] as String? ?? 'employee',
    employeeNumber: empNum is int
        ? empNum
        : (empNum != null ? int.tryParse(empNum.toString()) : null),
    email: m['email'] as String?,
    isActive: m['is_active'] as bool? ?? true,
    avatarPath: m['avatar_path'] as String?,
    firstName: m['first_name'] as String?,
    middleName: m['middle_name'] as String?,
    lastName: m['last_name'] as String?,
    suffix: m['suffix'] as String?,
    sex: m['sex'] as String?,
    dateOfBirth: dob != null ? DateTime.tryParse(dob.toString()) : null,
    contactNumber: m['contact_number'] as String?,
    address: m['address'] as String?,
    employmentType: m['employment_type'] as String?,
    salaryGrade: m['salary_grade'] as String?,
    dateHired: dateHiredRaw != null
        ? DateTime.tryParse(dateHiredRaw.toString())
        : null,
    separationDate: separationDateRaw != null
        ? DateTime.tryParse(separationDateRaw.toString())
        : null,
    leaveCreditEligibleUntil: leaveCreditEligibleUntilRaw != null
        ? DateTime.tryParse(leaveCreditEligibleUntilRaw.toString())
        : null,
    employmentStatus: m['employment_status'] as String?,
    leaveCreditEligible: m['leave_credit_eligible'] != false,
    biometricUserId: m['biometric_user_id'] as String?,
    departmentName: m['current_department_name'] as String?,
    positionName: m['current_position_name'] as String?,
  );
}

/// Employees management screen: list with filters and detail panel.
/// Matches reference: search, Privilege/Status filters, ID/Name/Privilege columns,
/// right panel with avatar, Add/Edit/Deactivate buttons.
class ManageEmployee extends StatefulWidget {
  const ManageEmployee({super.key, this.onOpenAssignmentForEmployee});

  /// When set (e.g. from admin DTR hub), detail panel can jump to Assignment with this employee.
  final void Function(String employeeId)? onOpenAssignmentForEmployee;

  @override
  State<ManageEmployee> createState() => _ManageEmployeeState();
}

enum _EmployeeToolbarAction { importFromDevice, biometricRoster, exportAllCsv }

class _ManageEmployeeState extends State<ManageEmployee> {
  static const _kSearchDebounceMs = 350;
  static const _kPageSizes = [10, 25, 50, 100];

  final _searchController = TextEditingController();
  Timer? _searchDebounceTimer;
  final EmployeeListRequestGuard _employeeListRequestGuard =
      EmployeeListRequestGuard();

  /// Search text applied to the API (after debounce).
  String _searchQuery = '';

  String _privilegeFilter = 'All';
  String _statusFilter = 'Active';
  String? _departmentFilterId;

  /// When set, list only employees whose biometric ID exists on this ZKTeco (admin API).
  String? _biometricDeviceFilterId;
  List<dynamic> _biometricDevicesForFilter = [];
  String? _selectedEmployeeId;
  List<_EmployeeProfile> _employees = [];
  List<DepartmentOption> _departmentOptions = [];
  bool _loading = false;
  String? _loadError;

  int _pageIndex = 0;
  int _pageSize = 25;
  int _totalCount = 0;

  /// API `sort` param (whitelist on server).
  String _sortField = 'employee_number';
  bool _sortAscending = true;
  bool _exportingCsv = false;

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

  final Set<String> _selectedBulkIds = {};
  final List<FocusNode> _rowFocusNodes = [];
  bool _multiSelectMode = false;
  bool _bulkWorking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadDepartmentOptions();
      _loadBiometricDevicesForFilter();
      _loadEmployees();
    });
  }

  Future<void> _loadDepartmentOptions() async {
    try {
      final res = await ApiClient.instance.get<List<dynamic>>(
        '/api/departments',
      );
      final data = res.data ?? [];
      final list =
          data
              .map((e) {
                final m = e as Map;
                final id = m['id']?.toString();
                final name = m['name']?.toString() ?? '—';
                return id != null ? DepartmentOption(id: id, name: name) : null;
              })
              .whereType<DepartmentOption>()
              .toList()
            ..sort(
              (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
            );
      if (mounted) {
        setState(() {
          _departmentOptions = list;
          final fid = _departmentFilterId;
          if (fid != null && !list.any((d) => d.id == fid)) {
            _departmentFilterId = null;
          }
        });
      }
    } catch (_) {
      if (mounted) setState(() => _departmentOptions = []);
    }
  }

  Future<void> _loadBiometricDevicesForFilter() async {
    try {
      final res = await ApiClient.instance.get<List<dynamic>>(
        '/api/biometric-devices',
        queryParameters: const {'status': 'Active', 'probe_online': '0'},
      );
      if (!mounted) return;
      final list = res.data ?? [];
      setState(() {
        _biometricDevicesForFilter = list;
        final fid = _biometricDeviceFilterId;
        if (fid != null &&
            !list.any((d) => (d as Map)['id']?.toString() == fid)) {
          _biometricDeviceFilterId = null;
        }
      });
    } catch (_) {
      if (mounted) setState(() => _biometricDevicesForFilter = []);
    }
  }

  /// Query params shared by the paged list and CSV export (filters, search, sort).
  Map<String, dynamic> _employeeListQueryBase() {
    final q = <String, dynamic>{
      'status': _statusFilter,
      'role': _privilegeFilter,
      'sort': _sortField,
      'order': _sortAscending ? 'asc' : 'desc',
    };
    if (_departmentFilterId != null && _departmentFilterId!.isNotEmpty) {
      q['department_id'] = _departmentFilterId;
    }
    final bioDev = _biometricDeviceFilterId?.trim();
    if (bioDev != null && bioDev.isNotEmpty) {
      q['biometric_device_id'] = bioDev;
    }
    final sq = _searchQuery.trim();
    if (sq.isNotEmpty) {
      q['q'] = sq;
    }
    return q;
  }

  Map<String, dynamic> _employeeListPageQuery() => <String, dynamic>{
    ..._employeeListQueryBase(),
    'limit': _pageSize,
    'offset': _pageIndex * _pageSize,
  };

  Future<void> _loadEmployees({bool clampPage = true}) async {
    if (!mounted) return;
    final query = _employeeListPageQuery();
    final request = _employeeListRequestGuard.begin(query);
    bool acceptsCurrentRequest() =>
        mounted &&
        _employeeListRequestGuard.accepts(request, _employeeListPageQuery());
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final bioDev = _biometricDeviceFilterId?.trim();
      final res = await ApiClient.instance.get<dynamic>(
        '/api/employees',
        queryParameters: query,
        options: bioDev != null && bioDev.isNotEmpty
            ? Options(receiveTimeout: const Duration(seconds: 120))
            : null,
      );
      if (!acceptsCurrentRequest()) return;
      final data = res.data;
      List<_EmployeeProfile> next;
      int total;
      if (data is Map) {
        final list = data['employees'] as List<dynamic>? ?? [];
        total = (data['total'] as num?)?.toInt() ?? 0;
        next = list
            .map(
              (e) =>
                  _employeeProfileFromJson(Map<String, dynamic>.from(e as Map)),
            )
            .toList();
      } else if (data is List) {
        next = data
            .map(
              (e) =>
                  _employeeProfileFromJson(Map<String, dynamic>.from(e as Map)),
            )
            .toList();
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
        });
        await _loadEmployees(clampPage: false);
        return;
      }

      _syncRowFocusNodes(next.length);
      setState(() {
        _employees = next;
        _totalCount = total;
        _loading = false;
        _loadError = null;
        final id = _selectedEmployeeId;
        if (id != null && !_employees.any((e) => e.id == id)) {
          _selectedEmployeeId = null;
        }
        _selectedBulkIds.removeWhere(
          (id) => !_employees.any((e) => e.id == id),
        );
      });
    } catch (e) {
      debugPrint('Load employees failed: $e');
      if (!acceptsCurrentRequest()) return;
      _syncRowFocusNodes(0);
      setState(() {
        _employees = [];
        _totalCount = 0;
        _loadError = _messageForEmployeesLoadError(e);
        _loading = false;
        _selectedEmployeeId = null;
      });
    }
  }

  void _onSearchChanged(String _) {
    _searchDebounceTimer?.cancel();
    _searchDebounceTimer = Timer(
      const Duration(milliseconds: _kSearchDebounceMs),
      () {
        if (!mounted) return;
        final next = _searchController.text.trim();
        if (next == _searchQuery) return;
        setState(() {
          _searchQuery = next;
          _pageIndex = 0;
        });
        _loadEmployees();
      },
    );
  }

  void _goToPage(int index) {
    if (index < 0) return;
    final maxPage = _totalCount > 0 ? (_totalCount - 1) ~/ _pageSize : 0;
    if (index > maxPage) return;
    setState(() => _pageIndex = index);
    _loadEmployees();
  }

  void _setPageSize(int size) {
    if (!_kPageSizes.contains(size)) return;
    setState(() {
      _pageSize = size;
      _pageIndex = 0;
    });
    _loadEmployees();
  }

  void _setSort(String sortKey) {
    setState(() {
      if (_sortField == sortKey) {
        _sortAscending = !_sortAscending;
      } else {
        _sortField = sortKey;
        _sortAscending = true;
      }
      _pageIndex = 0;
    });
    _loadEmployees();
  }

  Future<void> _exportCsv() async {
    if (!mounted || _exportingCsv) return;
    setState(() => _exportingCsv = true);
    try {
      final bioDev = _biometricDeviceFilterId?.trim();
      final res = await ApiClient.instance.dio.get<List<int>>(
        '/api/employees/export/csv',
        queryParameters: _employeeListQueryBase(),
        options: Options(
          responseType: ResponseType.bytes,
          receiveTimeout: Duration(
            seconds: bioDev != null && bioDev.isNotEmpty ? 120 : 90,
          ),
          headers: const {'Accept': 'text/csv'},
        ),
      );
      final raw = res.data;
      if (raw == null || raw.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Export returned no data.')),
          );
        }
        return;
      }
      final bytes = Uint8List.fromList(raw);
      final day = DateTime.now().toIso8601String().split('T').first;
      await shareOrDownloadFile(bytes, 'employees_export_$day.csv', 'text/csv');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Employee export downloaded.')),
        );
      }
    } on DioException catch (e) {
      if (!mounted) return;
      if (e.response?.statusCode == 413) {
        final body = e.response?.data;
        var msg =
            'Too many rows for one export. Narrow filters or search and try again.';
        if (body is Map && body['error'] != null) {
          msg = body['error'].toString();
        }
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_messageForEmployeesLoadError(e))),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _exportingCsv = false);
    }
  }

  void _syncRowFocusNodes(int count) {
    while (_rowFocusNodes.length < count) {
      _rowFocusNodes.add(
        FocusNode(debugLabel: 'employee_row_${_rowFocusNodes.length}'),
      );
    }
    while (_rowFocusNodes.length > count) {
      _rowFocusNodes.removeLast().dispose();
    }
  }

  bool? _headerSelectAllValue() {
    if (_employees.isEmpty) return false;
    final onPage = _employees.map((e) => e.id).toSet();
    var n = 0;
    for (final id in onPage) {
      if (_selectedBulkIds.contains(id)) n++;
    }
    if (n == 0) return false;
    if (n == onPage.length) return true;
    return null;
  }

  void _onHeaderSelectAllChanged(bool? v) {
    setState(() {
      _multiSelectMode = true;
      if (v == true) {
        for (final e in _employees) {
          _selectedBulkIds.add(e.id);
        }
      } else {
        for (final e in _employees) {
          _selectedBulkIds.remove(e.id);
        }
      }
    });
  }

  void _toggleMultiSelectMode() {
    setState(() {
      _multiSelectMode = !_multiSelectMode;
      if (!_multiSelectMode) _selectedBulkIds.clear();
    });
  }

  void _exitMultiSelectMode() {
    if (!_multiSelectMode && _selectedBulkIds.isEmpty) return;
    setState(() {
      _multiSelectMode = false;
      _selectedBulkIds.clear();
    });
  }

  KeyEventResult _handleEmployeeRowKey(KeyEvent event, int index) {
    if (_multiSelectMode &&
        event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.space) {
      final id = _employees[index].id;
      setState(() {
        if (_selectedBulkIds.contains(id)) {
          _selectedBulkIds.remove(id);
        } else {
          _selectedBulkIds.add(id);
        }
      });
      return KeyEventResult.handled;
    }
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (index < _employees.length - 1) {
        _rowFocusNodes[index + 1].requestFocus();
        setState(() => _selectedEmployeeId = _employees[index + 1].id);
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (index > 0) {
        _rowFocusNodes[index - 1].requestFocus();
        setState(() => _selectedEmployeeId = _employees[index - 1].id);
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _confirmBulkDeactivate() async {
    final targets = _employees
        .where((e) => _selectedBulkIds.contains(e.id) && e.isActive)
        .toList();
    if (targets.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Deactivate ${targets.length} employees?'),
        content: Text(
          targets.length <= 3
              ? targets.map((e) => e.fullName).join(', ')
              : 'This will deactivate ${targets.length} selected accounts. They will no longer be able to sign in.',
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
    final messenger = ScaffoldMessenger.of(context);
    final dtr = context.read<DtrProvider>();
    setState(() => _bulkWorking = true);
    try {
      await ApiClient.instance.post(
        '/api/employees/bulk-status',
        data: {
          'employee_ids': targets.map((e) => e.id).toList(),
          'is_active': false,
        },
      );
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('${targets.length} employees deactivated.')),
      );
      setState(() {
        _bulkWorking = false;
        _selectedBulkIds.clear();
      });
      await _loadEmployees();
      if (mounted) {
        dtr.invalidateCachedDtrData(includeReferenceData: true);
        dtr.loadEmployees(forceRefresh: true);
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Bulk deactivate failed: $e')),
        );
        setState(() => _bulkWorking = false);
      }
    }
  }

  Future<void> _confirmBulkActivate() async {
    final targets = _employees
        .where((e) => _selectedBulkIds.contains(e.id) && !e.isActive)
        .toList();
    if (targets.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Activate ${targets.length} employees?'),
        content: Text(
          targets.length <= 3
              ? targets.map((e) => e.fullName).join(', ')
              : 'This will reactivate ${targets.length} selected accounts. They will be able to sign in again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF4CAF50),
            ),
            child: const Text('Activate'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final dtr = context.read<DtrProvider>();
    setState(() => _bulkWorking = true);
    try {
      await ApiClient.instance.post(
        '/api/employees/bulk-status',
        data: {
          'employee_ids': targets.map((e) => e.id).toList(),
          'is_active': true,
        },
      );
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('${targets.length} employees activated.')),
      );
      setState(() {
        _bulkWorking = false;
        _selectedBulkIds.clear();
      });
      await _loadEmployees();
      if (mounted) {
        dtr.invalidateCachedDtrData(includeReferenceData: true);
        dtr.loadEmployees(forceRefresh: true);
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Bulk activate failed: $e')),
        );
        setState(() => _bulkWorking = false);
      }
    }
  }

  Widget _buildBulkSelectionBar() {
    final n = _selectedBulkIds.length;
    final canDeactivate = _employees.any(
      (e) => _selectedBulkIds.contains(e.id) && e.isActive,
    );
    final canActivate = _employees.any(
      (e) => _selectedBulkIds.contains(e.id) && !e.isActive,
    );
    final dark = _isDark(context);
    return Material(
      color: dark
          ? AppTheme.primaryNavy.withValues(alpha: 0.22)
          : AppTheme.primaryNavy.withValues(alpha: 0.07),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Wrap(
          spacing: 10,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              '$n selected',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _headingColor(context),
              ),
            ),
            TextButton(
              onPressed: _bulkWorking
                  ? null
                  : () => setState(() => _selectedBulkIds.clear()),
              child: const Text('Clear'),
            ),
            FilledButton.icon(
              onPressed: _bulkWorking || !canDeactivate
                  ? null
                  : _confirmBulkDeactivate,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFE53935),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
              icon: const Icon(Icons.person_off_rounded, size: 18),
              label: const Text('Deactivate'),
            ),
            FilledButton.icon(
              onPressed: _bulkWorking || !canActivate
                  ? null
                  : _confirmBulkActivate,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF4CAF50),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
              icon: const Icon(Icons.person_add_rounded, size: 18),
              label: const Text('Activate'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openAddEmployeePanel() async {
    final messenger = ScaffoldMessenger.of(context);

    await openResponsiveRightSidePanel<void>(
      context: context,
      barrierLabel: 'Close add employee',
      breakpoint: 900,
      minWidth: 760,
      initialWidthFraction: 0.66,
      builder: (panelContext) {
        return Material(
          color: AppTheme.dashPanelOf(panelContext),
          child: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 18, 12, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Add employee',
                              style: TextStyle(
                                color: AppTheme.dashTextPrimaryOf(panelContext),
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Create the account, profile, and optional initial assignment in one place.',
                              style: TextStyle(
                                color: AppTheme.dashTextSecondaryOf(
                                  panelContext,
                                ),
                                fontSize: 13,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      IconButton(
                        icon: Icon(
                          Icons.close_rounded,
                          color: AppTheme.dashTextSecondaryOf(panelContext),
                        ),
                        tooltip: 'Close',
                        onPressed: () => Navigator.of(panelContext).pop(),
                      ),
                    ],
                  ),
                ),
                Divider(
                  height: 1,
                  color: AppTheme.dashHairlineOf(panelContext),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AddEmployeeForm(
                      onAccountCreated: () {
                        Navigator.of(panelContext).pop();
                        if (!mounted) return;
                        setState(() => _pageIndex = 0);
                        _loadEmployees();
                        messenger.showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Account created. The list has been refreshed.',
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _searchDebounceTimer?.cancel();
    _employeeListRequestGuard.invalidate();
    for (final n in _rowFocusNodes) {
      n.dispose();
    }
    _rowFocusNodes.clear();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final isNarrow = w < 700;

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(
          LogicalKeyboardKey.keyM,
          control: true,
          shift: true,
        ): _toggleMultiSelectMode,
        const SingleActivator(LogicalKeyboardKey.escape): _exitMultiSelectMode,
      },
      child: Focus(
        autofocus: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildEmployeesHeader(isNarrow: isNarrow),
            const SizedBox(height: 20),
            isNarrow ? _buildNarrowLayout() : _buildWideLayout(),
          ],
        ),
      ),
    );
  }

  Widget _buildEmployeesHeader({required bool isNarrow}) {
    final title = Text(
      'Employees',
      style: TextStyle(
        color: _headingColor(context),
        fontSize: 24,
        fontWeight: FontWeight.w800,
      ),
    );
    final actions = _buildEmployeeHeaderActions();

    if (isNarrow) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          title,
          const SizedBox(height: 12),
          Align(alignment: Alignment.centerRight, child: actions),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: title),
        const SizedBox(width: 16),
        actions,
      ],
    );
  }

  Widget _buildWideLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 2, child: _buildLeftPanel()),
        const SizedBox(width: 24),
        SizedBox(width: 280, child: _buildRightPanel()),
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

  Widget _buildEmployeesToolbar() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 720.0;
        const gap = 10.0;
        const roleWidth = 128.0;
        const statusWidth = 128.0;
        final searchWidth = (maxWidth * 0.22).clamp(165.0, 230.0).toDouble();
        final departmentWidth = (maxWidth * 0.22)
            .clamp(165.0, 220.0)
            .toDouble();
        final usedWidth =
            searchWidth + roleWidth + statusWidth + departmentWidth + gap * 4;
        final deviceWidth = (maxWidth - usedWidth)
            .clamp(150.0, 220.0)
            .toDouble();

        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(width: searchWidth, child: _buildSearchField()),
            const SizedBox(width: gap),
            SizedBox(
              width: roleWidth,
              child: _buildDropdown(
                _privilegeFilter,
                ['All', 'Admin', 'Employee'],
                (v) {
                  setState(() {
                    _privilegeFilter = v ?? 'All';
                    _pageIndex = 0;
                  });
                  _loadEmployees();
                },
              ),
            ),
            const SizedBox(width: gap),
            SizedBox(
              width: statusWidth,
              child: _buildDropdown(
                _statusFilter,
                ['Active', 'Inactive', 'All'],
                (v) {
                  setState(() {
                    _statusFilter = v ?? 'Active';
                    _pageIndex = 0;
                  });
                  _loadEmployees();
                },
              ),
            ),
            const SizedBox(width: gap),
            _buildDepartmentFilterDropdown(width: departmentWidth),
            const SizedBox(width: gap),
            _buildBiometricDeviceFilterDropdown(width: deviceWidth),
          ],
        );
      },
    );
  }

  Widget _buildEmployeeHeaderActions() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        PopupMenuButton<_EmployeeToolbarAction>(
          tooltip: 'More actions',
          offset: const Offset(0, 8),
          onSelected: (action) {
            switch (action) {
              case _EmployeeToolbarAction.importFromDevice:
                _showImportDialog(context);
              case _EmployeeToolbarAction.biometricRoster:
                _showBiometricRosterDialog(context);
              case _EmployeeToolbarAction.exportAllCsv:
                _exportCsv();
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              value: _EmployeeToolbarAction.importFromDevice,
              child: _toolbarMenuItem(
                icon: Icons.download_rounded,
                label: 'Import from Device',
              ),
            ),
            PopupMenuItem(
              value: _EmployeeToolbarAction.biometricRoster,
              child: _toolbarMenuItem(
                icon: Icons.badge_outlined,
                label: 'Biometric roster',
              ),
            ),
            const PopupMenuDivider(),
            PopupMenuItem(
              value: _EmployeeToolbarAction.exportAllCsv,
              enabled: !_exportingCsv,
              child: _toolbarMenuItem(
                icon: Icons.file_download_outlined,
                label: _exportingCsv ? 'Exporting CSV...' : 'Export CSV',
              ),
            ),
          ],
          child: Container(
            width: 46,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppTheme.dashPanelOf(context),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: AppTheme.primaryNavy.withValues(alpha: 0.45),
              ),
            ),
            child: Icon(
              Icons.more_vert_rounded,
              color: _isDark(context)
                  ? AppTheme.primaryNavyLight
                  : AppTheme.primaryNavy,
            ),
          ),
        ),
        FilledButton.icon(
          onPressed: _openAddEmployeePanel,
          icon: const Icon(Icons.person_add_rounded, size: 18),
          label: const Text('Add employee'),
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.primaryNavy,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
      ],
    );
  }

  Widget _toolbarMenuItem({required IconData icon, required String label}) {
    return Row(
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 10),
        Expanded(child: Text(label)),
      ],
    );
  }

  Widget _buildDepartmentFilterDropdown({required double width}) {
    return SizedBox(
      width: width,
      height: 44,
      child: Container(
        padding: const EdgeInsets.only(left: 12, right: 8),
        decoration: _filterDecoration(context),
        alignment: Alignment.center,
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String?>(
            value: _departmentFilterId,
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
              ..._departmentOptions.map(
                (d) => DropdownMenuItem<String?>(
                  value: d.id,
                  child: Text(
                    d.name,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: AppTheme.dashFieldTextStyle(context),
                  ),
                ),
              ),
            ],
            onChanged: (v) {
              setState(() {
                _departmentFilterId = v;
                _pageIndex = 0;
              });
              _loadEmployees();
            },
          ),
        ),
      ),
    );
  }

  Widget _buildBiometricDeviceFilterDropdown({required double width}) {
    return SizedBox(
      width: width,
      height: 44,
      child: Container(
        padding: const EdgeInsets.only(left: 12, right: 8),
        decoration: _filterDecoration(context),
        alignment: Alignment.center,
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String?>(
            value: _biometricDeviceFilterId,
            dropdownColor: AppTheme.dashPanelOf(context),
            style: AppTheme.dashFieldTextStyle(context),
            icon: Icon(
              Icons.arrow_drop_down_rounded,
              color: _mutedColor(context),
            ),
            hint: Text(
              'All devices',
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: AppTheme.dashFieldHintStyle(context),
            ),
            isExpanded: true,
            items: [
              DropdownMenuItem<String?>(
                value: null,
                child: Text(
                  'All devices',
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: AppTheme.dashFieldTextStyle(context),
                ),
              ),
              ..._biometricDevicesForFilter.map((d) {
                final m = Map<String, dynamic>.from(d as Map);
                final id = m['id']?.toString() ?? '';
                final name = m['name']?.toString() ?? id;
                final loc = m['location']?.toString();
                final line = (loc != null && loc.isNotEmpty)
                    ? '$name · $loc'
                    : name;
                return DropdownMenuItem<String?>(
                  value: id,
                  child: Text(
                    line,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: AppTheme.dashFieldTextStyle(context),
                  ),
                );
              }),
            ],
            onChanged: (v) {
              setState(() {
                _biometricDeviceFilterId = v;
                _pageIndex = 0;
              });
              _loadEmployees();
            },
          ),
        ),
      ),
    );
  }

  Widget _buildLoadErrorBanner() {
    final err = _loadError;
    if (err == null) return const SizedBox.shrink();
    final dark = _isDark(context);
    return Material(
      color: dark
          ? Colors.red.shade900.withValues(alpha: 0.35)
          : const Color(0xFFFFEBEE),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.error_outline_rounded,
              color: dark ? Colors.red.shade300 : Colors.red.shade700,
              size: 22,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                err,
                style: TextStyle(
                  color: dark ? Colors.red.shade100 : _headingColor(context),
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
            ),
            TextButton(onPressed: _loadEmployees, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCellContent(_EmployeeProfile e) {
    final hrRaw = e.employmentStatus?.trim();
    final showHr =
        hrRaw != null && hrRaw.isNotEmpty && hrRaw.toLowerCase() != 'active';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          e.isActive ? 'Active' : 'Inactive',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: e.isActive
                ? const Color(0xFF2E7D32)
                : const Color(0xFFC62828),
          ),
        ),
        if (showHr)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              _titleCaseUnderscores(hrRaw),
              style: TextStyle(
                fontSize: 10,
                color: _mutedColor(context).withValues(alpha: 0.9),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    );
  }

  Widget _buildLeftPanel() {
    final dark = _isDark(context);
    String emptyMessage() {
      if (_totalCount == 0) {
        return _searchQuery.trim().isNotEmpty
            ? 'No results for your search.'
            : 'No employees match these filters yet.';
      }
      if (_employees.isEmpty) {
        return 'No rows on this page.';
      }
      return '';
    }

    const kTableMinWidth = 768.0;
    final columnWidths = <int, TableColumnWidth>{
      0: FixedColumnWidth(_multiSelectMode ? 44 : 0),
      1: FixedColumnWidth(88),
      2: FlexColumnWidth(1.35),
      3: FlexColumnWidth(1.15),
      4: FixedColumnWidth(104),
      5: FixedColumnWidth(92),
    };

    Widget tableCore() {
      final headerRow = TableRow(
        decoration: BoxDecoration(
          color: AppTheme.dashMutedSurfaceOf(context),
          borderRadius: BorderRadius.circular(8),
        ),
        children: [
          TableCell(
            verticalAlignment: TableCellVerticalAlignment.middle,
            child: _multiSelectMode
                ? Semantics(
                    label: 'Select all employees on this page',
                    child: Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Checkbox(
                        tristate: true,
                        value: _headerSelectAllValue(),
                        onChanged: (_employees.isEmpty || _loading)
                            ? null
                            : _onHeaderSelectAllChanged,
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          _sortableHeaderCell('EMP ID', 'employee_number'),
          _sortableHeaderCell('Name', 'full_name'),
          _sortableHeaderCell('Assignment', 'department'),
          _sortableHeaderCell('Status', 'is_active'),
          _sortableHeaderCell('Privilege', 'role'),
        ],
      );

      if (_loading) {
        return Table(
          columnWidths: columnWidths,
          children: [headerRow, ..._employeeTableSkeletonRows()],
        );
      }

      if (_employees.isEmpty) {
        final msg = emptyMessage();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Table(columnWidths: columnWidths, children: [headerRow]),
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 120),
              alignment: Alignment.center,
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: AppTheme.dashHairlineOf(
                      context,
                    ).withValues(alpha: 0.6),
                  ),
                ),
              ),
              child: Semantics(
                label: msg,
                child: Text(
                  msg,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _mutedColor(context).withValues(alpha: 0.88),
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
              ),
            ),
          ],
        );
      }

      return Table(
        columnWidths: columnWidths,
        children: [
          headerRow,
          ..._employees.asMap().entries.map((entry) {
            final i = entry.key;
            final e = entry.value;
            final isSelected = _selectedEmployeeId == e.id;
            return TableRow(
              decoration: BoxDecoration(
                color: isSelected
                    ? (dark
                          ? AppTheme.primaryNavy.withValues(alpha: 0.35)
                          : AppTheme.primaryNavy.withValues(alpha: 0.08))
                    : null,
              ),
              children: [
                TableCell(
                  verticalAlignment: TableCellVerticalAlignment.middle,
                  child: _multiSelectMode
                      ? Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: Checkbox(
                            value: _selectedBulkIds.contains(e.id),
                            onChanged: (v) {
                              setState(() {
                                if (v == true) {
                                  _selectedBulkIds.add(e.id);
                                } else {
                                  _selectedBulkIds.remove(e.id);
                                }
                                _selectedEmployeeId = e.id;
                              });
                              if (i >= 0 && i < _rowFocusNodes.length) {
                                _rowFocusNodes[i].requestFocus();
                              }
                            },
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
                TableCell(
                  verticalAlignment: TableCellVerticalAlignment.middle,
                  child: _employeeRowInkWell(
                    e: e,
                    isSelected: isSelected,
                    primarySemanticForRow: false,
                    rowIndex: i,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: Tooltip(
                        message: e.displayEmployeeNo,
                        child: Text(
                          e.compactEmployeeNo,
                          style: TextStyle(
                            fontSize: 12,
                            color: _mutedColor(context),
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                    ),
                  ),
                ),
                TableCell(
                  verticalAlignment: TableCellVerticalAlignment.middle,
                  child: Focus(
                    focusNode: _rowFocusNodes[i],
                    onKeyEvent: (node, event) =>
                        _handleEmployeeRowKey(event, i),
                    child: _employeeRowInkWell(
                      e: e,
                      isSelected: isSelected,
                      primarySemanticForRow: true,
                      rowIndex: i,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        child: Row(
                          children: [
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
                            if (!e.isActive)
                              Container(
                                margin: const EdgeInsets.only(left: 6),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.red.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  e.biometricUserId != null
                                      ? 'Imported (Inactive)'
                                      : 'Inactive',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: Colors.red,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                TableCell(
                  verticalAlignment: TableCellVerticalAlignment.middle,
                  child: _employeeRowInkWell(
                    e: e,
                    isSelected: isSelected,
                    primarySemanticForRow: false,
                    rowIndex: i,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: Text(
                        e.assignmentDisplay,
                        style: TextStyle(
                          fontSize: 12,
                          color: _mutedColor(context),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
                TableCell(
                  verticalAlignment: TableCellVerticalAlignment.middle,
                  child: _employeeRowInkWell(
                    e: e,
                    isSelected: isSelected,
                    primarySemanticForRow: false,
                    rowIndex: i,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: _buildStatusCellContent(e),
                    ),
                  ),
                ),
                TableCell(
                  verticalAlignment: TableCellVerticalAlignment.middle,
                  child: _employeeRowInkWell(
                    e: e,
                    isSelected: isSelected,
                    primarySemanticForRow: false,
                    rowIndex: i,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: Text(
                        e.roleDisplay,
                        style: TextStyle(
                          fontSize: 12,
                          color: _mutedColor(context),
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  ),
                ),
              ],
            );
          }),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppTheme.dashSurfaceCard(context, radius: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildEmployeesToolbar(),
          const SizedBox(height: 16),
          if (_multiSelectMode && _selectedBulkIds.isNotEmpty) ...[
            _buildBulkSelectionBar(),
            const SizedBox(height: 12),
          ],
          if (_loadError != null) ...[
            _buildLoadErrorBanner(),
            const SizedBox(height: 16),
          ],
          if (_loadError == null) ...[
            LayoutBuilder(
              builder: (context, constraints) {
                final useHScroll = constraints.maxWidth < kTableMinWidth;
                if (!useHScroll) return tableCore();
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(width: kTableMinWidth, child: tableCore()),
                );
              },
            ),
            _buildPaginationBar(),
          ],
        ],
      ),
    );
  }

  Widget _buildPaginationBar() {
    if (_loading && _employees.isEmpty) return const SizedBox.shrink();
    final total = _totalCount;
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
              fontSize: 13,
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
                  if (v != null) _setPageSize(v);
                },
              ),
            ],
          ),
          if (maxPage > 0)
            IconButton(
              tooltip: 'Previous page',
              icon: const Icon(Icons.chevron_left_rounded),
              onPressed: _pageIndex > 0
                  ? () => _goToPage(_pageIndex - 1)
                  : null,
            ),
          Text(
            'Page ${_pageIndex + 1} / ${maxPage + 1}',
            style: TextStyle(
              fontSize: 13,
              color: _headingColor(context),
              fontWeight: FontWeight.w500,
            ),
          ),
          if (maxPage > 0)
            IconButton(
              tooltip: 'Next page',
              icon: const Icon(Icons.chevron_right_rounded),
              onPressed: _pageIndex < maxPage
                  ? () => _goToPage(_pageIndex + 1)
                  : null,
            ),
        ],
      ),
    );
  }

  Widget _employeeRowInkWell({
    required _EmployeeProfile e,
    required bool isSelected,
    required bool primarySemanticForRow,
    required Widget child,
    int? rowIndex,
  }) {
    final ink = InkWell(
      onTap: () {
        if (rowIndex != null &&
            rowIndex >= 0 &&
            rowIndex < _rowFocusNodes.length) {
          _rowFocusNodes[rowIndex].requestFocus();
        }
        setState(() => _selectedEmployeeId = e.id);
      },
      focusColor: AppTheme.primaryNavy.withValues(alpha: 0.08),
      canRequestFocus: false,
      child: child,
    );
    if (primarySemanticForRow) {
      return Semantics(
        button: true,
        selected: isSelected,
        label:
            '${e.fullName}, employee number ${e.displayEmployeeNo}, '
            '${e.assignmentDisplay}, '
            '${e.isActive ? "active account" : "inactive account"}, '
            '${e.roleDisplay}. Activate to select. '
            'Arrow up and down to move between rows. Space toggles bulk selection.',
        child: ink,
      );
    }
    return ExcludeSemantics(child: ink);
  }

  List<TableRow> _employeeTableSkeletonRows() {
    Widget skelBox(double width) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Shimmer.fromColors(
            baseColor: _isDark(context)
                ? AppTheme.dashMutedSurfaceOf(context)
                : AppTheme.lightGray.withValues(alpha: 0.55),
            highlightColor: _isDark(context)
                ? AppTheme.dashPanelOf(context)
                : AppTheme.white,
            period: const Duration(milliseconds: 1200),
            child: SizedBox(
              width: width,
              height: 12,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: _isDark(context)
                      ? AppTheme.dashHairlineOf(context)
                      : AppTheme.lightGray.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return List<TableRow>.generate(
      6,
      (_) => TableRow(
        children: [
          TableCell(
            verticalAlignment: TableCellVerticalAlignment.middle,
            child: skelBox(22),
          ),
          TableCell(
            verticalAlignment: TableCellVerticalAlignment.middle,
            child: skelBox(52),
          ),
          TableCell(
            verticalAlignment: TableCellVerticalAlignment.middle,
            child: skelBox(160),
          ),
          TableCell(
            verticalAlignment: TableCellVerticalAlignment.middle,
            child: skelBox(120),
          ),
          TableCell(
            verticalAlignment: TableCellVerticalAlignment.middle,
            child: skelBox(64),
          ),
          TableCell(
            verticalAlignment: TableCellVerticalAlignment.middle,
            child: skelBox(72),
          ),
        ],
      ),
    );
  }

  Widget _sortableHeaderCell(String label, String sortKey) {
    final active = _sortField == sortKey;
    final orderHint = active
        ? (_sortAscending ? ', ascending' : ', descending')
        : '';
    return Semantics(
      button: true,
      label: 'Sort by $label$orderHint',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _setSort(sortKey),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: _headingColor(context),
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
                if (active)
                  Icon(
                    _sortAscending
                        ? Icons.arrow_upward_rounded
                        : Icons.arrow_downward_rounded,
                    size: 16,
                    color: _isDark(context)
                        ? AppTheme.primaryNavyLight
                        : AppTheme.primaryNavy,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchField() {
    return TextField(
      controller: _searchController,
      onChanged: _onSearchChanged,
      style: AppTheme.dashFieldTextStyle(context),
      decoration: AppTheme.dashInputDecoration(
        context,
        hintText: 'Search name, ID, or email',
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

  Widget _buildDropdown(
    String value,
    List<String> options,
    ValueChanged<String?> onChanged,
  ) {
    return Container(
      constraints: const BoxConstraints(minWidth: 128, maxWidth: 200),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: _filterDecoration(context),
      child: DropdownButton<String>(
        value: value,
        dropdownColor: AppTheme.dashPanelOf(context),
        style: AppTheme.dashFieldTextStyle(context),
        underline: const SizedBox.shrink(),
        isDense: true,
        isExpanded: true,
        items: options
            .map(
              (o) => DropdownMenuItem(
                value: o,
                child: Text(o, style: AppTheme.dashFieldTextStyle(context)),
              ),
            )
            .toList(),
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildRightPanel() {
    final dark = _isDark(context);
    _EmployeeProfile? selected;
    if (_selectedEmployeeId != null) {
      try {
        selected = _employees.firstWhere((e) => e.id == _selectedEmployeeId);
      } catch (_) {}
    }
    final sel = selected;
    final hasSelection = sel != null;
    final emailTrim = sel?.email?.trim();
    final bioTrim = sel?.biometricUserId?.trim();

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: AppTheme.dashSurfaceCard(context, radius: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 24),
          hasSelection && (sel.avatarPath ?? '').isNotEmpty
              ? ClipOval(
                  child: Image.network(
                    userAvatarImageUrl(sel.id, avatarPath: sel.avatarPath),
                    key: ValueKey(sel.avatarPath),
                    width: 96,
                    height: 96,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 96,
                      height: 96,
                      color: AppTheme.dashMutedSurfaceOf(context),
                      child: Icon(
                        Icons.person_rounded,
                        size: 56,
                        color: _mutedColor(context).withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                )
              : CircleAvatar(
                  radius: 48,
                  backgroundColor: AppTheme.dashMutedSurfaceOf(context),
                  child: Icon(
                    Icons.person_rounded,
                    size: 56,
                    color: _mutedColor(context).withValues(alpha: 0.5),
                  ),
                ),
          const SizedBox(height: 16),
          Text(
            hasSelection ? sel.fullName : 'Select an employee',
            style: TextStyle(
              color: hasSelection
                  ? _headingColor(context)
                  : _mutedColor(context).withValues(alpha: 0.8),
              fontSize: 14,
              fontWeight: hasSelection ? FontWeight.w600 : FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
          if (emailTrim != null && emailTrim.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              emailTrim,
              style: TextStyle(
                color: _mutedColor(context).withValues(alpha: 0.9),
                fontSize: 12,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (hasSelection && sel.assignmentDisplay != '—') ...[
            const SizedBox(height: 10),
            Text(
              sel.assignmentDisplay,
              style: TextStyle(
                color: _mutedColor(context).withValues(alpha: 0.85),
                fontSize: 12,
                height: 1.3,
              ),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (bioTrim != null && bioTrim.isNotEmpty) ...[
            const SizedBox(height: 12),
            Semantics(
              container: true,
              label:
                  'Linked to time clock device. Biometric user identifier $bioTrim',
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.primaryNavy.withValues(
                    alpha: dark ? 0.22 : 0.08,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: AppTheme.primaryNavy.withValues(
                      alpha: dark ? 0.45 : 0.2,
                    ),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      'Linked to device',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color:
                            (dark
                                    ? AppTheme.primaryNavyLight
                                    : AppTheme.primaryNavy)
                                .withValues(alpha: 0.9),
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.fingerprint_rounded,
                          size: 14,
                          color:
                              (dark
                                      ? AppTheme.primaryNavyLight
                                      : AppTheme.primaryNavy)
                                  .withValues(alpha: 0.85),
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            bioTrim,
                            style: TextStyle(
                              fontSize: 11,
                              color: _headingColor(
                                context,
                              ).withValues(alpha: 0.85),
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (hasSelection && widget.onOpenAssignmentForEmployee != null) ...[
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () => widget.onOpenAssignmentForEmployee!(sel.id),
              icon: Icon(
                Icons.assignment_turned_in_outlined,
                size: 18,
                color: dark ? AppTheme.primaryNavyLight : AppTheme.primaryNavy,
              ),
              label: Text(
                'View assignment & shift',
                style: TextStyle(
                  color: dark
                      ? AppTheme.primaryNavyLight
                      : AppTheme.primaryNavy,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: TextButton.styleFrom(
                foregroundColor: dark
                    ? AppTheme.primaryNavyLight
                    : AppTheme.primaryNavy,
              ),
            ),
          ],
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: hasSelection
                  ? () => _openEditEmployeePanel(sel)
                  : null,
              icon: Icon(
                Icons.edit_rounded,
                size: 20,
                color: hasSelection
                    ? _headingColor(context)
                    : _mutedColor(context).withValues(alpha: 0.5),
              ),
              label: const Text('Edit'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _headingColor(context),
                side: BorderSide(
                  color: hasSelection
                      ? const Color(0xFF4CAF50).withValues(alpha: 0.6)
                      : AppTheme.dashHairlineOf(context),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: hasSelection
                  ? () {
                      final p = sel;
                      p.isActive ? _confirmDeactivate(p) : _confirmActivate(p);
                    }
                  : null,
              icon: Icon(
                (hasSelection && !sel.isActive)
                    ? Icons.person_add_rounded
                    : Icons.person_off_rounded,
                size: 20,
                color: hasSelection
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.5),
              ),
              label: Text(
                hasSelection && !sel.isActive ? 'Activate' : 'Deactivate',
              ),
              style: FilledButton.styleFrom(
                backgroundColor: (hasSelection && !sel.isActive)
                    ? const Color(0xFF4CAF50)
                    : const Color(0xFFE53935),
                disabledBackgroundColor: Colors.red.shade200.withValues(
                  alpha: 0.5,
                ),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmActivate(_EmployeeProfile profile) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Activate employee?'),
        content: Text(
          'This will reactivate the account of ${profile.fullName}. They will be able to sign in again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF4CAF50),
            ),
            child: const Text('Activate'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ApiClient.instance.put(
        '/api/employees/${profile.id}',
        data: {'is_active': true},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${profile.fullName} has been activated.')),
      );
      await _loadEmployees();
      if (!mounted) return;
      final dtr = context.read<DtrProvider>();
      dtr.invalidateCachedDtrData(includeReferenceData: true);
      dtr.loadEmployees(forceRefresh: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to activate: $e')));
    }
  }

  Future<void> _openEditEmployeePanel(_EmployeeProfile profile) async {
    final updated = await openResponsiveRightSidePanel<bool>(
      context: context,
      barrierLabel: 'Close edit employee',
      breakpoint: 900,
      minWidth: 760,
      initialWidthFraction: 0.62,
      builder: (panelCtx) => _EditEmployeeDialog(profile: profile),
    );
    if (updated != true || !mounted) return;
    await _loadEmployees();
    if (!mounted) return;
    final dtr = context.read<DtrProvider>();
    dtr.invalidateCachedDtrData(includeReferenceData: true);
    dtr.loadEmployees(forceRefresh: true);
  }

  void _showImportDialog(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => _BiometricImportDialog(
        onImportSuccess: () {
          setState(() => _pageIndex = 0);
          _loadEmployees();
          final dtr = dialogContext.read<DtrProvider>();
          dtr.invalidateCachedDtrData(includeReferenceData: true);
          dtr.loadEmployees(forceRefresh: true);
        },
      ),
    );
  }

  void _showBiometricRosterDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => const _BiometricRosterDialog(),
    );
  }

  Future<void> _confirmDeactivate(_EmployeeProfile profile) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Deactivate employee?'),
        content: Text(
          'This will deactivate the account of ${profile.fullName}. They will no longer be able to sign in.',
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
      await ApiClient.instance.delete('/api/employees/${profile.id}');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${profile.fullName} has been deactivated.')),
      );
      await _loadEmployees();
      if (!mounted) return;
      final dtr = context.read<DtrProvider>();
      dtr.invalidateCachedDtrData(includeReferenceData: true);
      dtr.loadEmployees(forceRefresh: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to deactivate: $e')));
    }
  }
}

/// Parses full_name into first, middle, last.
void _parseFullName(
  String fullName,
  TextEditingController first,
  TextEditingController middle,
  TextEditingController last,
) {
  final parts = fullName
      .trim()
      .split(RegExp(r'\s+'))
      .where((e) => e.isNotEmpty)
      .toList();
  if (parts.isEmpty) {
    first.text = '';
    middle.text = '';
    last.text = '';
    return;
  }
  if (parts.length == 1) {
    first.text = parts[0];
    middle.text = '';
    last.text = '';
    return;
  }
  if (parts.length == 2) {
    first.text = parts[0];
    middle.text = '';
    last.text = parts[1];
    return;
  }
  first.text = parts.first;
  last.text = parts.last;
  middle.text = parts.sublist(1, parts.length - 1).join(' ');
}
