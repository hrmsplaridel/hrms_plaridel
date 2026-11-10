import 'package:flutter/material.dart';
import 'package:hrms_plaridel/shared/widgets/settings_master_detail.dart';
import 'package:hrms_plaridel/shared/widgets/settings_loading_skeleton.dart';

import 'package:hrms_plaridel/features/docutracker/data/repositories/docutracker_repository.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_builder.dart';
import 'package:hrms_plaridel/features/docutracker/models/official_signatory.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/widgets/docutracker_slide_in_panel.dart';
import 'package:hrms_plaridel/features/docutracker/services/employee_directory_lookup.dart';

const _dtrRoles = {
  'dtr_office_hours_verifier': 'Office-hours Verifier',
  'dtr_hr_officer': 'HR Report Officer',
};

const _memorandumRoles = <({String key, String title, String subtitle})>[
  (
    key: 'memo_prepared_by',
    title: 'Prepared by',
    subtitle: 'HR Department Head',
  ),
  (
    key: 'memo_noted_by',
    title: 'Noted by',
    subtitle: "Mayor's Office representative",
  ),
  (key: 'memo_approved_by', title: 'Approved by', subtitle: 'Municipal Mayor'),
];

String docuTrackerMemoSignatoryConfigurationMessage(
  List<OfficialSignatoryPeriod> periods,
) {
  OfficialSignatoryPeriod? current(String roleKey) {
    for (final period in periods) {
      if (period.roleKey == roleKey && period.isEffective) return period;
    }
    return null;
  }

  final prepared = current('memo_prepared_by');
  final noted = current('memo_noted_by');
  final approved = current('memo_approved_by');
  final missing = [
    if (prepared == null) 'Prepared by',
    if (noted == null) 'Noted by',
    if (approved == null) 'Approved by',
  ];
  final sameAccount =
      noted != null &&
      approved != null &&
      noted.employeeId.isNotEmpty &&
      noted.employeeId == approved.employeeId;
  if (sameAccount) {
    return 'Noted by and Approved by are the same account. New memorandums '
        'keep automatic signatories until those assignments are different people.';
  }
  if (missing.isNotEmpty) {
    return 'New memorandums keep automatic signatories until every '
        'Memorandum assignment is configured. Missing: ${missing.join(', ')}.';
  }
  return 'New memorandums use the configured Prepared by, Noted by, and '
      'Approved by officials. Existing documents stay unchanged.';
}

class DocuTrackerMemorandumSignatorySection extends StatelessWidget {
  const DocuTrackerMemorandumSignatorySection({
    super.key,
    required this.periods,
    required this.onConfigure,
    this.resolution,
    this.automaticResolutionUnavailable = false,
  });

  final List<OfficialSignatoryPeriod> periods;
  final ValueChanged<String> onConfigure;
  final DocuTrackerMemoSignatories? resolution;
  final bool automaticResolutionUnavailable;

  bool get _usesAutomatic {
    final configuration = resolution?.configuration;
    if (configuration != null) return configuration.usesAutomaticResolution;
    return !docuTrackerMemoSignatoryConfigurationMessage(
      periods,
    ).startsWith('New memorandums use the configured');
  }

  DocuTrackerMemoDepartmentHead? _automaticSigner(String roleKey) {
    return switch (roleKey) {
      'memo_prepared_by' => resolution?.preparedBy,
      'memo_noted_by' => resolution?.notedBy,
      'memo_approved_by' => resolution?.approvedBy,
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final usesAutomatic = _usesAutomatic;
    final unavailable =
        usesAutomatic &&
        (automaticResolutionUnavailable || resolution?.configuration == null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Memorandum', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          docuTrackerMemoSignatoryConfigurationMessage(periods),
          style: theme.textTheme.bodyMedium,
        ),
        if (usesAutomatic) ...[
          const SizedBox(height: 8),
          Text(
            unavailable
                ? 'Automatic signatories could not be loaded. Opening this '
                      'screen does not save a configuration.'
                : 'Automatic names are resolved for new memorandums. They are '
                      'not saved Official Signatories.',
            style: theme.textTheme.bodyMedium,
          ),
        ],
        const SizedBox(height: 16),
        for (final role in _memorandumRoles) ...[
          _SignatorySection(
            roleKey: role.key,
            title: role.title,
            subtitle: role.subtitle,
            periods: [
              for (final period in periods)
                if (period.roleKey == role.key) period,
            ],
            onConfigure: () => onConfigure(role.key),
            status: _MemorandumResolutionStatus(
              current: _currentPeriod(role.key),
              automatic: unavailable ? null : _automaticSigner(role.key),
              usesAutomatic: usesAutomatic,
              automaticUnavailable: unavailable,
            ),
          ),
          const SizedBox(height: 16),
        ],
      ],
    );
  }

  OfficialSignatoryPeriod? _currentPeriod(String roleKey) {
    for (final period in periods) {
      if (period.roleKey == roleKey && period.isEffective) return period;
    }
    return null;
  }
}

class DocuTrackerOfficialSignatoriesScreen extends StatefulWidget {
  const DocuTrackerOfficialSignatoriesScreen({super.key, this.dtrOnly = false});

  final bool dtrOnly;

  @override
  State<DocuTrackerOfficialSignatoriesScreen> createState() =>
      _DocuTrackerOfficialSignatoriesScreenState();
}

class _DocuTrackerOfficialSignatoriesScreenState
    extends State<DocuTrackerOfficialSignatoriesScreen> {
  final _repository = DocuTrackerRepository.instance;
  final _directory = EmployeeDirectoryLookup();
  List<OfficialSignatoryPeriod> _periods = const [];
  DocuTrackerMemoSignatories? _memoResolution;
  bool _memoResolutionUnavailable = false;
  AutomaticMayorSignatory? _mayor;
  bool _loading = true;
  bool _reResolving = false;
  String? _error;
  String _selectedRole = 'dtr_office_hours_verifier';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _reResolveSigners() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Re-resolve form signers?'),
        content: const Text(
          'This fills empty automatic e-sign slots on existing RSP and L&D forms '
          '(Prepared by, Checked by, Dept Head, Mayor, etc.). '
          'Already assigned or signed slots are not changed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Run backfill'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _reResolving = true);
    try {
      final summary = await _repository.reResolveSourceSignatureAssignments();
      if (!mounted) return;
      final processed = summary['processed'] ?? 0;
      final assigned = summary['assigned_forms'] ?? 0;
      final skipped = summary['skipped_forms'] ?? 0;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            'Backfill done: $assigned form(s) updated, '
            '$skipped already complete ($processed scanned).',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    } finally {
      if (mounted) setState(() => _reResolving = false);
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _directory.load();
      if (!_directory.isLoaded) {
        throw Exception('Employee directory could not be loaded.');
      }
      final results = await Future.wait([
        _repository.listOfficialSignatories(),
        if (!widget.dtrOnly) _repository.getAutomaticMayorSignatory(),
      ]);
      DocuTrackerMemoSignatories? memoResolution;
      var memoUnavailable = false;
      if (!widget.dtrOnly) {
        try {
          memoResolution = await _repository.getMemorandumSignatoryResolution();
          memoUnavailable = memoResolution?.configuration == null;
        } catch (_) {
          memoUnavailable = true;
        }
      }
      if (!mounted) return;
      setState(() {
        _periods = results[0] as List<OfficialSignatoryPeriod>;
        _mayor = widget.dtrOnly ? null : results[1] as AutomaticMayorSignatory?;
        _memoResolution = memoResolution;
        _memoResolutionUnavailable = memoUnavailable;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _configure(String roleKey) async {
    final eligible = _directory.entries;
    final current = _periods.cast<OfficialSignatoryPeriod?>().firstWhere(
      (period) => period?.roleKey == roleKey && period?.isEffective == true,
      orElse: () => null,
    );
    final saved = await showDocuTrackerSlideInPanel<bool>(
      context: context,
      title: 'Configure ${_roleTitle(roleKey)}',
      width: 560,
      child: DocuTrackerOfficialSignatoryPanel(
        roleKey: roleKey,
        employees: eligible,
        current: current,
      ),
    );
    if (saved == true && mounted) {
      await _load();
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Row(
            children: [
              const Icon(
                Icons.check_circle_outline_rounded,
                color: Colors.white,
              ),
              const SizedBox(width: 12),
              Expanded(child: Text('${_roleTitle(roleKey)} saved.')),
            ],
          ),
        ),
      );
    }
  }

  List<OfficialSignatoryPeriod> _forRole(String roleKey) => _periods
      .where((period) => period.roleKey == roleKey)
      .toList(growable: false);

  String _roleTitle(String roleKey) {
    for (final role in _memorandumRoles) {
      if (role.key == roleKey) return role.title;
    }
    return _dtrRoles[roleKey] ?? roleKey;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.dtrOnly) return _buildDtrLayout();
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !widget.dtrOnly,
        title: Text(
          widget.dtrOnly ? 'Report Signatories' : 'Official Signatories',
        ),
        actions: [
          if (!widget.dtrOnly)
            TextButton.icon(
              onPressed: (_loading || _reResolving) ? null : _reResolveSigners,
              icon: _reResolving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.manage_history_rounded),
              label: Text(_reResolving ? 'Backfilling…' : 'Re-resolve signers'),
            ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                key: PageStorageKey(
                  'official-signatories-list-${widget.dtrOnly}',
                ),
                primary: false,
                padding: const EdgeInsets.all(24),
                children: [
                  if (_error != null) ...[
                    MaterialBanner(
                      content: Text(_error!),
                      actions: [
                        TextButton(
                          onPressed: _load,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (widget.dtrOnly)
                    for (final role in _dtrRoles.entries) ...[
                      _SignatorySection(
                        roleKey: role.key,
                        title: role.value,
                        subtitle: 'DTR and tardiness reports',
                        periods: _forRole(role.key),
                        onConfigure: () => _configure(role.key),
                      ),
                      const SizedBox(height: 16),
                    ],
                  if (!widget.dtrOnly)
                    DocuTrackerMemorandumSignatorySection(
                      periods: _periods,
                      onConfigure: _configure,
                      resolution: _memoResolution,
                      automaticResolutionUnavailable:
                          _memoResolutionUnavailable,
                    ),
                  const ListTile(
                    leading: Icon(Icons.info_outline),
                    title: Text('Leave credit certification (7.A)'),
                    subtitle: Text(
                      'Uses the primary Final HR Review assignment in Approvals & '
                      'Signatories. The signature appears only when that reviewer '
                      'personally signs the request.',
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (!widget.dtrOnly) _AutomaticMayorSection(mayor: _mayor),
                  const SizedBox(height: 16),
                  if (!widget.dtrOnly)
                    _BackfillHintCard(
                      onRun: _reResolveSigners,
                      busy: _reResolving,
                    ),
                ],
              ),
            ),
    );
  }

  Widget _buildDtrLayout() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Report Signatories',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            IconButton(
              tooltip: 'Refresh',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const Text(
          'Leave form 7.A uses the primary Final HR Review assignment in '
          'Approvals & Signatories.',
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
              key: const PageStorageKey('signatory-master-detail'),
              searchLabel: 'Search roles',
              selectedId: _selectedRole,
              entries: [
                for (final role in _dtrRoles.entries)
                  SettingsListEntry(
                    id: role.key,
                    title: role.value,
                    icon: Icons.draw_outlined,
                    subtitle:
                        _forRole(
                          role.key,
                        ).where((p) => p.isEffective).firstOrNull?.name ??
                        'Not configured for today',
                  ),
              ],
              onSelected: (role) => setState(() => _selectedRole = role),
              detail: ListView(
                key: PageStorageKey('official-signatory-detail-$_selectedRole'),
                primary: false,
                padding: const EdgeInsets.all(8),
                children: [
                  _SignatorySection(
                    roleKey: _selectedRole,
                    title: _dtrRoles[_selectedRole]!,
                    subtitle: 'DTR and tardiness reports',
                    periods: _forRole(_selectedRole),
                    onConfigure: () => _configure(_selectedRole),
                    framed: false,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _BackfillHintCard extends StatelessWidget {
  const _BackfillHintCard({required this.onRun, required this.busy});

  final VoidCallback onRun;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.manage_history_rounded),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Existing RSP / L&D forms',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  'Forms saved before auto-assign may still have empty e-sign '
                  'slots. Re-resolve fills only empty automatic slots '
                  '(creator, HRMDO, department head, mayor).',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  onPressed: busy ? null : onRun,
                  icon: busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.manage_history_rounded),
                  label: Text(busy ? 'Backfilling…' : 'Re-resolve signers'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AutomaticMayorSection extends StatelessWidget {
  const _AutomaticMayorSection({required this.mayor});

  final AutomaticMayorSignatory? mayor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final details = [
      mayor?.positionTitle,
      mayor?.departmentName,
    ].whereType<String>().where((value) => value.trim().isNotEmpty).join(' · ');
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.verified_user_outlined),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Leave Approving Authority',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  mayor?.name ?? 'No active Mayor account found',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                if (details.isNotEmpty) Text(details),
              ],
            ),
          ),
          const Chip(label: Text('Automatic')),
        ],
      ),
    );
  }
}

class _SignatorySection extends StatelessWidget {
  const _SignatorySection({
    required this.roleKey,
    required this.title,
    required this.subtitle,
    required this.periods,
    required this.onConfigure,
    this.status,
    this.framed = true,
  });

  final String roleKey;
  final String title;
  final String subtitle;
  final List<OfficialSignatoryPeriod> periods;
  final VoidCallback onConfigure;
  final Widget? status;
  final bool framed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = periods.cast<OfficialSignatoryPeriod?>().firstWhere(
      (period) => period?.isEffective == true,
      orElse: () => null,
    );
    return Container(
      decoration: !framed
          ? null
          : BoxDecoration(
              border: Border.all(color: theme.dividerColor),
              borderRadius: BorderRadius.circular(8),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(18),
            child: _SignatorySectionHeader(
              title: title,
              subtitle: subtitle,
              onConfigure: onConfigure,
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(18),
            child:
                status ??
                (current == null
                    ? const Text('No official is configured for today.')
                    : _PeriodDetails(period: current, showStatus: true)),
          ),
          if (periods.isNotEmpty) ...[
            const Divider(height: 1),
            ExpansionTile(
              key: PageStorageKey('official-signatory-history-$roleKey'),
              title: Text('Designation history (${periods.length})'),
              children: periods
                  .map(
                    (period) => Padding(
                      padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
                      child: _PeriodDetails(period: period),
                    ),
                  )
                  .toList(growable: false),
            ),
          ],
        ],
      ),
    );
  }
}

class _SignatorySectionHeader extends StatelessWidget {
  const _SignatorySectionHeader({
    required this.title,
    required this.subtitle,
    required this.onConfigure,
  });

  final String title;
  final String subtitle;
  final VoidCallback onConfigure;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final identity = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(subtitle, style: theme.textTheme.bodySmall),
      ],
    );
    final action = FilledButton.icon(
      onPressed: onConfigure,
      icon: const Icon(Icons.edit_outlined),
      label: const Text('Configure'),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 560;
        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.draw_outlined),
                  const SizedBox(width: 12),
                  Expanded(child: identity),
                ],
              ),
              const SizedBox(height: 12),
              Align(alignment: Alignment.centerLeft, child: action),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.draw_outlined),
            const SizedBox(width: 12),
            Expanded(child: identity),
            const SizedBox(width: 12),
            action,
          ],
        );
      },
    );
  }
}

class _MemorandumResolutionStatus extends StatelessWidget {
  const _MemorandumResolutionStatus({
    required this.current,
    required this.automatic,
    required this.usesAutomatic,
    required this.automaticUnavailable,
  });

  final OfficialSignatoryPeriod? current;
  final DocuTrackerMemoDepartmentHead? automatic;
  final bool usesAutomatic;
  final bool automaticUnavailable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = theme.textTheme.labelLarge;
    final automaticName = automatic?.fullName.trim() ?? '';
    final position = automatic?.position?.trim() ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Configuration', style: label),
        const SizedBox(height: 4),
        if (current == null)
          const Text('Not configured')
        else ...[
          _PeriodDetails(period: current!, showStatus: !usesAutomatic),
          if (usesAutomatic) ...[
            const SizedBox(height: 4),
            Text(
              'Saved configuration. New memorandums still use automatic '
              'signatories until every role is valid.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ],
        if (usesAutomatic && !automaticUnavailable) ...[
          const SizedBox(height: 12),
          Text('Currently automatic', style: label),
          const SizedBox(height: 4),
          Text(
            automaticName.isEmpty ? 'None available' : automaticName,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          if (position.isNotEmpty) Text(position),
        ],
      ],
    );
  }
}

class _PeriodDetails extends StatelessWidget {
  const _PeriodDetails({required this.period, this.showStatus = false});

  final OfficialSignatoryPeriod period;
  final bool showStatus;

  @override
  Widget build(BuildContext context) {
    final details = [
      period.positionTitle,
      period.departmentName,
    ].whereType<String>().where((value) => value.trim().isNotEmpty).join(' · ');
    final end = period.effectiveTo == null
        ? 'Onward'
        : _displayDate(period.effectiveTo!);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                period.name,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              if (details.isNotEmpty) Text(details),
              const SizedBox(height: 4),
              Text('${_displayDate(period.effectiveFrom)} to $end'),
            ],
          ),
        ),
        if (showStatus && period.isEffective)
          const Chip(label: Text('Current')),
      ],
    );
  }
}

class DocuTrackerSignatoryEmployeeField extends StatelessWidget {
  const DocuTrackerSignatoryEmployeeField({
    super.key,
    required this.employees,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final List<EmployeeDirectoryEntry> employees;
  final String? value;
  final ValueChanged<String?> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final selected = employees.any((employee) => employee.id == value)
        ? value
        : null;
    final theme = Theme.of(context);
    final menuHeight = MediaQuery.sizeOf(context).height * 0.45;
    return DropdownButtonFormField<String>(
      initialValue: selected,
      isExpanded: true,
      menuMaxHeight: menuHeight < 160 ? 160 : menuHeight,
      itemHeight: 72,
      decoration: const InputDecoration(
        hintText: 'Select employee',
        prefixIcon: Icon(Icons.person_outline_rounded),
      ),
      selectedItemBuilder: (context) => [
        for (final employee in employees)
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              employee.signatorySelectionLine,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      items: [
        for (final employee in employees)
          DropdownMenuItem<String>(
            value: employee.id,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  employee.fullName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
                if (employee.signatorySelectionDetails.isNotEmpty)
                  Text(
                    employee.signatorySelectionDetails,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
              ],
            ),
          ),
      ],
      onChanged: enabled ? onChanged : null,
      validator: (choice) => choice == null ? 'Select an employee.' : null,
    );
  }
}

class DocuTrackerOfficialSignatoryPanel extends StatefulWidget {
  const DocuTrackerOfficialSignatoryPanel({
    super.key,
    required this.roleKey,
    required this.employees,
    required this.current,
  });

  final String roleKey;
  final List<EmployeeDirectoryEntry> employees;
  final OfficialSignatoryPeriod? current;

  @override
  State<DocuTrackerOfficialSignatoryPanel> createState() =>
      _OfficialSignatoryPanelState();
}

class _OfficialSignatoryPanelState
    extends State<DocuTrackerOfficialSignatoryPanel> {
  final _formKey = GlobalKey<FormState>();
  final _remarksController = TextEditingController();
  String? _employeeId;
  late DateTime _effectiveFrom;
  DateTime? _effectiveTo;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _employeeId = widget.current?.employeeId;
    _effectiveFrom = DateUtils.dateOnly(DateTime.now());
  }

  @override
  void dispose() {
    _remarksController.dispose();
    super.dispose();
  }

  Future<void> _pickFrom() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _effectiveFrom,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (selected != null) setState(() => _effectiveFrom = selected);
  }

  Future<void> _pickTo() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _effectiveTo ?? _effectiveFrom,
      firstDate: _effectiveFrom,
      lastDate: DateTime(2100),
    );
    if (selected != null) setState(() => _effectiveTo = selected);
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await DocuTrackerRepository.instance.configureOfficialSignatory(
        roleKey: widget.roleKey,
        employeeId: _employeeId!,
        effectiveFrom: _effectiveFrom,
        effectiveTo: _effectiveTo,
        remarks: _remarksController.text,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error.toString().replaceFirst('Exception: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _dateButton({
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      height: 48,
      child: OutlinedButton.icon(
        onPressed: _saving ? null : onPressed,
        icon: Icon(icon, size: 19),
        label: Text(label, overflow: TextOverflow.ellipsis),
      ),
    );
  }

  Widget _buildEffectivePeriod() {
    final from = _dateButton(
      label: 'From ${_displayDate(_effectiveFrom)}',
      icon: Icons.calendar_today_outlined,
      onPressed: _pickFrom,
    );
    final to = Row(
      children: [
        Expanded(
          child: _dateButton(
            label: _effectiveTo == null
                ? 'No end date'
                : 'To ${_displayDate(_effectiveTo!)}',
            icon: Icons.event_outlined,
            onPressed: _pickTo,
          ),
        ),
        if (_effectiveTo != null) ...[
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'Clear end date',
            onPressed: _saving
                ? null
                : () => setState(() => _effectiveTo = null),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 640) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [from, const SizedBox(height: 10), to],
          );
        }
        return Row(
          children: [
            Expanded(child: from),
            const SizedBox(width: 12),
            Expanded(child: to),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.scaffoldBackgroundColor,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Employee', style: theme.textTheme.labelLarge),
                    const SizedBox(height: 8),
                    DocuTrackerSignatoryEmployeeField(
                      employees: widget.employees,
                      value: _employeeId,
                      enabled: !_saving,
                      onChanged: (value) => setState(() => _employeeId = value),
                    ),
                    const SizedBox(height: 24),
                    Text('Effective period', style: theme.textTheme.labelLarge),
                    const SizedBox(height: 8),
                    _buildEffectivePeriod(),
                    const SizedBox(height: 24),
                    Text('Remarks', style: theme.textTheme.labelLarge),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _remarksController,
                      enabled: !_saving,
                      minLines: 3,
                      maxLines: 5,
                      decoration: const InputDecoration(
                        hintText: 'Optional',
                        alignLabelWithHint: true,
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.errorContainer,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.error_outline_rounded,
                              size: 20,
                              color: theme.colorScheme.onErrorContainer,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _error!,
                                style: TextStyle(
                                  color: theme.colorScheme.onErrorContainer,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 16),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: theme.dividerColor)),
              ),
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 12,
                runSpacing: 8,
                children: [
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_outlined),
                    label: const Text('Save'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _displayDate(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';
