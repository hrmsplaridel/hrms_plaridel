import 'package:flutter/material.dart';
import 'package:hrms_plaridel/core/api/user_facing_api_error.dart';
import 'package:hrms_plaridel/shared/widgets/settings_master_detail.dart';
import 'package:hrms_plaridel/shared/widgets/settings_loading_skeleton.dart';
import '../data/approval_configuration_repository.dart';

/// Shared groups are configured from their workflow step, alongside explicit assignees.
Future<void> showWorkflowReviewerConfiguration(
  BuildContext context, {
  required String source,
  String? departmentId,
}) async {
  if (source == 'department_reviewers' && (departmentId ?? '').trim().isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Select a department before configuring reviewers.'),
      ),
    );
    return;
  }
  if (![
    'submitter_department_reviewers',
    'department_reviewers',
    'final_hr_reviewers',
  ].contains(source)) {
    return;
  }
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) =>
        _WorkflowReviewerDialog(source: source, departmentId: departmentId),
  );
}

class _WorkflowReviewerDialog extends StatefulWidget {
  const _WorkflowReviewerDialog({required this.source, this.departmentId});
  final String source;
  final String? departmentId;
  @override
  State<_WorkflowReviewerDialog> createState() =>
      _WorkflowReviewerDialogState();
}

class _WorkflowReviewerDialogState extends State<_WorkflowReviewerDialog> {
  bool _dirty = false;
  bool _saving = false;
  void _onDirtyChanged(bool value) {
    if (mounted) setState(() => _dirty = value);
  }

  void _onSavingChanged(bool value) {
    if (mounted) setState(() => _saving = value);
  }

  @override
  Widget build(BuildContext context) {
    final byDepartment = widget.source == 'submitter_department_reviewers';
    final finalHr = widget.source == 'final_hr_reviewers';
    return PopScope(
      canPop: !_dirty && !_saving,
      child: Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: SizedBox(
          width: 1000,
          height: 740,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  finalHr
                      ? 'Configure Final HR reviewers'
                      : 'Configure department reviewers',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                const Text(
                  'This reviewer group is shared by every workflow that references it. Changes take effect from the selected date when saved.',
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: byDepartment
                      ? _ReviewersPage(
                          onDirtyChanged: _onDirtyChanged,
                          onSavingChanged: _onSavingChanged,
                        )
                      : ListView(
                          children: [
                            _ReviewerSection(
                              title: finalHr
                                  ? 'Final HR Review'
                                  : 'Department Review',
                              departmentId: finalHr
                                  ? null
                                  : widget.departmentId,
                              onDirtyChanged: _onDirtyChanged,
                              onSavingChanged: _onSavingChanged,
                              onSaved: () async {},
                            ),
                          ],
                        ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    if (_dirty)
                      TextButton(
                        onPressed: _saving
                            ? null
                            : () => Navigator.pop(context),
                        child: const Text('Close without saving'),
                      ),
                    FilledButton(
                      onPressed: _dirty || _saving
                          ? null
                          : () => Navigator.pop(context),
                      child: const Text('Done'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReviewersPage extends StatefulWidget {
  const _ReviewersPage({
    required this.onDirtyChanged,
    required this.onSavingChanged,
  });
  final ValueChanged<bool> onDirtyChanged;
  final ValueChanged<bool> onSavingChanged;
  @override
  State<_ReviewersPage> createState() => _ReviewersPageState();
}

class _ReviewersPageState extends State<_ReviewersPage> {
  final _repository = ApprovalConfigurationRepository();
  List<Map<String, dynamic>> _departments = [];
  Map<String, String> _summaries = {};
  String? _selectedId;
  String? _error;
  bool _loading = true;
  bool _dirty = false;
  int _revision = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _refreshSummaries() async {
    try {
      final summaries = await _repository.primarySummaries();
      if (mounted) setState(() => _summaries = summaries);
    } catch (_) {
      if (mounted) setState(() => _summaries = {});
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final departments = await _repository.departments();
      if (!mounted) return;
      setState(() {
        _departments = departments;
        if (!departments.any((d) => d['id'] == _selectedId)) {
          _selectedId = departments.isEmpty
              ? null
              : departments.first['id'] as String;
        }
        _revision++;
      });
      await _refreshSummaries();
    } catch (error) {
      if (mounted) {
        setState(() => _error = userFacingApiError(error));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = [
      for (final department in _departments)
        SettingsListEntry(
          id: department['id'] as String,
          title: department['name'] as String,
          icon: Icons.business_outlined,
          subtitle: _summaries[department['id']] ?? 'Status unavailable',
          group: 'Departments',
        ),
    ];
    final selected = entries.where((e) => e.id == _selectedId).firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.link, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Shared reviewer assignments for Leave and Locator'),
            ),
            IconButton(
              tooltip: 'Refresh reviewers',
              onPressed: _loading || _dirty ? null : _load,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_loading) const Expanded(child: SettingsMasterDetailSkeleton()),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                TextButton(onPressed: _load, child: const Text('Retry')),
              ],
            ),
          ),
        if (!_loading && _error == null)
          Expanded(
            child: SettingsMasterDetail(
              key: const PageStorageKey('reviewer-master-detail'),
              entries: entries,
              selectedId: _selectedId,
              searchLabel: 'Search departments',
              navigationEnabled: !_dirty,
              onSelected: (id) => setState(() => _selectedId = id),
              detail: ListView(
                key: PageStorageKey('reviewer-detail-$_selectedId'),
                primary: false,
                padding: const EdgeInsets.all(24),
                children: [
                  Text(
                    selected?.title ?? 'Select a department',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Department reviewers',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const Divider(height: 32),
                  if (_selectedId != null)
                    _ReviewerSection(
                      key: ValueKey('reviewers-$_selectedId-$_revision'),
                      departmentId: _selectedId,
                      title: 'Department Review',
                      onDirtyChanged: (dirty) {
                        setState(() => _dirty = dirty);
                        widget.onDirtyChanged(dirty);
                      },
                      onSavingChanged: widget.onSavingChanged,
                      onSaved: _refreshSummaries,
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _ReviewerSection extends StatefulWidget {
  const _ReviewerSection({
    super.key,
    required this.title,
    this.departmentId,
    required this.onDirtyChanged,
    this.onSavingChanged,
    required this.onSaved,
  });
  final String title;
  final String? departmentId;
  final ValueChanged<bool> onDirtyChanged;
  final ValueChanged<bool>? onSavingChanged;
  final Future<void> Function() onSaved;
  @override
  State<_ReviewerSection> createState() => _ReviewerSectionState();
}

class _ReviewerSectionState extends State<_ReviewerSection> {
  final _repository = ApprovalConfigurationRepository();
  Map<String, dynamic>? _config;
  List<String> _backups = [];
  String? _date;
  String? _error;
  bool _loading = true;
  bool _saving = false;
  bool _dirty = false;

  bool get _department => widget.departmentId != null;
  String _id(Map row) =>
      (row[_department ? 'reviewerId' : 'id'] ?? '').toString();
  String _name(Map row) =>
      (row[_department ? 'reviewerName' : 'name'] ?? 'Not configured')
          .toString();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _config = null;
    });
    try {
      final config = await _repository.reviewers(widget.departmentId, _date);
      if (!mounted) return;
      setState(() {
        _config = config;
        _date = config['effective_date'] as String;
        _backups = ApprovalConfigurationRepository.rows(
          config['backups'],
        ).map(_id).toList();
        _dirty = false;
      });
      widget.onDirtyChanged(false);
    } catch (error) {
      if (mounted) {
        setState(() => _error = userFacingApiError(error));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.parse(_date!),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;
    _date = _isoDate(date);
    await _load();
  }

  Future<void> _save() async {
    widget.onSavingChanged?.call(true);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _repository.saveBackups(widget.departmentId, _date!, _backups);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Reviewer backups saved.')));
      await _load();
      if (mounted) await widget.onSaved();
    } catch (error) {
      if (mounted) {
        setState(() => _error = userFacingApiError(error));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
      widget.onSavingChanged?.call(false);
    }
  }

  Future<void> _designate() async {
    await showDialog<void>(
      context: context,
      builder: (_) => _DesignationDialog(
        departmentId: widget.departmentId,
        effectiveDate: _date!,
      ),
    );
    if (mounted) {
      await _load();
      if (mounted) await widget.onSaved();
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = _config?['primary'] as Map?;
    final roster = ApprovalConfigurationRepository.rows(
      _config?['eligible_employees'],
    );
    final eligible = roster
        .where((r) => r['id'] != (primary == null ? null : _id(primary)))
        .toList();
    final busy = _loading || _saving;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        if (_loading) const SettingsDetailsSkeleton(),
        if (_error != null)
          Row(
            children: [
              Expanded(
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
              IconButton(
                tooltip: 'Retry',
                onPressed: busy ? null : _load,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        if (_config != null && !_loading) ...[
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: busy || _dirty ? null : _pickDate,
                icon: const Icon(Icons.calendar_today_outlined),
                label: Text('Effective $_date'),
              ),
              OutlinedButton.icon(
                onPressed: busy || _dirty ? null : _designate,
                icon: const Icon(Icons.badge_outlined),
                label: const Text('Primary designation'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Primary reviewer',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          Text(primary == null ? 'Not configured' : _name(primary)),
          const SizedBox(height: 16),
          Text(
            'Backup reviewers (${_backups.length}/5)',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          for (var index = 0; index < _backups.length; index++)
            Row(
              children: [
                Text('${index + 1}.'),
                const SizedBox(width: 8),
                Expanded(child: Text(_backupName(_backups[index], roster))),
                IconButton(
                  tooltip: 'Move earlier',
                  onPressed: busy || index == 0
                      ? null
                      : () => setState(() {
                          final id = _backups.removeAt(index);
                          _backups.insert(index - 1, id);
                          _dirty = true;
                          widget.onDirtyChanged(true);
                        }),
                  icon: const Icon(Icons.arrow_upward, size: 18),
                ),
                IconButton(
                  tooltip: 'Remove backup',
                  onPressed: busy
                      ? null
                      : () => setState(() {
                          _backups.removeAt(index);
                          _dirty = true;
                          widget.onDirtyChanged(true);
                        }),
                  icon: const Icon(Icons.close, size: 18),
                ),
              ],
            ),
          if (_backups.length < 5)
            DropdownButtonFormField<String>(
              key: ValueKey(_backups.join(',')),
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Add backup reviewer',
              ),
              items: eligible
                  .where((r) => !_backups.contains(r['id']))
                  .map(
                    (r) => DropdownMenuItem(
                      value: r['id'] as String,
                      child: Text(
                        r['name'] as String,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: busy
                  ? null
                  : (value) {
                      if (value != null) {
                        setState(() {
                          _backups.add(value);
                          _dirty = true;
                          widget.onDirtyChanged(true);
                        });
                      }
                    },
            ),
          if (eligible.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('No eligible backup reviewers.'),
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            children: [
              FilledButton.icon(
                onPressed: busy || !_dirty ? null : _save,
                icon: const Icon(Icons.save_outlined),
                label: Text(_saving ? 'Saving...' : 'Save backups'),
              ),
              if (_dirty)
                TextButton(
                  onPressed: busy ? null : _load,
                  child: const Text('Discard changes'),
                ),
            ],
          ),
        ],
      ],
    );
  }

  String _backupName(String id, List<Map<String, dynamic>> roster) {
    for (final row in roster) {
      if (row['id'] == id) return row['name'] as String;
    }
    for (final row in ApprovalConfigurationRepository.rows(
      _config?['backups'],
    )) {
      if (_id(row) == id) return _name(row);
    }
    return 'Unavailable reviewer';
  }
}

class _DesignationDialog extends StatefulWidget {
  const _DesignationDialog({this.departmentId, required this.effectiveDate});
  final String effectiveDate;
  final String? departmentId;
  @override
  State<_DesignationDialog> createState() => _DesignationDialogState();
}

class _DesignationDialogState extends State<_DesignationDialog> {
  final _repository = ApprovalConfigurationRepository();
  List<Map<String, dynamic>> _employees = [];
  String? _selectedId;
  bool _enabled = false;
  DateTime _from = DateUtils.dateOnly(DateTime.now());
  DateTime? _to;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  bool get _department => widget.departmentId != null;
  Map<String, dynamic>? get _employee {
    for (final row in _employees) {
      if (row['id'] == _selectedId) return row;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final config = await _repository.reviewers(
        widget.departmentId,
        widget.effectiveDate,
      );
      final primary = config['primary'] as Map?;
      if (mounted) {
        setState(() {
          _employees = ApprovalConfigurationRepository.rows(
            config['eligible_employees'],
          );
          _selectedId = primary?[_department ? 'reviewerId' : 'id']?.toString();
          _enabled = _selectedId != null;
          if (primary != null &&
              _selectedId != null &&
              !_employees.any((e) => e['id'] == _selectedId)) {
            _employees.add({
              'id': _selectedId,
              'name': primary[_department ? 'reviewerName' : 'name'],
              'position_title': primary['position_title'],
            });
          }
          _from = DateTime.parse(widget.effectiveDate);
          _to = DateTime.tryParse(primary?['effective_to']?.toString() ?? '');
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = userFacingApiError(error));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_enabled && _employee == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _repository.savePrimary(widget.departmentId, {
        'employee_id': _enabled ? _selectedId : null,
        'effective_from': _isoDate(_from),
        'effective_to': _to == null ? null : _isoDate(_to!),
      });
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        setState(() => _error = userFacingApiError(error));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickDate(bool from) async {
    final selected = await showDatePicker(
      context: context,
      initialDate: from ? _from : (_to ?? _from),
      firstDate: from ? DateTime(2000) : _from,
      lastDate: DateTime(2100),
    );
    if (selected != null && mounted) {
      setState(() {
        if (from) {
          _from = selected;
          if (_to != null && _to!.isBefore(_from)) _to = null;
        } else {
          _to = selected;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(_department ? 'Department Head Reviewer' : 'Final HR Reviewer'),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_loading) const SettingsDetailsSkeleton(),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            DropdownButtonFormField<String>(
              key: ValueKey('primary-employee-$_loading'),
              initialValue: _employees.any((e) => e['id'] == _selectedId)
                  ? _selectedId
                  : null,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Employee'),
              items: _employees
                  .map(
                    (p) => DropdownMenuItem(
                      value: p['id'] as String,
                      child: Text(
                        p['name'] as String,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: _saving
                  ? null
                  : (value) => setState(() {
                      _selectedId = value;
                      _enabled = value != null;
                    }),
            ),
            if (_employee != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Position: ${_employee!['position_title'] ?? 'No assigned position'}',
                ),
              ),
            ],
            Material(
              color: Colors.transparent,
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Designate as primary reviewer'),
                value: _enabled,
                onChanged: _saving || _employee == null
                    ? null
                    : (value) => setState(() => _enabled = value),
              ),
            ),
            if (_enabled)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _saving ? null : () => _pickDate(true),
                    icon: const Icon(Icons.calendar_today),
                    label: Text('From ${_isoDate(_from)}'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _saving ? null : () => _pickDate(false),
                    icon: const Icon(Icons.event),
                    label: Text(
                      _to == null ? 'No end date' : 'To ${_isoDate(_to!)}',
                    ),
                  ),
                  if (_to != null)
                    IconButton(
                      tooltip: 'Clear end date',
                      onPressed: _saving
                          ? null
                          : () => setState(() => _to = null),
                      icon: const Icon(Icons.close),
                    ),
                ],
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton.icon(
        onPressed: _loading || _saving || (_enabled && _employee == null)
            ? null
            : _save,
        icon: const Icon(Icons.save_outlined),
        label: Text(_saving ? 'Saving...' : 'Save designation'),
      ),
    ],
  );
}

String _isoDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
