import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../api/client.dart';
import '../../landingpage/constants/app_theme.dart';
import '../models/leave_type_definition.dart';

class LeaveTypeManagementScreen extends StatefulWidget {
  const LeaveTypeManagementScreen({super.key});

  @override
  State<LeaveTypeManagementScreen> createState() =>
      _LeaveTypeManagementScreenState();
}

class _LeaveTypeManagementScreenState extends State<LeaveTypeManagementScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _displayNameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _maxDaysController = TextEditingController();
  final _attachmentOverDaysController = TextEditingController();

  List<LeaveTypeDefinition> _items = const [];
  LeaveTypeDefinition? _selected;
  bool _loading = true;
  bool _saving = false;
  bool _isActive = true;
  bool _employeeCanFile = true;
  bool _adminOnly = false;
  bool _allowsPastDates = true;
  bool _requiresAttachment = false;
  bool _affectsDtrNormally = true;
  String _balanceLedgerType = 'others';

  static const _ledgerTypes = <String, String>{
    'vacationLeave': 'Vacation Leave',
    'sickLeave': 'Sick Leave',
    'maternityLeave': 'Maternity Leave',
    'paternityLeave': 'Paternity Leave',
    'specialPrivilegeLeave': 'Special Privilege Leave',
    'soloParentLeave': 'Solo Parent Leave',
    'studyLeave': 'Study Leave',
    'tenDayVawcLeave': '10-Day VAWC Leave',
    'rehabilitationPrivilege': 'Rehabilitation Privilege',
    'specialLeaveBenefitsForWomen': 'Special Leave Benefits for Women',
    'specialEmergencyCalamityLeave': 'Special Emergency (Calamity) Leave',
    'adoptionLeave': 'Adoption Leave',
    'others': 'Others / Custom',
  };

  @override
  void initState() {
    super.initState();
    _displayNameController.addListener(_syncKeyFromDisplayName);
    _load();
  }

  @override
  void dispose() {
    _displayNameController.removeListener(_syncKeyFromDisplayName);
    _nameController.dispose();
    _displayNameController.dispose();
    _descriptionController.dispose();
    _maxDaysController.dispose();
    _attachmentOverDaysController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await ApiClient.instance.get<List<dynamic>>(
        '/api/leave/types',
        queryParameters: const {'include_inactive': '1'},
      );
      final rows = (res.data ?? const [])
          .map(
            (item) => LeaveTypeDefinition.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList();
      if (!mounted) return;
      setState(() {
        _items = rows;
        _loading = false;
        if (_selected == null && rows.isNotEmpty) {
          _select(rows.first);
        } else if (_selected != null) {
          final match = rows.where((item) => item.id == _selected!.id);
          if (match.isNotEmpty) _select(match.first);
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        _showMessage('Could not load leave types: $e');
      }
    }
  }

  void _select(LeaveTypeDefinition item) {
    _selected = item;
    _nameController.text = item.name;
    _displayNameController.text = item.displayName;
    _descriptionController.text = item.description ?? '';
    _maxDaysController.text = item.maxDays?.toString() ?? '';
    _attachmentOverDaysController.text =
        item.requiresAttachmentWhenOverDays?.toString() ?? '';
    _isActive = item.isActive;
    _employeeCanFile = item.employeeCanFile;
    _adminOnly = item.adminOnly;
    _allowsPastDates = item.allowsPastDates;
    _requiresAttachment = item.requiresAttachment;
    _affectsDtrNormally = item.affectsDtrNormally;
    _balanceLedgerType = _ledgerTypes.containsKey(item.balanceLedgerType)
        ? item.balanceLedgerType
        : 'others';
  }

  void _newCustom() {
    setState(() {
      _selected = null;
      _nameController.clear();
      _displayNameController.clear();
      _descriptionController.clear();
      _maxDaysController.clear();
      _attachmentOverDaysController.clear();
      _isActive = true;
      _employeeCanFile = true;
      _adminOnly = false;
      _allowsPastDates = true;
      _requiresAttachment = false;
      _affectsDtrNormally = true;
      _balanceLedgerType = 'others';
    });
  }

  void _syncKeyFromDisplayName() {
    if (_selected != null || _nameController.text.trim().isNotEmpty) return;
    final slug = _slugName(_displayNameController.text);
    if (slug == null) return;
    _nameController.text = slug;
  }

  String? _slugName(String displayName) {
    final words = RegExp(r'[A-Za-z0-9]+')
        .allMatches(displayName)
        .map((m) => m.group(0)!)
        .toList();
    if (words.isEmpty) return null;
    final first = words.first.toLowerCase();
    final rest = words.skip(1).map((word) {
      final lower = word.toLowerCase();
      return '${lower[0].toUpperCase()}${lower.substring(1)}';
    });
    final base = ([first, ...rest]).join();
    return base.toLowerCase().endsWith('leave') ? base : '${base}Leave';
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final selected = _selected;
    final data = <String, dynamic>{
      'name': _nameController.text.trim(),
      'display_name': _displayNameController.text.trim(),
      'description': _descriptionController.text.trim(),
      'is_active': _isActive,
      'employee_can_file': _employeeCanFile,
      'admin_only': _adminOnly,
      'allows_past_dates': _allowsPastDates,
      'requires_attachment': _requiresAttachment,
      'requires_attachment_when_over_days': _numberOrNull(
        _attachmentOverDaysController.text,
      ),
      'max_days': _numberOrNull(_maxDaysController.text),
      'affects_dtr_normally': _affectsDtrNormally,
      'balance_ledger_type': _balanceLedgerType,
    };
    try {
      LeaveTypeDefinition? saved;
      if (selected?.id == null) {
        final res = await ApiClient.instance.post<Map<String, dynamic>>(
          '/api/leave/types',
          data: data,
        );
        final body = res.data;
        if (body != null) saved = LeaveTypeDefinition.fromJson(body);
        _showMessage('Leave type added.');
      } else {
        final res = await ApiClient.instance.put<Map<String, dynamic>>(
          '/api/leave/types/${selected!.id}',
          data: data,
        );
        final body = res.data;
        if (body != null) saved = LeaveTypeDefinition.fromJson(body);
        _showMessage('Leave type updated.');
      }
      if (saved != null) _selected = saved;
      await _load();
    } on DioException catch (e) {
      _showMessage(_messageFromDio(e));
    } catch (e) {
      _showMessage('Save failed: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    final systemLocked = selected?.isSystem == true;

    return SizedBox(
      width: 1180,
      height: 720,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Leave Type Rules',
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: _saving ? null : _newCustom,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('New custom type'),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 360,
                    child: _buildList(),
                  ),
                  const SizedBox(width: 18),
                  Expanded(child: _buildForm(systemLocked)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return Container(
      decoration: _panelDecoration(),
      child: ListView.separated(
        itemCount: _items.length,
        separatorBuilder: (_, __) => Divider(
          height: 1,
          color: Colors.black.withValues(alpha: 0.06),
        ),
        itemBuilder: (context, index) {
          final item = _items[index];
          final selected = item.id == _selected?.id;
          return ListTile(
            selected: selected,
            title: Text(item.displayName),
            subtitle: Text(item.name),
            leading: Icon(
              item.isSystem ? Icons.verified_outlined : Icons.tune_rounded,
              color: selected ? AppTheme.primaryNavy : AppTheme.textSecondary,
            ),
            trailing: item.isActive
                ? const Icon(Icons.check_circle_rounded, color: Colors.green)
                : const Icon(Icons.pause_circle_outline_rounded),
            onTap: () => setState(() => _select(item)),
          );
        },
      ),
    );
  }

  Widget _buildForm(bool systemLocked) {
    return Container(
      decoration: _panelDecoration(),
      padding: const EdgeInsets.all(18),
      child: Form(
        key: _formKey,
        child: ListView(
          children: [
            if (systemLocked)
              _InfoPanel(
                icon: Icons.lock_outline_rounded,
                text:
                    'Built-in CSC leave types are protected. You can review their rules here; custom leave types can be edited.',
              ),
            TextFormField(
              controller: _displayNameController,
              enabled: !_saving && !systemLocked,
              decoration: const InputDecoration(labelText: 'Display name'),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _nameController,
              enabled: !_saving && !systemLocked,
              decoration: const InputDecoration(
                labelText: 'System key',
                helperText: 'Example: bereavementLeave',
              ),
              validator: (v) {
                final text = v?.trim() ?? '';
                if (text.isEmpty) return 'Required';
                if (!RegExp(r'^[A-Za-z][A-Za-z0-9_]*$').hasMatch(text)) {
                  return 'Use letters, numbers, or underscore only';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _descriptionController,
              enabled: !_saving && !systemLocked,
              decoration: const InputDecoration(labelText: 'Description'),
              maxLines: 2,
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                _switchChip(
                  label: 'Active',
                  value: _isActive,
                  enabled: !systemLocked,
                  onChanged: (v) => setState(() => _isActive = v),
                ),
                _switchChip(
                  label: 'Employee can file',
                  value: _employeeCanFile,
                  enabled: !systemLocked,
                  onChanged: (v) => setState(() => _employeeCanFile = v),
                ),
                _switchChip(
                  label: 'Admin only',
                  value: _adminOnly,
                  enabled: !systemLocked,
                  onChanged: (v) => setState(() => _adminOnly = v),
                ),
                _switchChip(
                  label: 'Allows past dates',
                  value: _allowsPastDates,
                  enabled: !systemLocked,
                  onChanged: (v) => setState(() => _allowsPastDates = v),
                ),
                _switchChip(
                  label: 'Requires attachment',
                  value: _requiresAttachment,
                  enabled: !systemLocked,
                  onChanged: (v) => setState(() => _requiresAttachment = v),
                ),
                _switchChip(
                  label: 'Affects DTR',
                  value: _affectsDtrNormally,
                  enabled: !systemLocked,
                  onChanged: (v) => setState(() => _affectsDtrNormally = v),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _maxDaysController,
                    enabled: !_saving && !systemLocked,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Max working days',
                      helperText: 'Blank means no limit',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _attachmentOverDaysController,
                    enabled: !_saving && !systemLocked,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Attachment required at days',
                      helperText: 'Useful for sick leave threshold',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            DropdownButtonFormField<String>(
              value: _balanceLedgerType,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Balance ledger bucket',
                helperText:
                    'Custom leave types normally use Others unless they should deduct from an existing credit bucket.',
              ),
              items: _ledgerTypes.entries
                  .map(
                    (entry) => DropdownMenuItem(
                      value: entry.key,
                      child: Text(entry.value),
                    ),
                  )
                  .toList(),
              onChanged: _saving || systemLocked
                  ? null
                  : (v) => setState(() => _balanceLedgerType = v ?? 'others'),
            ),
            const SizedBox(height: 24),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _saving || systemLocked ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_rounded),
                label: Text(_saving ? 'Saving...' : 'Save rules'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _switchChip({
    required String label,
    required bool value,
    required bool enabled,
    required ValueChanged<bool> onChanged,
  }) {
    return FilterChip(
      label: Text(label),
      selected: value,
      onSelected: enabled ? onChanged : null,
      avatar: Icon(value ? Icons.check_rounded : Icons.close_rounded, size: 16),
    );
  }

  BoxDecoration _panelDecoration() {
    return BoxDecoration(
      color: AppTheme.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
    );
  }

  double? _numberOrNull(String value) {
    final text = value.trim();
    if (text.isEmpty) return null;
    return double.tryParse(text);
  }

  String _messageFromDio(DioException e) {
    final data = e.response?.data;
    if (data is Map && data['error'] != null) return data['error'].toString();
    return e.message ?? 'Request failed';
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

class _InfoPanel extends StatelessWidget {
  const _InfoPanel({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.primaryNavy.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.primaryNavy),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: AppTheme.textPrimary, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}
