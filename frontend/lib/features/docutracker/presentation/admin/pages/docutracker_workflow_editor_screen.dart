// Legacy workflow presentation widgets remain available for compatibility;
// the active editor intentionally uses the simplified single-list layout.
// ignore_for_file: unused_element, unused_element_parameter

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/providers/auth_provider.dart';
import 'package:hrms_plaridel/features/docutracker/data/providers/docutracker_provider.dart';
import 'package:hrms_plaridel/features/docutracker/data/dto/docutracker_api_result.dart';
import 'package:hrms_plaridel/features/docutracker/data/repositories/docutracker_repository.dart';
import 'package:hrms_plaridel/features/docutracker/security/docutracker_roles.dart';
import 'package:hrms_plaridel/features/docutracker/data/styles/docutracker_styles.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_routing_config.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_type.dart';
import 'package:hrms_plaridel/features/docutracker/models/workflow_step.dart';
import 'package:hrms_plaridel/features/docutracker/services/docutracker_workflow_config_validator.dart';
import 'package:hrms_plaridel/features/docutracker/theme/docutracker_tokens.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/widgets/docutracker_error_banner.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/widgets/docutracker_responsive_body.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/widgets/docutracker_section_header.dart';
import 'docutracker_escalation_config_screen.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/admin/widgets/workflow_step_editor_panel.dart';

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

  /// Stable per-step IDs used for selection, reorder identity and preview mapping.
  late List<String> _stepIds;

  /// A [GlobalKey] per stable step ID for preview-chip jump scrolling.
  final Map<String, GlobalKey> _stepItemKeyById = {};
  final ScrollController _listScrollController = ScrollController();
  List<DocuTrackerWorkflowValidationIssue> _issues = const [];
  bool _saving = false;
  bool _hasUnsavedChanges = false;
  String? _error;
  String? _selectedStepId;
  final Map<String, String> _departmentNameById = {};
  final Map<String, _WorkflowStepAssigneeSnapshot> _assigneeSnapshotsByStepId =
      {};

  @override
  void initState() {
    super.initState();
    _steps =
        widget.initialConfig.steps
            .map(
              (s) => WorkflowStep(
                stepOrder: s.stepOrder,
                assigneeType: s.assigneeType,
                assigneeSource: s.assigneeSource,
                roleId: s.roleId,
                departmentId: s.departmentId,
                officeId: s.officeId,
                userIds: s.userIds == null
                    ? null
                    : List<String>.from(s.userIds!),
                label: s.label,
                enabled: s.enabled,
                deadlineHours: s.deadlineHours,
                allowedActions: List<String>.from(s.allowedActions),
              ),
            )
            .toList()
          ..sort((a, b) => a.stepOrder.compareTo(b.stepOrder));

    final stamp = DateTime.now().microsecondsSinceEpoch;
    _stepIds = List.generate(_steps.length, (i) => 'wf-$stamp-$i');
    for (final id in _stepIds) {
      _stepItemKeyById[id] = GlobalKey();
    }
    _selectedStepId = _stepIds.isEmpty ? null : _stepIds.first;

    _defaultDeadlineController.text = widget.initialConfig.reviewDeadlineHours
        .toString();
    _revalidate();
    _loadDepartmentLookup();
    _loadStepAssigneeSnapshots();
  }

  Future<void> _loadDepartmentLookup() async {
    try {
      final res = await ApiClient.instance.get<List<dynamic>>(
        '/api/departments',
      );
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

  Future<void> _loadStepAssigneeSnapshots() async {
    try {
      final rows = await DocuTrackerRepository.instance.getWorkflowSteps(
        documentType: widget.initialConfig.documentType.value,
        workflowVersion: widget.initialConfig.version,
      );
      final snapshots = <String, _WorkflowStepAssigneeSnapshot>{};
      final legacyActionsByOrder = <int, List<String>>{};
      final assigneeIdsByOrder = <int, List<String>>{};
      for (final row in rows) {
        final order =
            (row['step_order'] as num?)?.toInt() ??
            int.tryParse(row['step_order']?.toString() ?? '');
        if (order == null || order < 1 || order > _stepIds.length) continue;

        final key = _stepIds[order - 1];
        final rawAssignees = row['assignees'];
        final names = <String>[];
        final backupNames = <String>[];
        final primaryActions = <String>{};
        final primaryIds = <String>[];
        final backupIds = <String>[];

        if (rawAssignees is List) {
          final assignees = rawAssignees
              .whereType<Map>()
              .map((a) => Map<String, dynamic>.from(a))
              .where((a) => a['is_enabled'] != false)
              .toList();

          for (final a in assignees) {
            final name = (a['full_name']?.toString() ?? '').trim();
            final fallback = (a['user_id']?.toString() ?? '').trim();
            final label = name.isNotEmpty ? name : fallback;
            if (label.isEmpty) continue;
            if (a['is_primary'] == true) {
              names.add(label);
              if (fallback.isNotEmpty) primaryIds.add(fallback);
            } else {
              backupNames.add(label);
              if (fallback.isNotEmpty) backupIds.add(fallback);
            }

            final rawActions = a['allowed_actions'];
            if (rawActions is List) {
              for (final x in rawActions) {
                final action = x?.toString().trim();
                if (action != null && action.isNotEmpty) {
                  if (a['is_primary'] == true) primaryActions.add(action);
                }
              }
            }
          }
        }

        final resolvedActions = primaryActions.toList()..sort();
        assigneeIdsByOrder[order] = [...primaryIds, ...backupIds];
        snapshots[key] = _WorkflowStepAssigneeSnapshot(
          primaryUserName: names.isEmpty ? null : names.first,
          backupUserNames: backupNames,
          allowedActions: resolvedActions,
        );
        legacyActionsByOrder[order] = resolvedActions;
      }

      if (!mounted) return;
      setState(() {
        if (!_hasUnsavedChanges) {
          _steps = [
            for (final step in _steps)
              WorkflowStep(
                stepOrder: step.stepOrder,
                assigneeType: step.assigneeType,
                assigneeSource: step.assigneeSource,
                roleId: step.roleId,
                departmentId: step.departmentId,
                officeId: step.officeId,
                userIds: step.assigneeSource == 'department_reviewers'
                    ? step.userIds
                    : assigneeIdsByOrder[step.stepOrder] ?? step.userIds,
                label: step.label,
                enabled: step.enabled,
                deadlineHours: step.deadlineHours,
                allowedActions: step.allowedActions.isNotEmpty
                    ? step.allowedActions
                    : legacyActionsByOrder[step.stepOrder] ?? const [],
              ),
          ];
        }
        _assigneeSnapshotsByStepId
          ..clear()
          ..addAll(snapshots);
      });
    } catch (_) {
      // Non-blocking: the builder can still display draft workflow data.
    }
  }

  @override
  void dispose() {
    _listScrollController.dispose();
    _defaultDeadlineController.dispose();
    super.dispose();
  }

  bool _isAdminUser() {
    AuthProvider? auth;
    try {
      auth = context.read<AuthProvider>();
    } catch (_) {
      auth = null;
    }
    if (auth?.user == null) return true; // Allow tests and isolated previews.
    return DocuTrackerRoles.normalize(auth!.user!.role) ==
        DocuTrackerRoles.admin;
  }

  bool _ensureAdminAction() {
    if (_isAdminUser()) return true;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Access denied. Only admins can edit workflows.'),
        ),
      );
    }
    return false;
  }

  Future<bool> _confirmDiscardUnsavedChanges() async {
    if (!_hasUnsavedChanges || _saving) return true;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard unsaved changes?'),
        content: const Text(
          'You have unsaved workflow edits. Leaving now will discard all pending changes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Stay'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return confirm == true;
  }

  Future<void> _discardAndClose() async {
    if (!await _confirmDiscardUnsavedChanges()) return;
    if (!mounted) return;
    Navigator.of(context).pop(false);
  }

  void _markUnsaved() {
    if (_hasUnsavedChanges) return;
    _hasUnsavedChanges = true;
  }

  void _onPreviewSelectStep(int index) {
    if (index < 0 || index >= _stepIds.length) return;
    setState(() => _selectedStepId = _stepIds[index]);
    _scrollStepIntoView(index);
  }

  void _scrollStepIntoView(int index) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (index < 0 || index >= _stepIds.length) return;
      final stepId = _stepIds[index];
      final ctx = _stepItemKeyById[stepId]?.currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.12,
        duration: const Duration(milliseconds: 340),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _revalidate() {
    setState(() {
      _issues = _validator.validate(_steps);
    });
  }

  List<String> _restrictionErrors() {
    final errors = <String>[];
    final blocking = _issues.where((i) => !i.isWarning).toList();
    if (blocking.isNotEmpty) {
      errors.addAll(blocking.map((e) => e.message));
    }
    if (_steps.isEmpty) {
      errors.add('Workflow must contain at least one step.');
      return errors;
    }

    final orders = _steps.map((s) => s.stepOrder).toList()..sort();
    final expectedOrders = List<int>.generate(_steps.length, (i) => i + 1);
    if (orders.length != orders.toSet().length) {
      errors.add('Step order values must be unique.');
    }
    if (orders.isEmpty || orders.first != 1) {
      errors.add('Step order must start at 1.');
    }
    if (orders.length == expectedOrders.length) {
      for (var i = 0; i < orders.length; i++) {
        if (orders[i] != expectedOrders[i]) {
          errors.add('Step order must be continuous with no gaps.');
          break;
        }
      }
    }

    const maxDeadlineHours = 720;
    final activeCount = _steps.where((s) => s.enabled).length;
    if (activeCount == 0) {
      errors.add('Workflow must have at least one active step.');
    }

    const allowedActionsSet = {'approve', 'forward', 'reject', 'return'};
    for (var i = 0; i < _steps.length; i++) {
      final s = _steps[i];
      final stepLabel = 'Step ${s.stepOrder}';
      final label = (s.label ?? '').trim();
      if (label.isEmpty) {
        errors.add('$stepLabel must have a non-empty step name.');
      }

      if (s.deadlineHours != null) {
        if (s.deadlineHours! <= 0) {
          errors.add('$stepLabel deadline must be greater than 0 hours.');
        } else if (s.deadlineHours! > maxDeadlineHours) {
          errors.add(
            '$stepLabel deadline cannot exceed $maxDeadlineHours hours.',
          );
        }
      }

      if (!s.enabled) continue;

      if (s.assigneeType.trim().toLowerCase() == 'user') {
        final usesDepartmentReviewers =
            s.assigneeSource == 'department_reviewers';
        final userIds = (s.userIds ?? [])
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
        if (!usesDepartmentReviewers && userIds.isEmpty) {
          errors.add('$stepLabel requires at least one assigned user.');
        } else if (!usesDepartmentReviewers) {
          final primaryId = userIds.first;
          final backups = userIds.skip(1).toList();
          if (backups.contains(primaryId)) {
            errors.add(
              '$stepLabel backup users cannot include the primary user.',
            );
          }
          if (backups.length != backups.toSet().length) {
            errors.add('$stepLabel has duplicate backup users.');
          }
        }

        if (s.assigneeSource == 'department_reviewers' &&
            (s.departmentId ?? '').trim().isEmpty) {
          errors.add(
            '$stepLabel must include a department scope for selected users.',
          );
        }
      }

      if (s.assigneeType.trim().toLowerCase() == 'department' &&
          (s.departmentId ?? '').trim().isEmpty) {
        errors.add(
          '$stepLabel is department-based but no department is selected.',
        );
      }

      final stepActions = s.allowedActions;
      if (stepActions.isEmpty) {
        errors.add(
          '$stepLabel must include at least one allowed workflow action.',
        );
      } else {
        final invalid = stepActions.where(
          (a) => !allowedActionsSet.contains(a.trim().toLowerCase()),
        );
        if (invalid.isNotEmpty) {
          errors.add(
            '$stepLabel has invalid allowed actions: ${invalid.join(', ')}.',
          );
        }
      }
    }

    return errors.toSet().toList();
  }

  bool get _canSave =>
      _isAdminUser() && _restrictionErrors().isEmpty && !_saving;

  bool get _canPublish =>
      _isAdminUser() &&
      _hasUnsavedChanges &&
      _restrictionErrors().isEmpty &&
      !_saving;

  String? _validateStepDraft(WorkflowStep step) {
    final label = (step.label ?? '').trim();
    if (label.isEmpty) return 'Step name is required.';

    if (step.deadlineHours != null) {
      if (step.deadlineHours! <= 0) {
        return 'Step deadline must be greater than 0.';
      }
      if (step.deadlineHours! > 720) {
        return 'Step deadline cannot exceed 720 hours.';
      }
    }

    if (!step.enabled) return null;

    if (step.assigneeType.trim().toLowerCase() == 'department' &&
        (step.departmentId ?? '').trim().isEmpty) {
      return 'Department-based steps require a selected department.';
    }

    if (step.assigneeType.trim().toLowerCase() == 'user') {
      final usesDepartmentReviewers =
          step.assigneeSource == 'department_reviewers';
      final userIds = (step.userIds ?? [])
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      if (!usesDepartmentReviewers && userIds.isEmpty) {
        return 'Active selected-user steps need at least one user.';
      }
      if (usesDepartmentReviewers && (step.departmentId ?? '').trim().isEmpty) {
        return 'Automatic department-reviewer steps require a department.';
      }
      if (!usesDepartmentReviewers) {
        final primary = userIds.first;
        final backups = userIds.skip(1).toList();
        if (backups.contains(primary)) {
          return 'Backup users cannot include the primary user.';
        }
        if (backups.length != backups.toSet().length) {
          return 'Duplicate backup users are not allowed.';
        }
      }
    }
    return null;
  }

  /// Renumbers `stepOrder` to 1..n in **current list order** (required for drag-and-drop).
  void _renumberStepsContiguously() {
    _steps = [
      for (var i = 0; i < _steps.length; i++)
        WorkflowStep(
          stepOrder: i + 1,
          assigneeType: _steps[i].assigneeType,
          assigneeSource: _steps[i].assigneeSource,
          roleId: _steps[i].roleId,
          departmentId: _steps[i].departmentId,
          officeId: _steps[i].officeId,
          userIds: _steps[i].userIds,
          label: _steps[i].label,
          enabled: _steps[i].enabled,
          deadlineHours: _steps[i].deadlineHours,
          allowedActions: List<String>.from(_steps[i].allowedActions),
        ),
    ];
  }

  Future<void> _addStep({String? afterStepId}) async {
    if (!_ensureAdminAction()) return;
    final afterIndex = afterStepId == null
        ? null
        : _stepIds.indexWhere((id) => id == afterStepId);
    final resolvedAfterIndex = (afterIndex == null || afterIndex < 0)
        ? null
        : afterIndex;
    final nextOrder = _steps.isEmpty
        ? 1
        : (resolvedAfterIndex == null
              ? _steps.length + 1
              : resolvedAfterIndex + 2);
    final created = await showWorkflowStepEditor(
      context,
      title: resolvedAfterIndex == null
          ? 'Add step'
          : 'Add step after ${resolvedAfterIndex + 1}',
      initial: WorkflowStep(
        stepOrder: nextOrder,
        assigneeType: 'user',
        label: 'New step',
      ),
    );
    if (created == null) return;
    final draftIssue = _validateStepDraft(created);
    if (draftIssue != null) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(draftIssue)));
      }
      return;
    }
    setState(() {
      final insertAt = resolvedAfterIndex == null
          ? _steps.length
          : resolvedAfterIndex + 1;
      final key =
          'wf-${DateTime.now().microsecondsSinceEpoch}-${_stepIds.length}';
      _steps.insert(insertAt, created);
      _stepIds.insert(insertAt, key);
      _stepItemKeyById[key] = GlobalKey();
      _selectedStepId = key;
      _renumberStepsContiguously();
      _markUnsaved();
      _revalidate();
    });
  }

  Future<void> _addStepAfterSelected() async {
    if (_selectedStepId == null) {
      await _addStep();
      return;
    }
    await _addStep(afterStepId: _selectedStepId);
  }

  Future<void> _editStep(int index) async {
    if (!_ensureAdminAction()) return;
    final edited = await showWorkflowStepEditor(
      context,
      title: 'Edit step ${_steps[index].stepOrder}',
      initial: _steps[index],
    );
    if (edited == null) return;
    final draftIssue = _validateStepDraft(edited);
    if (draftIssue != null) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(draftIssue)));
      }
      return;
    }
    setState(() {
      _steps[index] = edited;
      _selectedStepId = _stepIds[index];
      _renumberStepsContiguously();
      _markUnsaved();
      _revalidate();
    });
  }

  Future<void> _removeStep(int index) async {
    if (!_ensureAdminAction()) return;
    final activeCount = _steps.where((s) => s.enabled).length;
    if (_steps[index].enabled && activeCount <= 1) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('At least one active step is required.'),
          ),
        );
      }
      return;
    }
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete step?'),
        content: Text(
          'Remove step ${_steps[index].stepOrder} from this workflow?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (shouldDelete != true) return;

    setState(() {
      final removedKey = _stepIds.removeAt(index);
      _stepItemKeyById.remove(removedKey);
      _assigneeSnapshotsByStepId.remove(removedKey);
      _steps.removeAt(index);
      if (_selectedStepId == removedKey) {
        final nextIndex = index >= _stepIds.length
            ? _stepIds.length - 1
            : index;
        _selectedStepId = _stepIds.isEmpty ? null : _stepIds[nextIndex];
      }
      _renumberStepsContiguously();
      _markUnsaved();
      _revalidate();
    });
  }

  void _onReorderSteps(int oldIndex, int newIndex) {
    if (!_ensureAdminAction()) return;
    if (oldIndex < 0 || oldIndex >= _steps.length) return;
    if (newIndex < 0 || newIndex > _steps.length) return;

    setState(() {
      if (newIndex == oldIndex) return;

      final movedStep = _steps.removeAt(oldIndex);
      _steps.insert(newIndex, movedStep);

      final movedStepId = _stepIds.removeAt(oldIndex);
      _stepIds.insert(newIndex, movedStepId);

      _renumberStepsContiguously();
      _markUnsaved();
      _revalidate();
    });
  }

  Future<void> _save({required bool publish}) async {
    if (!_ensureAdminAction()) return;
    if (_saving) return;
    if (publish) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Publish workflow version?'),
          content: const Text(
            'This will become the active workflow for new documents. Documents already in progress will keep their current version.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Publish'),
            ),
          ],
        ),
      );
      if (confirm != true) return;
    }
    final restrictionErrors = _restrictionErrors();
    if (restrictionErrors.isNotEmpty) {
      setState(() {
        _error = restrictionErrors.first;
      });
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final defaultDeadline =
          int.tryParse(_defaultDeadlineController.text.trim()) ?? 1;
      final updated = DocumentRoutingConfig(
        documentType: widget.initialConfig.documentType,
        steps: _steps,
        reviewDeadlineHours: defaultDeadline < 1 ? 1 : defaultDeadline,
      );

      final repo = DocuTrackerRepository.instance;
      final saveResult = await repo.saveRoutingConfig(updated);
      if (saveResult is DocuTrackerFailure<int>) {
        setState(() {
          _error = saveResult.message.isNotEmpty
              ? saveResult.message
              : 'Save was rejected by the server. Check that routing rules are valid, '
                    'or that no blocking constraint exists for this document type.';
          _saving = false;
        });
        return;
      }
      if (saveResult is! DocuTrackerSuccess<int>) {
        setState(() {
          _error = 'Save failed.';
          _saving = false;
        });
        return;
      }

      if (!mounted) return;
      await context.read<DocuTrackerProvider>().loadRoutingConfigs();
      if (!mounted) return;
      _hasUnsavedChanges = false;
      if (publish) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Workflow version published.')),
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        _error =
            'Could not publish workflow: ${docuTrackerDisplayError(e.toString())}';
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAdminUser = _isAdminUser();
    final blocking = _issues.where((i) => !i.isWarning).toList();
    final warnings = _issues.where((i) => i.isWarning).toList();
    if (!isAdminUser) {
      return Scaffold(
        appBar: AppBar(title: const Text('Workflow Editor')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.lock_rounded,
                    color: Colors.red.shade700,
                    size: 44,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Access denied',
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Only admins can edit, publish, or manage workflow rules.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    void openEscalationRules() {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const DocuTrackerEscalationConfigScreen(),
        ),
      );
    }

    Widget workflowHeaderBlock() {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final deadline = TextField(
                controller: _defaultDeadlineController,
                keyboardType: TextInputType.number,
                decoration: DocuTrackerStyles.inputDecoration(
                  context,
                  'Default deadline (hours)',
                  Icons.timer_outlined,
                ),
                onChanged: (_) {
                  _markUnsaved();
                  _revalidate();
                },
              );
              final add = FilledButton.icon(
                onPressed: _saving ? null : () => _addStep(),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add step'),
              );
              if (constraints.maxWidth < 520) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [deadline, const SizedBox(height: 10), add],
                );
              }
              return Row(
                children: [
                  Expanded(child: deadline),
                  const SizedBox(width: 12),
                  add,
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          if (_issues.isNotEmpty)
            _ValidationPanel(blocking: blocking, warnings: warnings),
          if (_error != null) ...[
            const SizedBox(height: 8),
            DocuTrackerErrorBanner(
              message: _error!,
              onDismiss: () => setState(() => _error = null),
            ),
          ],
          const SizedBox(height: 8),
        ],
      );
    }

    return PopScope(
      canPop: !_hasUnsavedChanges || _saving,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        if (!await _confirmDiscardUnsavedChanges()) return;
        if (!navigator.mounted) return;
        navigator.pop(false);
      },
      child: Scaffold(
        backgroundColor: DocuTrackerTokens.canvasOf(context),
        appBar: AppBar(
          backgroundColor: DocuTrackerTokens.surface,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          shadowColor: Colors.black.withValues(alpha: 0.06),
          title: Text(
            '${widget.initialConfig.documentType.displayName} workflow',
          ),
          actions: [
            Center(
              child: Text(
                _hasUnsavedChanges
                    ? 'Unsaved changes'
                    : 'Version ${widget.initialConfig.version}',
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            PopupMenuButton<String>(
              tooltip: 'More workflow settings',
              onSelected: (value) {
                if (value == 'escalation') openEscalationRules();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'escalation',
                  child: Text('Escalation rules'),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton(
                onPressed: _canPublish ? () => _save(publish: true) : null,
                child: Text(_saving ? 'Publishing…' : 'Publish workflow'),
              ),
            ),
          ],
        ),
        body: DocuTrackerResponsiveBody(
          maxWidth: DocuTrackerTokens.maxContentWidth,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: LayoutBuilder(
            builder: (context, constraints) {
              Widget workflowScroll() {
                return CustomScrollView(
                  controller: _listScrollController,
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(child: workflowHeaderBlock()),
                    if (_steps.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: true,
                        child: _EmptySteps(
                          onAdd: _saving ? null : () => _addStep(),
                        ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.only(bottom: 8),
                        sliver: SliverReorderableList(
                          itemCount: _steps.length,
                          onReorderItem: _onReorderSteps,
                          proxyDecorator: (child, index, animation) {
                            return AnimatedBuilder(
                              animation: animation,
                              builder: (context, _) {
                                final t = Curves.easeOut.transform(
                                  animation.value,
                                );
                                return Material(
                                  elevation: 6 + 10 * t,
                                  shadowColor: Colors.black.withValues(
                                    alpha: 0.18,
                                  ),
                                  borderRadius: BorderRadius.circular(
                                    DocuTrackerTokens.radiusLg,
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: child,
                                );
                              },
                            );
                          },
                          itemBuilder: (ctx, idx) {
                            final s = _steps[idx];
                            final last = idx == _steps.length - 1;
                            final stepId = _stepIds[idx];
                            final activeCount = _steps
                                .where((x) => x.enabled)
                                .length;
                            final canDeleteStep =
                                !(s.enabled && activeCount <= 1) && !_saving;
                            return _WorkflowStepFlowCard(
                              key: _stepItemKeyById[stepId]!,
                              index: idx,
                              step: s,
                              departmentNameById: _departmentNameById,
                              assigneeSnapshot:
                                  _assigneeSnapshotsByStepId[stepId],
                              defaultDeadlineHours:
                                  int.tryParse(
                                    _defaultDeadlineController.text.trim(),
                                  ) ??
                                  1,
                              showConnector: !last,
                              isSelected: _selectedStepId == stepId,
                              hasBlockingIssue: blocking.any(
                                (i) => i.stepOrder == s.stepOrder,
                              ),
                              hasWarning: warnings.any(
                                (i) => i.stepOrder == s.stepOrder,
                              ),
                              onSelect: () {
                                setState(() => _selectedStepId = stepId);
                                _editStep(idx);
                              },
                              onEdit: () => _editStep(idx),
                              onDelete: canDeleteStep
                                  ? () => _removeStep(idx)
                                  : null,
                              onAddAfter: _saving
                                  ? null
                                  : () => _addStep(afterStepId: stepId),
                            );
                          },
                        ),
                      ),
                  ],
                );
              }

              return workflowScroll();
            },
          ),
        ),
      ),
    );
  }
}

// --- Layout pieces ---

BoxDecoration _workflowPanelDecoration({Color? fill, Color? border}) {
  return BoxDecoration(
    color: fill ?? DocuTrackerTokens.surface,
    borderRadius: BorderRadius.circular(14),
    border: Border.all(color: border ?? DocuTrackerTokens.highlightPeachBorder),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.035),
        blurRadius: 14,
        offset: const Offset(0, 3),
      ),
    ],
  );
}

class _WorkflowEditorHeader extends StatelessWidget {
  const _WorkflowEditorHeader({
    required this.documentType,
    required this.version,
    required this.hasUnsavedChanges,
  });

  final DocumentType documentType;
  final int version;
  final bool hasUnsavedChanges;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          tooltip: 'Back to documents',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'BACK TO DOCUMENTS',
                style: DocuTrackerTokens.metaStyle(context).copyWith(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 2),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    'Workflow Builder',
                    style: const TextStyle(
                      color: DocuTrackerTokens.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  _MiniChip(
                    icon: Icons.description_outlined,
                    label: documentType.displayName,
                    tint: DocuTrackerTokens.brand,
                  ),
                  _MiniChip(
                    icon: Icons.new_releases_outlined,
                    label: 'v$version - Draft',
                    tint: hasUnsavedChanges
                        ? DocuTrackerTokens.brand
                        : DocuTrackerTokens.textMuted,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _WorkflowToolsPanel extends StatelessWidget {
  const _WorkflowToolsPanel({
    required this.enabledStepCount,
    required this.stepCount,
    required this.onEscalationRules,
  });

  final int enabledStepCount;
  final int stepCount;
  final VoidCallback onEscalationRules;

  @override
  Widget build(BuildContext context) {
    final insight = stepCount == 0
        ? 'Add the first route step before publishing this workflow.'
        : '$enabledStepCount of $stepCount steps are enabled.';
    return DecoratedBox(
      decoration: _workflowPanelDecoration(fill: DocuTrackerTokens.canvas),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.tune_rounded,
                  color: DocuTrackerTokens.brand,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Additional Settings',
                    overflow: TextOverflow.ellipsis,
                    style: DocuTrackerTokens.titleStyle(
                      context,
                    ).copyWith(fontSize: 15, fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _WorkflowToolTile(
              icon: Icons.notifications_active_outlined,
              label: 'Escalation Rules',
              onTap: onEscalationRules,
            ),
            const SizedBox(height: 18),
            _WorkflowInsightPanel(
              insight: insight,
              progress: stepCount == 0
                  ? 0.08
                  : (enabledStepCount / stepCount).clamp(0.08, 1.0).toDouble(),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkflowToolTile extends StatelessWidget {
  const _WorkflowToolTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: DocuTrackerTokens.surface,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: DocuTrackerTokens.highlightPeachBorder),
          ),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: DocuTrackerTokens.brandSoft,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: DocuTrackerTokens.brand, size: 16),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: DocuTrackerTokens.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: DocuTrackerTokens.textMuted,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WorkflowInsightPanel extends StatelessWidget {
  const _WorkflowInsightPanel({required this.insight, required this.progress});

  final String insight;
  final double progress;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: _workflowPanelDecoration(
        fill: DocuTrackerTokens.highlightPeach,
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'ANALYTICS INSIGHT',
              style: DocuTrackerTokens.metaStyle(context).copyWith(
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              insight,
              style: DocuTrackerTokens.subtitleStyle(
                context,
              ).copyWith(fontSize: 12),
            ),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 7,
                backgroundColor: DocuTrackerTokens.brandSoft,
                valueColor: const AlwaysStoppedAnimation<Color>(
                  DocuTrackerTokens.brand,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkflowEditorBottomActions extends StatelessWidget {
  const _WorkflowEditorBottomActions({
    required this.saving,
    required this.canSave,
    required this.canPublish,
    required this.hasUnsavedChanges,
    required this.restrictionErrors,
    required this.onAddStep,
    required this.onAddAfter,
    required this.onDiscard,
    required this.onSave,
    required this.onPublish,
  });

  final bool saving;
  final bool canSave;
  final bool canPublish;
  final bool hasUnsavedChanges;
  final List<String> restrictionErrors;
  final VoidCallback onAddStep;
  final VoidCallback onAddAfter;
  final VoidCallback onDiscard;
  final VoidCallback onSave;
  final VoidCallback onPublish;

  @override
  Widget build(BuildContext context) {
    final helperText = restrictionErrors.isNotEmpty
        ? '${restrictionErrors.length} issue(s) block save/publish.'
        : (!canSave && !saving
              ? 'Fix validation errors above before saving.'
              : null);

    return SafeArea(
      top: false,
      child: Material(
        color: DocuTrackerTokens.surface,
        elevation: 10,
        shadowColor: Colors.black.withValues(alpha: 0.08),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: saving ? null : onAddStep,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Add step'),
                  ),
                  OutlinedButton.icon(
                    onPressed: saving ? null : onAddAfter,
                    icon: const Icon(Icons.playlist_add_rounded),
                    label: const Text('Add after selected'),
                  ),
                  OutlinedButton.icon(
                    onPressed: hasUnsavedChanges && !saving ? onDiscard : null,
                    icon: const Icon(Icons.cancel_outlined),
                    style: DocuTrackerStyles.outlinedRedStyle(),
                    label: const Text('Discard changes'),
                  ),
                  FilledButton.icon(
                    onPressed: canSave ? onSave : null,
                    icon: saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_rounded),
                    label: Text(saving ? 'Saving…' : 'Save workflow'),
                  ),
                  FilledButton.icon(
                    onPressed: canPublish ? onPublish : null,
                    icon: const Icon(Icons.publish_rounded),
                    label: const Text('Publish version'),
                  ),
                ],
              ),
              if (helperText != null) ...[
                const SizedBox(height: 6),
                Text(
                  helperText,
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 11.5,
                  ),
                ),
              ],
              if (restrictionErrors.isNotEmpty && !saving) ...[
                const SizedBox(height: 8),
                _RestrictionPanel(messages: restrictionErrors),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.version});

  final int version;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: _workflowPanelDecoration(
        fill: DocuTrackerTokens.highlightPeach,
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.info_outline_rounded,
              color: DocuTrackerTokens.brand,
              size: 22,
            ),
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
      decoration: _workflowPanelDecoration(fill: DocuTrackerTokens.surface),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.groups_rounded,
                  color: Colors.green.shade800,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Each step now contains its primary assignee, optional backup, and '
                    'allowed actions. Document visibility follows the active workflow '
                    'automatically; no separate visibility setup is needed.',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ValidationPanel extends StatelessWidget {
  const _ValidationPanel({required this.blocking, required this.warnings});

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
                  blocking.isNotEmpty
                      ? Icons.block_rounded
                      : Icons.warning_amber_rounded,
                  size: 20,
                  color: blocking.isNotEmpty
                      ? Colors.red.shade800
                      : Colors.orange.shade900,
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

class _RestrictionPanel extends StatelessWidget {
  const _RestrictionPanel({required this.messages});

  final List<String> messages;

  @override
  Widget build(BuildContext context) {
    if (messages.isEmpty) return const SizedBox.shrink();
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFFFEBEE),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.withValues(alpha: 0.24)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.gpp_bad_rounded,
                  color: Colors.red.shade800,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Workflow restrictions',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final message in messages.take(8))
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '• $message',
                  style: TextStyle(
                    color: Colors.red.shade900,
                    fontSize: 12.5,
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

class _EmptySteps extends StatelessWidget {
  const _EmptySteps({required this.onAdd});

  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final minHeight = (constraints.maxHeight - 16)
            .clamp(0.0, double.infinity)
            .toDouble();
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minHeight),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.account_tree_rounded,
                      size: 48,
                      color: AppTheme.textSecondary.withValues(alpha: 0.4),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Start your route',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Each step is one stop where someone reviews or acts on the document. '
                      'Add the first step—you can drag cards into the right order any time before saving.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 13,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Tooltip(
                      message:
                          'Opens the step editor so you can name this step and choose who is involved.',
                      child: FilledButton.icon(
                        onPressed: onAdd,
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Add first step'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _WorkflowStepAssigneeSnapshot {
  const _WorkflowStepAssigneeSnapshot({
    required this.primaryUserName,
    required this.backupUserNames,
    required this.allowedActions,
  });

  final String? primaryUserName;
  final List<String> backupUserNames;
  final List<String> allowedActions;
}

class _WorkflowBuilderOverview extends StatelessWidget {
  const _WorkflowBuilderOverview({
    required this.documentType,
    required this.stepCount,
    required this.enabledStepCount,
    required this.selectedStep,
    required this.defaultDeadlineHours,
    required this.defaultDeadlineController,
    required this.onDeadlineChanged,
  });

  final DocumentType documentType;
  final int stepCount;
  final int enabledStepCount;
  final WorkflowStep? selectedStep;
  final int defaultDeadlineHours;
  final TextEditingController defaultDeadlineController;
  final VoidCallback onDeadlineChanged;

  @override
  Widget build(BuildContext context) {
    final selectedLabel = selectedStep == null
        ? 'None'
        : 'Step ${selectedStep!.stepOrder}';
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 760;
        final activeCard = _WorkflowActiveSummaryCard(
          documentType: documentType,
          enabledStepCount: enabledStepCount,
          stepCount: stepCount,
          defaultDeadlineHours: defaultDeadlineHours,
        );
        final deadlineCard = _DeadlineMetricCard(
          controller: defaultDeadlineController,
          onChanged: onDeadlineChanged,
        );
        final selectedCard = _OverviewMetricCard(
          icon: Icons.manage_search_rounded,
          label: 'Highlighted item',
          value: selectedLabel,
          emphasized: true,
        );
        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              activeCard,
              const SizedBox(height: 12),
              deadlineCard,
              const SizedBox(height: 12),
              selectedCard,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 2, child: activeCard),
            const SizedBox(width: 14),
            Expanded(child: deadlineCard),
            const SizedBox(width: 14),
            Expanded(child: selectedCard),
          ],
        );
      },
    );
  }
}

class _WorkflowActiveSummaryCard extends StatelessWidget {
  const _WorkflowActiveSummaryCard({
    required this.documentType,
    required this.enabledStepCount,
    required this.stepCount,
    required this.defaultDeadlineHours,
  });

  final DocumentType documentType;
  final int enabledStepCount;
  final int stepCount;
  final int defaultDeadlineHours;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: _workflowPanelDecoration(),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'ACTIVE WORKFLOW',
              style: DocuTrackerTokens.metaStyle(context).copyWith(
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              documentType.displayName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: DocuTrackerTokens.brandDark,
                fontSize: 22,
                height: 1.05,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 26),
            Wrap(
              spacing: 18,
              runSpacing: 10,
              children: [
                _OverviewMiniStat(
                  icon: Icons.account_tree_rounded,
                  value: '$enabledStepCount Active',
                  label: 'Steps',
                ),
                _OverviewMiniStat(
                  icon: Icons.schedule_rounded,
                  value: '${defaultDeadlineHours}h',
                  label: 'Default SLA',
                ),
                _OverviewMiniStat(
                  icon: Icons.layers_rounded,
                  value: '$stepCount Total',
                  label: 'Cards',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _OverviewMiniStat extends StatelessWidget {
  const _OverviewMiniStat({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 17, color: DocuTrackerTokens.brand),
        const SizedBox(width: 7),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: const TextStyle(
                color: DocuTrackerTokens.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
            Text(
              label,
              style: DocuTrackerTokens.metaStyle(
                context,
              ).copyWith(fontSize: 11),
            ),
          ],
        ),
      ],
    );
  }
}

class _DeadlineMetricCard extends StatelessWidget {
  const _DeadlineMetricCard({
    required this.controller,
    required this.onChanged,
  });

  final TextEditingController controller;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return _OverviewMetricCard(
      icon: Icons.timer_rounded,
      label: 'Default deadline',
      value: 'Hours',
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 25,
          fontWeight: FontWeight.w900,
          color: DocuTrackerTokens.textPrimary,
        ),
        decoration: const InputDecoration(
          border: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.zero,
        ),
        onChanged: (_) => onChanged(),
      ),
    );
  }
}

class _OverviewMetricCard extends StatelessWidget {
  const _OverviewMetricCard({
    required this.icon,
    required this.label,
    required this.value,
    this.child,
    this.emphasized = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final Widget? child;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: DocuTrackerTokens.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: emphasized
              ? DocuTrackerTokens.brand
              : DocuTrackerTokens.highlightPeachBorder,
          width: emphasized ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 14,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: DocuTrackerTokens.brand, size: 25),
            const SizedBox(height: 10),
            Text(
              label,
              textAlign: TextAlign.center,
              style: DocuTrackerTokens.metaStyle(
                context,
              ).copyWith(fontSize: 10, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            child ??
                Text(
                  value,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: DocuTrackerTokens.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _WorkflowPathPreviewStrip extends StatelessWidget {
  const _WorkflowPathPreviewStrip({
    required this.steps,
    required this.rowKeys,
    required this.departmentNameById,
    required this.assigneeSnapshotsByKey,
    required this.selectedIndex,
    this.onSelectIndex,
  });

  final List<WorkflowStep> steps;
  final List<String> rowKeys;
  final Map<String, String> departmentNameById;
  final Map<String, _WorkflowStepAssigneeSnapshot> assigneeSnapshotsByKey;
  final int selectedIndex;
  final ValueChanged<int>? onSelectIndex;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: DocuTrackerTokens.cardDecoration(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.route_rounded,
                  size: 20,
                  color: DocuTrackerTokens.brand.withValues(alpha: 0.9),
                ),
                const SizedBox(width: 8),
                Text(
                  'Route preview',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 6),
                Tooltip(
                  message:
                      'Read-only summary of the same order as the cards below. '
                      'Tap a step to highlight it and scroll the list to that card.',
                  triggerMode: TooltipTriggerMode.tap,
                  child: Icon(
                    Icons.help_outline_rounded,
                    size: 18,
                    color: AppTheme.textSecondary.withValues(alpha: 0.75),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              'Same order as the builder · Tap a step to highlight it and scroll to its card',
              style: DocuTrackerTokens.subtitleStyle(
                context,
              ).copyWith(fontSize: 11.5),
            ),
            const SizedBox(height: 10),
            if (steps.isEmpty)
              Text(
                'Add steps below to see how the document will move through your office.',
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12.5,
                  height: 1.35,
                ),
              )
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < steps.length; i++) ...[
                      _PathPreviewChip(
                        step: steps[i],
                        departmentNameById: departmentNameById,
                        assigneeSnapshot: assigneeSnapshotsByKey[rowKeys[i]],
                        isSelected: i == selectedIndex,
                        onTap: onSelectIndex == null
                            ? null
                            : () => onSelectIndex!(i),
                      ),
                      if (i < steps.length - 1)
                        Padding(
                          padding: const EdgeInsets.only(
                            top: 10,
                            left: 2,
                            right: 2,
                          ),
                          child: Icon(
                            Icons.arrow_forward_rounded,
                            size: 18,
                            color: AppTheme.textSecondary.withValues(
                              alpha: 0.45,
                            ),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PathPreviewChip extends StatelessWidget {
  const _PathPreviewChip({
    required this.step,
    required this.departmentNameById,
    required this.assigneeSnapshot,
    required this.isSelected,
    this.onTap,
  });

  final WorkflowStep step;
  final Map<String, String> departmentNameById;
  final _WorkflowStepAssigneeSnapshot? assigneeSnapshot;
  final bool isSelected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = step.enabled;
    final borderColor = isSelected
        ? DocuTrackerTokens.brand
        : DocuTrackerTokens.borderSubtle;
    final fill = isSelected
        ? DocuTrackerTokens.brand.withValues(alpha: 0.06)
        : DocuTrackerTokens.surface;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.fromLTRB(8, 8, 10, 8),
          constraints: const BoxConstraints(maxWidth: 168),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: borderColor, width: isSelected ? 2 : 1),
          ),
          child: Opacity(
            opacity: enabled ? 1 : 0.55,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: DocuTrackerTokens.brand.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${step.stepOrder}',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                      color: DocuTrackerTokens.brand,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _stepName(step),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 12.5,
                          color: enabled
                              ? AppTheme.textPrimary
                              : AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _primaryUserLabel(step, assigneeSnapshot),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10.5,
                          color: AppTheme.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _departmentLabel(step, departmentNameById),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          color: AppTheme.textSecondary.withValues(alpha: 0.9),
                        ),
                      ),
                    ],
                  ),
                ),
                if (!enabled)
                  Padding(
                    padding: const EdgeInsets.only(left: 2),
                    child: Icon(
                      Icons.pause_circle_outline_rounded,
                      size: 16,
                      color: AppTheme.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WorkflowBuilderToolbar extends StatelessWidget {
  const _WorkflowBuilderToolbar({
    required this.stepCount,
    required this.selectedStepOrder,
  });

  final int stepCount;
  final int? selectedStepOrder;

  @override
  Widget build(BuildContext context) {
    final status = selectedStepOrder == null
        ? '$stepCount step${stepCount == 1 ? '' : 's'}'
        : 'Step $selectedStepOrder highlighted';

    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth >= 520) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Flexible(
                child: DocuTrackerSectionHeader(
                  title: 'Step Details',
                  icon: Icons.account_tree_rounded,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _MiniChip(
                        icon: Icons.swap_vert_rounded,
                        label: 'Drag to reorder',
                        tint: DocuTrackerTokens.brand,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        status,
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DocuTrackerSectionHeader(
              title: 'Step Details',
              icon: Icons.account_tree_rounded,
            ),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _MiniChip(
                  icon: Icons.swap_vert_rounded,
                  label: 'Drag to reorder',
                  tint: DocuTrackerTokens.brand,
                ),
                Text(
                  status,
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

String _stepName(WorkflowStep step) {
  final label = (step.label ?? '').trim();
  return label.isEmpty ? 'Step ${step.stepOrder}' : label;
}

String _shortId(String id) {
  final trimmed = id.trim();
  if (trimmed.length <= 12) return trimmed;
  return '${trimmed.substring(0, 8)}...';
}

String _departmentLabel(
  WorkflowStep step,
  Map<String, String> departmentNameById,
) {
  final type = step.assigneeType.trim().toLowerCase();
  final departmentId = (step.departmentId ?? '').trim();
  if (departmentId.isNotEmpty) {
    return departmentNameById[departmentId] ?? _shortId(departmentId);
  }
  if (type == 'office') {
    final officeId = (step.officeId ?? '').trim();
    return officeId.isEmpty
        ? 'No department scope'
        : 'Office: ${_shortId(officeId)}';
  }
  if (type == 'role') return 'No department scope';
  return 'Department not set';
}

String _primaryUserLabel(
  WorkflowStep step,
  _WorkflowStepAssigneeSnapshot? snapshot,
) {
  if (step.assigneeSource == 'department_reviewers') {
    return 'Official Department Head';
  }
  final snapshotName = snapshot?.primaryUserName?.trim();
  if (snapshotName != null && snapshotName.isNotEmpty) return snapshotName;

  final ids =
      step.userIds?.map((e) => e.trim()).where((e) => e.isNotEmpty).toList() ??
      const <String>[];
  if (ids.isNotEmpty) return 'User ${_shortId(ids.first)}';

  switch (step.assigneeType.trim().toLowerCase()) {
    case 'department':
      return 'First available department assignee';
    case 'office':
      return 'First available office assignee';
    case 'role':
      final role = (step.roleId ?? '').trim();
      return role.isEmpty ? 'Role not set' : 'Role: $role';
    default:
      return 'Primary user not set';
  }
}

List<String> _backupUserLabels(
  WorkflowStep step,
  _WorkflowStepAssigneeSnapshot? snapshot,
) {
  if (step.assigneeSource == 'department_reviewers') {
    return const ['Configured department backups'];
  }
  if (snapshot != null && snapshot.backupUserNames.isNotEmpty) {
    return snapshot.backupUserNames;
  }
  final ids =
      step.userIds?.map((e) => e.trim()).where((e) => e.isNotEmpty).toList() ??
      const <String>[];
  if (ids.length <= 1) return const [];
  return ids.skip(1).map((id) => 'User ${_shortId(id)}').toList();
}

List<String> _allowedActionLabels(
  WorkflowStep step,
  _WorkflowStepAssigneeSnapshot? snapshot,
) {
  final actions = step.allowedActions.isNotEmpty
      ? step.allowedActions
      : snapshot?.allowedActions;
  final raw = actions == null || actions.isEmpty
      ? const <String>['approve', 'forward', 'reject', 'return']
      : actions;
  return raw.map(_workflowActionLabel).toList();
}

String _workflowActionLabel(String raw) {
  return switch (raw.trim().toLowerCase()) {
    'approve' => 'Approve and continue',
    'forward' => 'Forward without approval',
    'return' => 'Return for changes',
    'reject' => 'Reject and stop',
    final value when value.isNotEmpty =>
      '${value[0].toUpperCase()}${value.substring(1)}',
    _ => raw,
  };
}

String _deadlineLabel(WorkflowStep step, int defaultDeadlineHours) {
  final hours = step.deadlineHours;
  if (hours == null) return '$defaultDeadlineHours h default';
  return '$hours h';
}

Color _stepAccentColor(
  WorkflowStep step,
  bool hasBlockingIssue,
  bool hasWarning,
) {
  if (!step.enabled) return Colors.grey.shade600;
  if (hasBlockingIssue) return Colors.red.shade700;
  if (hasWarning) return Colors.orange.shade800;
  const palette = [
    Color(0xFF2563EB),
    Color(0xFF059669),
    Color(0xFFD97706),
    Color(0xFF0891B2),
    Color(0xFF7C3AED),
  ];
  return palette[(step.stepOrder - 1) % palette.length];
}

class _WorkflowStepFlowCard extends StatelessWidget {
  const _WorkflowStepFlowCard({
    super.key,
    required this.index,
    required this.step,
    required this.departmentNameById,
    required this.assigneeSnapshot,
    required this.defaultDeadlineHours,
    required this.showConnector,
    required this.isSelected,
    required this.hasBlockingIssue,
    required this.hasWarning,
    required this.onSelect,
    required this.onEdit,
    required this.onDelete,
    required this.onAddAfter,
  });

  final int index;
  final WorkflowStep step;
  final Map<String, String> departmentNameById;
  final _WorkflowStepAssigneeSnapshot? assigneeSnapshot;
  final int defaultDeadlineHours;
  final bool showConnector;
  final bool isSelected;
  final bool hasBlockingIssue;
  final bool hasWarning;
  final VoidCallback onSelect;
  final VoidCallback onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onAddAfter;

  @override
  Widget build(BuildContext context) {
    final accent = _stepAccentColor(step, hasBlockingIssue, hasWarning);
    final backupUsers = _backupUserLabels(step, assigneeSnapshot);
    final actionLabels = _allowedActionLabels(step, assigneeSnapshot);
    final borderColor = isSelected
        ? accent
        : hasBlockingIssue
        ? Colors.red.shade300
        : DocuTrackerTokens.borderSubtle;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TimelineMarker(
            stepOrder: step.stepOrder,
            accent: accent,
            showConnector: showConnector,
            isSelected: isSelected,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: InkWell(
              onTap: onSelect,
              borderRadius: BorderRadius.circular(DocuTrackerTokens.radiusLg),
              splashColor: accent.withValues(alpha: 0.12),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                decoration: BoxDecoration(
                  color: DocuTrackerTokens.surface,
                  borderRadius: BorderRadius.circular(
                    DocuTrackerTokens.radiusLg,
                  ),
                  border: Border.all(
                    color: borderColor,
                    width: isSelected || hasBlockingIssue ? 2 : 1,
                  ),
                  boxShadow: [
                    if (isSelected)
                      BoxShadow(
                        color: accent.withValues(alpha: 0.2),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      )
                    else
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 12,
                        offset: const Offset(0, 3),
                      ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 14, 14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 18,
                            backgroundColor: accent.withValues(alpha: 0.14),
                            foregroundColor: accent,
                            child: Text(
                              '${step.stepOrder}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _stepName(step),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 16,
                                    color: step.enabled
                                        ? AppTheme.textPrimary
                                        : AppTheme.textSecondary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Deadline: ${_deadlineLabel(step, defaultDeadlineHours)}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          ReorderableDragStartListener(
                            index: index,
                            child: Tooltip(
                              message:
                                  'Drag to reorder: press and hold, then move the card up or down',
                              child: Icon(
                                Icons.drag_indicator_rounded,
                                color: AppTheme.textSecondary.withValues(
                                  alpha: 0.85,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _StepBadge(
                            label: 'Step ${step.stepOrder}',
                            color: accent,
                          ),
                          if (isSelected)
                            _StepBadge(
                              label: 'Highlighted',
                              color: DocuTrackerTokens.brand,
                              isSoft: true,
                            ),
                          if (!step.enabled)
                            _StepBadge(
                              label: 'Disabled',
                              color: Colors.grey.shade700,
                              isSoft: true,
                            ),
                          if (hasBlockingIssue)
                            _StepBadge(
                              label: 'Needs fixing',
                              color: Colors.red.shade700,
                              isSoft: true,
                            ),
                          _ActionChip(
                            label: _departmentLabel(step, departmentNameById),
                            accent: accent,
                          ),
                          _ActionChip(
                            label:
                                'Primary: ${_primaryUserLabel(step, assigneeSnapshot)}',
                            accent: accent,
                          ),
                          _ActionChip(
                            label: backupUsers.isEmpty
                                ? 'Backups: none'
                                : 'Backups: ${backupUsers.join(', ')}',
                            accent: accent,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Allowed actions',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final label in actionLabels)
                            _ActionChip(label: label, accent: accent),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          OutlinedButton.icon(
                            onPressed: onEdit,
                            icon: const Icon(Icons.edit_rounded, size: 18),
                            label: const Text('Edit'),
                          ),
                          const Spacer(),
                          PopupMenuButton<String>(
                            tooltip: 'More step actions',
                            onSelected: (value) {
                              if (value == 'add') onAddAfter?.call();
                              if (value == 'delete') onDelete?.call();
                            },
                            itemBuilder: (_) => [
                              PopupMenuItem<String>(
                                value: 'add',
                                enabled: onAddAfter != null,
                                child: const Text('Add step after'),
                              ),
                              PopupMenuItem<String>(
                                value: 'delete',
                                enabled: onDelete != null,
                                child: const Text('Delete step'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TimelineMarker extends StatelessWidget {
  const _TimelineMarker({
    required this.stepOrder,
    required this.accent,
    required this.showConnector,
    required this.isSelected,
  });

  final int stepOrder;
  final Color accent;
  final bool showConnector;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    const railWidth = 48.0;
    final nodeSize = isSelected ? 40.0 : 36.0;

    return SizedBox(
      width: railWidth,
      child: Column(
        children: [
          Container(
            width: nodeSize,
            height: nodeSize,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isSelected ? accent : accent.withValues(alpha: 0.12),
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected
                    ? accent.withValues(alpha: 0.9)
                    : accent.withValues(alpha: 0.45),
                width: isSelected ? 2.5 : 1.5,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: accent.withValues(alpha: 0.35),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            child: Text(
              '$stepOrder',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 14,
                color: isSelected ? Colors.white : accent,
              ),
            ),
          ),
          if (showConnector) ...[
            Container(
              width: 3,
              height: 14,
              margin: const EdgeInsets.only(top: 4),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Icon(
              Icons.arrow_downward_rounded,
              size: 20,
              color: accent.withValues(alpha: 0.75),
            ),
            Container(
              width: 3,
              height: 40,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    accent.withValues(alpha: 0.32),
                    accent.withValues(alpha: 0.12),
                  ],
                ),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StepBadge extends StatelessWidget {
  const _StepBadge({
    required this.label,
    required this.color,
    this.isSoft = false,
  });

  final String label;
  final Color color;
  final bool isSoft;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isSoft ? color.withValues(alpha: 0.1) : color,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: isSoft ? 0.25 : 1)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: isSoft ? color : Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({required this.label, required this.accent});

  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent.withValues(alpha: 0.2)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: accent,
        ),
      ),
    );
  }
}

class _MiniChip extends StatelessWidget {
  const _MiniChip({required this.icon, required this.label, this.tint});

  final IconData icon;
  final String label;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final color = tint ?? AppTheme.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
