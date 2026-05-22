import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../api/client.dart';
import '../../landingpage/constants/app_theme.dart';

/// Department record for display/CRUD.
class _DepartmentRecord {
  const _DepartmentRecord({
    required this.id,
    required this.name,
    this.departmentNumber,
    this.description,
    required this.isActive,
  });
  final String id;
  final String name;
  final int? departmentNumber;
  final String? description;
  final bool isActive;

  String get displayDepartmentNo => departmentNumber != null
      ? 'DEPT-${departmentNumber!.toString().padLeft(3, '0')}'
      : '—';
}

/// Department management screen: list with search/status filter + form for Add/Update/Deactivate.
class ManageDepartment extends StatefulWidget {
  const ManageDepartment({super.key});

  @override
  State<ManageDepartment> createState() => _ManageDepartmentState();
}

class _ManageDepartmentState extends State<ManageDepartment> {
  final _searchController = TextEditingController();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();

  String _statusFilter = 'Active';
  List<_DepartmentRecord> _departments = [];
  bool _loading = false;
  _DepartmentRecord? _selectedDepartment;
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

  void _updateDepartmentFormState(VoidCallback update) {
    if (mounted) setState(update);
    _drawerSetState?.call(() {});
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadDepartments());
  }

  @override
  void dispose() {
    _searchController.dispose();
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _loadDepartments() async {
    setState(() => _loading = true);
    try {
      final res = await ApiClient.instance.get<List<dynamic>>(
        '/api/departments',
        queryParameters: {'status': _statusFilter},
      );
      final data = res.data ?? [];
      _departments = (data).map((e) {
        final m = e as Map<String, dynamic>;
        final numVal = m['department_number'];
        return _DepartmentRecord(
          id: m['id'] as String,
          name: m['name'] as String? ?? '',
          departmentNumber: numVal is int
              ? numVal
              : (numVal != null ? int.tryParse(numVal.toString()) : null),
          description: m['description'] as String?,
          isActive: m['is_active'] as bool? ?? true,
        );
      }).toList();
    } on DioException catch (e) {
      debugPrint('Load departments failed: ${e.response?.data ?? e.message}');
      _departments = [];
    } catch (e) {
      debugPrint('Load departments failed: $e');
      _departments = [];
    }
    if (mounted) setState(() => _loading = false);
  }

  void _selectDepartment(_DepartmentRecord d) {
    _updateDepartmentFormState(() {
      _selectedDepartment = d;
      _nameController.text = d.name;
      _descriptionController.text = d.description ?? '';
    });
  }

  void _clearForm() {
    _updateDepartmentFormState(() {
      _selectedDepartment = null;
      _nameController.clear();
      _descriptionController.clear();
    });
  }

  Future<bool> _addDepartment() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a department name.')),
      );
      return false;
    }
    try {
      await ApiClient.instance.post(
        '/api/departments',
        data: {
          'name': name,
          'description': _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
          'is_active': true,
        },
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Department added.')));
        _clearForm();
        _loadDepartments();
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
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to add: $e')));
      }
      return false;
    }
  }

  Future<bool> _updateDepartment() async {
    final d = _selectedDepartment;
    if (d == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a department to update.')),
      );
      return false;
    }
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a department name.')),
      );
      return false;
    }
    try {
      await ApiClient.instance.put(
        '/api/departments/${d.id}',
        data: {
          'name': name,
          'description': _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
        },
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Department updated.')));
        _clearForm();
        _loadDepartments();
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
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to update: $e')));
      }
      return false;
    }
  }

  Future<bool> _deactivateDepartment() async {
    final d = _selectedDepartment;
    if (d == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a department to deactivate.')),
      );
      return false;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Deactivate department?'),
        content: Text(
          'This will deactivate "${d.name}". It will no longer appear in active lists.',
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
        '/api/departments/${d.id}',
        data: {'is_active': false},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${d.name} has been deactivated.')),
        );
        _clearForm();
        _loadDepartments();
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
        ).showSnackBar(SnackBar(content: Text('Failed to deactivate: $msg')));
      }
      return false;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to deactivate: $e')));
      }
      return false;
    }
  }

  Future<void> _openDepartmentDrawer({_DepartmentRecord? department}) async {
    if (department == null) {
      _clearForm();
    } else {
      _selectDepartment(department);
    }

    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
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
                  return _buildDepartmentDrawer(dialogContext);
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

    _drawerSetState = null;
  }

  Widget _buildDepartmentDrawer(BuildContext drawerContext) {
    final isEditing = _selectedDepartment != null;
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
                    isEditing ? 'Edit Department' : 'Add Department',
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
    final isEditing = _selectedDepartment != null;
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
                final ok = await _deactivateDepartment();
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
                  ? await _updateDepartment()
                  : await _addDepartment();
              if (ok && drawerContext.mounted) {
                Navigator.of(drawerContext).pop();
              }
            },
            icon: Icon(
              isEditing ? Icons.edit_rounded : Icons.add_rounded,
              size: 18,
            ),
            label: Text(isEditing ? 'Update' : 'Add Department'),
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
                'Department',
                style: TextStyle(
                  color: _headingColor(context),
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            FilledButton.icon(
              onPressed: () => _openDepartmentDrawer(),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add Department'),
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
        ? _departments
        : _departments.where((d) {
            final n = d.name.toLowerCase();
            final desc = (d.description ?? '').toLowerCase();
            return n.contains(search) || desc.contains(search);
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
              SizedBox(width: 200, child: _buildSearchField()),
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
                SizedBox(width: 88, child: _tableHeaderText('No.')),
                Expanded(child: _tableHeaderText('Name')),
                Expanded(flex: 2, child: _tableHeaderText('Description')),
              ],
            ),
          ),
          if (_loading)
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 160),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: const CircularProgressIndicator(),
            )
          else if (filtered.isEmpty)
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 120),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Text(
                'No departments',
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
                2: FlexColumnWidth(2),
              },
              children: filtered.map((d) {
                final isSelected = _selectedDepartment?.id == d.id;
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
                      d.displayDepartmentNo,
                      onTap: () => _openDepartmentDrawer(department: d),
                    ),
                    _tableCell(
                      d.name,
                      onTap: () => _openDepartmentDrawer(department: d),
                    ),
                    _tableCell(
                      d.description ?? '—',
                      onTap: () => _openDepartmentDrawer(department: d),
                      secondary: true,
                    ),
                  ],
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _tableHeaderText(String text) {
    return Text(
      text,
      style: TextStyle(
        fontWeight: FontWeight.w700,
        fontSize: 13,
        color: _headingColor(context),
      ),
      overflow: TextOverflow.ellipsis,
      maxLines: 1,
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
          _loadDepartments();
        },
      ),
    );
  }

  Widget _buildFormPanel({bool framed = true, bool showActions = true}) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Department Name',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: _mutedColor(context),
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: _nameController,
          style: AppTheme.dashFieldTextStyle(context),
          decoration: _inputDecoration('Department Name'),
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
                onPressed: () => _addDepartment(),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add Department'),
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
                onPressed: _selectedDepartment != null
                    ? () => _updateDepartment()
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
                onPressed: _selectedDepartment != null
                    ? () => _deactivateDepartment()
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
