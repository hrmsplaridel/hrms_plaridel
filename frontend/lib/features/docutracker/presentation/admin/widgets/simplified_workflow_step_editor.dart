import 'package:flutter/material.dart';

import 'package:hrms_plaridel/features/docutracker/models/workflow_step.dart';
import 'package:hrms_plaridel/features/docutracker/services/employee_directory_lookup.dart';
import 'package:hrms_plaridel/features/docutracker/theme/docutracker_tokens.dart';
import 'package:hrms_plaridel/features/docutracker/utils/docutracker_return_text.dart';
import 'package:hrms_plaridel/features/dtr/management/approvals/widgets/workflow_reviewer_configuration.dart';

enum _AssigneeMode {
  specificPeople,
  submitterDepartmentHead,
  fixedDepartmentHead,
  finalHr,
  currentMayor,
  manualMayor,
}

class SimplifiedWorkflowStepEditor extends StatefulWidget {
  const SimplifiedWorkflowStepEditor({
    super.key,
    required this.title,
    required this.initial,
    this.approvalOnly = false,
  });

  final String title;
  final WorkflowStep initial;
  final bool approvalOnly;

  @override
  State<SimplifiedWorkflowStepEditor> createState() =>
      _SimplifiedWorkflowStepEditorState();
}

class _SimplifiedWorkflowStepEditorState
    extends State<SimplifiedWorkflowStepEditor> {
  static const _actionMeta = <String, ({String title, String subtitle})>{
    'approve': (
      title: 'Approve and continue',
      subtitle: 'Approve and move to the next step.',
    ),
    'return': (
      title: docuTrackerReturnActionLabel,
      subtitle: 'Send back to the previous step.',
    ),
    'reject': (
      title: 'Reject and stop',
      subtitle: 'Reject the document and end the workflow.',
    ),
    'forward': (
      title: 'Forward without approval',
      subtitle: 'Send to another step without approving.',
    ),
  };

  final _directory = EmployeeDirectoryLookup();
  final _nameController = TextEditingController();
  final _deadlineController = TextEditingController();

  late bool _enabled;
  late bool _requiresSignature;
  late _AssigneeMode _assigneeMode;
  late Set<String> _allowedActions;
  String? _primaryUserId;
  String? _backupUserId;
  List<String> _legacyAdditionalBackupIds = const [];
  bool _loadingPeople = true;
  bool _searchingPrimary = false;
  bool _searchingBackup = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final step = widget.initial;
    _nameController.text = step.label ?? '';
    _deadlineController.text = step.deadlineHours?.toString() ?? '';
    _enabled = step.enabled;
    _requiresSignature = widget.approvalOnly || step.requiresSignature;
    if (step.assigneeSource == 'submitter_department_reviewers') {
      _assigneeMode = _AssigneeMode.submitterDepartmentHead;
    } else if (step.assigneeSource == 'department_reviewers') {
      _assigneeMode = _AssigneeMode.fixedDepartmentHead;
    } else if (step.assigneeSource == 'final_hr_reviewers') {
      _assigneeMode = _AssigneeMode.finalHr;
    } else if (step.assigneeSource == 'active_mayor') {
      _assigneeMode = _AssigneeMode.currentMayor;
    } else if (step.assigneeSource == 'manual_mayor') {
      _assigneeMode = _AssigneeMode.manualMayor;
    } else {
      _assigneeMode = _AssigneeMode.specificPeople;
    }
    final ids = (step.userIds ?? const <String>[])
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
    _primaryUserId = ids.isEmpty ? null : ids.first;
    _backupUserId = ids.length < 2 ? null : ids[1];
    _legacyAdditionalBackupIds = ids.length < 3
        ? const <String>[]
        : ids.sublist(2);
    _allowedActions = step.allowedActions
        .map((action) => action.trim().toLowerCase())
        .where(_actionMeta.containsKey)
        .toSet();
    if (widget.approvalOnly) {
      _allowedActions.remove('forward');
      _allowedActions.add('approve');
    }
    _searchingPrimary = _primaryUserId == null;
    _searchingBackup = _backupUserId == null;
    _loadPeople(ids);
  }

  Future<void> _loadPeople(List<String> currentIds) async {
    await _directory.load();
    await _directory.ensureIds(currentIds);
    if (!mounted) return;
    setState(() => _loadingPeople = false);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _deadlineController.dispose();
    super.dispose();
  }

  bool get _usesSpecificPeople => _assigneeMode == _AssigneeMode.specificPeople;

  bool get _usesSubmitterDepartmentHead =>
      _assigneeMode == _AssigneeMode.submitterDepartmentHead;

  bool get _usesFixedDepartmentHead =>
      _assigneeMode == _AssigneeMode.fixedDepartmentHead;

  Future<void> _configureReviewers() => showWorkflowReviewerConfiguration(
    context,
    source: _usesSubmitterDepartmentHead
        ? 'submitter_department_reviewers'
        : _usesFixedDepartmentHead
        ? 'department_reviewers'
        : 'final_hr_reviewers',
    departmentId: _usesFixedDepartmentHead ? widget.initial.departmentId : null,
  );

  void _submit() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Step name is required.');
      return;
    }
    if (_usesSpecificPeople && _primaryUserId == null) {
      setState(() => _error = 'Choose a primary assignee.');
      return;
    }
    if (_usesFixedDepartmentHead &&
        (widget.initial.departmentId ?? '').trim().isEmpty) {
      setState(
        () => _error =
            'This fixed-department reviewer step has no department. Choose specific people or Department reviewer of submitter instead.',
      );
      return;
    }
    if (_allowedActions.isEmpty) {
      setState(() => _error = 'Choose at least one allowed action.');
      return;
    }

    final deadlineText = _deadlineController.text.trim();
    final deadline = deadlineText.isEmpty ? null : int.tryParse(deadlineText);
    if (deadlineText.isNotEmpty && (deadline == null || deadline <= 0)) {
      setState(() => _error = 'Deadline must be a positive whole number.');
      return;
    }

    final userIds = <String>[
      if (_primaryUserId != null) _primaryUserId!,
      if (_backupUserId != null && _backupUserId != _primaryUserId)
        _backupUserId!,
      for (final id in _legacyAdditionalBackupIds)
        if (id != _primaryUserId && id != _backupUserId) id,
    ];
    final primaryDepartmentId = _primaryUserId == null
        ? null
        : _directory[_primaryUserId!]?.departmentId;

    final String assigneeSource;
    final String? departmentId;
    final List<String> savedUserIds;
    switch (_assigneeMode) {
      case _AssigneeMode.submitterDepartmentHead:
        assigneeSource = 'submitter_department_reviewers';
        departmentId = null;
        savedUserIds = const [];
      case _AssigneeMode.fixedDepartmentHead:
        assigneeSource = 'department_reviewers';
        departmentId = widget.initial.departmentId;
        savedUserIds = const [];
      case _AssigneeMode.specificPeople:
        assigneeSource = 'specific_users';
        departmentId = primaryDepartmentId;
        savedUserIds = userIds;
      case _AssigneeMode.finalHr:
        assigneeSource = 'final_hr_reviewers';
        departmentId = null;
        savedUserIds = const [];
      case _AssigneeMode.currentMayor:
        assigneeSource = 'active_mayor';
        departmentId = null;
        savedUserIds = const [];
      case _AssigneeMode.manualMayor:
        assigneeSource = 'manual_mayor';
        departmentId = null;
        savedUserIds = const [];
    }

    Navigator.of(context).pop(
      WorkflowStep(
        stepOrder: widget.initial.stepOrder,
        assigneeType: 'user',
        assigneeSource: assigneeSource,
        departmentId: departmentId,
        userIds: savedUserIds,
        label: name,
        enabled: _enabled,
        deadlineHours: deadline,
        requiresSignature: _requiresSignature,
        allowedActions: _allowedActions.toList(growable: false),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canUseFixedDepartment =
        (widget.initial.departmentId ?? '').trim().isNotEmpty ||
        _usesFixedDepartmentHead;
    final primary = DocuTrackerTokens.textPrimaryOf(context);
    final muted = DocuTrackerTokens.textMutedOf(context);
    final narrow = MediaQuery.sizeOf(context).width < 600;
    final contentPad = narrow ? 14.0 : 20.0;

    return RadioGroup<_AssigneeMode>(
      groupValue: _assigneeMode,
      onChanged: (value) => setState(() {
        _assigneeMode = value!;
        _error = null;
      }),
      child: Material(
        color: DocuTrackerTokens.surfaceOf(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(
              title: widget.title,
              compact: narrow,
              onClose: () => Navigator.of(context).pop(),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  contentPad,
                  narrow ? 12 : 16,
                  contentPad,
                  20,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _FieldHeading(
                      number: 1,
                      label: 'Step Name',
                      required: true,
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      key: const ValueKey('workflow-step-name'),
                      controller: _nameController,
                      decoration:
                          DocuTrackerTokens.warmSearchDecoration(
                            context,
                            'Example: Department Head Review',
                          ).copyWith(
                            prefixIcon: Icon(
                              Icons.description_outlined,
                              color: DocuTrackerTokens.brand.withValues(
                                alpha: 0.9,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                DocuTrackerTokens.radiusMd,
                              ),
                              borderSide: const BorderSide(
                                color: DocuTrackerTokens.brand,
                                width: 1.5,
                              ),
                            ),
                          ),
                      onChanged: (_) => setState(() => _error = null),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Use a clear name for this approval step (e.g., '
                      'Department Head Review, Final Approval).',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        color: muted,
                      ),
                    ),
                    const SizedBox(height: 20),
                    const _FieldHeading(
                      number: 2,
                      label: 'Assign Mode',
                      required: true,
                    ),
                    const SizedBox(height: 8),
                    if (narrow) ...[
                      _AssignModeCard(
                        key: const ValueKey('workflow-step-mode-specific'),
                        value: _AssigneeMode.specificPeople,
                        selected: _assigneeMode == _AssigneeMode.specificPeople,
                        icon: Icons.groups_outlined,
                        title: 'Specific people',
                        subtitle:
                            'Pick a primary assignee and an optional backup.',
                        onTap: () => setState(() {
                          _assigneeMode = _AssigneeMode.specificPeople;
                          _error = null;
                        }),
                      ),
                      const SizedBox(height: 10),
                      _AssignModeCard(
                        key: const ValueKey('workflow-step-mode-submitter'),
                        value: _AssigneeMode.submitterDepartmentHead,
                        selected:
                            _assigneeMode ==
                            _AssigneeMode.submitterDepartmentHead,
                        icon: Icons.apartment_outlined,
                        title: 'Department reviewer of submitter',
                        subtitle:
                            'Routes to the primary reviewer of the '
                            'submitter\'s department. If the primary '
                            'reviewer is the document creator, an eligible '
                            'backup reviewer is used instead.',
                        onTap: () => setState(() {
                          _assigneeMode = _AssigneeMode.submitterDepartmentHead;
                          _error = null;
                        }),
                      ),
                    ] else
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _AssignModeCard(
                              key: const ValueKey(
                                'workflow-step-mode-specific',
                              ),
                              value: _AssigneeMode.specificPeople,
                              selected:
                                  _assigneeMode == _AssigneeMode.specificPeople,
                              icon: Icons.groups_outlined,
                              title: 'Specific people',
                              subtitle:
                                  'Pick a primary assignee and an optional backup.',
                              onTap: () => setState(() {
                                _assigneeMode = _AssigneeMode.specificPeople;
                                _error = null;
                              }),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _AssignModeCard(
                              key: const ValueKey(
                                'workflow-step-mode-submitter',
                              ),
                              value: _AssigneeMode.submitterDepartmentHead,
                              selected:
                                  _assigneeMode ==
                                  _AssigneeMode.submitterDepartmentHead,
                              icon: Icons.apartment_outlined,
                              title: 'Department reviewer of submitter',
                              subtitle:
                                  'Routes to the primary reviewer of the '
                                  'submitter\'s department. If the primary '
                                  'reviewer is the document creator, an '
                                  'eligible backup reviewer is used instead.',
                              onTap: () => setState(() {
                                _assigneeMode =
                                    _AssigneeMode.submitterDepartmentHead;
                                _error = null;
                              }),
                            ),
                          ),
                        ],
                      ),
                    if (canUseFixedDepartment) ...[
                      const SizedBox(height: 10),
                      _AssignModeCard(
                        value: _AssigneeMode.fixedDepartmentHead,
                        selected:
                            _assigneeMode == _AssigneeMode.fixedDepartmentHead,
                        icon: Icons.business_outlined,
                        title: 'Department reviewer of a fixed department',
                        subtitle:
                            'Legacy: keeps the department stored on this step.',
                        onTap: () => setState(() {
                          _assigneeMode = _AssigneeMode.fixedDepartmentHead;
                          _error = null;
                        }),
                      ),
                    ],
                    if (widget.approvalOnly) ...[
                      const SizedBox(height: 10),
                      for (final option in {
                        _AssigneeMode.finalHr: (
                          'Configured Final HR reviewers',
                          Icons.badge_outlined,
                        ),
                        _AssigneeMode.currentMayor: (
                          'Current Municipal Mayor',
                          Icons.account_balance_outlined,
                        ),
                        _AssigneeMode.manualMayor: (
                          'Manual Mayor signing (printed form)',
                          Icons.draw_outlined,
                        ),
                      }.entries)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _AssignModeCard(
                            value: option.key,
                            selected: _assigneeMode == option.key,
                            icon: option.value.$2,
                            title: option.value.$1,
                            subtitle: 'Approval workflow assignee mode.',
                            onTap: () => setState(() {
                              _assigneeMode = option.key;
                              _error = null;
                            }),
                          ),
                        ),
                    ],
                    const SizedBox(height: 20),
                    if (_usesSubmitterDepartmentHead) ...[
                      const _FieldHeading(
                        number: 3,
                        label: 'Resolved Assignees',
                      ),
                      const SizedBox(height: 8),
                      const _InfoBanner(
                        text:
                            'Primary: the primary reviewer (Department Head) of '
                            'the submitter\'s department at routing time.\n'
                            'Backup: that department\'s backup reviewers, in '
                            'their configured order.\n'
                            'The submitter never reviews their own document. '
                            'If no other reviewer is eligible, submission is '
                            'blocked.\n'
                            'Use Configure reviewers below to manage this '
                            'shared department group from the workflow editor.',
                      ),
                    ] else if (_usesFixedDepartmentHead) ...[
                      const _FieldHeading(
                        number: 3,
                        label: 'Resolved Assignees',
                      ),
                      const SizedBox(height: 8),
                      const _InfoBanner(
                        text:
                            'Primary: the primary reviewer (Department Head) of '
                            'the fixed department on this step.\n'
                            'Backup: that department\'s backup reviewers, in '
                            'their configured order.\n'
                            'The submitter never reviews their own document.',
                      ),
                    ] else if (_usesSpecificPeople) ...[
                      const _FieldHeading(
                        number: 3,
                        label: 'Primary Assignee',
                        required: true,
                      ),
                      const SizedBox(height: 8),
                      if (_loadingPeople)
                        const LinearProgressIndicator(minHeight: 2)
                      else
                        _AssigneeField(
                          key: const ValueKey('workflow-step-primary'),
                          hint: 'Search by name, department, or position',
                          selectedId: _primaryUserId,
                          excludeId: _backupUserId,
                          searching: _searchingPrimary,
                          directory: _directory,
                          onStartSearch: () =>
                              setState(() => _searchingPrimary = true),
                          onChanged: (value) => setState(() {
                            _primaryUserId = value;
                            _searchingPrimary = value == null;
                            if (_backupUserId == value) {
                              _backupUserId = null;
                              _searchingBackup = true;
                            }
                            _legacyAdditionalBackupIds =
                                _legacyAdditionalBackupIds
                                    .where((id) => id != value)
                                    .toList(growable: false);
                            _error = null;
                          }),
                        ),
                      const SizedBox(height: 18),
                      const _FieldHeading(
                        number: 4,
                        label: 'Backup Assignee (Optional)',
                      ),
                      const SizedBox(height: 8),
                      if (!_loadingPeople)
                        _AssigneeField(
                          key: const ValueKey('workflow-step-backup'),
                          hint: 'Search optional backup',
                          selectedId: _backupUserId,
                          excludeId: _primaryUserId,
                          searching: _searchingBackup,
                          optional: true,
                          directory: _directory,
                          onStartSearch: () =>
                              setState(() => _searchingBackup = true),
                          onChanged: (value) => setState(() {
                            _backupUserId = value;
                            _searchingBackup = value == null;
                            _error = null;
                          }),
                        ),
                      const SizedBox(height: 8),
                      const _InfoBanner(
                        text:
                            'The backup assignee can act on the document if '
                            'the primary assignee is unavailable.',
                      ),
                      if (_legacyAdditionalBackupIds.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          '${_legacyAdditionalBackupIds.length} additional '
                          'existing backup(s) will be preserved for '
                          'compatibility.',
                          style: TextStyle(color: muted, fontSize: 11),
                        ),
                      ],
                    ],
                    if (_usesSubmitterDepartmentHead ||
                        _usesFixedDepartmentHead ||
                        _assigneeMode == _AssigneeMode.finalHr) ...[
                      const SizedBox(height: 12),
                      if (_assigneeMode == _AssigneeMode.finalHr)
                        const _InfoBanner(
                          text:
                              'Uses the shared Final HR primary and backup '
                              'reviewers. Configure this group here; changes '
                              'apply to every workflow using Final HR review.',
                        ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: _configureReviewers,
                          icon: const Icon(Icons.manage_accounts_outlined),
                          label: const Text('Configure reviewers'),
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    const _FieldHeading(
                      number: 5,
                      label: 'Allowed Actions',
                      required: true,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Choose the actions this step can perform. These apply '
                      'equally to the primary and backup assignee.',
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.35,
                        color: muted,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _ActionGrid(
                      narrow: narrow,
                      approvalOnly: widget.approvalOnly,
                      allowedActions: _allowedActions,
                      meta: _actionMeta,
                      onToggle: (action, checked) => setState(() {
                        if (checked) {
                          _allowedActions.add(action);
                        } else {
                          _allowedActions.remove(action);
                        }
                        _error = null;
                      }),
                    ),
                    const SizedBox(height: 10),
                    const _InfoBanner(
                      text: 'Note: At least one action must be selected.',
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      key: const Key('workflow-step-requires-signature'),
                      contentPadding: EdgeInsets.zero,
                      secondary: Icon(
                        Icons.draw_outlined,
                        color: DocuTrackerTokens.brand,
                      ),
                      title: Text(
                        'Signature required',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: primary,
                        ),
                      ),
                      subtitle: Text(
                        'The reviewer must sign the document before they can '
                        'approve or forward it at this step.',
                        style: TextStyle(color: muted, fontSize: 12),
                      ),
                      value: _requiresSignature,
                      activeThumbColor: DocuTrackerTokens.brand,
                      onChanged: widget.approvalOnly
                          ? null
                          : (value) =>
                                setState(() => _requiresSignature = value),
                    ),
                    if (!widget.approvalOnly)
                      Theme(
                        data: Theme.of(
                          context,
                        ).copyWith(dividerColor: Colors.transparent),
                        child: ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          childrenPadding: EdgeInsets.zero,
                          title: Text(
                            'Additional settings',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: primary,
                            ),
                          ),
                          subtitle: Text(
                            'Enable state and review deadline',
                            style: TextStyle(color: muted, fontSize: 12),
                          ),
                          children: [
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Step enabled'),
                              value: _enabled,
                              activeThumbColor: DocuTrackerTokens.brand,
                              onChanged: (value) =>
                                  setState(() => _enabled = value),
                            ),
                            TextField(
                              controller: _deadlineController,
                              keyboardType: TextInputType.number,
                              decoration:
                                  DocuTrackerTokens.warmSearchDecoration(
                                    context,
                                    'Review deadline in hours (optional)',
                                  ).copyWith(
                                    prefixIcon: Icon(
                                      Icons.timer_outlined,
                                      color: muted,
                                    ),
                                  ),
                            ),
                          ],
                        ),
                      ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        style: const TextStyle(
                          color: Color(0xFFB91C1C),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            SafeArea(
              top: false,
              child: Container(
                padding: EdgeInsets.fromLTRB(
                  contentPad,
                  12,
                  contentPad,
                  narrow ? 10 : 14,
                ),
                decoration: BoxDecoration(
                  color: DocuTrackerTokens.surfaceOf(context),
                  border: Border(
                    top: BorderSide(
                      color: DocuTrackerTokens.borderSubtleOf(context),
                    ),
                  ),
                ),
                child: narrow
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          FilledButton.icon(
                            key: const ValueKey('workflow-step-save'),
                            onPressed: _submit,
                            style: FilledButton.styleFrom(
                              backgroundColor: DocuTrackerTokens.brand,
                              foregroundColor: Colors.white,
                              minimumSize: const Size.fromHeight(48),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  DocuTrackerTokens.radiusMd,
                                ),
                              ),
                            ),
                            icon: const Icon(Icons.check_rounded, size: 18),
                            label: const Text('Save Step'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            style: TextButton.styleFrom(
                              foregroundColor: DocuTrackerTokens.brand,
                            ),
                            child: const Text('Cancel'),
                          ),
                        ],
                      )
                    : Row(
                        children: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            style: TextButton.styleFrom(
                              foregroundColor: DocuTrackerTokens.brand,
                            ),
                            child: const Text('Cancel'),
                          ),
                          const Spacer(),
                          FilledButton.icon(
                            key: const ValueKey('workflow-step-save'),
                            onPressed: _submit,
                            style: FilledButton.styleFrom(
                              backgroundColor: DocuTrackerTokens.brand,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  DocuTrackerTokens.radiusMd,
                                ),
                              ),
                            ),
                            icon: const Icon(Icons.check_rounded, size: 18),
                            label: const Text('Save Step'),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.onClose,
    this.compact = false,
  });

  final String title;
  final VoidCallback onClose;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final primary = DocuTrackerTokens.textPrimaryOf(context);
    final muted = DocuTrackerTokens.textMutedOf(context);
    return Container(
      padding: EdgeInsets.fromLTRB(compact ? 14 : 20, 14, 8, 14),
      decoration: BoxDecoration(
        color: DocuTrackerTokens.highlightPeachOf(context),
        border: Border(
          bottom: BorderSide(
            color: DocuTrackerTokens.highlightPeachBorderOf(context),
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: compact ? 32 : 36,
            height: compact ? 32 : 36,
            decoration: BoxDecoration(
              color: DocuTrackerTokens.brandSoftOf(context),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: DocuTrackerTokens.highlightPeachBorderOf(context),
              ),
            ),
            child: Icon(
              Icons.account_tree_outlined,
              size: compact ? 18 : 20,
              color: DocuTrackerTokens.brand,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: compact ? 16 : 18,
                    fontWeight: FontWeight.w800,
                    color: primary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Set who handles this step and what they can do.',
                  style: TextStyle(color: muted, fontSize: compact ? 12 : 12.5),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Close',
            onPressed: onClose,
            icon: Icon(Icons.close_rounded, color: muted),
          ),
        ],
      ),
    );
  }
}

class _FieldHeading extends StatelessWidget {
  const _FieldHeading({
    required this.number,
    required this.label,
    this.required = false,
  });

  final int number;
  final String label;
  final bool required;

  @override
  Widget build(BuildContext context) {
    final primary = DocuTrackerTokens.textPrimaryOf(context);
    return Row(
      children: [
        Text(
          '$number',
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: DocuTrackerTokens.brand,
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Row(
            children: [
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: primary,
                  ),
                ),
              ),
              if (required)
                const Text(
                  ' *',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFFDC2626),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AssignModeCard extends StatelessWidget {
  const _AssignModeCard({
    super.key,
    required this.value,
    required this.selected,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final _AssigneeMode value;
  final bool selected;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primary = DocuTrackerTokens.textPrimaryOf(context);
    final muted = DocuTrackerTokens.textMutedOf(context);
    return Material(
      color: selected
          ? DocuTrackerTokens.brandSoftOf(context)
          : DocuTrackerTokens.surfaceOf(context),
      borderRadius: BorderRadius.circular(DocuTrackerTokens.radiusMd),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DocuTrackerTokens.radiusMd),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(DocuTrackerTokens.radiusMd),
            border: Border.all(
              color: selected
                  ? DocuTrackerTokens.brand
                  : DocuTrackerTokens.borderSubtleOf(context),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Radio<_AssigneeMode>(
                value: value,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 4),
              Icon(
                icon,
                size: 20,
                color: selected ? DocuTrackerTokens.brand : muted,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: primary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.35,
                        color: muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AssigneeField extends StatefulWidget {
  const _AssigneeField({
    super.key,
    required this.hint,
    required this.selectedId,
    required this.excludeId,
    required this.searching,
    required this.directory,
    required this.onStartSearch,
    required this.onChanged,
    this.optional = false,
  });

  final String hint;
  final String? selectedId;
  final String? excludeId;
  final bool searching;
  final EmployeeDirectoryLookup directory;
  final VoidCallback onStartSearch;
  final ValueChanged<String?> onChanged;
  final bool optional;

  @override
  State<_AssigneeField> createState() => _AssigneeFieldState();
}

class _AssigneeFieldState extends State<_AssigneeField> {
  final TextEditingController _query = TextEditingController();
  final FocusNode _focus = FocusNode();

  @override
  void dispose() {
    _query.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _AssigneeField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.searching && !oldWidget.searching) {
      _query.clear();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.searching) _focus.requestFocus();
      });
    }
  }

  List<EmployeeDirectoryEntry> _matches(String query) {
    final matches = <EmployeeDirectoryEntry>[];
    for (final entry in widget.directory.entries) {
      if (entry.id == widget.excludeId) continue;
      final searchable = [
        entry.fullName,
        entry.departmentName ?? '',
        entry.positionName ?? '',
      ].join(' ').toLowerCase();
      if (!searchable.contains(query)) continue;
      matches.add(entry);
      if (matches.length == 8) break;
    }
    return matches;
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.selectedId == null
        ? null
        : widget.directory[widget.selectedId!];
    final showChip = widget.selectedId != null && !widget.searching;

    if (showChip) {
      return _SelectedAssigneeChip(
        entry: selected,
        fallbackLabel: 'Existing assignee',
        onClear: () => widget.onChanged(null),
        onOpen: widget.onStartSearch,
      );
    }

    final query = _query.text.trim().toLowerCase();
    final matches = query.isEmpty
        ? const <EmployeeDirectoryEntry>[]
        : _matches(query);
    final muted = DocuTrackerTokens.textMutedOf(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _query,
          focusNode: _focus,
          decoration: DocuTrackerTokens.warmSearchDecoration(
            context,
            widget.hint,
          ).copyWith(prefixIcon: Icon(Icons.search_rounded, color: muted)),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 6),
        if (query.isEmpty)
          Text(
            widget.optional
                ? 'Optional. Type a name, department, or position.'
                : 'Type a name, department, or position.',
            style: TextStyle(fontSize: 12, height: 1.35, color: muted),
          )
        else if (matches.isEmpty)
          Text(
            'No matches.',
            style: TextStyle(fontSize: 12, height: 1.35, color: muted),
          )
        else
          DecoratedBox(
            decoration: BoxDecoration(
              color: DocuTrackerTokens.surfaceOf(context),
              borderRadius: BorderRadius.circular(DocuTrackerTokens.radiusMd),
              border: Border.all(
                color: DocuTrackerTokens.borderSubtleOf(context),
              ),
            ),
            child: Column(
              children: [
                for (var i = 0; i < matches.length; i++) ...[
                  if (i > 0)
                    Divider(
                      height: 1,
                      color: DocuTrackerTokens.borderSubtleOf(context),
                    ),
                  _AssigneeChoice(
                    entry: matches[i],
                    onTap: () => widget.onChanged(matches[i].id),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _AssigneeChoice extends StatelessWidget {
  const _AssigneeChoice({required this.entry, required this.onTap});

  final EmployeeDirectoryEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final detail = [
      entry.departmentName,
      entry.positionName,
    ].whereType<String>().where((value) => value.isNotEmpty).join(' • ');
    return InkWell(
      key: ValueKey('workflow-assignee-option-${entry.id}'),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            _InitialsAvatar(name: entry.fullName),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.fullName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: DocuTrackerTokens.textPrimaryOf(context),
                    ),
                  ),
                  if (detail.isNotEmpty)
                    Text(
                      detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: DocuTrackerTokens.textMutedOf(context),
                      ),
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

class _SelectedAssigneeChip extends StatelessWidget {
  const _SelectedAssigneeChip({
    required this.entry,
    required this.fallbackLabel,
    required this.onClear,
    required this.onOpen,
  });

  final EmployeeDirectoryEntry? entry;
  final String fallbackLabel;
  final VoidCallback onClear;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final muted = DocuTrackerTokens.textMutedOf(context);
    final primary = DocuTrackerTokens.textPrimaryOf(context);
    final name = entry?.fullName ?? fallbackLabel;
    final detail = [
      entry?.departmentName,
      entry?.positionName,
    ].whereType<String>().where((v) => v.isNotEmpty).join(' • ');

    return Material(
      color: DocuTrackerTokens.surfaceOf(context),
      borderRadius: BorderRadius.circular(DocuTrackerTokens.radiusMd),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(DocuTrackerTokens.radiusMd),
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(DocuTrackerTokens.radiusMd),
            border: Border.all(
              color: DocuTrackerTokens.borderSubtleOf(context),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.fromLTRB(8, 6, 4, 6),
                  decoration: BoxDecoration(
                    color: DocuTrackerTokens.brandSoftOf(context),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: DocuTrackerTokens.highlightPeachBorderOf(context),
                    ),
                  ),
                  child: Row(
                    children: [
                      _InitialsAvatar(name: name, compact: true),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: primary,
                              ),
                            ),
                            if (detail.isNotEmpty)
                              Text(
                                detail,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 11, color: muted),
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Clear',
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 28,
                          minHeight: 28,
                        ),
                        onPressed: onClear,
                        icon: Icon(Icons.close_rounded, size: 16, color: muted),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.expand_more_rounded, color: muted),
            ],
          ),
        ),
      ),
    );
  }
}

class _InitialsAvatar extends StatelessWidget {
  const _InitialsAvatar({required this.name, this.compact = false});

  final String name;
  final bool compact;

  String get _initials {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final size = compact ? 28.0 : 32.0;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: DocuTrackerTokens.brand,
        shape: BoxShape.circle,
      ),
      child: Text(
        _initials,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: compact ? 10 : 11,
        ),
      ),
    );
  }
}

class _ActionGrid extends StatelessWidget {
  const _ActionGrid({
    required this.narrow,
    required this.approvalOnly,
    required this.allowedActions,
    required this.meta,
    required this.onToggle,
  });

  final bool narrow;
  final bool approvalOnly;
  final Set<String> allowedActions;
  final Map<String, ({String title, String subtitle})> meta;
  final void Function(String action, bool checked) onToggle;

  @override
  Widget build(BuildContext context) {
    final actions = meta.entries
        .where((entry) => !approvalOnly || entry.key != 'forward')
        .toList(growable: false);

    Widget tile(MapEntry<String, ({String title, String subtitle})> entry) {
      final checked = allowedActions.contains(entry.key);
      final lockedApprove = approvalOnly && entry.key == 'approve';
      return _ActionCard(
        key: ValueKey('workflow-step-action-${entry.key}'),
        title: entry.value.title,
        subtitle: entry.value.subtitle,
        checked: checked,
        onChanged: lockedApprove
            ? null
            : (value) => onToggle(entry.key, value ?? false),
      );
    }

    if (narrow) {
      return Column(
        children: [
          for (var i = 0; i < actions.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            tile(actions[i]),
          ],
        ],
      );
    }

    final rows = <Widget>[];
    for (var i = 0; i < actions.length; i += 2) {
      final left = actions[i];
      final right = i + 1 < actions.length ? actions[i + 1] : null;
      rows.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: tile(left)),
            const SizedBox(width: 8),
            Expanded(
              child: right == null ? const SizedBox.shrink() : tile(right),
            ),
          ],
        ),
      );
      if (i + 2 < actions.length) rows.add(const SizedBox(height: 8));
    }
    return Column(children: rows);
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.checked,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool checked;
  final ValueChanged<bool?>? onChanged;

  @override
  Widget build(BuildContext context) {
    final primary = DocuTrackerTokens.textPrimaryOf(context);
    final muted = DocuTrackerTokens.textMutedOf(context);
    return Material(
      color: checked
          ? DocuTrackerTokens.brandSoftOf(context)
          : DocuTrackerTokens.surfaceOf(context),
      borderRadius: BorderRadius.circular(DocuTrackerTokens.radiusMd),
      child: InkWell(
        onTap: onChanged == null ? null : () => onChanged!(!checked),
        borderRadius: BorderRadius.circular(DocuTrackerTokens.radiusMd),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(DocuTrackerTokens.radiusMd),
            border: Border.all(
              color: checked
                  ? DocuTrackerTokens.brand
                  : DocuTrackerTokens.borderSubtleOf(context),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: checked,
                onChanged: onChanged,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
                activeColor: DocuTrackerTokens.brand,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: primary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.3,
                        color: muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: DocuTrackerTokens.brandSoftOf(context),
        borderRadius: BorderRadius.circular(DocuTrackerTokens.radiusMd),
        border: Border.all(
          color: DocuTrackerTokens.highlightPeachBorderOf(context),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: DocuTrackerTokens.toneOf(context, DocuTrackerTokens.brand),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.35,
                color: DocuTrackerTokens.textSecondaryOf(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
