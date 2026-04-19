import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../api/client.dart';
import '../../landingpage/constants/app_theme.dart';

/// Office record for display/CRUD.
class _OfficeRecord {
  const _OfficeRecord({
    required this.id,
    required this.name,
    this.officeNumber,
    this.description,
    required this.isActive,
  });
  final String id;
  final String name;
  final int? officeNumber;
  final String? description;
  final bool isActive;

  String get displayOfficeNo => officeNumber != null
      ? 'OFF-${officeNumber!.toString().padLeft(3, '0')}'
      : '—';
}

/// Office management (branch/site). Used by DocuTracker office routing and users.office_id.
class ManageOffice extends StatefulWidget {
  const ManageOffice({super.key});

  @override
  State<ManageOffice> createState() => _ManageOfficeState();
}

class _ManageOfficeState extends State<ManageOffice> {
  final _searchController = TextEditingController();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();

  String _statusFilter = 'Active';
  List<_OfficeRecord> _offices = [];
  bool _loading = false;
  _OfficeRecord? _selectedOffice;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadOffices());
  }

  @override
  void dispose() {
    _searchController.dispose();
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _loadOffices() async {
    setState(() => _loading = true);
    try {
      final res = await ApiClient.instance.get<List<dynamic>>(
        '/api/offices',
        queryParameters: {'status': _statusFilter},
      );
      final data = res.data ?? [];
      _offices = (data).map((e) {
        final m = e as Map<String, dynamic>;
        final numVal = m['office_number'];
        return _OfficeRecord(
          id: m['id'] as String,
          name: m['name'] as String? ?? '',
          officeNumber: numVal is int
              ? numVal
              : (numVal != null ? int.tryParse(numVal.toString()) : null),
          description: m['description'] as String?,
          isActive: m['is_active'] as bool? ?? true,
        );
      }).toList();
    } on DioException catch (e) {
      debugPrint('Load offices failed: ${e.response?.data ?? e.message}');
      _offices = [];
    } catch (e) {
      debugPrint('Load offices failed: $e');
      _offices = [];
    }
    if (mounted) setState(() => _loading = false);
  }

  void _selectOffice(_OfficeRecord d) {
    setState(() {
      _selectedOffice = d;
      _nameController.text = d.name;
      _descriptionController.text = d.description ?? '';
    });
  }

  void _clearForm() {
    setState(() {
      _selectedOffice = null;
      _nameController.clear();
      _descriptionController.clear();
    });
  }

  Future<void> _addOffice() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter an office name.')),
      );
      return;
    }
    try {
      await ApiClient.instance.post(
        '/api/offices',
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
        ).showSnackBar(const SnackBar(content: Text('Office added.')));
        _clearForm();
        _loadOffices();
      }
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
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to add: $e')));
      }
    }
  }

  Future<void> _updateOffice() async {
    final d = _selectedOffice;
    if (d == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select an office to update.')),
      );
      return;
    }
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter an office name.')),
      );
      return;
    }
    try {
      await ApiClient.instance.put(
        '/api/offices/${d.id}',
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
        ).showSnackBar(const SnackBar(content: Text('Office updated.')));
        _clearForm();
        _loadOffices();
      }
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
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to update: $e')));
      }
    }
  }

  Future<void> _deactivateOffice() async {
    final d = _selectedOffice;
    if (d == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select an office to deactivate.')),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Deactivate office?'),
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
      await ApiClient.instance.put(
        '/api/offices/${d.id}',
        data: {'is_active': false},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${d.name} has been deactivated.')),
        );
        _clearForm();
        _loadOffices();
      }
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
          'Office',
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
        ? _offices
        : _offices.where((d) {
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
                'No offices',
                style: TextStyle(
                  color: AppTheme.textSecondary.withOpacity(0.8),
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
                final isSelected = _selectedOffice?.id == d.id;
                return TableRow(
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppTheme.primaryNavy.withOpacity(0.08)
                        : null,
                  ),
                  children: [
                    _tableCell(
                      d.displayOfficeNo,
                      onTap: () => _selectOffice(d),
                    ),
                    _tableCell(d.name, onTap: () => _selectOffice(d)),
                    _tableCell(
                      d.description ?? '—',
                      onTap: () => _selectOffice(d),
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
        color: AppTheme.textPrimary,
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
              color: secondary ? AppTheme.textSecondary : AppTheme.textPrimary,
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
          _loadOffices();
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
            'Office name',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: _nameController,
            decoration: _inputDecoration('Office name'),
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
                onPressed: _addOffice,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add office'),
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
                onPressed: _selectedOffice != null
                    ? _updateOffice
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
                onPressed: _selectedOffice != null
                    ? _deactivateOffice
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
