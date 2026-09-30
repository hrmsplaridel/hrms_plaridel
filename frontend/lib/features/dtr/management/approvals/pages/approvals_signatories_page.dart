import 'package:flutter/material.dart';
import 'package:hrms_plaridel/core/api/user_facing_api_error.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/shared/widgets/settings_master_detail.dart';
import 'package:hrms_plaridel/shared/widgets/settings_loading_skeleton.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/admin/pages/docutracker_official_signatories_screen.dart';
import '../data/approval_configuration_repository.dart';

class ApprovalsSignatoriesPage extends StatefulWidget {
  const ApprovalsSignatoriesPage({super.key});

  @override
  State<ApprovalsSignatoriesPage> createState() =>
      _ApprovalsSignatoriesPageState();
}

class _ApprovalsSignatoriesPageState extends State<ApprovalsSignatoriesPage> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 3,
    child: SizedBox(
      height: 760,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Approvals & Signatories',
            style: TextStyle(
              color: AppTheme.dashTextPrimaryOf(context),
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: AppTheme.dashPanelOf(context),
              border: Border.all(color: AppTheme.dashHairlineOf(context)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: TabBar(
              key: const PageStorageKey('dtr-approvals-tabs'),
              onTap: (index) => setState(() => _tab = index),
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              padding: EdgeInsets.zero,
              labelPadding: const EdgeInsets.symmetric(horizontal: 16),
              indicatorSize: TabBarIndicatorSize.tab,
              indicator: const BoxDecoration(color: AppTheme.primaryNavy),
              dividerColor: Colors.transparent,
              labelColor: Colors.white,
              unselectedLabelColor: AppTheme.dashTextSecondaryOf(context),
              labelStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
              unselectedLabelStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
              tabs: const [
                Tab(
                  height: 46,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.event_note_outlined, size: 18),
                      SizedBox(width: 8),
                      Text('Leave Workflow'),
                    ],
                  ),
                ),
                Tab(
                  height: 46,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.location_on_outlined, size: 18),
                      SizedBox(width: 8),
                      Text('Locator Workflow'),
                    ],
                  ),
                ),
                Tab(
                  height: 46,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.draw_outlined, size: 18),
                      SizedBox(width: 8),
                      Text('Report Signatories'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: IndexedStack(
              index: _tab == 2 ? 1 : 0,
              children: [
                _ReviewersPage(locator: _tab == 1),
                const DocuTrackerOfficialSignatoriesScreen(dtrOnly: true),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _ReviewersPage extends StatefulWidget {
  const _ReviewersPage({this.locator = false});
  final bool locator;
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
        if (_selectedId != 'office-wide' &&
            !departments.any((d) => d['id'] == _selectedId)) {
          _selectedId = departments.isEmpty
              ? 'office-wide'
              : departments.first['id'] as String;
        }
        _revision++;
      });
      await _refreshSummaries();
    } catch (error) {
      if (mounted) setState(() => _error = userFacingApiError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final office = _selectedId == 'office-wide';
    final entries = [
      for (final department in _departments)
        SettingsListEntry(
          id: department['id'] as String,
          title: department['name'] as String,
          icon: Icons.business_outlined,
          subtitle: _summaries[department['id']] ?? 'Status unavailable',
          group: 'Departments',
        ),
      SettingsListEntry(
        id: 'office-wide',
        title: 'Final HR Review',
        subtitle: _summaries['office-wide'] ?? 'Status unavailable',
        group: 'Office-wide',
        icon: Icons.verified_user_outlined,
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
              child: Text(
                widget.locator
                    ? 'Shared with Leave Workflow'
                    : 'Shared with Locator Workflow',
              ),
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
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
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
                    office ? 'Office-wide' : 'Department reviewers',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const Divider(height: 32),
                  _ReviewerSection(
                    key: ValueKey('reviewers-$_selectedId-$_revision'),
                    departmentId: office ? null : _selectedId,
                    title: office ? 'Final HR Review' : 'Department Review',
                    onDirtyChanged: (dirty) => setState(() => _dirty = dirty),
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
    required this.onSaved,
  });
  final String title;
  final String? departmentId;
  final ValueChanged<bool> onDirtyChanged;
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
      if (mounted) setState(() => _error = userFacingApiError(error));
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
      if (mounted) setState(() => _error = userFacingApiError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _designate() async {
    await showDialog<void>(
      context: context,
      builder: (_) => _DesignationDialog(departmentId: widget.departmentId),
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
                label: const Text('Position designations'),
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
  const _DesignationDialog({this.departmentId});
  final String? departmentId;
  @override
  State<_DesignationDialog> createState() => _DesignationDialogState();
}

class _DesignationDialogState extends State<_DesignationDialog> {
  final _repository = ApprovalConfigurationRepository();
  List<Map<String, dynamic>> _positions = [];
  String? _selectedId;
  bool _enabled = false;
  DateTime _from = DateUtils.dateOnly(DateTime.now());
  DateTime? _to;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  bool get _department => widget.departmentId != null;
  Map<String, dynamic>? get _position {
    for (final row in _positions) {
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
      final positions = await _repository.positions(widget.departmentId);
      if (mounted) setState(() => _positions = positions);
    } catch (error) {
      if (mounted) setState(() => _error = userFacingApiError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_position == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _repository.saveDesignation(
        _selectedId!,
        _department
            ? {
                'is_department_head': _enabled,
                if (_position!['department_head_period_id'] != null)
                  'department_head_period_id':
                      _position!['department_head_period_id'],
                if (_enabled) 'department_head_effective_from': _isoDate(_from),
                if (_enabled)
                  'department_head_effective_to': _to == null
                      ? null
                      : _isoDate(_to!),
              }
            : {'is_leave_final_reviewer': _enabled},
      );
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) setState(() => _error = userFacingApiError(error));
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
    title: Text(
      _department ? 'Department Head Position' : 'Final Reviewer Position',
    ),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_loading) const LinearProgressIndicator(),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            DropdownButtonFormField<String>(
              initialValue: _selectedId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Position'),
              items: _positions
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
                      _enabled =
                          _position?[_department
                              ? 'is_department_head'
                              : 'is_leave_final_reviewer'] ==
                          true;
                      _from =
                          DateTime.tryParse(
                            _position?['department_head_effective_from']
                                    ?.toString() ??
                                '',
                          ) ??
                          DateUtils.dateOnly(DateTime.now());
                      _to = DateTime.tryParse(
                        _position?['department_head_effective_to']
                                ?.toString() ??
                            '',
                      );
                    }),
            ),
            Material(
              color: Colors.transparent,
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  _department
                      ? 'Official Department Head'
                      : 'Official Final Reviewer',
                ),
                value: _enabled,
                onChanged: _saving || _position == null
                    ? null
                    : (value) => setState(() => _enabled = value),
              ),
            ),
            if (_department && _enabled)
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
        onPressed: _saving || _position == null ? null : _save,
        icon: const Icon(Icons.save_outlined),
        label: Text(_saving ? 'Saving...' : 'Save designation'),
      ),
    ],
  );
}

String _isoDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
