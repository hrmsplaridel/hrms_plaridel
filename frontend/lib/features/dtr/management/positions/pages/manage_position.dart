import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';

/// Position record for display/CRUD.
class _PositionRecord {
  const _PositionRecord({
    required this.id,
    required this.name,
    this.description,
    this.departmentId,
    this.departmentName,
    required this.isDepartmentHead,
    required this.isActive,
    required this.canPermanentlyDelete,
    this.departmentHeadPeriodId,
    this.departmentHeadEffectiveFrom,
    this.departmentHeadEffectiveTo,
    this.departmentHeadPeriods = const [],
    this.positionNumber,
  });
  final String id;
  final String name;
  final String? description;
  final String? departmentId;
  final String? departmentName;
  final bool isDepartmentHead;
  final bool isActive;
  final bool canPermanentlyDelete;
  final String? departmentHeadPeriodId;
  final DateTime? departmentHeadEffectiveFrom;
  final DateTime? departmentHeadEffectiveTo;
  final List<Map<String, dynamic>> departmentHeadPeriods;
  final int? positionNumber;

  /// Display as POS-001, POS-002, etc., or "—" if null.
  String get displayPositionNo => positionNumber != null
      ? 'POS-${positionNumber!.toString().padLeft(3, '0')}'
      : '—';
}

/// Position management screen: list with search/department/status filter + form.
class ManagePosition extends StatefulWidget {
  const ManagePosition({super.key});

  @override
  State<ManagePosition> createState() => _ManagePositionState();
}

class _ManagePositionState extends State<ManagePosition> {
  static const int _rowsPerPage = 10;

  final _searchController = TextEditingController();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();

  String? _departmentFilterId;
  String _statusFilter = 'Active';
  int _page = 0;
  List<_PositionRecord> _positions = [];
  List<Map<String, dynamic>> _departments = [];
  bool _loading = false;
  _PositionRecord? _selectedPosition;
  String? _selectedDepartmentId;
  bool _isDepartmentHead = false;
  String? _departmentHeadPeriodId;
  DateTime? _departmentHeadEffectiveFrom;
  DateTime? _departmentHeadEffectiveTo;
  List<Map<String, dynamic>> _departmentHeadPeriods = [];
  StateSetter? _drawerSetState;

  bool _isDark(BuildContext context) => AppTheme.dashIsDark(context);

  Color _headingColor(BuildContext context) =>
      AppTheme.dashTextPrimaryOf(context);

  Color _mutedColor(BuildContext context) =>
      AppTheme.dashTextSecondaryOf(context);

  String _apiErrorMessage(DioException error, String fallback) {
    final data = error.response?.data;
    if (data is Map && data['error'] != null) {
      final message = data['error'].toString().trim();
      if (message.isNotEmpty) return message;
    }
    final message = error.message?.trim();
    return message == null || message.isEmpty ? fallback : message;
  }

  DateTime? _parseDate(dynamic value) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty) return null;
    return DateTime.tryParse(text.length >= 10 ? text.substring(0, 10) : text);
  }

  String? _apiDate(DateTime? value) {
    if (value == null) return null;
    return '${value.year.toString().padLeft(4, '0')}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')}';
  }

  String _displayDate(DateTime? value) =>
      _apiDate(value) ?? 'Official HRMS date';

  Future<void> _pickDepartmentHeadDate({required bool isStart}) async {
    final current = isStart
        ? _departmentHeadEffectiveFrom
        : _departmentHeadEffectiveTo;
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? _departmentHeadEffectiveFrom ?? DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    _updatePositionFormState(() {
      if (isStart) {
        _departmentHeadEffectiveFrom = picked;
        if (_departmentHeadEffectiveTo != null &&
            _departmentHeadEffectiveTo!.isBefore(picked)) {
          _departmentHeadEffectiveTo = null;
        }
      } else {
        _departmentHeadEffectiveTo = picked;
      }
    });
  }

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

  void _updatePositionFormState(VoidCallback update) {
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadDepartments();
      _loadPositions();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _loadDepartments() async {
    try {
      final res = await ApiClient.instance.get<List<dynamic>>(
        '/api/departments',
        queryParameters: {'status': 'All'},
      );
      final data = res.data ?? [];
      _departments = data.map((e) {
        final m = e as Map<String, dynamic>;
        return {'id': m['id'], 'name': m['name'] as String? ?? ''};
      }).toList();
    } on DioException catch (e) {
      debugPrint('Load departments failed: ${e.response?.data ?? e.message}');
      _departments = [];
    } catch (e) {
      debugPrint('Load departments failed: $e');
      _departments = [];
    }
    _updatePositionFormState(() {});
  }

  Future<void> _loadPositions() async {
    setState(() {
      _loading = true;
      _page = 0;
    });
    try {
      final params = <String, String>{'status': _statusFilter};
      if (_departmentFilterId != null) {
        params['department_id'] = _departmentFilterId!;
      }
      final res = await ApiClient.instance.get<List<dynamic>>(
        '/api/positions',
        queryParameters: params,
      );
      final data = res.data ?? [];
      _positions = (data).map((e) {
        final m = e as Map<String, dynamic>;
        final dept = m['departments'];
        final deptName =
            m['department_name'] as String? ??
            (dept is Map ? dept['name'] as String? : null);
        final posNum = m['position_number'];
        return _PositionRecord(
          id: m['id'] as String,
          name: m['name'] as String? ?? '',
          description: m['description'] as String?,
          departmentId: m['department_id'] as String?,
          departmentName: deptName,
          isDepartmentHead: m['is_department_head'] as bool? ?? false,
          departmentHeadPeriodId: m['department_head_period_id'] as String?,
          departmentHeadEffectiveFrom: _parseDate(
            m['department_head_effective_from'],
          ),
          departmentHeadEffectiveTo: _parseDate(
            m['department_head_effective_to'],
          ),
          departmentHeadPeriods:
              (m['department_head_periods'] as List<dynamic>? ?? const [])
                  .whereType<Map>()
                  .map((period) => Map<String, dynamic>.from(period))
                  .toList(),
          isActive: m['is_active'] as bool? ?? true,
          canPermanentlyDelete: m['can_permanently_delete'] as bool? ?? false,
          positionNumber: posNum is int
              ? posNum
              : (posNum != null ? int.tryParse(posNum.toString()) : null),
        );
      }).toList();
    } on DioException catch (e) {
      debugPrint('Load positions failed: ${e.response?.data ?? e.message}');
      _positions = [];
    }
    if (mounted) setState(() => _loading = false);
  }

  void _selectPosition(_PositionRecord p) {
    _updatePositionFormState(() {
      _selectedPosition = p;
      _titleController.text = p.name;
      _descriptionController.text = p.description ?? '';
      _selectedDepartmentId = p.departmentId;
      _isDepartmentHead = p.isDepartmentHead;
      _departmentHeadPeriodId = p.departmentHeadPeriodId;
      _departmentHeadEffectiveFrom = p.departmentHeadEffectiveFrom;
      _departmentHeadEffectiveTo = p.departmentHeadEffectiveTo;
      _departmentHeadPeriods = p.departmentHeadPeriods;
    });
  }

  void _clearForm() {
    _updatePositionFormState(() {
      _selectedPosition = null;
      _titleController.clear();
      _descriptionController.clear();
      _selectedDepartmentId = null;
      _isDepartmentHead = false;
      _departmentHeadPeriodId = null;
      _departmentHeadEffectiveFrom = null;
      _departmentHeadEffectiveTo = null;
      _departmentHeadPeriods = [];
    });
  }

  Future<bool> _addPosition() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a position title.')),
      );
      return false;
    }
    if (_isDepartmentHead && _selectedDepartmentId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Select a department for the official Department Head position.',
          ),
        ),
      );
      return false;
    }
    if (_isDepartmentHead &&
        _departmentHeadEffectiveFrom != null &&
        _departmentHeadEffectiveTo != null &&
        _departmentHeadEffectiveTo!.isBefore(_departmentHeadEffectiveFrom!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'The Department Head end date cannot precede its start date.',
          ),
        ),
      );
      return false;
    }
    try {
      await ApiClient.instance.post(
        '/api/positions',
        data: {
          'name': title,
          'description': _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
          'department_id': _selectedDepartmentId,
          'is_department_head': _isDepartmentHead,
          'department_head_effective_from': _isDepartmentHead
              ? _apiDate(_departmentHeadEffectiveFrom)
              : null,
          'department_head_effective_to': _isDepartmentHead
              ? _apiDate(_departmentHeadEffectiveTo)
              : null,
          'is_active': true,
        },
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Position added.')));
        _clearForm();
        _loadPositions();
      }
      return true;
    } on DioException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_apiErrorMessage(e, 'Failed to add position')),
          ),
        );
      }
      return false;
    }
  }

  Future<bool> _updatePosition() async {
    final p = _selectedPosition;
    if (p == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a position to update.')),
      );
      return false;
    }
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a position title.')),
      );
      return false;
    }
    if (_isDepartmentHead && _selectedDepartmentId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Select a department for the official Department Head position.',
          ),
        ),
      );
      return false;
    }
    if (_isDepartmentHead &&
        _departmentHeadEffectiveFrom != null &&
        _departmentHeadEffectiveTo != null &&
        _departmentHeadEffectiveTo!.isBefore(_departmentHeadEffectiveFrom!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'The Department Head end date cannot precede its start date.',
          ),
        ),
      );
      return false;
    }
    try {
      await ApiClient.instance.put(
        '/api/positions/${p.id}',
        data: {
          'name': title,
          'description': _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
          'department_id': _selectedDepartmentId,
          'is_department_head': _isDepartmentHead,
          'department_head_period_id': _departmentHeadPeriodId,
          'department_head_effective_from': _isDepartmentHead
              ? _apiDate(_departmentHeadEffectiveFrom)
              : null,
          'department_head_effective_to': _isDepartmentHead
              ? _apiDate(_departmentHeadEffectiveTo)
              : null,
        },
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Position updated.')));
        _clearForm();
        _loadPositions();
      }
      return true;
    } on DioException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_apiErrorMessage(e, 'Failed to update position')),
          ),
        );
      }
      return false;
    }
  }

  Future<bool> _deactivatePosition() async {
    final p = _selectedPosition;
    if (p == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a position to deactivate.')),
      );
      return false;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Deactivate position?'),
        content: Text(
          'This will deactivate "${p.name}". It will no longer appear in active lists.',
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
        '/api/positions/${p.id}',
        data: {'is_active': false},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${p.name} has been deactivated.')),
        );
        _clearForm();
        _loadPositions();
      }
      return true;
    } on DioException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_apiErrorMessage(e, 'Failed to deactivate position')),
          ),
        );
      }
      return false;
    }
  }

  Future<String?> _requestMistakenDeleteReason(_PositionRecord position) async {
    final formKey = GlobalKey<FormState>();
    var enteredReason = '';
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete unused position?'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'This permanently removes "${position.name}". This is allowed only because the position has no assignment history.',
              ),
              const SizedBox(height: 16),
              TextFormField(
                autofocus: true,
                maxLength: 1000,
                maxLines: 3,
                onChanged: (value) => enteredReason = value,
                decoration: const InputDecoration(
                  labelText: 'Reason',
                  hintText: 'Why should this unused position be deleted?',
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'A reason is required.'
                    : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () {
              if (formKey.currentState?.validate() != true) return;
              Navigator.of(dialogContext).pop(enteredReason.trim());
            },
            icon: const Icon(Icons.delete_forever_rounded, size: 18),
            label: const Text('Delete permanently'),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
          ),
        ],
      ),
    );
    return reason;
  }

  Future<bool> _deleteMistakenPosition() async {
    final position = _selectedPosition;
    if (position == null || !position.canPermanentlyDelete) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'This position has assignment history and cannot be permanently deleted.',
          ),
        ),
      );
      return false;
    }

    final reason = await _requestMistakenDeleteReason(position);
    if (reason == null || !mounted) return false;
    try {
      await ApiClient.instance.delete(
        '/api/positions/${position.id}',
        data: {'reason': reason},
      );
      return true;
    } on DioException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _apiErrorMessage(e, 'Failed to delete mistaken position'),
            ),
          ),
        );
      }
      return false;
    }
  }

  Future<void> _openPositionDrawer({_PositionRecord? position}) async {
    _drawerSetState = null;
    var positionDeleted = false;
    if (position == null) {
      _clearForm();
    } else {
      _selectPosition(position);
    }

    try {
      final result = await showGeneralDialog<bool>(
        context: context,
        barrierDismissible: true,
        barrierLabel: MaterialLocalizations.of(
          context,
        ).modalBarrierDismissLabel,
        barrierColor: Colors.black.withValues(alpha: 0.32),
        transitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (dialogContext, _, __) {
          final screenWidth = MediaQuery.of(dialogContext).size.width;
          final drawerWidth = screenWidth < 720 ? screenWidth : 520.0;
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
                    return _buildPositionDrawer(dialogContext);
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
      positionDeleted = result ?? false;
    } finally {
      _drawerSetState = null;
    }
    if (positionDeleted && mounted) {
      _clearForm();
      await _loadPositions();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unused position deleted.')),
        );
      }
    }
  }

  Widget _buildPositionDrawer(BuildContext drawerContext) {
    final isEditing = _selectedPosition != null;
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
                    isEditing ? 'Edit Position' : 'Add Position',
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
    final isEditing = _selectedPosition != null;
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
          if (isEditing)
            OutlinedButton.icon(
              onPressed: () async {
                final ok = await _deactivatePosition();
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
          if (_selectedPosition?.canPermanentlyDelete == true)
            OutlinedButton.icon(
              onPressed: () async {
                final ok = await _deleteMistakenPosition();
                if (ok && drawerContext.mounted) {
                  Navigator.of(drawerContext).pop(true);
                }
              },
              icon: const Icon(Icons.delete_forever_rounded, size: 18),
              label: const Text('Delete Unused Position'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: const BorderSide(color: Colors.red),
              ),
            ),
          FilledButton.icon(
            onPressed: () async {
              final ok = isEditing
                  ? await _updatePosition()
                  : await _addPosition();
              if (ok && drawerContext.mounted) {
                Navigator.of(drawerContext).pop();
              }
            },
            icon: Icon(
              isEditing ? Icons.edit_rounded : Icons.add_rounded,
              size: 18,
            ),
            label: Text(isEditing ? 'Update' : 'Add Position'),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Position',
                style: TextStyle(
                  color: _headingColor(context),
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            FilledButton.icon(
              onPressed: () => _openPositionDrawer(),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add Position'),
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
        _buildLeftPanel(),
      ],
    );
  }

  Widget _buildLeftPanel() {
    final dark = _isDark(context);
    final search = _searchController.text.toLowerCase();
    final filtered = search.isEmpty
        ? _positions
        : _positions.where((p) {
            final n = p.name.toLowerCase();
            final desc = (p.description ?? '').toLowerCase();
            final dept = (p.departmentName ?? '').toLowerCase();
            return n.contains(search) ||
                desc.contains(search) ||
                dept.contains(search);
          }).toList();
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
        ? <_PositionRecord>[]
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
              SizedBox(width: 180, child: _buildSearchField()),
              _buildDepartmentFilterDropdown(),
              _buildStatusDropdown(),
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
                    'ID',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: _headingColor(context),
                    ),
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: Text(
                    'Position',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: _headingColor(context),
                    ),
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: Text(
                    'Department',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: _headingColor(context),
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'Description',
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
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (filtered.isEmpty)
            Container(
              constraints: const BoxConstraints(minHeight: 120),
              alignment: Alignment.center,
              child: Text(
                'No positions',
                style: TextStyle(
                  color: _mutedColor(context).withValues(alpha: 0.8),
                  fontSize: 14,
                ),
              ),
            )
          else
            Column(
              children: [
                Table(
                  columnWidths: const {
                    0: FixedColumnWidth(88),
                    1: FlexColumnWidth(),
                    2: FlexColumnWidth(),
                    3: FlexColumnWidth(2),
                  },
                  children: paged.map((p) {
                    final isSelected = _selectedPosition?.id == p.id;
                    return TableRow(
                      decoration: BoxDecoration(
                        color: isSelected
                            ? (dark
                                  ? AppTheme.primaryNavy.withValues(alpha: 0.35)
                                  : AppTheme.primaryNavy.withValues(
                                      alpha: 0.08,
                                    ))
                            : null,
                      ),
                      children: [
                        _tableCell(
                          p.displayPositionNo,
                          onTap: () => _openPositionDrawer(position: p),
                          secondary: true,
                        ),
                        _tableCell(
                          p.name,
                          onTap: () => _openPositionDrawer(position: p),
                        ),
                        _tableCell(
                          p.departmentName ?? '—',
                          onTap: () => _openPositionDrawer(position: p),
                          secondary: true,
                        ),
                        _tableCell(
                          p.description ?? '—',
                          onTap: () => _openPositionDrawer(position: p),
                          secondary: true,
                        ),
                      ],
                    );
                  }).toList(),
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

  Widget _tableCell(
    String text, {
    VoidCallback? onTap,
    bool secondary = false,
  }) {
    return TableCell(
      verticalAlignment: TableCellVerticalAlignment.middle,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Text(
            text,
            style: TextStyle(
              fontSize: secondary ? 12 : 13,
              color: secondary ? _mutedColor(context) : _headingColor(context),
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
      ),
    );
  }

  Widget _buildSearchField() {
    return TextField(
      controller: _searchController,
      onChanged: (_) => setState(() => _page = 0),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: _filterDecoration(context),
      child: DropdownButton<String?>(
        value: _departmentFilterId,
        dropdownColor: AppTheme.dashPanelOf(context),
        style: AppTheme.dashFieldTextStyle(context),
        underline: const SizedBox.shrink(),
        isDense: true,
        items: [
          DropdownMenuItem(
            value: null,
            child: Text('All', style: AppTheme.dashFieldTextStyle(context)),
          ),
          ..._departments.map(
            (d) => DropdownMenuItem(
              value: d['id'] as String?,
              child: Text(
                d['name'] as String? ?? '',
                style: AppTheme.dashFieldTextStyle(context),
              ),
            ),
          ),
        ],
        onChanged: (v) {
          setState(() {
            _departmentFilterId = v;
            _page = 0;
          });
          _loadPositions();
        },
      ),
    );
  }

  Widget _buildStatusDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
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
                child: Text(o, style: AppTheme.dashFieldTextStyle(context)),
              ),
            )
            .toList(),
        onChanged: (v) {
          setState(() {
            _statusFilter = v ?? 'Active';
            _page = 0;
          });
          _loadPositions();
        },
      ),
    );
  }

  Widget _buildFormPanel({bool framed = true, bool showActions = true}) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Position Title',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: _mutedColor(context),
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: _titleController,
          style: AppTheme.dashFieldTextStyle(context),
          decoration: _inputDecoration('Position Title'),
        ),
        const SizedBox(height: 20),
        Text(
          'Department',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: _mutedColor(context),
          ),
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<String?>(
          key: ValueKey(_selectedDepartmentId),
          initialValue:
              _departments.any((d) => d['id'] == _selectedDepartmentId)
              ? _selectedDepartmentId
              : null,
          dropdownColor: AppTheme.dashPanelOf(context),
          style: AppTheme.dashFieldTextStyle(context),
          decoration: _inputDecoration('Select department'),
          hint: Text(
            'Select department',
            style: TextStyle(color: _mutedColor(context)),
          ),
          isExpanded: true,
          icon: Icon(
            Icons.arrow_drop_down_rounded,
            color: _mutedColor(context).withValues(alpha: 0.8),
          ),
          items: [
            DropdownMenuItem(
              value: null,
              child: Text(
                'Select department',
                style: AppTheme.dashFieldTextStyle(context),
              ),
            ),
            ..._departments.map(
              (d) => DropdownMenuItem<String?>(
                value: d['id'] as String?,
                child: Text(
                  d['name'] as String? ?? '',
                  style: AppTheme.dashFieldTextStyle(context),
                ),
              ),
            ),
          ],
          onChanged: (v) => _updatePositionFormState(() {
            _selectedDepartmentId = v;
            if (v == null) _isDepartmentHead = false;
          }),
        ),
        const SizedBox(height: 14),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          value: _isDepartmentHead,
          onChanged: _selectedDepartmentId == null
              ? null
              : (value) => _updatePositionFormState(() {
                  _isDepartmentHead = value;
                  if (value && _departmentHeadPeriodId == null) {
                    _departmentHeadEffectiveFrom = null;
                    _departmentHeadEffectiveTo = null;
                  }
                }),
          title: Text(
            'Official Department Head',
            style: AppTheme.dashFieldTextStyle(context),
          ),
          subtitle: Text(
            'The employee assigned to this position becomes the primary reviewer.',
            style: TextStyle(fontSize: 12, color: _mutedColor(context)),
          ),
        ),
        if (_isDepartmentHead) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildDepartmentHeadDateField(
                  label: 'Effective from',
                  value: _departmentHeadEffectiveFrom,
                  onTap: () => _pickDepartmentHeadDate(isStart: true),
                  allowClear: _departmentHeadEffectiveFrom != null,
                  onClear: () => _updatePositionFormState(
                    () => _departmentHeadEffectiveFrom = null,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildDepartmentHeadDateField(
                  label: 'Effective to (optional)',
                  value: _departmentHeadEffectiveTo,
                  onTap: () => _pickDepartmentHeadDate(isStart: false),
                  allowClear: _departmentHeadEffectiveTo != null,
                  onClear: () => _updatePositionFormState(
                    () => _departmentHeadEffectiveTo = null,
                  ),
                ),
              ),
            ],
          ),
        ],
        if (_departmentHeadPeriods.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(
            'Designation history',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _mutedColor(context),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _departmentHeadPeriods.map((period) {
              final from = period['effective_from']?.toString() ?? 'Unknown';
              final to = period['effective_to']?.toString() ?? 'Onward';
              final active = period['is_active'] == true;
              return Chip(
                avatar: Icon(
                  active
                      ? Icons.event_available_rounded
                      : Icons.event_busy_rounded,
                  size: 16,
                ),
                label: Text('$from to $to'),
                visualDensity: VisualDensity.compact,
              );
            }).toList(),
          ),
        ],
        const SizedBox(height: 20),
        Text(
          'Description',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: _mutedColor(context),
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: _descriptionController,
          style: AppTheme.dashFieldTextStyle(context),
          decoration: _inputDecoration('Description'),
          maxLines: 4,
        ),
        if (showActions) ...[
          const SizedBox(height: 28),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                onPressed: () => _addPosition(),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add Position'),
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
              OutlinedButton.icon(
                onPressed: _selectedPosition != null
                    ? () => _updatePosition()
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
              FilledButton.icon(
                onPressed: _selectedPosition != null
                    ? () => _deactivatePosition()
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
      padding: const EdgeInsets.all(24),
      decoration: AppTheme.dashSurfaceCard(context, radius: 12),
      child: content,
    );
  }

  InputDecoration _inputDecoration(String hint) => AppTheme.dashInputDecoration(
    context,
    hintText: hint,
    radius: 8,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
  );

  Widget _buildDepartmentHeadDateField({
    required String label,
    required DateTime? value,
    required VoidCallback onTap,
    required bool allowClear,
    required VoidCallback onClear,
  }) {
    return Column(
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
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: InputDecorator(
            decoration: _inputDecoration(label).copyWith(
              prefixIcon: const Icon(Icons.calendar_today_rounded, size: 18),
              suffixIcon: allowClear
                  ? IconButton(
                      tooltip: 'Clear date',
                      onPressed: onClear,
                      icon: const Icon(Icons.close_rounded, size: 18),
                    )
                  : null,
            ),
            child: Text(
              _displayDate(value),
              style: AppTheme.dashFieldTextStyle(context),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
    );
  }
}
