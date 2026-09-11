import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/dtr/management/attendance_policies/data/attendance_policy_request_guard.dart';

class _PolicyRecord {
  const _PolicyRecord({
    required this.id,
    required this.policyName,
    this.description,
    required this.workHoursPerDay,
    required this.useEquivalentDayConversion,

    required this.deductLate,

    required this.deductUndertime,

    required this.absentEqualsFullDayDeduction,

    required this.combineLateAndUndertime,
    required this.deductionMultiplier,
    required this.isDefault,
    required this.isActive,
    required this.isUsed,
  });
  final String id;
  final String policyName;
  final String? description;

  final double workHoursPerDay;
  final bool useEquivalentDayConversion;

  final bool deductLate;

  final bool deductUndertime;

  final bool absentEqualsFullDayDeduction;

  final bool combineLateAndUndertime;
  final double deductionMultiplier;

  final bool isDefault;
  final bool isActive;
  final bool isUsed;
}

class _ShiftWorkHoursOption {
  const _ShiftWorkHoursOption({
    required this.id,
    required this.name,
    required this.hours,
  });

  final String id;
  final String name;
  final double hours;

  String get hoursDisplay =>
      hours % 1 == 0 ? hours.toStringAsFixed(0) : hours.toStringAsFixed(2);
}

class ManageAttendancePolicy extends StatefulWidget {
  const ManageAttendancePolicy({super.key});

  @override
  State<ManageAttendancePolicy> createState() => _ManageAttendancePolicyState();
}

class _ManageAttendancePolicyState extends State<ManageAttendancePolicy> {
  static const int _rowsPerPage = 10;

  final _searchController = TextEditingController();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();

  // Computation settings
  final _workHoursPerDayController = TextEditingController(text: '8');
  bool _useEquivalentDayConversion = true;
  String? _selectedShiftTemplateId;
  List<_ShiftWorkHoursOption> _shiftTemplates = [];

  // Late settings
  bool _deductLate = false;

  // Undertime settings
  bool _deductUndertime = true;

  // Absence settings
  bool _absentEqualsFullDayDeduction = true;

  // Advanced settings
  bool _combineLateAndUndertime = false;
  final _deductionMultiplierController = TextEditingController(text: '1.0');

  String _statusFilter = 'Active';
  int _page = 0;
  List<_PolicyRecord> _policies = [];
  bool _loading = false;
  String? _loadError;
  String? _loadedStatusFilter;
  _PolicyRecord? _selectedPolicy;
  bool _isDefault = false;
  bool _isActive = true;
  StateSetter? _drawerSetState;

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadPolicies();
      _loadShiftTemplates();
    });
  }

  @override
  void dispose() {
    _policyRequestGuard.invalidate();
    _searchController.dispose();
    _nameController.dispose();
    _descriptionController.dispose();
    _workHoursPerDayController.dispose();
    _deductionMultiplierController.dispose();
    super.dispose();
  }

  final _policyRequestGuard = AttendancePolicyRequestGuard();

  String? _validateForm() {
    final workHours = double.tryParse(_workHoursPerDayController.text.trim());
    if (workHours == null || workHours <= 0) {
      return 'Work Hours Per Day must be greater than 0.';
    }

    final mult = double.tryParse(_deductionMultiplierController.text.trim());
    if (mult == null || mult <= 0) {
      return 'Deduction Multiplier must be greater than 0.';
    }
    return null;
  }

  int? _timeToMinutes(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    final match = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(text);
    if (match == null) return null;
    final hour = int.tryParse(match.group(1) ?? '');
    final minute = int.tryParse(match.group(2) ?? '');
    if (hour == null || minute == null) return null;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
    return hour * 60 + minute;
  }

  String _shiftTypeFromPayload(Map<String, dynamic> shift) {
    final explicit = shift['punch_mode']?.toString().trim().toLowerCase();
    if (explicit == 'full_day' ||
        explicit == 'am_only' ||
        explicit == 'pm_only' ||
        explicit == 'single_session') {
      return explicit!;
    }

    final start = _timeToMinutes(shift['start_time']);
    final end = _timeToMinutes(shift['end_time']);
    final breakEnd = _timeToMinutes(shift['break_end']);
    if (start == null) return 'full_day';
    if (start >= 12 * 60) return 'pm_only';
    if (breakEnd == null && end != null && end <= 13 * 60) return 'am_only';
    return 'full_day';
  }

  double? _computeShiftWorkHours(Map<String, dynamic> shift) {
    final start = _timeToMinutes(shift['start_time']);
    final end = _timeToMinutes(shift['end_time']);
    if (start == null || end == null) return null;

    var span = end - start;
    if (span < 0) span += 24 * 60;
    if (span <= 0) return null;

    final type = _shiftTypeFromPayload(shift);
    var workMinutes = span;
    if (type == 'full_day') {
      final breakEnd = _timeToMinutes(shift['break_end']);
      final lunchMinutes = breakEnd != null
          ? (breakEnd - 12 * 60).clamp(0, span)
          : 60;
      workMinutes = (span - lunchMinutes).clamp(0, span).toInt();
    }
    if (workMinutes <= 0) return null;
    return double.parse((workMinutes / 60).toStringAsFixed(2));
  }

  String _formatHours(double hours) =>
      hours % 1 == 0 ? hours.toStringAsFixed(0) : hours.toStringAsFixed(2);

  void _updatePolicyFormState(VoidCallback update) {
    if (mounted) setState(update);
    final drawerSetState = _drawerSetState;
    if (!mounted || drawerSetState == null) return;
    try {
      drawerSetState(() {});
    } catch (_) {
      _drawerSetState = null;
    }
  }

  Future<void> _loadShiftTemplates() async {
    try {
      final res = await ApiClient.instance.get<List<dynamic>>(
        '/api/shifts',
        queryParameters: {'status': 'Active'},
      );

      final templates = <_ShiftWorkHoursOption>[];
      for (final raw in res.data ?? const []) {
        if (raw is! Map) continue;
        final shift = Map<String, dynamic>.from(raw);
        final id = shift['id']?.toString();
        final name = shift['name']?.toString().trim() ?? '';
        final hours = _computeShiftWorkHours(shift);
        if (id == null || id.isEmpty || name.isEmpty || hours == null) {
          continue;
        }
        templates.add(_ShiftWorkHoursOption(id: id, name: name, hours: hours));
      }
      _updatePolicyFormState(() => _shiftTemplates = templates);
    } on DioException catch (e) {
      debugPrint(
        'Load shifts for policy failed: ${e.response?.data ?? e.message}',
      );
      _updatePolicyFormState(() => _shiftTemplates = []);
    }
  }

  void _applyShiftTemplate(String? shiftId) {
    _ShiftWorkHoursOption? selected;
    if (shiftId != null) {
      for (final shift in _shiftTemplates) {
        if (shift.id == shiftId) {
          selected = shift;
          break;
        }
      }
    }
    _updatePolicyFormState(() {
      _selectedShiftTemplateId = shiftId;
      if (selected != null) {
        _workHoursPerDayController.text = _formatHours(selected.hours);
      }
    });
  }

  Future<void> _loadPolicies() async {
    if (!mounted) return;
    final requestedStatus = _statusFilter;
    final request = _policyRequestGuard.begin(requestedStatus);
    setState(() {
      _loading = true;
      _loadError = null;
      _page = 0;
    });
    try {
      final res = await ApiClient.instance.get<List<dynamic>>(
        '/api/attendance-policies',
        queryParameters: {'status': requestedStatus},
      );
      final data = res.data ?? [];
      final policies = (data).map((e) {
        final m = e as Map<String, dynamic>;
        return _PolicyRecord(
          id: m['id'] as String,
          policyName:
              (m['policy_name'] as String?) ?? (m['name'] as String? ?? ''),
          description: m['description'] as String?,
          workHoursPerDay: (m['work_hours_per_day'] as num?)?.toDouble() ?? 8.0,
          useEquivalentDayConversion:
              m['use_equivalent_day_conversion'] as bool? ?? true,
          deductLate: m['deduct_late'] as bool? ?? false,
          deductUndertime: m['deduct_undertime'] as bool? ?? true,
          absentEqualsFullDayDeduction:
              m['absent_equals_full_day_deduction'] as bool? ?? true,
          combineLateAndUndertime:
              m['combine_late_and_undertime'] as bool? ?? false,
          deductionMultiplier:
              (m['deduction_multiplier'] as num?)?.toDouble() ?? 1.0,
          isDefault: m['is_default'] as bool? ?? false,
          isActive: m['is_active'] as bool? ?? true,
          isUsed: m['is_used'] as bool? ?? false,
        );
      }).toList();
      if (!mounted || !_policyRequestGuard.accepts(request, _statusFilter)) {
        return;
      }
      setState(() {
        _policies = policies;
        _loadedStatusFilter = requestedStatus;
        _loadError = null;
      });
    } on DioException catch (e) {
      if (!mounted || !_policyRequestGuard.accepts(request, _statusFilter)) {
        return;
      }
      debugPrint('Load policies failed: ${e.response?.data ?? e.message}');
      setState(() {
        _loadError = 'Unable to load attendance policies. Please try again.';
      });
    } catch (e) {
      if (!mounted || !_policyRequestGuard.accepts(request, _statusFilter)) {
        return;
      }
      debugPrint('Load policies failed: $e');
      setState(() {
        _loadError = 'Unable to load attendance policies. Please try again.';
      });
    } finally {
      if (mounted && _policyRequestGuard.accepts(request, _statusFilter)) {
        setState(() => _loading = false);
      }
    }
  }

  void _selectPolicy(_PolicyRecord p) {
    setState(() {
      _selectedPolicy = p;
      _nameController.text = p.policyName;
      _descriptionController.text = p.description ?? '';

      _selectedShiftTemplateId = null;
      _workHoursPerDayController.text = p.workHoursPerDay.toStringAsFixed(
        p.workHoursPerDay % 1 == 0 ? 0 : 2,
      );
      _useEquivalentDayConversion = p.useEquivalentDayConversion;

      _deductLate = p.deductLate;

      _deductUndertime = p.deductUndertime;

      _absentEqualsFullDayDeduction = p.absentEqualsFullDayDeduction;

      _combineLateAndUndertime = p.combineLateAndUndertime;
      _deductionMultiplierController.text = p.deductionMultiplier
          .toStringAsFixed(p.deductionMultiplier % 1 == 0 ? 0 : 3);

      _isDefault = p.isDefault;
      _isActive = p.isActive;
    });
  }

  void _clearForm() {
    setState(() {
      _selectedPolicy = null;
      _nameController.clear();
      _descriptionController.clear();
      _selectedShiftTemplateId = null;
      _workHoursPerDayController.text = '8';
      _useEquivalentDayConversion = true;

      _deductLate = false;

      _deductUndertime = true;

      _absentEqualsFullDayDeduction = true;

      _combineLateAndUndertime = false;
      _deductionMultiplierController.text = '1.0';

      _isDefault = false;
      _isActive = true;
    });
  }

  Future<bool> _addPolicy() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a policy name.')),
      );
      return false;
    }
    final validation = _validateForm();
    if (validation != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(validation)));
      return false;
    }
    try {
      await ApiClient.instance.post(
        '/api/attendance-policies',
        data: {
          'policy_name': name,
          'description': _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
          'work_hours_per_day':
              double.tryParse(_workHoursPerDayController.text.trim()) ?? 8,
          'use_equivalent_day_conversion': _useEquivalentDayConversion,
          'deduct_late': _deductLate,
          'deduct_undertime': _deductUndertime,
          'absent_equals_full_day_deduction': _absentEqualsFullDayDeduction,
          'combine_late_and_undertime': _combineLateAndUndertime,
          'deduction_multiplier':
              double.tryParse(_deductionMultiplierController.text.trim()) ??
              1.0,
          'is_default': _isDefault,
          'is_active': _isActive,
        },
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Attendance policy added.')),
        );
        _clearForm();
        _loadPolicies();
      }
      return true;
    } on DioException catch (e) {
      if (mounted) {
        final msg =
            (e.response?.data as Map?)?['error'] ??
            e.message ??
            'Failed to add';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to add: $msg')));
      }
      return false;
    }
  }

  Future<bool> _updatePolicy() async {
    final p = _selectedPolicy;
    if (p == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a policy to update.')),
      );
      return false;
    }
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a policy name.')),
      );
      return false;
    }
    final validation = _validateForm();
    if (validation != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(validation)));
      return false;
    }
    try {
      await ApiClient.instance.put(
        '/api/attendance-policies/${p.id}',
        data: {
          'policy_name': name,
          'description': _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
          'work_hours_per_day':
              double.tryParse(_workHoursPerDayController.text.trim()) ?? 8,
          'use_equivalent_day_conversion': _useEquivalentDayConversion,
          'deduct_late': _deductLate,
          'deduct_undertime': _deductUndertime,
          'absent_equals_full_day_deduction': _absentEqualsFullDayDeduction,
          'combine_late_and_undertime': _combineLateAndUndertime,
          'deduction_multiplier':
              double.tryParse(_deductionMultiplierController.text.trim()) ??
              1.0,
          'is_default': _isDefault,
          'is_active': _isActive,
        },
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Attendance policy updated.')),
        );
        _clearForm();
        _loadPolicies();
      }
      return true;
    } on DioException catch (e) {
      if (mounted) {
        final msg =
            (e.response?.data as Map?)?['error'] ??
            e.message ??
            'Failed to update';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to update: $msg')));
      }
      return false;
    }
  }

  Future<bool> _deactivatePolicy() async {
    final p = _selectedPolicy;
    if (p == null || !p.isActive) return false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Deactivate policy?'),
        content: Text(
          '"${p.policyName}" will no longer appear in active lists.',
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
        '/api/attendance-policies/${p.id}',
        data: {'is_active': false},
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Policy deactivated.')));
        _clearForm();
        _loadPolicies();
      }
      return true;
    } on DioException catch (e) {
      if (mounted) {
        final msg =
            (e.response?.data as Map?)?['error'] ??
            e.message ??
            'Failed to deactivate';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed: $msg')));
      }
      return false;
    }
  }

  Future<bool> _reactivatePolicy() async {
    final policy = _selectedPolicy;
    if (policy == null || policy.isActive) return false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reactivate policy?'),
        content: Text(
          'This will restore "${policy.policyName}" to active policy lists.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            icon: const Icon(Icons.restore_rounded, size: 18),
            label: const Text('Reactivate'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return false;
    try {
      await ApiClient.instance.put(
        '/api/attendance-policies/${policy.id}',
        data: {'is_active': true},
      );
      if (!mounted) return false;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Policy reactivated.')));
      _clearForm();
      _loadPolicies();
      return true;
    } on DioException catch (error) {
      if (mounted) {
        final message =
            (error.response?.data as Map?)?['error'] ??
            error.message ??
            'Failed to reactivate';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed: $message')));
      }
      return false;
    }
  }

  Future<bool> _deleteUnusedPolicy() async {
    final p = _selectedPolicy;
    if (p == null || p.isUsed) return false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete unused policy?'),
        content: Text(
          '"${p.policyName}" will be permanently deleted. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(ctx).pop(true),
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
            label: const Text('Delete'),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return false;
    try {
      await ApiClient.instance.delete('/api/attendance-policies/${p.id}');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Unused policy deleted.')));
        _clearForm();
        _loadPolicies();
      }
      return true;
    } on DioException catch (e) {
      if (mounted) {
        final msg =
            (e.response?.data as Map?)?['error'] ??
            e.message ??
            'Failed to delete policy';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed: $msg')));
      }
      return false;
    }
  }

  Future<void> _openPolicyDrawer({_PolicyRecord? policy}) async {
    _drawerSetState = null;
    if (policy == null) {
      _clearForm();
    } else {
      _selectPolicy(policy);
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
          final drawerWidth = screenWidth < 720 ? screenWidth : 560.0;
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
                    return _buildPolicyDrawer(dialogContext);
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

  Widget _buildPolicyDrawer(BuildContext drawerContext) {
    final isEditing = _selectedPolicy != null;
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
                        ? 'Edit Attendance Policy'
                        : 'Add Attendance Policy',
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
              child: _buildFormPanel(framed: false, showActions: false),
            ),
          ),
          _buildDrawerFooter(drawerContext),
        ],
      ),
    );
  }

  Widget _buildDrawerFooter(BuildContext drawerContext) {
    final isEditing = _selectedPolicy != null;
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
          if (isEditing && (_selectedPolicy?.isActive ?? false))
            OutlinedButton.icon(
              onPressed: () async {
                final ok = await _deactivatePolicy();
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
          if (isEditing && !(_selectedPolicy?.isActive ?? true))
            OutlinedButton.icon(
              key: const Key('reactivate-attendance-policy'),
              onPressed: () async {
                final ok = await _reactivatePolicy();
                if (ok && drawerContext.mounted) {
                  Navigator.of(drawerContext).pop();
                }
              },
              icon: const Icon(Icons.restore_rounded, size: 18),
              label: const Text('Reactivate'),
            ),
          if (isEditing && !(_selectedPolicy?.isUsed ?? true))
            OutlinedButton.icon(
              onPressed: () async {
                final ok = await _deleteUnusedPolicy();
                if (ok && drawerContext.mounted) {
                  Navigator.of(drawerContext).pop();
                }
              },
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              label: const Text('Delete Unused'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: const BorderSide(color: Colors.red),
              ),
            ),
          FilledButton.icon(
            onPressed: () async {
              final ok = isEditing ? await _updatePolicy() : await _addPolicy();
              if (ok && drawerContext.mounted) {
                Navigator.of(drawerContext).pop();
              }
            },
            icon: Icon(
              isEditing ? Icons.edit_rounded : Icons.add_rounded,
              size: 18,
            ),
            label: Text(isEditing ? 'Update' : 'Add Policy'),
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
    final search = _searchController.text.toLowerCase();
    final hasCurrentFilterData = _loadedStatusFilter == _statusFilter;
    final filtered = (hasCurrentFilterData ? _policies : <_PolicyRecord>[])
        .where(
          (p) =>
              p.policyName.toLowerCase().contains(search) ||
              (p.description ?? '').toLowerCase().contains(search),
        )
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Attendance Policy',
                style: TextStyle(
                  color: _headingColor(context),
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            FilledButton.icon(
              onPressed: () => _openPolicyDrawer(),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add Policy'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFE85D04),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        _buildListPanel(filtered),
      ],
    );
  }

  Widget _buildListPanel(List<_PolicyRecord> filtered) {
    final dark = _isDark(context);
    final hasCurrentFilterData = _loadedStatusFilter == _statusFilter;
    final total = filtered.length;
    final pageCount = total == 0
        ? 1
        : ((total + _rowsPerPage - 1) ~/ _rowsPerPage);
    final page = _page >= pageCount ? pageCount - 1 : _page;
    final pageStart = page * _rowsPerPage;
    final pageEnd = pageStart + _rowsPerPage > total
        ? total
        : pageStart + _rowsPerPage;
    final paged = total == 0
        ? <_PolicyRecord>[]
        : filtered.sublist(pageStart, pageEnd);
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
              SizedBox(
                width: 200,
                child: TextField(
                  controller: _searchController,
                  onChanged: (_) => setState(() => _page = 0),
                  style: AppTheme.dashFieldTextStyle(context),
                  decoration: AppTheme.dashInputDecoration(
                    context,
                    hintText: 'Search',
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    radius: 10,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                decoration: _filterDecoration(context),
                child: DropdownButton<String>(
                  value: _statusFilter,
                  dropdownColor: AppTheme.dashPanelOf(context),
                  style: AppTheme.dashFieldTextStyle(context),
                  underline: const SizedBox.shrink(),
                  isDense: true,
                  items: ['Active', 'Inactive', 'All']
                      .map(
                        (o) => DropdownMenuItem(
                          value: o,
                          child: Text(
                            o,
                            style: AppTheme.dashFieldTextStyle(context),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    setState(() {
                      _statusFilter = v ?? 'Active';
                      _page = 0;
                    });
                    _loadPolicies();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_loadError != null) ...[
            Container(
              key: const Key('attendance-policy-load-error'),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.12),
                border: Border.all(color: Colors.red.withValues(alpha: 0.65)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded, color: Colors.red),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _loadError!,
                      style: TextStyle(color: _headingColor(context)),
                    ),
                  ),
                  TextButton(
                    onPressed: _loading ? null : _loadPolicies,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (_loading && !hasCurrentFilterData)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(),
              ),
            )
          else if (!hasCurrentFilterData && _loadError != null)
            const SizedBox(height: 120)
          else if (filtered.isEmpty && _loadError == null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'No policies',
                  style: TextStyle(color: _mutedColor(context), fontSize: 14),
                ),
              ),
            )
          else
            Column(
              children: [
                if (_loading) const LinearProgressIndicator(minHeight: 2),
                ListView.separated(
                  shrinkWrap: true,
                  itemCount: paged.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final p = paged[i];
                    final isSelected = _selectedPolicy?.id == p.id;
                    return Material(
                      color: Colors.transparent,
                      child: ListTile(
                        selected: isSelected,
                        selectedTileColor: dark
                            ? AppTheme.primaryNavy.withValues(alpha: 0.35)
                            : AppTheme.primaryNavy.withValues(alpha: 0.08),
                        title: Row(
                          children: [
                            Flexible(
                              child: Text(
                                p.policyName,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: _headingColor(context),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (p.isDefault) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: AppTheme.primaryNavy.withValues(
                                    alpha: 0.15,
                                  ),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'Default',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: AppTheme.primaryNavy,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        subtitle: Text(
                          'Work hours/day: ${p.workHoursPerDay % 1 == 0 ? p.workHoursPerDay.toStringAsFixed(0) : p.workHoursPerDay.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: _mutedColor(context),
                          ),
                        ),
                        onTap: () => _openPolicyDrawer(policy: p),
                      ),
                    );
                  },
                ),
                _buildPaginationFooter(
                  total: total,
                  page: page,
                  pageCount: pageCount,
                  pageStart: pageStart,
                  pageEnd: pageEnd,
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildPaginationFooter({
    required int total,
    required int page,
    required int pageCount,
    required int pageStart,
    required int pageEnd,
  }) {
    final summary = total == 0
        ? 'No results'
        : 'Showing ${pageStart + 1}-$pageEnd of $total';
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Row(
        children: [
          Expanded(
            child: Text(
              summary,
              style: TextStyle(fontSize: 12, color: _mutedColor(context)),
            ),
          ),
          Text(
            'Page ${page + 1} of $pageCount',
            style: TextStyle(fontSize: 12, color: _mutedColor(context)),
          ),
          if (pageCount > 1) ...[
            const SizedBox(width: 12),
            OutlinedButton(
              onPressed: page > 0
                  ? () => setState(() => _page = page - 1)
                  : null,
              child: const Text('Previous'),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: page < pageCount - 1
                  ? () => setState(() => _page = page + 1)
                  : null,
              child: const Text('Next'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFormPanel({bool framed = true, bool showActions = true}) {
    final computationLocked = _selectedPolicy?.isUsed ?? false;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle('Basic Info'),
        const SizedBox(height: 12),
        _label('Policy Name'),
        const SizedBox(height: 6),
        TextFormField(
          controller: _nameController,
          style: AppTheme.dashFieldTextStyle(context),
          decoration: _decoration('Name'),
        ),
        const SizedBox(height: 16),
        _label('Description'),
        const SizedBox(height: 6),
        TextFormField(
          controller: _descriptionController,
          style: AppTheme.dashFieldTextStyle(context),
          decoration: _decoration('Description'),
          maxLines: 2,
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Checkbox(
              value: _isDefault,
              onChanged: (v) =>
                  _updatePolicyFormState(() => _isDefault = v ?? false),
              activeColor: AppTheme.primaryNavy,
            ),
            Text(
              'Default policy',
              style: TextStyle(color: _headingColor(context)),
            ),
          ],
        ),
        Row(
          children: [
            Checkbox(
              value: _isActive,
              onChanged: (v) =>
                  _updatePolicyFormState(() => _isActive = v ?? true),
              activeColor: AppTheme.primaryNavy,
            ),
            Text('Active', style: TextStyle(color: _headingColor(context))),
          ],
        ),

        const SizedBox(height: 24),
        _sectionTitle('Computation Settings'),
        if (computationLocked) ...[
          const SizedBox(height: 10),
          Container(
            key: const Key('attendance-policy-computation-lock'),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFE85D04).withValues(alpha: 0.10),
              border: Border.all(
                color: const Color(0xFFE85D04).withValues(alpha: 0.45),
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lock_outline_rounded, size: 18),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'This policy has already been used. Create a new policy to change computation settings.',
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        _label('Calculate From Shift'),
        const SizedBox(height: 6),
        _buildShiftTemplateDropdown(enabled: !computationLocked),
        const SizedBox(height: 12),
        _label('Work Hours Per Day'),
        const SizedBox(height: 6),
        TextFormField(
          key: const Key('attendance-policy-work-hours'),
          controller: _workHoursPerDayController,
          enabled: !computationLocked,
          style: AppTheme.dashFieldTextStyle(context),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: _decoration('8'),
        ),
        const SizedBox(height: 12),
        _switchTile(
          title: 'Use Equivalent Day Conversion',
          value: _useEquivalentDayConversion,
          enabled: !computationLocked,
          onChanged: (v) =>
              _updatePolicyFormState(() => _useEquivalentDayConversion = v),
        ),

        const SizedBox(height: 24),
        _sectionTitle('Late Settings'),
        const SizedBox(height: 12),
        _switchTile(
          title: 'Deduct Late',
          value: _deductLate,
          enabled: !computationLocked,
          onChanged: (v) => _updatePolicyFormState(() => _deductLate = v),
        ),

        const SizedBox(height: 24),
        _sectionTitle('Undertime Settings'),
        const SizedBox(height: 12),
        _switchTile(
          title: 'Deduct Undertime',
          value: _deductUndertime,
          enabled: !computationLocked,
          onChanged: (v) => _updatePolicyFormState(() => _deductUndertime = v),
        ),

        const SizedBox(height: 24),
        _sectionTitle('Absence Settings'),
        const SizedBox(height: 12),
        _switchTile(
          title: 'Absent Equals Full Day Deduction',
          value: _absentEqualsFullDayDeduction,
          enabled: !computationLocked,
          onChanged: (v) =>
              _updatePolicyFormState(() => _absentEqualsFullDayDeduction = v),
        ),

        const SizedBox(height: 24),
        _sectionTitle('Advanced Settings'),
        const SizedBox(height: 12),
        _switchTile(
          title: 'Combine Late and Undertime',
          value: _combineLateAndUndertime,
          enabled: !computationLocked,
          onChanged: (v) =>
              _updatePolicyFormState(() => _combineLateAndUndertime = v),
        ),
        const SizedBox(height: 12),
        _label('Deduction Multiplier'),
        const SizedBox(height: 6),
        TextFormField(
          key: const Key('attendance-policy-deduction-multiplier'),
          controller: _deductionMultiplierController,
          enabled: !computationLocked,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: _decoration('1.0'),
        ),

        if (showActions) ...[
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _addPolicy(),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Add Policy'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF4CAF50),
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _selectedPolicy != null
                      ? () => _updatePolicy()
                      : null,
                  icon: const Icon(Icons.edit_rounded, size: 18),
                  label: const Text('Update'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _selectedPolicy != null
                ? () => _deactivatePolicy()
                : null,
            icon: const Icon(Icons.person_off_rounded, size: 18),
            label: const Text('Deactivate'),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
          ),
          if (_selectedPolicy != null && !_selectedPolicy!.isUsed) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _deleteUnusedPolicy(),
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              label: const Text('Delete Unused Policy'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: const BorderSide(color: Colors.red),
              ),
            ),
          ],
        ],
      ],
    );

    if (!framed) {
      return Padding(padding: const EdgeInsets.all(24), child: content);
    }

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: AppTheme.dashSurfaceCard(context, radius: 12),
      child: content,
    );
  }

  Widget _sectionTitle(String text) => Text(
    text,
    style: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w800,
      color: _headingColor(context),
    ),
  );

  Widget _switchTile({
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
    bool enabled = true,
  }) {
    return Row(
      children: [
        Switch(
          key: ValueKey('attendance-policy-switch-$title'),
          value: value,
          onChanged: enabled ? onChanged : null,
          activeThumbColor: AppTheme.primaryNavy,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              color: enabled ? _headingColor(context) : _mutedColor(context),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildShiftTemplateDropdown({bool enabled = true}) {
    return DropdownButtonFormField<String>(
      key: ValueKey(_selectedShiftTemplateId),
      initialValue: _selectedShiftTemplateId,
      dropdownColor: AppTheme.dashPanelOf(context),
      style: AppTheme.dashFieldTextStyle(context),
      decoration: _decoration('Select shift'),
      isExpanded: true,
      items: [
        DropdownMenuItem<String>(
          value: null,
          child: Text(
            'Select shift',
            overflow: TextOverflow.ellipsis,
            style: AppTheme.dashFieldTextStyle(context),
          ),
        ),
        ..._shiftTemplates.map(
          (shift) => DropdownMenuItem<String>(
            value: shift.id,
            child: Text(
              '${shift.name} - ${shift.hoursDisplay} hrs',
              overflow: TextOverflow.ellipsis,
              style: AppTheme.dashFieldTextStyle(context),
            ),
          ),
        ),
      ],
      onChanged: !enabled || _shiftTemplates.isEmpty
          ? null
          : _applyShiftTemplate,
    );
  }

  Widget _label(String text) => Text(
    text,
    style: TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: _mutedColor(context),
    ),
  );

  InputDecoration _decoration(String hint) => AppTheme.dashInputDecoration(
    context,
    hintText: hint,
    radius: 8,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
  );
}
