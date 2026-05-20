import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../api/client.dart';
import '../../landingpage/constants/app_theme.dart';
import '../leave_type_definition_cache.dart';
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
  final _searchController = TextEditingController();

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

  bool _isDark(BuildContext context) => AppTheme.dashIsDark(context);

  Color _headingColor(BuildContext context) =>
      AppTheme.dashTextPrimaryOf(context);

  Color _mutedColor(BuildContext context) =>
      AppTheme.dashTextSecondaryOf(context);

  Color _hairline(BuildContext context) => AppTheme.dashHairlineOf(context);

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
    _searchController.addListener(() => setState(() {}));
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
    _searchController.dispose();
    super.dispose();
  }

  List<LeaveTypeDefinition> get _filteredItems {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return _items;
    return _items.where((item) {
      return item.displayName.toLowerCase().contains(query) ||
          item.name.toLowerCase().contains(query) ||
          (item.description ?? '').toLowerCase().contains(query);
    }).toList();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = await LeaveTypeDefinitionCache.instance.listAll(
        includeInactive: true,
      );
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
    _isActive = item.isActive;
    _employeeCanFile = item.employeeCanFile;
    _adminOnly = item.adminOnly;
    _allowsPastDates = item.allowsPastDates;
    _requiresAttachment = item.requiresAttachment;
    _attachmentOverDaysController.text = _requiresAttachment
        ? item.requiresAttachmentWhenOverDays?.toString() ?? ''
        : '';
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
    final words = RegExp(
      r'[A-Za-z0-9]+',
    ).allMatches(displayName).map((m) => m.group(0)!).toList();
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
    final data = _payloadFromForm();
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
      LeaveTypeDefinitionCache.instance.invalidate();
      await _load();
    } on DioException catch (e) {
      _showMessage(_messageFromDio(e));
    } catch (e) {
      _showMessage('Save failed: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _toggleSelectedActive() async {
    final selected = _selected;
    if (selected?.id == null || selected!.isSystem || _saving) return;
    if (!_formKey.currentState!.validate()) return;

    final nextActive = !selected.isActive;
    if (!nextActive) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Deactivate leave type?'),
          content: Text(
            '${selected.displayName} will be hidden from future leave filing, '
            'but existing requests, reports, and history will stay intact.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(true),
              icon: const Icon(Icons.block_rounded),
              label: const Text('Deactivate'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    setState(() {
      _saving = true;
      _isActive = nextActive;
    });

    try {
      final res = await ApiClient.instance.put<Map<String, dynamic>>(
        '/api/leave/types/${selected.id}',
        data: _payloadFromForm(isActiveOverride: nextActive),
      );
      final body = res.data;
      if (body != null) _selected = LeaveTypeDefinition.fromJson(body);
      LeaveTypeDefinitionCache.instance.invalidate();
      _showMessage(
        nextActive ? 'Leave type reactivated.' : 'Leave type deactivated.',
      );
      await _load();
    } on DioException catch (e) {
      if (mounted) setState(() => _isActive = selected.isActive);
      _showMessage(_messageFromDio(e));
    } catch (e) {
      if (mounted) setState(() => _isActive = selected.isActive);
      _showMessage('Update failed: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Map<String, dynamic> _payloadFromForm({bool? isActiveOverride}) {
    return {
      'name': _nameController.text.trim(),
      'display_name': _displayNameController.text.trim(),
      'description': _descriptionController.text.trim(),
      'is_active': isActiveOverride ?? _isActive,
      'employee_can_file': _employeeCanFile,
      'admin_only': _adminOnly,
      'allows_past_dates': _allowsPastDates,
      'requires_attachment': _requiresAttachment,
      'requires_attachment_when_over_days': _requiresAttachment
          ? _numberOrNull(_attachmentOverDaysController.text)
          : null,
      'max_days': _numberOrNull(_maxDaysController.text),
      'affects_dtr_normally': _affectsDtrNormally,
      'balance_ledger_type': _balanceLedgerType,
    };
  }

  void _setRequiresAttachment(bool value) {
    setState(() {
      _requiresAttachment = value;
      if (!value) _attachmentOverDaysController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    final systemLocked = selected?.isSystem == true;

    return SizedBox(
      width: 1180,
      height: 720,
      child: ColoredBox(
        color: AppTheme.dashCanvasOf(context),
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
                        color: _headingColor(context),
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
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
                    icon: Icon(
                      Icons.close_rounded,
                      color: _mutedColor(context),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(width: 360, child: _buildList()),
                    const SizedBox(width: 18),
                    Expanded(child: _buildForm(systemLocked)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildList() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final items = _filteredItems;
    return Container(
      decoration: _panelDecoration(),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_items.length} leave types',
                  style: TextStyle(
                    color: _headingColor(context),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _searchController,
                  style: AppTheme.dashFieldTextStyle(context),
                  decoration: AppTheme.dashInputDecoration(
                    context,
                    hintText: 'Search type or key',
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      size: 20,
                      color: _mutedColor(context).withValues(alpha: 0.7),
                    ),
                    suffixIcon: _searchController.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear search',
                            onPressed: _searchController.clear,
                            icon: Icon(
                              Icons.close_rounded,
                              size: 18,
                              color: _mutedColor(context),
                            ),
                          ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    radius: 8,
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: _hairline(context)),
          Expanded(
            child: items.isEmpty
                ? Center(
                    child: Text(
                      'No leave types found',
                      style: TextStyle(color: _mutedColor(context)),
                    ),
                  )
                : ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, __) =>
                        Divider(height: 1, color: _hairline(context)),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      final selected = item.id == _selected?.id;
                      return _LeaveTypeListTile(
                        item: item,
                        selected: selected,
                        onTap: () => setState(() => _select(item)),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildForm(bool systemLocked) {
    final selected = _selected;
    final isDraft = selected == null;
    return Container(
      decoration: _panelDecoration(),
      clipBehavior: Clip.antiAlias,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              isDraft
                                  ? 'New custom leave type'
                                  : selected.displayName,
                              style: TextStyle(
                                color: _headingColor(context),
                                fontSize: 19,
                                fontWeight: FontWeight.w800,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            _statusPill(
                              label: systemLocked
                                  ? 'Protected'
                                  : (isDraft ? 'Draft' : 'Custom'),
                              icon: systemLocked
                                  ? Icons.lock_rounded
                                  : Icons.tune_rounded,
                              color: systemLocked
                                  ? AppTheme.primaryNavy
                                  : AppTheme.primaryNavy,
                            ),
                            if (selected?.isActive == true)
                              _statusPill(
                                label: 'Active',
                                icon: Icons.check_circle_rounded,
                                color: const Color(0xFF2E7D32),
                              )
                            else if (selected?.id != null)
                              _statusPill(
                                label: 'Inactive',
                                icon: Icons.pause_circle_outline_rounded,
                                color: _mutedColor(context),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          systemLocked
                              ? 'Built-in CSC rule. Review only.'
                              : 'Configure filing, balance, and DTR behavior.',
                          style: TextStyle(
                            color: _mutedColor(context),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: _hairline(context)),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
                children: [
                  if (systemLocked)
                    _InfoPanel(
                      icon: Icons.lock_outline_rounded,
                      text:
                          'Built-in CSC leave types are protected. You can review their rules here; create a custom type when you need editable rules.',
                    ),
                  _sectionTitle(Icons.badge_outlined, 'Basic Info'),
                  TextFormField(
                    controller: _displayNameController,
                    readOnly: _saving || systemLocked,
                    style: AppTheme.dashFieldTextStyle(context),
                    decoration: _inputDecoration('Display name'),
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _nameController,
                    readOnly: _saving || systemLocked,
                    style: AppTheme.dashFieldTextStyle(context),
                    decoration: _inputDecoration(
                      'System key',
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
                    readOnly: _saving || systemLocked,
                    style: AppTheme.dashFieldTextStyle(context),
                    decoration: _inputDecoration('Description'),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 24),
                  _sectionTitle(Icons.rule_rounded, 'Filing Rules'),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _ruleChip(
                        label: 'Active',
                        value: _isActive,
                        editable: !systemLocked,
                        onChanged: (v) => setState(() => _isActive = v),
                      ),
                      _ruleChip(
                        label: 'Employee can file',
                        value: _employeeCanFile,
                        editable: !systemLocked,
                        onChanged: (v) => setState(() => _employeeCanFile = v),
                      ),
                      _ruleChip(
                        label: 'Admin only',
                        value: _adminOnly,
                        editable: !systemLocked,
                        onChanged: (v) => setState(() => _adminOnly = v),
                      ),
                      _ruleChip(
                        label: 'Allows past dates',
                        value: _allowsPastDates,
                        editable: !systemLocked,
                        onChanged: (v) => setState(() => _allowsPastDates = v),
                      ),
                      _ruleChip(
                        label: 'Requires attachment',
                        value: _requiresAttachment,
                        editable: !systemLocked,
                        onChanged: _setRequiresAttachment,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _maxDaysController,
                          readOnly: _saving || systemLocked,
                          style: AppTheme.dashFieldTextStyle(context),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: _inputDecoration(
                            'Max working days',
                            helperText: 'Blank means no limit',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _attachmentOverDaysController,
                          enabled:
                              systemLocked || (!_saving && _requiresAttachment),
                          readOnly:
                              _saving || systemLocked || !_requiresAttachment,
                          style: AppTheme.dashFieldTextStyle(context),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: _inputDecoration(
                            'Attachment required at days',
                            helperText: _requiresAttachment
                                ? 'Optional threshold'
                                : 'Enable Requires attachment first',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _sectionTitle(Icons.sync_alt_rounded, 'Balance And DTR'),
                  _ruleChip(
                    label: 'Affects DTR',
                    value: _affectsDtrNormally,
                    editable: !systemLocked,
                    onChanged: (v) => setState(() => _affectsDtrNormally = v),
                  ),
                  const SizedBox(height: 14),
                  if (systemLocked)
                    _ReadOnlyValue(
                      label: 'Balance ledger bucket',
                      value: _ledgerTypes[_balanceLedgerType] ?? 'Others',
                      helperText:
                          'Protected types keep their assigned credit bucket.',
                    )
                  else
                    DropdownButtonFormField<String>(
                      key: ValueKey(_balanceLedgerType),
                      initialValue: _balanceLedgerType,
                      isExpanded: true,
                      dropdownColor: AppTheme.dashPanelOf(context),
                      style: AppTheme.dashFieldTextStyle(context),
                      decoration: _inputDecoration(
                        'Balance ledger bucket',
                        helperText:
                            'Use Others unless this type should deduct from an existing credit bucket.',
                      ),
                      items: _ledgerTypes.entries
                          .map(
                            (entry) => DropdownMenuItem(
                              value: entry.key,
                              child: Text(
                                entry.value,
                                style: AppTheme.dashFieldTextStyle(context),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: _saving
                          ? null
                          : (v) => setState(
                              () => _balanceLedgerType = v ?? 'others',
                            ),
                    ),
                ],
              ),
            ),
            _buildFooter(systemLocked),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter(bool systemLocked) {
    final selected = _selected;
    final canToggleActive =
        selected?.id != null && selected?.isSystem != true && !_saving;
    final isSelectedActive = selected?.isActive == true;
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 16),
      decoration: BoxDecoration(
        color: AppTheme.dashPanelOf(context),
        border: Border(top: BorderSide(color: _hairline(context))),
      ),
      child: Row(
        children: [
          Icon(
            systemLocked ? Icons.lock_rounded : Icons.info_outline_rounded,
            color: systemLocked
                ? (_isDark(context)
                      ? AppTheme.primaryNavyLight
                      : AppTheme.primaryNavy)
                : _mutedColor(context),
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              systemLocked
                  ? 'Protected CSC leave types cannot be edited.'
                  : isSelectedActive
                  ? 'Changes affect future filing rules after saving.'
                  : 'Inactive types stay in history, but employees cannot file them.',
              style: TextStyle(color: _mutedColor(context), fontSize: 13),
            ),
          ),
          const SizedBox(width: 12),
          if (selected?.id != null && !systemLocked) ...[
            OutlinedButton.icon(
              onPressed: canToggleActive ? _toggleSelectedActive : null,
              icon: Icon(
                isSelectedActive ? Icons.block_rounded : Icons.restore_rounded,
              ),
              label: Text(isSelectedActive ? 'Deactivate' : 'Reactivate'),
            ),
            const SizedBox(width: 10),
          ],
          FilledButton.icon(
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
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(String label, {String? helperText}) {
    return AppTheme.dashInputDecoration(
      context,
      labelText: label,
      helperText: helperText,
      radius: 8,
    );
  }

  Widget _sectionTitle(IconData icon, String label) {
    final dark = _isDark(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(
            icon,
            size: 18,
            color: dark ? AppTheme.primaryNavyLight : AppTheme.primaryNavy,
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: _headingColor(context),
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _ruleChip({
    required String label,
    required bool value,
    required bool editable,
    required ValueChanged<bool> onChanged,
  }) {
    final dark = _isDark(context);
    final color = value
        ? (dark ? Colors.green.shade300 : const Color(0xFF2E7D32))
        : _mutedColor(context);
    final bg = value
        ? (dark
              ? Colors.green.shade900.withValues(alpha: 0.35)
              : const Color(0xFFE8F5E9))
        : AppTheme.dashMutedSurfaceOf(context);
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: editable ? () => onChanged(!value) : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.22)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              value ? Icons.check_circle_rounded : Icons.cancel_outlined,
              size: 18,
              color: color,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: value
                    ? (dark ? Colors.green.shade100 : const Color(0xFF1B5E20))
                    : _headingColor(context),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusPill({
    required String label,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  BoxDecoration _panelDecoration() {
    return AppTheme.dashSurfaceCard(context, radius: 8);
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
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _LeaveTypeListTile extends StatelessWidget {
  const _LeaveTypeListTile({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final LeaveTypeDefinition item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = AppTheme.dashIsDark(context);
    final accent = selected
        ? (dark ? AppTheme.primaryNavyLight : AppTheme.primaryNavy)
        : Colors.transparent;
    final iconColor = selected
        ? (dark ? AppTheme.primaryNavyLight : AppTheme.primaryNavy)
        : AppTheme.dashTextSecondaryOf(context);
    return Material(
      color: selected
          ? (dark
                ? AppTheme.primaryNavy.withValues(alpha: 0.28)
                : AppTheme.primaryNavy.withValues(alpha: 0.07))
          : null,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: accent, width: 4)),
          ),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  item.isSystem ? Icons.verified_outlined : Icons.tune_rounded,
                  color: iconColor,
                  size: 19,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.displayName,
                      style: TextStyle(
                        color: selected
                            ? (dark
                                  ? AppTheme.primaryNavyLight
                                  : AppTheme.primaryNavy)
                            : AppTheme.dashTextPrimaryOf(context),
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      item.name,
                      style: TextStyle(
                        color: AppTheme.dashTextSecondaryOf(context),
                        fontSize: 12.5,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _ListStatusBadge(
                label: item.isActive ? 'Active' : 'Off',
                color: item.isActive
                    ? (dark ? Colors.green.shade300 : const Color(0xFF2E7D32))
                    : AppTheme.dashTextSecondaryOf(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ListStatusBadge extends StatelessWidget {
  const _ListStatusBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _ReadOnlyValue extends StatelessWidget {
  const _ReadOnlyValue({
    required this.label,
    required this.value,
    this.helperText,
  });

  final String label;
  final String value;
  final String? helperText;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: AppTheme.dashInputDecoration(
        context,
        labelText: label,
        helperText: helperText,
        radius: 8,
      ),
      child: Text(
        value,
        style: TextStyle(
          color: AppTheme.dashTextPrimaryOf(context),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _InfoPanel extends StatelessWidget {
  const _InfoPanel({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final dark = AppTheme.dashIsDark(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: dark
            ? AppTheme.primaryNavy.withValues(alpha: 0.28)
            : AppTheme.primaryNavy.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: dark ? AppTheme.primaryNavyLight : AppTheme.primaryNavy,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: AppTheme.dashTextPrimaryOf(context),
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
