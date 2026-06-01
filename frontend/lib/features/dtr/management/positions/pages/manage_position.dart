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
    required this.isActive,
    this.positionNumber,
  });
  final String id;
  final String name;
  final String? description;
  final String? departmentId;
  final String? departmentName;
  final bool isActive;
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
  final _searchController = TextEditingController();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();

  String? _departmentFilterId;
  String _statusFilter = 'Active';
  List<_PositionRecord> _positions = [];
  List<Map<String, dynamic>> _departments = [];
  bool _loading = false;
  _PositionRecord? _selectedPosition;
  String? _selectedDepartmentId;
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
    setState(() => _loading = true);
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
          isActive: m['is_active'] as bool? ?? true,
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
    });
  }

  void _clearForm() {
    _updatePositionFormState(() {
      _selectedPosition = null;
      _titleController.clear();
      _descriptionController.clear();
      _selectedDepartmentId = null;
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
    try {
      await ApiClient.instance.post(
        '/api/positions',
        data: {
          'name': title,
          'description': _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
          'department_id': _selectedDepartmentId,
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
            content: Text('Failed to add: ${e.response?.data ?? e.message}'),
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
    try {
      await ApiClient.instance.put(
        '/api/positions/${p.id}',
        data: {
          'name': title,
          'description': _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
          'department_id': _selectedDepartmentId,
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
            content: Text('Failed to update: ${e.response?.data ?? e.message}'),
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
            content: Text(
              'Failed to deactivate: ${e.response?.data ?? e.message}',
            ),
          ),
        );
      }
      return false;
    }
  }

  Future<void> _openPositionDrawer({_PositionRecord? position}) async {
    _drawerSetState = null;
    if (position == null) {
      _clearForm();
    } else {
      _selectPosition(position);
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
    } finally {
      _drawerSetState = null;
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
          TextButton(
            onPressed: () => Navigator.of(drawerContext).pop(),
            child: const Text('Cancel'),
          ),
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
                SizedBox(
                  width: 96,
                  child: Text(
                    'Action',
                    textAlign: TextAlign.right,
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
            Table(
              columnWidths: const {
                0: FixedColumnWidth(88),
                1: FlexColumnWidth(),
                2: FlexColumnWidth(),
                3: FlexColumnWidth(2),
                4: FixedColumnWidth(96),
              },
              children: filtered.map((p) {
                final isSelected = _selectedPosition?.id == p.id;
                return TableRow(
                  decoration: BoxDecoration(
                    color: isSelected
                        ? (dark
                              ? AppTheme.primaryNavy.withValues(alpha: 0.35)
                              : AppTheme.primaryNavy.withValues(alpha: 0.08))
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
                    _actionCell(p),
                  ],
                );
              }).toList(),
            ),
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

  Widget _actionCell(_PositionRecord position) {
    return TableCell(
      verticalAlignment: TableCellVerticalAlignment.middle,
      child: Align(
        alignment: Alignment.centerRight,
        child: IconButton(
          onPressed: () => _openPositionDrawer(position: position),
          icon: const Icon(Icons.open_in_new_rounded, size: 18),
          tooltip: 'Open position',
          color: const Color(0xFFE85D04),
        ),
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
          setState(() => _departmentFilterId = v);
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
          setState(() => _statusFilter = v ?? 'Active');
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
          onChanged: (v) =>
              _updatePositionFormState(() => _selectedDepartmentId = v),
        ),
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
}
