import 'package:flutter/material.dart';

import 'package:hrms_plaridel/features/docutracker/data/repositories/docutracker_repository.dart';
import 'package:hrms_plaridel/features/docutracker/models/official_signatory.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/widgets/docutracker_slide_in_panel.dart';
import 'package:hrms_plaridel/features/docutracker/services/employee_directory_lookup.dart';

const _creditCertifier = 'leave_credit_certifier';

class DocuTrackerOfficialSignatoriesScreen extends StatefulWidget {
  const DocuTrackerOfficialSignatoriesScreen({super.key});

  @override
  State<DocuTrackerOfficialSignatoriesScreen> createState() =>
      _DocuTrackerOfficialSignatoriesScreenState();
}

class _DocuTrackerOfficialSignatoriesScreenState
    extends State<DocuTrackerOfficialSignatoriesScreen> {
  final _repository = DocuTrackerRepository.instance;
  final _directory = EmployeeDirectoryLookup();
  List<OfficialSignatoryPeriod> _periods = const [];
  AutomaticMayorSignatory? _mayor;
  bool _loading = true;
  bool _reResolving = false;
  String? _error;

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
          content: Text(
            error.toString().replaceFirst('Exception: ', ''),
          ),
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
      final results = await Future.wait([
        _repository.listOfficialSignatories(),
        _repository.getAutomaticMayorSignatory(),
      ]);
      if (!mounted) return;
      setState(() {
        _periods = results[0] as List<OfficialSignatoryPeriod>;
        _mayor = results[1] as AutomaticMayorSignatory?;
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
      title: 'Configure Leave Credit Certifier',
      width: 560,
      child: _OfficialSignatoryPanel(
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
          content: const Row(
            children: [
              Icon(Icons.check_circle_outline_rounded, color: Colors.white),
              SizedBox(width: 12),
              Expanded(child: Text('Leave Credit Certifier saved.')),
            ],
          ),
        ),
      );
    }
  }

  List<OfficialSignatoryPeriod> _forRole(String roleKey) => _periods
      .where((period) => period.roleKey == roleKey)
      .toList(growable: false);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Official Signatories'),
        actions: [
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
                  _SignatorySection(
                    title: 'Leave Credit Certifier',
                    subtitle: 'Printed in section 7.A of the leave form.',
                    periods: _forRole(_creditCertifier),
                    onConfigure: () => _configure(_creditCertifier),
                  ),
                  const SizedBox(height: 16),
                  _AutomaticMayorSection(mayor: _mayor),
                  const SizedBox(height: 16),
                  _BackfillHintCard(onRun: _reResolveSigners, busy: _reResolving),
                ],
              ),
            ),
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
    required this.title,
    required this.subtitle,
    required this.periods,
    required this.onConfigure,
  });

  final String title;
  final String subtitle;
  final List<OfficialSignatoryPeriod> periods;
  final VoidCallback onConfigure;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = periods.cast<OfficialSignatoryPeriod?>().firstWhere(
      (period) => period?.isEffective == true,
      orElse: () => null,
    );
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.draw_outlined),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text(subtitle, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                FilledButton.icon(
                  onPressed: onConfigure,
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Configure'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(18),
            child: current == null
                ? const Text('No official is configured for today.')
                : _PeriodDetails(period: current, showStatus: true),
          ),
          if (periods.isNotEmpty) ...[
            const Divider(height: 1),
            ExpansionTile(
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

class _OfficialSignatoryPanel extends StatefulWidget {
  const _OfficialSignatoryPanel({
    required this.roleKey,
    required this.employees,
    required this.current,
  });

  final String roleKey;
  final List<EmployeeDirectoryEntry> employees;
  final OfficialSignatoryPeriod? current;

  @override
  State<_OfficialSignatoryPanel> createState() =>
      _OfficialSignatoryPanelState();
}

class _OfficialSignatoryPanelState extends State<_OfficialSignatoryPanel> {
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
        if (constraints.maxWidth < 440) {
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
                    DropdownButtonFormField<String>(
                      initialValue:
                          widget.employees.any(
                            (employee) => employee.id == _employeeId,
                          )
                          ? _employeeId
                          : null,
                      decoration: const InputDecoration(
                        hintText: 'Select employee',
                        prefixIcon: Icon(Icons.person_outline_rounded),
                      ),
                      isExpanded: true,
                      items: widget.employees
                          .map(
                            (employee) => DropdownMenuItem(
                              value: employee.id,
                              child: Text(
                                [employee.fullName, employee.positionName]
                                    .whereType<String>()
                                    .where((value) => value.trim().isNotEmpty)
                                    .join(' · '),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: _saving
                          ? null
                          : (value) => setState(() => _employeeId = value),
                      validator: (value) =>
                          value == null ? 'Select an employee.' : null,
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
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
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
