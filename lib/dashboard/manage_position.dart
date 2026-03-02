import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../landingpage/constants/app_theme.dart';

/// Position record for display/CRUD.
class _PositionRecord {
  const _PositionRecord({
    required this.id,
    required this.name,
    this.description,
    this.departmentId,
    this.departmentName,
    required this.isActive,
  });
  final String id;
  final String name;
  final String? description;
  final String? departmentId;
  final String? departmentName;
  final bool isActive;
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
      final res = await Supabase.instance.client
          .from('departments')
          .select('id, name')
          .or('is_active.is.null,is_active.eq.true')
          .order('name');
      _departments = List<Map<String, dynamic>>.from(res);
    } catch (e) {
      debugPrint('Load departments failed: $e');
      _departments = [];
    }
    if (mounted) setState(() {});
  }

  Future<void> _loadPositions() async {
    setState(() => _loading = true);
    try {
      var query = Supabase.instance.client
          .from('positions')
          .select(
            'id, name, description, department_id, is_active, departments(name)',
          );

      if (_statusFilter == 'Active') {
        query = query.or('is_active.is.null,is_active.eq.true');
      } else if (_statusFilter == 'Inactive') {
        query = query.eq('is_active', false);
      }

      if (_departmentFilterId != null) {
        query = query.eq('department_id', _departmentFilterId!);
      }

      final res = await query.order('name');
      _positions = (res as List).map((e) {
        final m = e as Map<String, dynamic>;
        final dept = m['departments'];
        return _PositionRecord(
          id: m['id'] as String,
          name: m['name'] as String? ?? '',
          description: m['description'] as String?,
          departmentId: m['department_id'] as String?,
          departmentName: (dept is Map ? dept['name'] : null) as String?,
          isActive: m['is_active'] as bool? ?? true,
        );
      }).toList();
    } catch (e) {
      debugPrint('Load positions failed: $e');
      _positions = [];
    }
    if (mounted) setState(() => _loading = false);
  }

  void _selectPosition(_PositionRecord p) {
    setState(() {
      _selectedPosition = p;
      _titleController.text = p.name;
      _descriptionController.text = p.description ?? '';
      _selectedDepartmentId = p.departmentId;
    });
  }

  void _clearForm() {
    setState(() {
      _selectedPosition = null;
      _titleController.clear();
      _descriptionController.clear();
      _selectedDepartmentId = null;
    });
  }

  Future<void> _addPosition() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a position title.')),
      );
      return;
    }
    try {
      await Supabase.instance.client.from('positions').insert({
        'name': title,
        'description': _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        'department_id': _selectedDepartmentId,
        'is_active': true,
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Position added.')));
        _clearForm();
        _loadPositions();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to add: $e')));
      }
    }
  }

  Future<void> _updatePosition() async {
    final p = _selectedPosition;
    if (p == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a position to update.')),
      );
      return;
    }
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a position title.')),
      );
      return;
    }
    try {
      await Supabase.instance.client
          .from('positions')
          .update({
            'name': title,
            'description': _descriptionController.text.trim().isEmpty
                ? null
                : _descriptionController.text.trim(),
            'department_id': _selectedDepartmentId,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', p.id);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Position updated.')));
        _clearForm();
        _loadPositions();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to update: $e')));
      }
    }
  }

  Future<void> _deactivatePosition() async {
    final p = _selectedPosition;
    if (p == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a position to deactivate.')),
      );
      return;
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
    if (ok != true || !mounted) return;
    try {
      await Supabase.instance.client
          .from('positions')
          .update({
            'is_active': false,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', p.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${p.name} has been deactivated.')),
        );
        _clearForm();
        _loadPositions();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to deactivate: $e')));
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
          'Position',
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
        Expanded(flex: 1, child: _buildRightPanel()),
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
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
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
              color: AppTheme.lightGray.withOpacity(0.4),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 60,
                  child: Text(
                    'ID',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: AppTheme.textPrimary,
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
                      color: AppTheme.textPrimary,
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
                      color: AppTheme.textPrimary,
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
                  color: AppTheme.textSecondary.withOpacity(0.8),
                  fontSize: 14,
                ),
              ),
            )
          else
            ...filtered.map((p) {
              final isSelected = _selectedPosition?.id == p.id;
              return Material(
                color: isSelected
                    ? AppTheme.primaryNavy.withOpacity(0.08)
                    : Colors.transparent,
                child: InkWell(
                  onTap: () => _selectPosition(p),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 60,
                          child: Text(
                            p.id.length > 8
                                ? '${p.id.substring(0, 8)}...'
                                : p.id,
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 1,
                          child: Text(
                            p.name,
                            style: TextStyle(
                              fontSize: 13,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            p.description ?? '—',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.textSecondary,
                              overflow: TextOverflow.ellipsis,
                            ),
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
          color: AppTheme.textSecondary.withOpacity(0.8),
          fontSize: 14,
        ),
        prefixIcon: Icon(
          Icons.search_rounded,
          size: 20,
          color: AppTheme.textSecondary.withOpacity(0.7),
        ),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        filled: true,
        fillColor: AppTheme.lightGray.withOpacity(0.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _buildDepartmentFilterDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.lightGray.withOpacity(0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.transparent),
      ),
      child: DropdownButton<String?>(
        value: _departmentFilterId,
        underline: const SizedBox.shrink(),
        isDense: true,
        items: [
          const DropdownMenuItem(value: null, child: Text('All')),
          ..._departments.map(
            (d) => DropdownMenuItem(
              value: d['id'] as String?,
              child: Text(d['name'] as String? ?? ''),
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
      decoration: BoxDecoration(
        color: AppTheme.lightGray.withOpacity(0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.transparent),
      ),
      child: DropdownButton<String>(
        value: _statusFilter,
        underline: const SizedBox.shrink(),
        isDense: true,
        items: [
          'Active',
          'Inactive',
          'All',
        ].map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
        onChanged: (v) {
          setState(() => _statusFilter = v ?? 'Active');
          _loadPositions();
        },
      ),
    );
  }

  Widget _buildRightPanel() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Position Title',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: _titleController,
            decoration: _inputDecoration('Position Title'),
          ),
          const SizedBox(height: 20),
          Text(
            'Department',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            initialValue: _selectedDepartmentId,
            decoration: _inputDecoration('Select'),
            hint: const Text('Select'),
            items: [
              const DropdownMenuItem(value: null, child: Text('Select')),
              ..._departments.map(
                (d) => DropdownMenuItem(
                  value: d['id'] as String?,
                  child: Text(d['name'] as String? ?? ''),
                ),
              ),
            ],
            onChanged: (v) => setState(() => _selectedDepartmentId = v),
          ),
          const SizedBox(height: 20),
          Text(
            'Description',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: _descriptionController,
            decoration: _inputDecoration('Description'),
            maxLines: 4,
          ),
          const SizedBox(height: 28),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                onPressed: _addPosition,
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
                onPressed: _selectedPosition != null ? _updatePosition : null,
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
                    ? _deactivatePosition
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

  InputDecoration _inputDecoration(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(
      color: AppTheme.textSecondary.withOpacity(0.7),
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
