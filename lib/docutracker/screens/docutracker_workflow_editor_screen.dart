import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../api/client.dart';
import '../../landingpage/constants/app_theme.dart';
import '../docutracker_provider.dart';
import '../docutracker_api_result.dart';
import '../docutracker_repository.dart';
import '../docutracker_styles.dart';
import '../models/document_routing_config.dart';
import '../models/document_type.dart';
import '../models/workflow_step.dart';
import '../services/docutracker_workflow_config_validator.dart';
import '../widgets/docutracker_responsive_body.dart';
import '../widgets/workflow_step_editor_panel.dart';

class DocuTrackerWorkflowEditorScreen extends StatefulWidget {
  const DocuTrackerWorkflowEditorScreen({
    super.key,
    required this.initialConfig,
  });

  final DocumentRoutingConfig initialConfig;

  @override
  State<DocuTrackerWorkflowEditorScreen> createState() =>
      _DocuTrackerWorkflowEditorScreenState();
}

class _DocuTrackerWorkflowEditorScreenState
    extends State<DocuTrackerWorkflowEditorScreen> {
  final _validator = const DocuTrackerWorkflowConfigValidator();
  final _defaultDeadlineController = TextEditingController();

  late List<WorkflowStep> _steps;
  /// Stable keys for [ReorderableListView] across renumbering.
  late List<String> _rowKeys;
  List<DocuTrackerWorkflowValidationIssue> _issues = const [];
  bool _saving = false;
  String? _error;
  final Map<String, String> _departmentNameById = {};

  @override
  void initState() {
    super.initState();
    _steps = widget.initialConfig.steps
        .map((s) => WorkflowStep(
              stepOrder: s.stepOrder,
              assigneeType: s.assigneeType,
              roleId: s.roleId,
              departmentId: s.departmentId,
              officeId: s.officeId,
              userIds: s.userIds == null ? null : List<String>.from(s.userIds!),
              label: s.label,
              enabled: s.enabled,
              deadlineHours: s.deadlineHours,
            ))
        .toList()
      ..sort((a, b) => a.stepOrder.compareTo(b.stepOrder));

    final stamp = DateTime.now().microsecondsSinceEpoch;
    _rowKeys = List.generate(_steps.length, (i) => 'wf-$stamp-$i');

    _defaultDeadlineController.text =
        widget.initialConfig.reviewDeadlineHours.toString();
    _revalidate();
    _loadDepartmentLookup();
  }

  Future<void> _loadDepartmentLookup() async {
    try {
      final res = await ApiClient.instance.get<List<dynamic>>('/api/departments');
      final data = res.data ?? [];
      final map = <String, String>{};
      for (final e in data) {
        final m = e as Map<String, dynamic>;
        final id = m['id']?.toString();
        if (id == null || id.isEmpty) continue;
        map[id] = m['name']?.toString() ?? '—';
      }
      if (mounted) {
        setState(() {
          _departmentNameById
            ..clear()
            ..addAll(map);
        });
      }
    } on DioException catch (_) {
      // Non-blocking: list still shows technical ids.
    } catch (_) {}
  }

  @override
  void dispose() {
    _defaultDeadlineController.dispose();
    super.dispose();
  }

  void _revalidate() {
    setState(() {
      _issues = _validator.validate(_steps);
    });
  }

  bool get _canSave => _issues.where((i) => !i.isWarning).isEmpty && !_saving;

  /// Renumbers `stepOrder` to 1..n in **current list order** (required for drag-and-drop).
  void _renumberStepsContiguously() {
    _steps = [
      for (var i = 0; i < _steps.length; i++)
        WorkflowStep(
          stepOrder: i + 1,
          assigneeType: _steps[i].assigneeType,
          roleId: _steps[i].roleId,
          departmentId: _steps[i].departmentId,
          officeId: _steps[i].officeId,
          userIds: _steps[i].userIds,
          label: _steps[i].label,
          enabled: _steps[i].enabled,
          deadlineHours: _steps[i].deadlineHours,
        )
    ];
  }

  Future<void> _addStep() async {
    final nextOrder = _steps.isEmpty
        ? 1
        : (_steps.map((s) => s.stepOrder).reduce((a, b) => a > b ? a : b) + 1);
    final created = await showWorkflowStepEditor(
      context,
      title: 'Add step',
      initial: WorkflowStep(
        stepOrder: nextOrder,
        assigneeType: 'user',
        label: 'New step',
      ),
    );
    if (created == null) return;
    setState(() {
      _steps = [..._steps, created];
      _rowKeys.add('wf-${DateTime.now().microsecondsSinceEpoch}-${_rowKeys.length}');
      _renumberStepsContiguously();
      _revalidate();
    });
  }

  Future<void> _editStep(int index) async {
    final edited = await showWorkflowStepEditor(
      context,
      title: 'Edit step ${_steps[index].stepOrder}',
      initial: _steps[index],
    );
    if (edited == null) return;
    setState(() {
      _steps[index] = edited;
      _renumberStepsContiguously();
      _revalidate();
    });
  }

  void _removeStep(int index) {
    setState(() {
      _rowKeys.removeAt(index);
      _steps.removeAt(index);
      _renumberStepsContiguously();
      _revalidate();
    });
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final defaultDeadline = int.tryParse(_defaultDeadlineController.text.trim()) ?? 1;
      final updated = DocumentRoutingConfig(
        documentType: widget.initialConfig.documentType,
        steps: _steps,
        reviewDeadlineHours: defaultDeadline < 1 ? 1 : defaultDeadline,
      );

      final issues = _validator.validate(updated.steps);
      if (issues.where((i) => !i.isWarning).isNotEmpty) {
        setState(() {
          _issues = issues;
          _saving = false;
        });
        return;
      }

      final repo = DocuTrackerRepository.instance;
      final saveResult = await repo.saveRoutingConfig(updated);
      if (saveResult is DocuTrackerFailure<bool>) {
        setState(() {
          _error = saveResult.message.isNotEmpty
              ? saveResult.message
              : 'Save was rejected by the server. Check that routing rules are valid, '
                  'or that no blocking constraint exists for this document type.';
          _saving = false;
        });
        return;
      }

      if (!mounted) return;
      await context.read<DocuTrackerProvider>().loadRoutingConfigs();
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        _error = 'Save failed: $e';
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final blocking = _issues.where((i) => !i.isWarning).toList();
    final warnings = _issues.where((i) => i.isWarning).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Workflow • ${widget.initialConfig.documentType.displayName}',
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Center(
              child: Text(
                'v${widget.initialConfig.version} → new',
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
      body: DocuTrackerResponsiveBody(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _InfoBanner(version: widget.initialConfig.version),
            const SizedBox(height: 10),
            const _AssigneesReminderBanner(),
            const SizedBox(height: 12),
            _DefaultDeadlineCard(
              controller: _defaultDeadlineController,
              onChanged: _revalidate,
            ),
            const SizedBox(height: 12),
            if (_issues.isNotEmpty)
              _ValidationPanel(blocking: blocking, warnings: warnings),
            if (_error != null) ...[
              const SizedBox(height: 8),
              SelectableText(
                _error!,
                style: TextStyle(color: Colors.red.shade800, fontSize: 13),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  'Workflow flow',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Text(
                  '${_steps.length} step${_steps.length == 1 ? '' : 's'}',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Drag the handle to change order. The top card is step 1, then 2, 3, and so on. '
              'Turn a step off if you want to skip it without deleting it.',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, height: 1.25),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: _steps.isEmpty
                  ? _EmptySteps(onAdd: _saving ? null : _addStep)
                  : ReorderableListView.builder(
                      buildDefaultDragHandles: false,
                      padding: const EdgeInsets.only(bottom: 8),
                      itemCount: _steps.length,
                      onReorder: (oldIndex, newIndex) {
                        setState(() {
                          if (newIndex > oldIndex) newIndex -= 1;
                          final item = _steps.removeAt(oldIndex);
                          _steps.insert(newIndex, item);
                          final k = _rowKeys.removeAt(oldIndex);
                          _rowKeys.insert(newIndex, k);
                          _renumberStepsContiguously();
                          _revalidate();
                        });
                      },
                      itemBuilder: (ctx, idx) {
                        final s = _steps[idx];
                        final last = idx == _steps.length - 1;
                        return _WorkflowStepFlowCard(
                          key: ValueKey(_rowKeys[idx]),
                          index: idx,
                          step: s,
                          departmentNameById: _departmentNameById,
                          showConnector: !last,
                          onEdit: () => _editStep(idx),
                          onDelete: () => _removeStep(idx),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _saving ? null : _addStep,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Add step'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _canSave ? _save : null,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_rounded),
                    label: Text(_saving ? 'Saving…' : 'Save workflow'),
                  ),
                ),
              ],
            ),
            if (!_canSave && !_saving) ...[
              const SizedBox(height: 6),
              Text(
                blocking.isEmpty
                    ? 'Fix validation errors above before saving.'
                    : '${blocking.length} issue(s) must be resolved before saving.',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// --- Layout pieces ---

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.version});

  final int version;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFE3F2FD),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline_rounded, color: AppTheme.primaryNavy, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Saving creates a new workflow version (you are editing from v$version). '
                'Documents already in progress keep the version they started on.',
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AssigneesReminderBanner extends StatelessWidget {
  const _AssigneesReminderBanner();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFE8F5E9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.groups_rounded, color: Colors.green.shade800, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'After you save this workflow, open Admin → “Manage step assignees” to set '
                'who is primary, who is backup, and which actions (approve, forward, etc.) '
                'each person may use.',
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DefaultDeadlineCard extends StatelessWidget {
  const _DefaultDeadlineCard({
    required this.controller,
    required this.onChanged,
  });

  final TextEditingController controller;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.offWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Default deadline (hours)',
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: DocuTrackerStyles.inputDecoration(
                'Used when a step has no per-step deadline',
                Icons.schedule_rounded,
              ),
              onChanged: (_) => onChanged(),
            ),
          ],
        ),
      ),
    );
  }
}

class _ValidationPanel extends StatelessWidget {
  const _ValidationPanel({
    required this.blocking,
    required this.warnings,
  });

  final List<DocuTrackerWorkflowValidationIssue> blocking;
  final List<DocuTrackerWorkflowValidationIssue> warnings;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  blocking.isNotEmpty ? Icons.block_rounded : Icons.warning_amber_rounded,
                  size: 20,
                  color: blocking.isNotEmpty ? Colors.red.shade800 : Colors.orange.shade900,
                ),
                const SizedBox(width: 8),
                Text(
                  blocking.isNotEmpty ? 'Fix before save' : 'Warnings',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final i in blocking)
              _ValidationLine(
                message: i.message,
                stepOrder: i.stepOrder,
                isWarning: false,
              ),
            for (final i in warnings)
              _ValidationLine(
                message: i.message,
                stepOrder: i.stepOrder,
                isWarning: true,
              ),
          ],
        ),
      ),
    );
  }
}

class _ValidationLine extends StatelessWidget {
  const _ValidationLine({
    required this.message,
    required this.isWarning,
    this.stepOrder,
  });

  final String message;
  final int? stepOrder;
  final bool isWarning;

  @override
  Widget build(BuildContext context) {
    final step = stepOrder != null ? 'Step $stepOrder — ' : '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isWarning ? Icons.info_outline_rounded : Icons.cancel_rounded,
            size: 16,
            color: isWarning ? Colors.orange.shade900 : Colors.red.shade800,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '$step$message',
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12.5,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptySteps extends StatelessWidget {
  const _EmptySteps({required this.onAdd});

  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.account_tree_rounded, size: 48, color: AppTheme.textSecondary.withValues(alpha: 0.4)),
            const SizedBox(height: 12),
            Text(
              'No steps yet',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Add the first routing step. You can reorder steps at any time before saving.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.3),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add first step'),
            ),
          ],
        ),
      ),
    );
  }
}

String _assigneeTypeLabel(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'user':
      return 'Selected people';
    case 'department':
      return 'Department pool';
    case 'office':
      return 'Office pool';
    case 'role':
      return 'By role';
    default:
      return raw;
  }
}

String _assigneeSummary(WorkflowStep s, Map<String, String> departmentNameById) {
  final t = s.assigneeType.trim().toLowerCase();
  switch (t) {
    case 'role':
      final r = s.roleId?.trim() ?? '';
      return r.isEmpty ? 'Role not set' : 'Role: $r';
    case 'department':
      final d = s.departmentId?.trim() ?? '';
      if (d.isEmpty) return 'Department not set';
      return 'Department pool: ${departmentNameById[d] ?? d}';
    case 'office':
      final o = s.officeId?.trim() ?? '';
      return o.isEmpty ? 'Office not set' : 'Office: $o';
    case 'user':
      final ids = s.userIds?.where((e) => e.trim().isNotEmpty).toList() ?? [];
      final d = s.departmentId?.trim() ?? '';
      final dept = d.isEmpty
          ? 'No department'
          : (departmentNameById[d] ?? 'Department');
      if (ids.isEmpty) {
        return '$dept · No reviewers selected';
      }
      final backupCount = ids.length - 1;
      final backup = backupCount > 0 ? ', $backupCount backup${backupCount == 1 ? '' : 's'}' : '';
      return '$dept · 1 primary$backup';
    default:
      return 'Assignee type: ${s.assigneeType}';
  }
}

class _WorkflowStepFlowCard extends StatelessWidget {
  const _WorkflowStepFlowCard({
    super.key,
    required this.index,
    required this.step,
    required this.departmentNameById,
    required this.showConnector,
    required this.onEdit,
    required this.onDelete,
  });

  final int index;
  final WorkflowStep step;
  final Map<String, String> departmentNameById;
  final bool showConnector;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final enabled = step.enabled;
    final accent = enabled ? AppTheme.primaryNavy : Colors.grey.shade600;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 36,
            child: Column(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                    border: Border.all(color: accent.withValues(alpha: 0.35)),
                  ),
                  child: Text(
                    '${step.stepOrder}',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      color: accent,
                    ),
                  ),
                ),
                if (showConnector)
                  Container(
                    width: 2,
                    height: 18,
                    margin: const EdgeInsets.only(top: 2),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Material(
              color: AppTheme.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.black.withValues(alpha: 0.08)),
              ),
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  step.label ?? 'Step ${step.stepOrder}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                    color: enabled
                                        ? AppTheme.textPrimary
                                        : AppTheme.textSecondary,
                                  ),
                                ),
                              ),
                              if (!enabled)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade200,
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    'Disabled',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _assigneeSummary(step, departmentNameById),
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.textSecondary,
                              height: 1.25,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              _MiniChip(
                                icon: Icons.route_rounded,
                                label: _assigneeTypeLabel(step.assigneeType),
                              ),
                              _MiniChip(
                                icon: Icons.timer_outlined,
                                label: step.deadlineHours != null
                                    ? '${step.deadlineHours} h / step'
                                    : 'Default deadline',
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Edit',
                      icon: const Icon(Icons.edit_rounded, size: 20),
                      onPressed: onEdit,
                    ),
                    IconButton(
                      tooltip: 'Remove',
                      icon: Icon(Icons.delete_outline_rounded,
                          size: 20, color: Colors.red.shade700),
                      onPressed: onDelete,
                    ),
                    ReorderableDragStartListener(
                      index: index,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Icon(
                          Icons.drag_indicator_rounded,
                          color: AppTheme.textSecondary.withValues(alpha: 0.85),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniChip extends StatelessWidget {
  const _MiniChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.offWhite,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppTheme.textSecondary),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
