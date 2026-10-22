import 'package:flutter/material.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/core/api/user_facing_api_error.dart';
import 'approval_workflow_picker.dart';
import 'package:hrms_plaridel/features/docutracker/models/workflow_step.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/admin/widgets/workflow_step_editor_panel.dart';
import 'package:hrms_plaridel/features/docutracker/services/employee_directory_lookup.dart';
import 'workflow_reviewer_configuration.dart';

const _printPolicyLabels = {
  'mayor': 'Replace with Mayor',
  'blank': 'Leave blank',
  'actual_reviewer': 'Show actual approving reviewer',
};
const _printPolicyDescriptions = {
  'mayor': 'Show the Mayor in the applicant’s department-head or HR block. A signature appears only after confirmed Mayor approval.',
  'blank': 'Leave the applicant’s official name and signature blocks blank for manual completion.',
  'actual_reviewer': 'Show the authorized reviewer who actually approves that step, with their confirmed signature. Leave the block blank until approval.',
};

class ApprovalWorkflowsPanel extends StatefulWidget {
  const ApprovalWorkflowsPanel({
    super.key,
    this.allowDocumentBinding = false,
    this.initialWorkflowId,
  });
  final bool allowDocumentBinding;
  final String? initialWorkflowId;
  @override
  State<ApprovalWorkflowsPanel> createState() => _ApprovalWorkflowsPanelState();
}

class _ApprovalWorkflowsPanelState extends State<ApprovalWorkflowsPanel> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _error;
  bool _openedInitialEditor = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await ApiClient.instance.get<List<dynamic>>(
        '/api/approval-workflows',
      );
      if (mounted) {
        setState(
          () => _items = (response.data ?? [])
              .whereType<Map>()
              .map((r) => Map<String, dynamic>.from(r))
              .toList(),
        );
        if (!_openedInitialEditor && widget.initialWorkflowId != null) {
          final selected = _items
              .where((w) => w['id'] == widget.initialWorkflowId)
              .firstOrNull;
          _openedInitialEditor = true;
          if (selected != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _edit(selected);
            });
          }
        }
      }
    } catch (error) {
      if (mounted) setState(() => _error = userFacingApiError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _edit([Map<String, dynamic>? workflow]) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _WorkflowEditor(workflow: workflow),
    );
    if (saved == true && mounted) await _load();
  }

  Future<void> _bindDocument(Map<String, dynamic> workflow) async {
    try {
      final response = await ApiClient.instance.get<List<dynamic>>(
        '/api/approval-workflows/document-types',
      );
      if (!mounted) return;
      final types = (response.data ?? []).whereType<Map>().toList();
      String? selected;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, update) => AlertDialog(
            title: const Text('Use shared workflow in DocuTracker'),
            content: SizedBox(
              width: 480,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'New documents will use ${workflow['name']}. Publishing changes here also updates future documents; existing documents keep their version.',
                  ),
                  const SizedBox(height: 20),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Document type',
                    ),
                    items: [
                      for (final type in types)
                        DropdownMenuItem(
                          value: type['document_type'] as String,
                          child: Text(type['display_name'] as String),
                        ),
                    ],
                    onChanged: (value) => update(() => selected = value),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: selected == null
                    ? null
                    : () => Navigator.pop(dialogContext, true),
                child: const Text('Use workflow'),
              ),
            ],
          ),
        ),
      );
      if (confirmed != true || !mounted) return;
      await ApiClient.instance.post(
        '/api/approval-workflows/${workflow['id']}/document-types/${Uri.encodeComponent(selected!)}',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Shared workflow linked to document type.'),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userFacingApiError(error))));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      LayoutBuilder(
        builder: (context, constraints) {
          const title = Text(
            'Reusable approval workflows',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          );
          final actions = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Refresh workflows',
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _loading ? null : () => _edit(),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 14,
                  ),
                ),
                icon: const Icon(Icons.add, size: 20),
                label: const Text('New workflow'),
              ),
            ],
          );
          if (constraints.maxWidth < 640) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [title, const SizedBox(height: 16), actions],
            );
          }
          return Row(
            children: [
              const Expanded(child: title),
              const SizedBox(width: 24),
              actions,
            ],
          );
        },
      ),
      const SizedBox(height: 12),
      Text(
        'Create approval steps with their own primary and backup reviewers, then select this workflow in your leave or locator type settings.',
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          height: 1.5,
        ),
      ),
      const SizedBox(height: 24),
      if (_loading) ...[
        const LinearProgressIndicator(),
        const SizedBox(height: 16),
      ],
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      Expanded(
        child: _items.isEmpty
            ? !_loading && _error == null
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('Create a workflow to get started.'),
                    )
                  : const SizedBox.shrink()
            : ListView.separated(
                padding: const EdgeInsets.only(bottom: 24),
                itemCount: _items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 16),
                itemBuilder: (context, index) => _WorkflowCard(
                  workflow: _items[index],
                  onEdit: () => _edit(_items[index]),
                  onBind: widget.allowDocumentBinding
                      ? () => _bindDocument(_items[index])
                      : null,
                ),
              ),
      ),
    ],
  );
}

class _WorkflowCard extends StatelessWidget {
  const _WorkflowCard({
    required this.workflow,
    required this.onEdit,
    this.onBind,
  });

  final Map<String, dynamic> workflow;
  final VoidCallback onEdit;
  final VoidCallback? onBind;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final active = workflow['is_active'] == true;
    final statusColor = active
        ? theme.brightness == Brightness.dark
              ? const Color(0xFF81C784)
              : const Color(0xFF2E7D32)
        : colors.onSurfaceVariant;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.account_tree_outlined,
                color: colors.primary,
                size: 22,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            workflow['name'].toString(),
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: colors.onSurface,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      IconButton(
                        tooltip: 'Edit ${workflow['name']}',
                        onPressed: onEdit,
                        icon: const Icon(Icons.edit_outlined, size: 20),
                      ),
                      if (onBind != null)
                        IconButton(
                          tooltip: 'Use ${workflow['name']} in DocuTracker',
                          onPressed: onBind,
                          icon: const Icon(Icons.link, size: 20),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _WorkflowBadge(
                        label: 'Version ${workflow['current_version']}',
                        color: colors.onSurfaceVariant,
                      ),
                      _WorkflowBadge(
                        label: active ? 'Active' : 'Inactive',
                        color: statusColor,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    approvalStepsLabel(workflow['steps']),
                    style: TextStyle(color: colors.onSurface, height: 1.5),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Primary reviewer’s own filing: ${_printPolicyLabels[workflow['self_filing_signatory_policy'] ?? 'mayor']}',
                    style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
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

class _WorkflowBadge extends StatelessWidget {
  const _WorkflowBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      label,
      style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
    ),
  );
}

class _WorkflowEditor extends StatefulWidget {
  const _WorkflowEditor({this.workflow});
  final Map<String, dynamic>? workflow;
  @override
  State<_WorkflowEditor> createState() => _WorkflowEditorState();
}

class _WorkflowEditorState extends State<_WorkflowEditor> {
  late final TextEditingController _name = TextEditingController(
    text: widget.workflow?['name'] as String? ?? '',
  );
  late final List<dynamic> _steps = List<dynamic>.from(
    widget.workflow?['steps'] as List? ?? [],
  );
  final _directory = EmployeeDirectoryLookup();
  @override
  void initState() {
    super.initState();
    _loadPeople();
  }

  Future<void> _loadPeople() async {
    await _directory.load();
    if (mounted) setState(() {});
  }

  Map<String, dynamic> _stepJson(dynamic step, int index) => step is Map
      ? {...Map<String, dynamic>.from(step), 'step_order': index + 1}
      : {
          'step_order': index + 1,
          'label': approvalStepLabels[step],
          'assignee_type': 'user',
          'assignee_source': {
            'department': 'submitter_department_reviewers',
            'hr': 'final_hr_reviewers',
            'mayor': 'active_mayor',
            'manual_mayor': 'manual_mayor',
          }[step],
          'user_ids': <String>[],
          'requires_signature': true,
          'allowed_actions': ['approve', 'return', 'reject'],
        };

  Future<void> _editStep([int? index]) async {
    final initial = index == null
        ? WorkflowStep(
            stepOrder: _steps.length + 1,
            assigneeType: 'user',
            label: '',
            requiresSignature: true,
          )
        : WorkflowStep.fromJson(_stepJson(_steps[index], index));
    final saved = await showWorkflowStepEditor(
      context,
      title: index == null ? 'Add approval step' : 'Edit approval step',
      initial: initial,
      approvalOnly: true,
    );
    if (!mounted || saved == null) return;
    setState(() {
      if (index == null) {
        _steps.add(saved.toJson());
      } else {
        _steps[index] = saved.toJson();
      }
      _error = null;
    });
    await _loadPeople();
  }

  Future<void> _configureReviewers(int index) async {
    final step = _stepJson(_steps[index], index);
    await showWorkflowReviewerConfiguration(
      context,
      source: step['assignee_source'] as String,
      departmentId: step['department_id'] as String?,
    );
    if (mounted) await _loadPeople();
  }

  String _assigneeDescription(dynamic step, int index) {
    final json = _stepJson(step, index);
    final source = json['assignee_source'];
    if (source == 'specific_users') {
      final ids = (json['user_ids'] as List? ?? []).cast<String>();
      if (ids.isEmpty) return 'Choose a primary reviewer';
      final primary = _directory[ids.first]?.fullName ?? 'Selected reviewer';
      final backups = ids
          .skip(1)
          .map((id) => _directory[id]?.fullName ?? 'Selected backup')
          .join(', ');
      return 'Primary: $primary${backups.isEmpty ? '' : '\nBackup: $backups'}';
    }
    return {
          'submitter_department_reviewers':
              'Applicant’s department primary and backups',
          'department_reviewers': 'Selected department’s primary and backups',
          'final_hr_reviewers': 'Configured Final HR primary and backups',
          'active_mayor': 'Currently designated Municipal Mayor',
          'manual_mayor': 'Signs the printed form after system approval',
        }[source] ??
        'Choose reviewers';
  }

  late bool _active = widget.workflow?['is_active'] != false;
  late String _printPolicy = widget.workflow?['self_filing_signatory_policy'] as String? ?? 'mayor';
  bool _saving = false;
  String? _error;
  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _publish() async {
    if (_name.text.trim().isEmpty || _steps.isEmpty) {
      setState(() => _error = 'Enter a name and at least one approval step.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final data = {
        'name': _name.text.trim(),
        'steps': _steps.any((s) => s is Map)
            ? [for (var i = 0; i < _steps.length; i++) _stepJson(_steps[i], i)]
            : _steps,
        'is_active': _active,
        'self_filing_signatory_policy': _printPolicy,
        if (widget.workflow != null)
          'current_version': widget.workflow!['current_version'],
      };
      if (widget.workflow == null) {
        await ApiClient.instance.post('/api/approval-workflows', data: data);
      } else {
        await ApiClient.instance.put(
          '/api/approval-workflows/${widget.workflow!['id']}',
          data: data,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = userFacingApiError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      title: Text(
        widget.workflow == null
            ? 'Create approval workflow'
            : 'Edit approval workflow',
      ),
      content: SizedBox(
        width: 720,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _name,
                enabled: !_saving,
                maxLength: 100,
                decoration: const InputDecoration(labelText: 'Workflow name'),
              ),
              const SizedBox(height: 12),
              const Text(
                'Approval steps',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const Text(
                'Add steps in approval order and choose each step’s primary and backup reviewers. The last system step is the final approval.',
              ),
              for (var i = 0; i < _steps.length; i++)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(child: Text('${i + 1}')),
                  title: Text(_stepJson(_steps[i], i)['label'] as String),
                  subtitle: Text(_assigneeDescription(_steps[i], i)),
                  onTap: _saving ? null : () => _editStep(i),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if ([
                        'submitter_department_reviewers',
                        'department_reviewers',
                        'final_hr_reviewers',
                      ].contains(_stepJson(_steps[i], i)['assignee_source']))
                        IconButton(
                          tooltip:
                              'Configure ${_stepJson(_steps[i], i)['label']} reviewers',
                          onPressed: _saving
                              ? null
                              : () => _configureReviewers(i),
                          icon: const Icon(Icons.manage_accounts_outlined),
                        ),
                      PopupMenuButton<String>(
                        tooltip: 'Step ${i + 1} actions',
                        enabled: !_saving,
                        onSelected: (action) {
                          if (action == 'edit') {
                            _editStep(i);
                          } else {
                            setState(() {
                              final step = _steps.removeAt(i);
                              if (action != 'remove') {
                                _steps.insert(
                                  action == 'up' ? i - 1 : i + 1,
                                  step,
                                );
                              }
                            });
                          }
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                            value: 'edit',
                            child: Text('Edit approvers'),
                          ),
                          if (i > 0)
                            const PopupMenuItem(
                              value: 'up',
                              child: Text('Move up'),
                            ),
                          if (i < _steps.length - 1)
                            const PopupMenuItem(
                              value: 'down',
                              child: Text('Move down'),
                            ),
                          const PopupMenuItem(
                            value: 'remove',
                            child: Text('Remove step'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              if (_steps.length < 20)
                TextButton.icon(
                  onPressed: _saving ? null : () => _editStep(),
                  icon: const Icon(Icons.add),
                  label: const Text('Add approval step'),
                ),
              const SizedBox(height: 16),
              const Text(
                'When a primary reviewer files their own request',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: const ValueKey('self-filing-signatory-policy'),
                initialValue: _printPolicy,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Printed signatories'),
                items: [
                  for (final entry in _printPolicyLabels.entries)
                    DropdownMenuItem(value: entry.key, child: Text(entry.value)),
                ],
                onChanged: _saving ? null : (value) {
                  if (value != null) setState(() => _printPolicy = value);
                },
              ),
              const SizedBox(height: 8),
              Text(_printPolicyDescriptions[_printPolicy]!),
              const SizedBox(height: 8),
              const Text('Applies to Leave and Locator printed forms. Approval steps and reviewer permissions stay the same.'),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Active workflow'),
                value: _active,
                onChanged: _saving ? null : (v) => setState(() => _active = v),
              ),
              Text(
                widget.workflow == null
                    ? 'Publishing creates a new version for future filings. Existing requests retain their saved version.'
                    : 'Updating creates a new version for future filings. Existing requests retain their saved version.',
              ),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _publish,
          child: Text(
            widget.workflow == null
                ? (_saving ? 'Publishing…' : 'Publish workflow')
                : (_saving ? 'Updating…' : 'Update workflow'),
          ),
        ),
      ],
    ),
  );
}
