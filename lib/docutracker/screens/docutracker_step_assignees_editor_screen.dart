import 'dart:async';

import 'package:flutter/material.dart';

import '../../api/client.dart';
import '../../landingpage/constants/app_theme.dart';
import '../docutracker_api_result.dart';
import '../docutracker_repository.dart';
import '../docutracker_styles.dart';
import '../theme/docutracker_tokens.dart';
import '../models/document_routing_config.dart';
import '../models/document_type.dart';
import '../widgets/docutracker_error_banner.dart';
import '../widgets/docutracker_module_header.dart';
import '../widgets/docutracker_responsive_body.dart';

class DocuTrackerStepAssigneesEditorScreen extends StatefulWidget {
  const DocuTrackerStepAssigneesEditorScreen({
    super.key,
    this.initialDocumentType,
    this.initialWorkflowVersion,
  });

  final String? initialDocumentType;
  final int? initialWorkflowVersion;

  @override
  State<DocuTrackerStepAssigneesEditorScreen> createState() =>
      _DocuTrackerStepAssigneesEditorScreenState();
}

class _DocStep {
  const _DocStep({
    required this.stepId,
    required this.documentType,
    required this.workflowVersion,
    required this.stepOrder,
    required this.departmentId,
    required this.label,
    required this.enabled,
    required this.assignees,
  });

  final String stepId;
  final String documentType;
  final int workflowVersion;
  final int stepOrder;
  final String? departmentId;
  final String? label;
  final bool enabled;
  final List<_Assignee> assignees;

  String get displayLabel =>
      (label ?? '').trim().isEmpty ? 'Step $stepOrder' : label!.trim();
}

class _Assignee {
  const _Assignee({
    required this.userId,
    required this.fullName,
    this.departmentName,
    required this.isPrimary,
    required this.backupRank,
    required this.isEnabled,
    required this.allowedActions,
  });

  final String userId;
  final String fullName;
  final String? departmentName;
  final bool isPrimary;
  final int? backupRank;
  final bool isEnabled;
  final Set<String> allowedActions;

  _Assignee copyWith({
    String? userId,
    String? fullName,
    String? departmentName,
    bool? isPrimary,
    int? backupRank,
    bool? isEnabled,
    Set<String>? allowedActions,
  }) {
    return _Assignee(
      userId: userId ?? this.userId,
      fullName: fullName ?? this.fullName,
      departmentName: departmentName ?? this.departmentName,
      isPrimary: isPrimary ?? this.isPrimary,
      backupRank: backupRank ?? this.backupRank,
      isEnabled: isEnabled ?? this.isEnabled,
      allowedActions: allowedActions ?? this.allowedActions,
    );
  }
}

class _EmpRow {
  const _EmpRow({required this.id, required this.name});
  final String id;
  final String name;
}

class _DocuTrackerStepAssigneesEditorScreenState
    extends State<DocuTrackerStepAssigneesEditorScreen> {
  final _repo = DocuTrackerRepository.instance;

  String? _documentType;
  int? _workflowVersion;
  bool _loading = true;
  String? _error;

  final List<_DocStep> _steps = [];
  final Map<String, String> _departmentNameById = {};

  final _empSearchController = TextEditingController();
  Timer? _empSearchDebounce;
  bool _empLoading = false;
  List<_EmpRow> _empHits = const [];

  static const _workflowActions = <String>[
    'approve',
    'forward',
    'reject',
    'return',
  ];

  static Color _stepColor(int order) {
    const colors = [
      Color(0xFF3B82F6),
      Color(0xFF8B5CF6),
      Color(0xFF10B981),
      Color(0xFFF59E0B),
      Color(0xFFEF4444),
      Color(0xFF06B6D4),
    ];
    return colors[(order - 1) % colors.length];
  }

  @override
  void initState() {
    super.initState();
    _documentType =
        widget.initialDocumentType ??
        (DocumentRoutingConfig.defaults.isEmpty
            ? null
            : DocumentRoutingConfig.defaults.first.documentType.value);
    _workflowVersion = widget.initialWorkflowVersion;
    _empSearchController.addListener(_scheduleEmpSearch);
    _load();
  }

  @override
  void dispose() {
    _empSearchDebounce?.cancel();
    _empSearchController.removeListener(_scheduleEmpSearch);
    _empSearchController.dispose();
    super.dispose();
  }

  void _scheduleEmpSearch() {
    _empSearchDebounce?.cancel();
    _empSearchDebounce = Timer(
      const Duration(milliseconds: 350),
      _fetchEmployees,
    );
  }

  Future<void> _fetchEmployees({String? departmentId}) async {
    if (!mounted) return;
    setState(() => _empLoading = true);
    try {
      final q = _empSearchController.text.trim();
      final res = await ApiClient.instance.get<dynamic>(
        '/api/employees',
        queryParameters: <String, dynamic>{
          'status': 'Active',
          'role': 'All',
          'limit': 50,
          'offset': 0,
          if (q.isNotEmpty) 'q': q,
          if (departmentId != null && departmentId.trim().isNotEmpty)
            'department_id': departmentId,
          'sort': 'full_name',
          'order': 'asc',
        },
      );
      final data = res.data;
      List<dynamic> list;
      if (data is Map && data['employees'] is List) {
        list = data['employees'] as List<dynamic>;
      } else if (data is List) {
        list = data;
      } else {
        list = [];
      }
      final rows = <_EmpRow>[];
      for (final e in list) {
        final m = e as Map<String, dynamic>;
        final id = m['id']?.toString();
        if (id == null || id.isEmpty) continue;
        final name = m['full_name']?.toString() ?? 'Unknown';
        rows.add(_EmpRow(id: id, name: name));
      }
      if (mounted) setState(() => _empHits = rows);
    } catch (_) {
      if (mounted) setState(() => _empHits = const []);
    } finally {
      if (mounted) setState(() => _empLoading = false);
    }
  }

  Future<int?> _loadLatestVersionForType(String docType) async {
    try {
      final res = await ApiClient.instance.get<List<dynamic>>(
        '/api/docutracker/routing-configs',
        queryParameters: {'document_type': docType},
      );
      final list = res.data ?? const [];
      if (list.isEmpty) return null;
      final first = list.first;
      if (first is Map && first['version'] is num)
        return (first['version'] as num).toInt();
      if (first is Map && first['version'] != null)
        return int.tryParse(first['version'].toString());
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _ensureDepartmentNames() async {
    if (_departmentNameById.isNotEmpty) return;
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
      if (mounted) setState(() => _departmentNameById..addAll(map));
    } catch (_) {}
  }

  Future<void> _load() async {
    final dt = _documentType;
    if (dt == null || dt.trim().isEmpty) {
      setState(() {
        _loading = false;
        _steps.clear();
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _ensureDepartmentNames();
      final latest = await _loadLatestVersionForType(dt);
      final v = _workflowVersion ?? latest;
      if (v == null) {
        setState(() {
          _workflowVersion = null;
          _steps.clear();
          _loading = false;
          _error = 'No workflow version found for this document type.';
        });
        return;
      }
      _workflowVersion = v;

      final rows = await _repo.getWorkflowSteps(
        documentType: dt,
        workflowVersion: v,
      );
      final steps = <_DocStep>[];
      for (final r in rows) {
        final assigneesRaw = r['assignees'];
        final assignees = <_Assignee>[];
        if (assigneesRaw is List) {
          for (final a in assigneesRaw) {
            final m = a is Map ? Map<String, dynamic>.from(a) : null;
            if (m == null) continue;
            final uid = m['user_id']?.toString() ?? '';
            if (uid.isEmpty) continue;
            final name = m['full_name']?.toString() ?? uid;
            final deptName = m['department_name']?.toString();
            final isPrimary = m['is_primary'] == true;
            final backupRank = m['backup_rank'] is num
                ? (m['backup_rank'] as num).toInt()
                : int.tryParse('${m['backup_rank']}');
            final isEnabled = m['is_enabled'] != false;
            final acts = <String>{};
            final aa = m['allowed_actions'];
            if (aa is List) {
              for (final x in aa) {
                final s = x?.toString().trim();
                if (s != null && s.isNotEmpty) acts.add(s);
              }
            }
            assignees.add(
              _Assignee(
                userId: uid,
                fullName: name,
                departmentName: deptName,
                isPrimary: isPrimary,
                backupRank: isPrimary ? null : backupRank,
                isEnabled: isEnabled,
                allowedActions: acts,
              ),
            );
          }
        }
        steps.add(
          _DocStep(
            stepId: r['step_id']?.toString() ?? '',
            documentType: r['document_type']?.toString() ?? dt,
            workflowVersion: (r['workflow_version'] as num?)?.toInt() ?? v,
            stepOrder: (r['step_order'] as num?)?.toInt() ?? 0,
            departmentId: r['department_id']?.toString(),
            label: r['label']?.toString(),
            enabled: r['enabled'] != false,
            assignees: assignees,
          ),
        );
      }
      steps.sort((a, b) => a.stepOrder.compareTo(b.stepOrder));
      if (!mounted) return;
      setState(() {
        _steps
          ..clear()
          ..addAll(steps.where((s) => s.stepId.isNotEmpty));
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _editAssignees(_DocStep step) async {
    final draft = step.assignees.map((a) => a).toList();

    void normalizePrimaryAndRanks(List<_Assignee> list) {
      // Ensure at most one primary, and ranks are 1..N for backups in display order.
      final primaries = list.where((a) => a.isPrimary).toList();
      if (primaries.length > 1) {
        final keep = primaries.first.userId;
        for (var i = 0; i < list.length; i++) {
          if (list[i].userId != keep && list[i].isPrimary) {
            list[i] = list[i].copyWith(isPrimary: false, backupRank: 1);
          }
        }
      }
      final backups = list.where((a) => !a.isPrimary).toList();
      for (var i = 0; i < backups.length; i++) {
        final b = backups[i];
        final idx = list.indexWhere((x) => x.userId == b.userId);
        if (idx >= 0) list[idx] = b.copyWith(backupRank: i + 1);
      }
    }

    normalizePrimaryAndRanks(draft);

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final canSave = draft.isNotEmpty && draft.any((a) => a.isPrimary);
            final youMustHavePrimary =
                draft.isNotEmpty && !draft.any((a) => a.isPrimary);
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: SizedBox(
                height: MediaQuery.of(ctx).size.height * 0.92,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Step ${step.stepOrder}: ${step.displayLabel}',
                              style: TextStyle(
                                color: AppTheme.textPrimary,
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.of(ctx).pop(false),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                    ),
                    if (step.departmentId != null &&
                        step.departmentId!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          'Department-scoped step: only users in this department should be assigned.',
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () async {
                                    _empSearchController.text = '';
                                    await _fetchEmployees(
                                      departmentId: step.departmentId,
                                    );
                                    final picked = await showDialog<_EmpRow>(
                                      context: ctx,
                                      builder: (dctx) {
                                        return AlertDialog(
                                          title: const Text('Add employee'),
                                          content: SizedBox(
                                            width: 520,
                                            height: 420,
                                            child: Column(
                                              children: [
                                                TextField(
                                                  controller:
                                                      _empSearchController,
                                                  decoration:
                                                      DocuTrackerStyles.inputDecoration(
                                                        context,
                                                        'Search name',
                                                        Icons.search_rounded,
                                                      ),
                                                ),
                                                const SizedBox(height: 10),
                                                Expanded(
                                                  child: _empLoading
                                                      ? const Center(
                                                          child:
                                                              CircularProgressIndicator(),
                                                        )
                                                      : ListView.builder(
                                                          itemCount:
                                                              _empHits.length,
                                                          itemBuilder: (_, i) {
                                                            final e =
                                                                _empHits[i];
                                                            final exists = draft
                                                                .any(
                                                                  (a) =>
                                                                      a.userId ==
                                                                      e.id,
                                                                );
                                                            return ListTile(
                                                              dense: true,
                                                              enabled: !exists,
                                                              title: Text(
                                                                e.name,
                                                                maxLines: 1,
                                                                overflow:
                                                                    TextOverflow
                                                                        .ellipsis,
                                                              ),
                                                              subtitle: Text(
                                                                e.id,
                                                                maxLines: 1,
                                                                overflow:
                                                                    TextOverflow
                                                                        .ellipsis,
                                                              ),
                                                              trailing: exists
                                                                  ? const Text(
                                                                      'Added',
                                                                    )
                                                                  : const Icon(
                                                                      Icons
                                                                          .add_rounded,
                                                                    ),
                                                              onTap: exists
                                                                  ? null
                                                                  : () =>
                                                                        Navigator.of(
                                                                          dctx,
                                                                        ).pop(
                                                                          e,
                                                                        ),
                                                            );
                                                          },
                                                        ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.of(dctx).pop(),
                                              child: const Text('Close'),
                                            ),
                                          ],
                                        );
                                      },
                                    );
                                    if (picked == null) return;
                                    setModalState(() {
                                      draft.add(
                                        _Assignee(
                                          userId: picked.id,
                                          fullName: picked.name,
                                          departmentName: null,
                                          isPrimary: draft.isEmpty,
                                          backupRank: draft.isEmpty
                                              ? null
                                              : draft.length,
                                          isEnabled: true,
                                          allowedActions: _workflowActions
                                              .toSet(),
                                        ),
                                      );
                                      normalizePrimaryAndRanks(draft);
                                    });
                                  },
                                  icon: const Icon(
                                    Icons.person_add_alt_1_rounded,
                                    size: 18,
                                  ),
                                  label: const Text('Add user'),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          if (draft.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Text(
                                'No assignees yet.',
                                style: TextStyle(color: AppTheme.textSecondary),
                              ),
                            )
                          else ...[
                            for (var i = 0; i < draft.length; i++) ...[
                              _AssigneeEditorCard(
                                assignee: draft[i],
                                onSetPrimary: () {
                                  setModalState(() {
                                    for (var j = 0; j < draft.length; j++) {
                                      draft[j] = draft[j].copyWith(
                                        isPrimary: j == i,
                                        backupRank: j == i
                                            ? null
                                            : draft[j].backupRank ?? 1,
                                      );
                                    }
                                    normalizePrimaryAndRanks(draft);
                                  });
                                },
                                onToggleEnabled: (v) {
                                  setModalState(() {
                                    draft[i] = draft[i].copyWith(isEnabled: v);
                                  });
                                },
                                onToggleAction: (action, v) {
                                  setModalState(() {
                                    final next = Set<String>.from(
                                      draft[i].allowedActions,
                                    );
                                    if (v) {
                                      next.add(action);
                                    } else {
                                      next.remove(action);
                                    }
                                    draft[i] = draft[i].copyWith(
                                      allowedActions: next,
                                    );
                                  });
                                },
                                onRemove: () {
                                  setModalState(() {
                                    draft.removeAt(i);
                                    normalizePrimaryAndRanks(draft);
                                  });
                                },
                              ),
                              const SizedBox(height: 10),
                            ],
                          ],
                          if (youMustHavePrimary)
                            Text(
                              'Pick exactly one primary user.',
                              style: TextStyle(
                                color: Colors.red.shade700,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.of(ctx).pop(false),
                              child: const Text('Cancel'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: canSave && !youMustHavePrimary
                                  ? () => Navigator.of(ctx).pop(true)
                                  : null,
                              icon: const Icon(Icons.save_rounded, size: 18),
                              label: const Text('Save assignees'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (saved != true) return;

    final payload = <Map<String, dynamic>>[];
    for (final a in draft) {
      payload.add({
        'user_id': a.userId,
        'is_primary': a.isPrimary,
        'backup_rank': a.isPrimary ? null : (a.backupRank ?? 1),
        'is_enabled': a.isEnabled,
        'allowed_actions': a.allowedActions.toList()..sort(),
      });
    }

    setState(() => _loading = true);
    final saveResult = await _repo.updateWorkflowStepAssignees(
      stepId: step.stepId,
      assignees: payload,
    );
    await _load();
    if (!mounted) return;
    final msg = saveResult is DocuTrackerSuccess<bool>
        ? 'Saved step assignees.'
        : saveResult is DocuTrackerFailure<bool>
        ? saveResult.message
        : 'Failed to save step assignees.';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final typeOptions = [
      for (final c in DocumentRoutingConfig.defaults) c.documentType.value,
    ].toSet().toList()..sort();

    return Scaffold(
      body: DocuTrackerResponsiveBody(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DocuTrackerModuleHeader(
              title: 'Workflow step assignees',
              subtitle:
                  'Set primary/backup reviewers and allowed workflow actions per step.',
              trailing: OutlinedButton.icon(
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Refresh'),
              ),
            ),
            const SizedBox(height: 12),
            Material(
              color: AppTheme.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: Colors.black.withValues(alpha: 0.08)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Scope',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: _documentType,
                            decoration: DocuTrackerStyles.dropdownDecoration(
                              context,
                              'Document type',
                            ),
                            items: [
                              for (final t in typeOptions)
                                DropdownMenuItem(value: t, child: Text(t)),
                            ],
                            onChanged: (v) async {
                              if (v == null) return;
                              setState(() {
                                _documentType = v;
                                _workflowVersion = null;
                              });
                              await _load();
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 140,
                          child: TextFormField(
                            initialValue: _workflowVersion?.toString() ?? '',
                            decoration: DocuTrackerStyles.inputDecoration(
                              context,
                              'Version',
                              Icons.tag_rounded,
                            ),
                            keyboardType: TextInputType.number,
                            onFieldSubmitted: (v) async {
                              final n = int.tryParse(v.trim());
                              setState(() => _workflowVersion = n);
                              await _load();
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Approve/Forward/Reject/Return are enforced by these assignees (server-side).',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (_error != null) ...[
              DocuTrackerErrorBanner(
                message: _error!,
                onDismiss: () => setState(() => _error = null),
              ),
              const SizedBox(height: 8),
            ],
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      itemCount: _steps.where((s) => s.enabled).length,
                      itemBuilder: (ctx, i) {
                        final s = _steps.where((s) => s.enabled).elementAt(i);
                        final primary = s.assignees
                            .where((a) => a.isPrimary)
                            .toList();
                        final p = primary.isEmpty ? null : primary.first;
                        final primaryLine = p == null
                            ? '—'
                            : (p.departmentName != null &&
                                  p.departmentName!.trim().isNotEmpty)
                            ? '${p.fullName} · ${p.departmentName}'
                            : p.fullName;
                        final did = s.departmentId?.trim();
                        final stepDeptLabel = (did != null && did.isNotEmpty)
                            ? 'Step scope: ${_departmentNameById[did] ?? did}'
                            : null;
                        final stepColor = _stepColor(s.stepOrder);
                        final initials = p == null
                            ? '?'
                            : p.fullName
                                  .trim()
                                  .split(' ')
                                  .take(2)
                                  .map(
                                    (w) =>
                                        w.isNotEmpty ? w[0].toUpperCase() : '',
                                  )
                                  .join();
                        return Card(
                          elevation: 0,
                          margin: const EdgeInsets.only(bottom: 2),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: BorderSide(
                              color: Colors.black.withValues(alpha: 0.07),
                            ),
                          ),
                          child: InkWell(
                            onTap: () => _editAssignees(s),
                            borderRadius: BorderRadius.circular(14),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                              child: Row(
                                children: [
                                  // Colored step number badge
                                  Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: stepColor,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Center(
                                      child: Text(
                                        '${s.stepOrder}',
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w800,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          s.displayLabel,
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 14,
                                            color: AppTheme.textPrimary,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Row(
                                          children: [
                                            // Primary avatar
                                            CircleAvatar(
                                              radius: 12,
                                              backgroundColor: stepColor
                                                  .withValues(alpha: 0.15),
                                              child: Text(
                                                initials,
                                                style: TextStyle(
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.w700,
                                                  color: stepColor,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Expanded(
                                              child: Text(
                                                p == null
                                                    ? 'No primary assignee'
                                                    : primaryLine,
                                                style: TextStyle(
                                                  color: AppTheme.textSecondary,
                                                  fontSize: 12,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 2,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: stepColor.withValues(
                                                  alpha: 0.1,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(20),
                                                border: Border.all(
                                                  color: stepColor.withValues(
                                                    alpha: 0.3,
                                                  ),
                                                ),
                                              ),
                                              child: Text(
                                                '${s.assignees.length} ${s.assignees.length == 1 ? 'user' : 'users'}',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w600,
                                                  color: stepColor,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        if (stepDeptLabel != null) ...[
                                          const SizedBox(height: 4),
                                          Row(
                                            children: [
                                              Icon(
                                                Icons.business_rounded,
                                                size: 11,
                                                color: AppTheme.textSecondary
                                                    .withValues(alpha: 0.6),
                                              ),
                                              const SizedBox(width: 3),
                                              Text(
                                                stepDeptLabel,
                                                style: TextStyle(
                                                  color: AppTheme.textSecondary
                                                      .withValues(alpha: 0.7),
                                                  fontSize: 11,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  Icon(
                                    Icons.chevron_right_rounded,
                                    color: AppTheme.textSecondary.withValues(
                                      alpha: 0.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AssigneeEditorCard extends StatelessWidget {
  const _AssigneeEditorCard({
    required this.assignee,
    required this.onSetPrimary,
    required this.onToggleEnabled,
    required this.onToggleAction,
    required this.onRemove,
  });

  final _Assignee assignee;
  final VoidCallback onSetPrimary;
  final ValueChanged<bool> onToggleEnabled;
  final void Function(String action, bool value) onToggleAction;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final actions = <String>['approve', 'forward', 'reject', 'return'];
    return Material(
      color: AppTheme.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.black.withValues(alpha: 0.08)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    assignee.fullName,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Remove',
                  onPressed: onRemove,
                  icon: Icon(
                    Icons.delete_outline_rounded,
                    color: Colors.red.shade700,
                  ),
                ),
              ],
            ),
            if (assignee.departmentName != null &&
                assignee.departmentName!.trim().isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                assignee.departmentName!,
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 4),
            Text(
              assignee.userId,
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 11),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onSetPrimary,
                    icon: Icon(
                      assignee.isPrimary
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_off_rounded,
                      size: 18,
                      color: DocuTrackerTokens.brand,
                    ),
                    label: Text(
                      assignee.isPrimary ? 'Primary' : 'Make primary',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SwitchListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: assignee.isEnabled,
                    onChanged: onToggleEnabled,
                    title: const Text(
                      'Enabled',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Allowed actions',
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final a in actions)
                  FilterChip(
                    label: Text(a),
                    selected: assignee.allowedActions.contains(a),
                    onSelected: (v) => onToggleAction(a, v),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
