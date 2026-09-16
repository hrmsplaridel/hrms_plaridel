import 'package:flutter/material.dart';

import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/docutracker/data/styles/docutracker_styles.dart';
import 'package:hrms_plaridel/features/docutracker/models/workflow_step.dart';
import 'package:hrms_plaridel/features/docutracker/services/employee_directory_lookup.dart';
import 'package:hrms_plaridel/features/docutracker/theme/docutracker_tokens.dart';

class SimplifiedWorkflowStepEditor extends StatefulWidget {
  const SimplifiedWorkflowStepEditor({
    super.key,
    required this.title,
    required this.initial,
  });

  final String title;
  final WorkflowStep initial;

  @override
  State<SimplifiedWorkflowStepEditor> createState() =>
      _SimplifiedWorkflowStepEditorState();
}

class _SimplifiedWorkflowStepEditorState
    extends State<SimplifiedWorkflowStepEditor> {
  static const _actionLabels = <String, String>{
    'approve': 'Approve and continue',
    'forward': 'Forward without approval',
    'return': 'Return for changes',
    'reject': 'Reject and stop',
  };

  final _directory = EmployeeDirectoryLookup();
  final _nameController = TextEditingController();
  final _deadlineController = TextEditingController();

  late bool _enabled;
  late bool _usesAutomaticDepartmentReviewers;
  late Set<String> _allowedActions;
  String? _primaryUserId;
  String? _backupUserId;
  List<String> _legacyAdditionalBackupIds = const [];
  bool _loadingPeople = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    final step = widget.initial;
    _nameController.text = step.label ?? '';
    _deadlineController.text = step.deadlineHours?.toString() ?? '';
    _enabled = step.enabled;
    _usesAutomaticDepartmentReviewers =
        step.assigneeSource == 'department_reviewers';
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
        .where(_actionLabels.containsKey)
        .toSet();
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

  Widget _assigneePicker({
    required String label,
    required String? selectedId,
    required String? excludeId,
    required ValueChanged<String?> onChanged,
    bool optional = false,
  }) {
    final selected = selectedId == null ? null : _directory[selectedId];
    final initialText =
        selected?.nameAndDepartment ??
        (selectedId == null ? '' : 'Existing assignee');
    final entries = _directory.entries
        .where((entry) => entry.id != excludeId)
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Autocomplete<EmployeeDirectoryEntry>(
          key: ValueKey('$label-$selectedId-$excludeId'),
          initialValue: TextEditingValue(text: initialText),
          displayStringForOption: (entry) => entry.nameAndDepartment,
          optionsBuilder: (value) {
            final query = value.text.trim().toLowerCase();
            if (query.isEmpty) return entries;
            return entries.where((entry) {
              final searchable = [
                entry.fullName,
                entry.departmentName ?? '',
                entry.positionName ?? '',
              ].join(' ').toLowerCase();
              return searchable.contains(query);
            });
          },
          onSelected: (entry) => onChanged(entry.id),
          fieldViewBuilder:
              (context, controller, focusNode, onFieldSubmitted) => TextField(
                controller: controller,
                focusNode: focusNode,
                decoration: DocuTrackerStyles.inputDecoration(
                  context,
                  label,
                  Icons.search_rounded,
                ),
              ),
          optionsViewBuilder: (context, onSelected, options) => Align(
            alignment: Alignment.topLeft,
            child: Material(
              elevation: 6,
              borderRadius: BorderRadius.circular(10),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 520,
                  maxHeight: 280,
                ),
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  itemCount: options.length,
                  itemBuilder: (context, index) {
                    final entry = options.elementAt(index);
                    return ListTile(
                      dense: true,
                      title: Text(entry.fullName),
                      subtitle: Text(
                        [entry.positionName, entry.departmentName]
                            .whereType<String>()
                            .where((v) => v.isNotEmpty)
                            .join(' · '),
                      ),
                      onTap: () => onSelected(entry),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
        if (optional && selectedId != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => onChanged(null),
              child: const Text('Remove backup'),
            ),
          ),
      ],
    );
  }

  void _submit() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Step name is required.');
      return;
    }
    if (!_usesAutomaticDepartmentReviewers && _primaryUserId == null) {
      setState(() => _error = 'Choose a primary assignee.');
      return;
    }
    if (_usesAutomaticDepartmentReviewers &&
        (widget.initial.departmentId ?? '').trim().isEmpty) {
      setState(
        () => _error =
            'This legacy automatic-reviewer step has no department. Choose specific assignees instead.',
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

    Navigator.of(context).pop(
      WorkflowStep(
        stepOrder: widget.initial.stepOrder,
        assigneeType: 'user',
        assigneeSource: _usesAutomaticDepartmentReviewers
            ? 'department_reviewers'
            : 'specific_users',
        departmentId: _usesAutomaticDepartmentReviewers
            ? widget.initial.departmentId
            : primaryDepartmentId,
        userIds: _usesAutomaticDepartmentReviewers ? const [] : userIds,
        label: name,
        enabled: _enabled,
        deadlineHours: deadline,
        allowedActions: _allowedActions.toList(growable: false),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Set who handles this step and what they can do.',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _FieldHeading(number: 1, label: 'Step Name'),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _nameController,
                    decoration: DocuTrackerStyles.inputDecoration(
                      context,
                      'Example: Department Review',
                      Icons.label_outline_rounded,
                    ),
                    onChanged: (_) => setState(() => _error = null),
                  ),
                  const SizedBox(height: 20),
                  if (_usesAutomaticDepartmentReviewers) ...[
                    const _FieldHeading(number: 2, label: 'Assignees'),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: DocuTrackerTokens.brand.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: DocuTrackerTokens.brand.withValues(alpha: 0.2),
                        ),
                      ),
                      child: const Text(
                        'Primary: official Department Head\n'
                        'Backup: configured department backup reviewers',
                      ),
                    ),
                  ] else ...[
                    const _FieldHeading(number: 2, label: 'Primary Assignee'),
                    const SizedBox(height: 8),
                    if (_loadingPeople)
                      const LinearProgressIndicator(minHeight: 2)
                    else
                      _assigneePicker(
                        label: 'Search by name, department, or position',
                        selectedId: _primaryUserId,
                        excludeId: _backupUserId,
                        onChanged: (value) => setState(() {
                          _primaryUserId = value;
                          if (_backupUserId == value) _backupUserId = null;
                          _legacyAdditionalBackupIds =
                              _legacyAdditionalBackupIds
                                  .where((id) => id != value)
                                  .toList(growable: false);
                          _error = null;
                        }),
                      ),
                    const SizedBox(height: 20),
                    const _FieldHeading(
                      number: 3,
                      label: 'Backup Assignee (Optional)',
                    ),
                    const SizedBox(height: 8),
                    if (!_loadingPeople)
                      _assigneePicker(
                        label: 'Search optional backup',
                        selectedId: _backupUserId,
                        excludeId: _primaryUserId,
                        optional: true,
                        onChanged: (value) => setState(() {
                          _backupUserId = value;
                          _error = null;
                        }),
                      ),
                    if (_legacyAdditionalBackupIds.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        '${_legacyAdditionalBackupIds.length} additional existing backup(s) '
                        'will be preserved for compatibility.',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                  const SizedBox(height: 20),
                  const _FieldHeading(number: 4, label: 'Allowed Actions'),
                  const SizedBox(height: 6),
                  Text(
                    'These actions apply equally to the primary and backup assignee.',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 6),
                  for (final entry in _actionLabels.entries)
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(entry.value),
                      value: _allowedActions.contains(entry.key),
                      controlAffinity: ListTileControlAffinity.leading,
                      onChanged: (checked) => setState(() {
                        if (checked == true) {
                          _allowedActions.add(entry.key);
                        } else {
                          _allowedActions.remove(entry.key);
                        }
                        _error = null;
                      }),
                    ),
                  const SizedBox(height: 8),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text(
                      'Additional settings',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: const Text('Enable state and review deadline'),
                    children: [
                      if (widget.initial.assigneeSource ==
                          'department_reviewers')
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text(
                            'Use automatic department reviewers',
                          ),
                          subtitle: const Text(
                            'Turn this off to choose a specific primary and backup.',
                          ),
                          value: _usesAutomaticDepartmentReviewers,
                          onChanged: (value) => setState(() {
                            _usesAutomaticDepartmentReviewers = value;
                            _error = null;
                          }),
                        ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Step enabled'),
                        value: _enabled,
                        onChanged: (value) => setState(() => _enabled = value),
                      ),
                      TextField(
                        controller: _deadlineController,
                        keyboardType: TextInputType.number,
                        decoration: DocuTrackerStyles.inputDecoration(
                          context,
                          'Review deadline in hours (optional)',
                          Icons.timer_outlined,
                        ),
                      ),
                    ],
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
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: _submit,
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Save Step'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FieldHeading extends StatelessWidget {
  const _FieldHeading({required this.number, required this.label});

  final int number;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleAvatar(
          radius: 13,
          backgroundColor: DocuTrackerTokens.brand.withValues(alpha: 0.12),
          foregroundColor: DocuTrackerTokens.brand,
          child: Text(
            '$number',
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }
}
