import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../api/client.dart';
import '../../landingpage/constants/app_theme.dart';

class _PolicyRecord {
  const _PolicyRecord({
    required this.id,
    required this.name,
    this.description,
    required this.gracePeriodMinutes,
    this.maxLatePerMonthMinutes,
    this.lateDeductionRule,
    this.absentDeductionRule,
    this.undertimeRule,
    required this.isDefault,
    required this.isActive,
  });
  final String id;
  final String name;
  final String? description;
  final int gracePeriodMinutes;
  final int? maxLatePerMonthMinutes;
  final String? lateDeductionRule;
  final String? absentDeductionRule;
  final String? undertimeRule;
  final bool isDefault;
  final bool isActive;
}

class ManageAttendancePolicy extends StatefulWidget {
  const ManageAttendancePolicy({super.key});

  @override
  State<ManageAttendancePolicy> createState() => _ManageAttendancePolicyState();
}

class _ManageAttendancePolicyState extends State<ManageAttendancePolicy> {
  final _searchController = TextEditingController();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _graceController = TextEditingController(text: '0');
  final _maxLateController = TextEditingController();
  final _lateRuleController = TextEditingController();
  final _absentRuleController = TextEditingController();
  final _undertimeRuleController = TextEditingController();

  String _statusFilter = 'Active';
  List<_PolicyRecord> _policies = [];
  bool _loading = false;
  _PolicyRecord? _selectedPolicy;
  bool _isDefault = false;
  bool _isActive = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadPolicies());
  }

  @override
  void dispose() {
    _searchController.dispose();
    _nameController.dispose();
    _descriptionController.dispose();
    _graceController.dispose();
    _maxLateController.dispose();
    _lateRuleController.dispose();
    _absentRuleController.dispose();
    _undertimeRuleController.dispose();
    super.dispose();
  }

  Future<void> _loadPolicies() async {
    setState(() => _loading = true);
    try {
      final res = await ApiClient.instance.get<List<dynamic>>(
        '/api/attendance-policies',
        queryParameters: {'status': _statusFilter},
      );
      final data = res.data ?? [];
      _policies = (data).map((e) {
        final m = e as Map<String, dynamic>;
        return _PolicyRecord(
          id: m['id'] as String,
          name: m['name'] as String? ?? '',
          description: m['description'] as String?,
          gracePeriodMinutes: (m['grace_period_minutes'] as num?)?.toInt() ?? 0,
          maxLatePerMonthMinutes: (m['max_late_per_month_minutes'] as num?)?.toInt(),
          lateDeductionRule: m['late_deduction_rule'] as String?,
          absentDeductionRule: m['absent_deduction_rule'] as String?,
          undertimeRule: m['undertime_rule'] as String?,
          isDefault: m['is_default'] as bool? ?? false,
          isActive: m['is_active'] as bool? ?? true,
        );
      }).toList();
    } on DioException catch (e) {
      debugPrint('Load policies failed: ${e.response?.data ?? e.message}');
      _policies = [];
    }
    if (mounted) setState(() => _loading = false);
  }

  void _selectPolicy(_PolicyRecord p) {
    setState(() {
      _selectedPolicy = p;
      _nameController.text = p.name;
      _descriptionController.text = p.description ?? '';
      _graceController.text = p.gracePeriodMinutes.toString();
      _maxLateController.text = p.maxLatePerMonthMinutes?.toString() ?? '';
      _lateRuleController.text = p.lateDeductionRule ?? '';
      _absentRuleController.text = p.absentDeductionRule ?? '';
      _undertimeRuleController.text = p.undertimeRule ?? '';
      _isDefault = p.isDefault;
      _isActive = p.isActive;
    });
  }

  void _clearForm() {
    setState(() {
      _selectedPolicy = null;
      _nameController.clear();
      _descriptionController.clear();
      _graceController.text = '0';
      _maxLateController.clear();
      _lateRuleController.clear();
      _absentRuleController.clear();
      _undertimeRuleController.clear();
      _isDefault = false;
      _isActive = true;
    });
  }

  Future<void> _addPolicy() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a policy name.')),
      );
      return;
    }
    try {
      await ApiClient.instance.post(
        '/api/attendance-policies',
        data: {
          'name': name,
          'description': _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim(),
          'grace_period_minutes': int.tryParse(_graceController.text) ?? 0,
          'max_late_per_month_minutes': _maxLateController.text.trim().isEmpty ? null : int.tryParse(_maxLateController.text),
          'late_deduction_rule': _lateRuleController.text.trim().isEmpty ? null : _lateRuleController.text.trim(),
          'absent_deduction_rule': _absentRuleController.text.trim().isEmpty ? null : _absentRuleController.text.trim(),
          'undertime_rule': _undertimeRuleController.text.trim().isEmpty ? null : _undertimeRuleController.text.trim(),
          'is_default': _isDefault,
          'is_active': _isActive,
        },
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Attendance policy added.')));
        _clearForm();
        _loadPolicies();
      }
    } on DioException catch (e) {
      if (mounted) {
        final msg = (e.response?.data as Map?)?['error'] ?? e.message ?? 'Failed to add';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to add: $msg')));
      }
    }
  }

  Future<void> _updatePolicy() async {
    final p = _selectedPolicy;
    if (p == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a policy to update.')),
      );
      return;
    }
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a policy name.')),
      );
      return;
    }
    try {
      await ApiClient.instance.put(
        '/api/attendance-policies/${p.id}',
        data: {
          'name': name,
          'description': _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim(),
          'grace_period_minutes': int.tryParse(_graceController.text) ?? 0,
          'max_late_per_month_minutes': _maxLateController.text.trim().isEmpty ? null : int.tryParse(_maxLateController.text),
          'late_deduction_rule': _lateRuleController.text.trim().isEmpty ? null : _lateRuleController.text.trim(),
          'absent_deduction_rule': _absentRuleController.text.trim().isEmpty ? null : _absentRuleController.text.trim(),
          'undertime_rule': _undertimeRuleController.text.trim().isEmpty ? null : _undertimeRuleController.text.trim(),
          'is_default': _isDefault,
          'is_active': _isActive,
        },
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Attendance policy updated.')));
        _clearForm();
        _loadPolicies();
      }
    } on DioException catch (e) {
      if (mounted) {
        final msg = (e.response?.data as Map?)?['error'] ?? e.message ?? 'Failed to update';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to update: $msg')));
      }
    }
  }

  Future<void> _deactivatePolicy() async {
    final p = _selectedPolicy;
    if (p == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Deactivate policy?'),
        content: Text('"${p.name}" will no longer appear in active lists.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
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
      await ApiClient.instance.put('/api/attendance-policies/${p.id}', data: {'is_active': false});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Policy deactivated.')));
        _clearForm();
        _loadPolicies();
      }
    } on DioException catch (e) {
      if (mounted) {
        final msg = (e.response?.data as Map?)?['error'] ?? e.message ?? 'Failed to deactivate';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $msg')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final isNarrow = w < 700;
    final search = _searchController.text.toLowerCase();
    final filtered = _policies.where((p) =>
        p.name.toLowerCase().contains(search) ||
        (p.description ?? '').toLowerCase().contains(search)).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Attendance Policy',
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
                  Expanded(flex: 1, child: SingleChildScrollView(child: _buildFormPanel())),
                ],
              ),
      ],
    );
  }

  Widget _buildListPanel(List<_PolicyRecord> filtered) {
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
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                width: 200,
                child: TextField(
                  controller: _searchController,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Search',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    filled: true,
                    fillColor: AppTheme.lightGray.withOpacity(0.5),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                  ),
                ),
              ),
              DropdownButton<String>(
                value: _statusFilter,
                items: ['Active', 'Inactive', 'All'].map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
                onChanged: (v) {
                  setState(() => _statusFilter = v ?? 'Active');
                  _loadPolicies();
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_loading)
            const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()))
          else if (filtered.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text('No policies', style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              itemCount: filtered.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final p = filtered[i];
                final isSelected = _selectedPolicy?.id == p.id;
                return ListTile(
                  selected: isSelected,
                  selectedTileColor: AppTheme.primaryNavy.withOpacity(0.08),
                  title: Row(
                    children: [
                      Text(p.name, style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                      if (p.isDefault) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryNavy.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text('Default', style: TextStyle(fontSize: 10, color: AppTheme.primaryNavy, fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ],
                  ),
                  subtitle: Text(
                    'Grace: ${p.gracePeriodMinutes} min',
                    style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                  ),
                  onTap: () => _selectPolicy(p),
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
          _label('Policy name'),
          const SizedBox(height: 6),
          TextFormField(controller: _nameController, decoration: _decoration('Name')),
          const SizedBox(height: 16),
          _label('Description'),
          const SizedBox(height: 6),
          TextFormField(controller: _descriptionController, decoration: _decoration('Description'), maxLines: 2),
          const SizedBox(height: 16),
          _label('Grace period (minutes)'),
          const SizedBox(height: 6),
          TextFormField(
            controller: _graceController,
            keyboardType: TextInputType.number,
            decoration: _decoration('0'),
          ),
          const SizedBox(height: 16),
          _label('Max late per month (minutes, optional)'),
          const SizedBox(height: 6),
          TextFormField(
            controller: _maxLateController,
            keyboardType: TextInputType.number,
            decoration: _decoration('Optional'),
          ),
          const SizedBox(height: 16),
          _label('Late deduction rule (optional)'),
          const SizedBox(height: 6),
          TextFormField(controller: _lateRuleController, decoration: _decoration('e.g. Half day deduction'), maxLines: 2),
          const SizedBox(height: 16),
          _label('Absent deduction rule (optional)'),
          const SizedBox(height: 6),
          TextFormField(controller: _absentRuleController, decoration: _decoration('e.g. Full day deduction'), maxLines: 2),
          const SizedBox(height: 16),
          _label('Undertime rule (optional)'),
          const SizedBox(height: 6),
          TextFormField(controller: _undertimeRuleController, decoration: _decoration('Optional'), maxLines: 2),
          const SizedBox(height: 16),
          Row(
            children: [
              Checkbox(
                value: _isDefault,
                onChanged: (v) => setState(() => _isDefault = v ?? false),
                activeColor: AppTheme.primaryNavy,
              ),
              const Text('Default policy'),
            ],
          ),
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
                onPressed: _addPolicy,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add Policy'),
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF4CAF50), foregroundColor: Colors.white),
              ),
              OutlinedButton.icon(
                onPressed: _selectedPolicy != null ? _updatePolicy : null,
                icon: const Icon(Icons.edit_rounded, size: 18),
                label: const Text('Update'),
              ),
              FilledButton.icon(
                onPressed: _selectedPolicy != null ? _deactivatePolicy : null,
                icon: const Icon(Icons.person_off_rounded, size: 18),
                label: const Text('Deactivate'),
                style: FilledButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _label(String text) => Text(
        text,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textSecondary),
      );

  InputDecoration _decoration(String hint) => InputDecoration(
        hintText: hint,
        filled: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      );
}
