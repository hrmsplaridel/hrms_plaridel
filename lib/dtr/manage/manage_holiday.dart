import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../api/client.dart';
import '../../landingpage/constants/app_theme.dart';

class _HolidayRecord {
  const _HolidayRecord({
    required this.id,
    required this.holidayDate,
    required this.name,
    required this.holidayType,
    this.description,
    this.isActive = true,
  });
  final String id;
  final DateTime holidayDate;
  final String name;
  final String holidayType;
  final String? description;
  final bool isActive;
}

class ManageHoliday extends StatefulWidget {
  const ManageHoliday({super.key});

  @override
  State<ManageHoliday> createState() => _ManageHolidayState();
}

class _ManageHolidayState extends State<ManageHoliday> {
  final _searchController = TextEditingController();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  DateTime? _selectedDate;
  String _holidayType = 'regular';
  bool _isActive = true;

  List<_HolidayRecord> _holidays = [];
  bool _loading = false;
  _HolidayRecord? _selectedHoliday;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadHolidays());
  }

  @override
  void dispose() {
    _searchController.dispose();
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _loadHolidays() async {
    setState(() => _loading = true);
    try {
      final res = await ApiClient.instance.get<List<dynamic>>('/api/holidays');
      final data = res.data ?? [];
      _holidays = (data).map((e) {
        final m = e as Map<String, dynamic>;
        final d = m['holiday_date'];
        return _HolidayRecord(
          id: m['id'] as String,
          holidayDate: d != null ? DateTime.parse(d.toString()) : DateTime.now(),
          name: m['name'] as String? ?? '',
          holidayType: m['holiday_type'] as String? ?? 'regular',
          description: m['description'] as String?,
          isActive: m['is_active'] as bool? ?? true,
        );
      }).toList();
    } on DioException catch (e) {
      debugPrint('Load holidays failed: ${e.response?.data ?? e.message}');
      _holidays = [];
    }
    if (mounted) setState(() => _loading = false);
  }

  void _selectHoliday(_HolidayRecord h) {
    setState(() {
      _selectedHoliday = h;
      _nameController.text = h.name;
      _descriptionController.text = h.description ?? '';
      _selectedDate = h.holidayDate;
      _holidayType = h.holidayType;
      _isActive = h.isActive;
    });
  }

  void _clearForm() {
    setState(() {
      _selectedHoliday = null;
      _nameController.clear();
      _descriptionController.clear();
      _selectedDate = null;
      _holidayType = 'regular';
      _isActive = true;
    });
  }

  Future<void> _addHoliday() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a holiday name.')),
      );
      return;
    }
    if (_selectedDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a date.')),
      );
      return;
    }
    try {
      await ApiClient.instance.post(
        '/api/holidays',
        data: {
          'holiday_date': _selectedDate!.toIso8601String().split('T').first,
          'name': name,
          'holiday_type': _holidayType,
          'description': _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim(),
          'is_active': _isActive,
        },
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Holiday added.')));
        _clearForm();
        _loadHolidays();
      }
    } on DioException catch (e) {
      if (mounted) {
        final msg = (e.response?.data as Map?)?['error'] ?? e.message ?? 'Failed to add';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to add: $msg')));
      }
    }
  }

  Future<void> _updateHoliday() async {
    final h = _selectedHoliday;
    if (h == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a holiday to update.')),
      );
      return;
    }
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a holiday name.')),
      );
      return;
    }
    if (_selectedDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a date.')),
      );
      return;
    }
    try {
      await ApiClient.instance.put(
        '/api/holidays/${h.id}',
        data: {
          'holiday_date': _selectedDate!.toIso8601String().split('T').first,
          'name': name,
          'holiday_type': _holidayType,
          'description': _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim(),
          'is_active': _isActive,
        },
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Holiday updated.')));
        _clearForm();
        _loadHolidays();
      }
    } on DioException catch (e) {
      if (mounted) {
        final msg = (e.response?.data as Map?)?['error'] ?? e.message ?? 'Failed to update';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to update: $msg')));
      }
    }
  }

  Future<void> _deleteHoliday() async {
    final h = _selectedHoliday;
    if (h == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete holiday?'),
        content: Text('Remove "${h.name}" from the list?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ApiClient.instance.delete('/api/holidays/${h.id}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Holiday deleted.')));
        _clearForm();
        _loadHolidays();
      }
    } on DioException catch (e) {
      if (mounted) {
        final msg = (e.response?.data as Map?)?['error'] ?? e.message ?? 'Failed to delete';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to delete: $msg')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final isNarrow = w < 700;
    final search = _searchController.text.toLowerCase();
    final filtered = _holidays.where((h) =>
        h.name.toLowerCase().contains(search) ||
        h.holidayDate.toString().contains(search)).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Holiday Management',
          style: TextStyle(color: AppTheme.textPrimary, fontSize: 24, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 20),
        isNarrow
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [_buildListPanel(filtered), const SizedBox(height: 24), _buildFormPanel()],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 1, child: _buildListPanel(filtered)),
                  const SizedBox(width: 24),
                  Expanded(flex: 1, child: _buildFormPanel()),
                ],
              ),
      ],
    );
  }

  Widget _buildListPanel(List<_HolidayRecord> filtered) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 16, offset: const Offset(0, 4))],
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Search by name or date',
              hintStyle: TextStyle(color: AppTheme.textSecondary.withOpacity(0.8), fontSize: 14),
              prefixIcon: Icon(Icons.search_rounded, size: 20, color: AppTheme.textSecondary.withOpacity(0.7)),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              filled: true,
              fillColor: AppTheme.lightGray.withOpacity(0.5),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 16),
          if (_loading)
            const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()))
          else if (filtered.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text('No holidays', style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              itemCount: filtered.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final h = filtered[i];
                final isSelected = _selectedHoliday?.id == h.id;
                return ListTile(
                  selected: isSelected,
                  selectedTileColor: AppTheme.primaryNavy.withOpacity(0.08),
                  title: Text(h.name, style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                  subtitle: Text(
                    '${h.holidayDate.year}-${h.holidayDate.month.toString().padLeft(2, '0')}-${h.holidayDate.day.toString().padLeft(2, '0')} · ${h.holidayType}',
                    style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                  ),
                  onTap: () => _selectHoliday(h),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildFormPanel() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 16, offset: const Offset(0, 4))],
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Holiday name', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textSecondary)),
          const SizedBox(height: 6),
          TextFormField(
            controller: _nameController,
            decoration: InputDecoration(
              hintText: 'e.g. New Year\'s Day',
              filled: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
          const SizedBox(height: 16),
          Text('Date', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textSecondary)),
          const SizedBox(height: 6),
          InkWell(
            onTap: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: _selectedDate ?? DateTime.now(),
                firstDate: DateTime(2020),
                lastDate: DateTime(2030),
              );
              if (d != null) setState(() => _selectedDate = d);
            },
            child: InputDecorator(
              decoration: InputDecoration(
                filled: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: Text(
                _selectedDate != null
                    ? '${_selectedDate!.year}-${_selectedDate!.month.toString().padLeft(2, '0')}-${_selectedDate!.day.toString().padLeft(2, '0')}'
                    : 'Select date',
                style: TextStyle(color: _selectedDate != null ? AppTheme.textPrimary : AppTheme.textSecondary),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Type', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textSecondary)),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            value: _holidayType,
            decoration: InputDecoration(
              filled: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
            items: ['regular', 'special', 'local'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
            onChanged: (v) => setState(() => _holidayType = v ?? 'regular'),
          ),
          const SizedBox(height: 16),
          Text('Description (optional)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textSecondary)),
          const SizedBox(height: 6),
          TextFormField(
            controller: _descriptionController,
            decoration: InputDecoration(
              hintText: 'Short description',
              filled: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
            maxLines: 2,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Checkbox(
                value: _isActive,
                onChanged: (v) => setState(() => _isActive = v ?? true),
                activeColor: AppTheme.primaryNavy,
              ),
              const Text('Active'),
            ],
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                onPressed: _addHoliday,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add Holiday'),
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF4CAF50), foregroundColor: Colors.white),
              ),
              OutlinedButton.icon(
                onPressed: _selectedHoliday != null ? _updateHoliday : null,
                icon: const Icon(Icons.edit_rounded, size: 18),
                label: const Text('Update'),
              ),
              FilledButton.icon(
                onPressed: _selectedHoliday != null ? _deleteHoliday : null,
                icon: const Icon(Icons.delete_rounded, size: 18),
                label: const Text('Delete'),
                style: FilledButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
