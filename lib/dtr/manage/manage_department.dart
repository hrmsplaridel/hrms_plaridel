import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../landingpage/constants/app_theme.dart';

/// Department record for display/CRUD.
class _DepartmentRecord {
  const _DepartmentRecord({
    required this.id,
    required this.name,
    this.description,
    required this.isActive,
  });
  final String id;
  final String name;
  final String? description;
  final bool isActive;
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
      var query = Supabase.instance.client
          .from('departments')
          .select('id, name, description, is_active');

      if (_statusFilter == 'Active') {
        query = query.or('is_active.is.null,is_active.eq.true');
      } else if (_statusFilter == 'Inactive') {
        query = query.eq('is_active', false);
      }

      final res = await query.order('name');
      _departments = (res as List).map((e) {
        final m = e as Map<String, dynamic>;
        return _DepartmentRecord(
          id: m['id'] as String,
          name: m['name'] as String? ?? '',
          description: m['description'] as String?,
          isActive: m['is_active'] as bool? ?? true,
        );
      }).toList();
    } catch (e) {
      debugPrint('Load departments failed: $e');
      _departments = [];
    }
    if (mounted) setState(() => _loading = false);
  }

  void _selectDepartment(_DepartmentRecord d) {
    setState(() {
      _selectedDepartment = d;
      _nameController.text = d.name;
      _descriptionController.text = d.description ?? '';
    });
  }

  void _clearForm() {
    setState(() {
      _selectedDepartment = null;
      _nameController.clear();
      _descriptionController.clear();
    });
  }

  Future<void> _addDepartment() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a department name.')),
      );
      return;
    }
    try {
      await Supabase.instance.client.from('departments').insert({
        'name': name,
        'description': _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        'is_active': true,
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Department added.')));
        _clearForm();
        _loadDepartments();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to add: $e')));
      }
    }
  }

  Future<void> _updateDepartment() async {
    final d = _selectedDepartment;
    if (d == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a department to update.')),
      );
      return;
    }
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a department name.')),
      );
      return;
    }
    try {
      await Supabase.instance.client
          .from('departments')
          .update({
            'name': name,
            'description': _descriptionController.text.trim().isEmpty
                ? null
                : _descriptionController.text.trim(),
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', d.id);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Department updated.')));
        _clearForm();
        _loadDepartments();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to update: $e')));
      }
    }
  }

  Future<void> _deactivateDepartment() async {
    final d = _selectedDepartment;
    if (d == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a department to deactivate.')),
      );
      return;
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
    if (ok != true || !mounted) return;
    try {
      await Supabase.instance.client
          .from('departments')
          .update({
            'is_active': false,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', d.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${d.name} has been deactivated.')),
        );
        _clearForm();
        _loadDepartments();
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
          'Department',
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
        ? _departments
        : _departments.where((d) {
            final n = d.name.toLowerCase();
            final desc = (d.description ?? '').toLowerCase();
            return n.contains(search) || desc.contains(search);
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
              SizedBox(width: 200, child: _buildSearchField()),
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
                    'Name',
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
                'No departments',
                style: TextStyle(
                  color: AppTheme.textSecondary.withOpacity(0.8),
                  fontSize: 14,
                ),
              ),
            )
          else
            ...filtered.map((d) {
              final isSelected = _selectedDepartment?.id == d.id;
              return Material(
                color: isSelected
                    ? AppTheme.primaryNavy.withOpacity(0.08)
                    : Colors.transparent,
                child: InkWell(
                  onTap: () => _selectDepartment(d),
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
                            d.id.length > 8
                                ? '${d.id.substring(0, 8)}...'
                                : d.id,
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 1,
                          child: Text(
                            d.name,
                            style: TextStyle(
                              fontSize: 13,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            d.description ?? '—',
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
          _loadDepartments();
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
            'Department Name',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: _nameController,
            decoration: _inputDecoration('Department Name'),
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
                onPressed: _addDepartment,
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
                    ? _updateDepartment
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
                    ? _deactivateDepartment
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
