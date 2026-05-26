import 'package:flutter/material.dart';
import '../../api/client.dart';
import '../../landingpage/constants/app_theme.dart';
import '../docutracker_repository.dart';
import '../docutracker_styles.dart';
import '../theme/docutracker_tokens.dart';
import '../models/document_action.dart';
import '../models/document_permission.dart';
import '../models/document_type.dart';
import '../security/docutracker_roles.dart';
import '../services/docutracker_permission_service.dart';
import '../services/employee_directory_lookup.dart';
import '../widgets/docutracker_error_banner.dart';
import '../widgets/docutracker_module_header.dart';
import '../widgets/docutracker_responsive_body.dart';

String _permissionExplanationChipTooltip(DocuTrackerPermissionExplanation e) {
  final granted = e.granted ? 'Allowed' : 'Denied';
  final source = switch (e.source) {
    DocuTrackerPermissionSource.admin => 'System admin bypass (always on).',
    DocuTrackerPermissionSource.currentHolder =>
      'Workflow action allowed: you are the current holder.',
    DocuTrackerPermissionSource.stepAssignee =>
      'Workflow action allowed: you are assigned to the current step.',
    DocuTrackerPermissionSource.userSpecific =>
      'User-specific row for this document type.',
    DocuTrackerPermissionSource.userWildcard =>
      'User-specific wildcard (*) row.',
    DocuTrackerPermissionSource.roleSpecific =>
      'Role baseline for this document type.',
    DocuTrackerPermissionSource.roleWildcard =>
      'Role baseline wildcard (*) row.',
    DocuTrackerPermissionSource.defaultDeny =>
      'No matching permission row (default deny).',
  };
  final type = e.matchedDocumentType;
  final role = e.matchedRoleId;
  final buf = StringBuffer('$granted — $source');
  final reason = (e.reason ?? '').trim();
  if (reason.isNotEmpty) {
    buf.write('\nReason: $reason');
  }
  if (type != null) {
    buf.write('\nMatched document type key: $type');
  }
  if (role != null) {
    buf.write('\nMatched role id: $role');
  }
  return buf.toString();
}

/// Admin permission editor for DocuTracker.
///
/// - **Role baseline** tab: matrix **rows = roles**, **columns = actions** (checkboxes).
/// - **User override** tab: same action columns; **row 1** = read-only role baseline for the
///   selected employee’s role, **row 2** = editable user overrides.
class DocuTrackerPermissionEditorScreen extends StatefulWidget {
  const DocuTrackerPermissionEditorScreen({
    super.key,
    this.initialUserId,
    this.initialDocumentType,
    this.initialTabIsUserOverride = false,
  });

  /// When opening from an admin list row, pre-select this employee.
  final String? initialUserId;

  /// Pre-select document type filter (e.g. `*` or a [DocumentType] value string).
  final String? initialDocumentType;

  /// Open on the **User override** tab (tab index 1).
  final bool initialTabIsUserOverride;

  @override
  State<DocuTrackerPermissionEditorScreen> createState() =>
      _DocuTrackerPermissionEditorScreenState();
}

class _DocuTrackerPermissionEditorScreenState
    extends State<DocuTrackerPermissionEditorScreen>
    with SingleTickerProviderStateMixin {
  final _repo = DocuTrackerRepository.instance;
  late final TabController _tabs;

  late String _documentType;
  bool _editWildcardToo = false;

  /// Canonical role keys (matrix row order).
  static const _baselineRoleIds = <String>[
    DocuTrackerRoles.admin,
    DocuTrackerRoles.hr,
    DocuTrackerRoles.supervisor,
    DocuTrackerRoles.employee,
  ];

  /// Role → action → granted (draft for current document type).
  Map<String, Map<String, bool>> _baselineSpecificMatrixDraft = {};
  Map<String, Map<String, DocumentPermission>> _baselineSpecificMatrixExisting =
      {};
  Map<String, Map<String, bool>> _baselineWildcardMatrixDraft = {};
  Map<String, Map<String, DocumentPermission>> _baselineWildcardMatrixExisting =
      {};

  final List<_EmployeeOption> _employees = [];
  final EmployeeDirectoryLookup _employeeDirectory = EmployeeDirectoryLookup();
  bool _employeesLoading = true;
  String? _userId;
  String? _userRoleId;
  Map<String, bool> _userRoleBaselineGranted = {};
  Map<String, DocumentPermission> _overrideSpecificByAction = const {};
  Map<String, bool> _overrideSpecificDraft = const {};
  Map<String, DocumentPermission> _overrideWildcardByAction = const {};
  Map<String, bool> _overrideWildcardDraft = const {};

  bool _loading = true;
  String? _error;
  String _userSearchQuery = '';
  List<_EffectiveRow> _effectiveRows = const [];
  bool _effectiveLoading = false;

  static const _editableActions = <DocumentAction>[
    DocumentAction.view,
    DocumentAction.createDraft,
    DocumentAction.download,
    DocumentAction.submit,
  ];

  static const _draftOwnerActions = <DocumentAction>[
    DocumentAction.edit,
    DocumentAction.delete,
  ];

  static const _workflowActions = <DocumentAction>[
    DocumentAction.forward,
    DocumentAction.approve,
    DocumentAction.reject,
    DocumentAction.returnDoc,
  ];

  @override
  void initState() {
    super.initState();
    _documentType = widget.initialDocumentType ?? '*';
    _tabs = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTabIsUserOverride ? 1 : 0,
    );
    _init();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    await Future.wait([_loadEmployees(), _employeeDirectory.load()]);
    await _pickUserIfMissing();
    if (_userId != null) {
      await _employeeDirectory.ensureIds({_userId!});
    }
    await _loadBaselineMatrices();
    await _loadOverrides();
    await _loadEffectiveRows();
    if (!mounted) return;
    setState(() => _loading = false);
  }

  /// Human-readable line for the selected employee (name · department).
  String _userDisplayLabel() {
    final id = _userId;
    if (id == null || id.isEmpty) return '—';
    return _employeeDirectory.formatUserLine(id);
  }

  Future<void> _loadEmployees() async {
    setState(() => _employeesLoading = true);
    try {
      final res = await ApiClient.instance.get<List<dynamic>>(
        '/api/employees',
        queryParameters: {'status': 'Active', 'role': 'All'},
      );
      final data = res.data ?? [];
      _employees
        ..clear()
        ..addAll(
          data
              .map((e) {
                final m = e as Map;
                final id = m['id']?.toString() ?? '';
                final fullName = (m['full_name']?.toString() ?? '').isEmpty
                    ? 'Unknown'
                    : m['full_name'].toString();
                final roleId =
                    m['role']?.toString() ?? DocuTrackerRoles.employee;
                return _EmployeeOption(
                  id: id,
                  fullName: fullName,
                  roleId: roleId,
                );
              })
              .where((e) => e.id.isNotEmpty),
        );
    } catch (_) {
      _employees.clear();
    }
    if (!mounted) return;
    setState(() => _employeesLoading = false);
  }

  Future<void> _pickUserIfMissing() async {
    final want = widget.initialUserId?.trim();
    if (want != null && want.isNotEmpty) {
      _userId = want;
      _EmployeeOption? match;
      for (final e in _employees) {
        if (e.id == want) {
          match = e;
          break;
        }
      }
      _userRoleId = match?.roleId ?? DocuTrackerRoles.employee;
      return;
    }
    if (_userId != null) return;
    if (_employees.isEmpty) return;
    final first = _employees.first;
    _userId = first.id;
    _userRoleId = first.roleId;
  }

  List<_EmployeeOption> _filteredEmployees() {
    final q = _userSearchQuery.trim().toLowerCase();
    if (q.isEmpty) return _employees;
    return _employees.where((e) {
      final line = (_employeeDirectory[e.id]?.nameAndDepartment ?? e.fullName)
          .toLowerCase();
      return line.contains(q) || e.id.toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _loadBaselineMatrices() async {
    Future<
      (
        Map<String, Map<String, DocumentPermission>>,
        Map<String, Map<String, bool>>,
      )
    >
    loadFor(String docType) async {
      final existing = <String, Map<String, DocumentPermission>>{};
      final draft = <String, Map<String, bool>>{};
      for (final role in _baselineRoleIds) {
        final label = DocuTrackerRoles.normalize(role);
        final perms = <DocumentPermission>[];
        for (final r in DocuTrackerRoles.equivalentsForRead(role)) {
          perms.addAll(
            await _repo.listPermissions(roleId: r, documentType: docType),
          );
        }
        final byAction = <String, DocumentPermission>{};
        for (final p in perms) {
          byAction[p.action.name] = p;
        }
        existing[label] = byAction;
        draft[label] = {
          for (final a in _editableActions)
            a.name: (byAction[a.name]?.granted ?? false),
        };
      }
      return (existing, draft);
    }

    final spec = await loadFor(_documentType);
    _baselineSpecificMatrixExisting = spec.$1;
    _baselineSpecificMatrixDraft = spec.$2;

    final wild = await loadFor('*');
    _baselineWildcardMatrixExisting = wild.$1;
    _baselineWildcardMatrixDraft = wild.$2;
  }

  Future<void> _loadUserRoleBaseline() async {
    if (_userId == null || _userRoleId == null) {
      _userRoleBaselineGranted = {
        for (final a in _editableActions) a.name: false,
      };
      return;
    }
    final label = DocuTrackerRoles.normalize(_userRoleId);
    final perms = <DocumentPermission>[];
    for (final r in DocuTrackerRoles.equivalentsForRead(label)) {
      perms.addAll(
        await _repo.listPermissions(roleId: r, documentType: _documentType),
      );
    }
    final byAction = <String, DocumentPermission>{};
    for (final p in perms) {
      byAction[p.action.name] = p;
    }
    _userRoleBaselineGranted = {
      for (final a in _editableActions)
        a.name: (byAction[a.name]?.granted ?? false),
    };
  }

  Future<void> _loadOverrides() async {
    if (_userId == null) {
      _overrideSpecificByAction = const {};
      _overrideSpecificDraft = {
        for (final a in _editableActions) a.name: false,
      };
      _overrideWildcardByAction = const {};
      _overrideWildcardDraft = {
        for (final a in _editableActions) a.name: false,
      };
      _userRoleBaselineGranted = {
        for (final a in _editableActions) a.name: false,
      };
      return;
    }

    await _loadUserRoleBaseline(); // Load baseline first so we can use it for defaults

    Future<(Map<String, DocumentPermission>, Map<String, bool>)> loadForDocType(
      String docType,
      bool isWildcard,
    ) async {
      final perms = await _repo.listPermissions(
        userId: _userId,
        documentType: docType,
      );
      final byAction = <String, DocumentPermission>{};
      for (final p in perms) {
        byAction[p.action.name] = p;
      }
      final draft = <String, bool>{};
      for (final a in _editableActions) {
        if (byAction.containsKey(a.name)) {
          draft[a.name] = byAction[a.name]!.granted;
        } else {
          // Default to baseline if no explicit override exists
          draft[a.name] = isWildcard
              ? false
              : (_userRoleBaselineGranted[a.name] ?? false);
        }
      }
      return (byAction, draft);
    }

    final specific = await loadForDocType(_documentType, false);
    _overrideSpecificByAction = specific.$1;
    _overrideSpecificDraft = specific.$2;

    final wild = await loadForDocType('*', true);
    _overrideWildcardByAction = wild.$1;
    _overrideWildcardDraft = wild.$2;
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _loadBaselineMatrices();
      await _loadOverrides();
      await _loadEffectiveRows();
    } catch (e) {
      _error = e.toString();
    }
    if (!mounted) return;
    setState(() => _loading = false);
  }

  Future<void> _loadEffectiveRows() async {
    if (_userId == null || _userRoleId == null) {
      if (!mounted) return;
      setState(() {
        _effectiveRows = const [];
        _effectiveLoading = false;
      });
      return;
    }
    if (mounted) {
      setState(() => _effectiveLoading = true);
    }
    try {
      final rows = <_EffectiveRow>[];
      for (final action in [
        ..._editableActions,
        ..._draftOwnerActions,
        ..._workflowActions,
      ]) {
        final exp = await _repo.explainPermission(
          userId: _userId!,
          roleId: _userRoleId,
          documentType: _documentType,
          action: action.value,
        );
        rows.add(_EffectiveRow(action: action, explanation: exp));
      }
      if (!mounted) return;
      setState(() {
        _effectiveRows = rows;
        _effectiveLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _effectiveRows = const [];
        _effectiveLoading = false;
      });
    }
  }

  List<_PermissionChange> _diffChanges({
    required String scopeLabel,
    required String documentType,
    required Map<String, bool> desiredByAction,
    required Map<String, DocumentPermission> existingByAction,
  }) {
    final changes = <_PermissionChange>[];
    for (final a in _editableActions) {
      final desired = desiredByAction[a.name] ?? false;
      final existing = existingByAction[a.name]?.granted;
      final before = existing ?? false;
      if (before == desired) continue;
      changes.add(
        _PermissionChange(
          scopeLabel: scopeLabel,
          documentType: documentType,
          action: a,
          before: before,
          after: desired,
        ),
      );
    }
    return changes;
  }

  Future<bool> _confirmBulkSave(List<_PermissionChange> changes) async {
    if (changes.isEmpty) {
      if (!mounted) return false;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No changes to save.')));
      return false;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final shown = changes.take(12).toList();
        final remaining = changes.length - shown.length;
        final submitRemovals = changes.where(
          (c) => c.action == DocumentAction.submit && c.before && !c.after,
        );
        return AlertDialog(
          title: const Text('Confirm bulk update'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'You are about to change ${changes.length} permission(s).',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 12),
                for (final c in shown)
                  Text(
                    '• ${c.scopeLabel} • ${c.documentType} • ${c.action.displayName}: '
                    '${c.before ? "Allow" : "Deny"} → ${c.after ? "Allow" : "Deny"}',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                if (remaining > 0) ...[
                  const SizedBox(height: 8),
                  Text(
                    '…and $remaining more',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
                if (submitRemovals.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Warning: this removes submit access from ${submitRemovals.length} rule(s).',
                    style: TextStyle(
                      color: Colors.red.shade800,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Confirm'),
            ),
          ],
        );
      },
    );

    return confirmed == true;
  }

  Future<void> _saveBaseline() async {
    final changes = <_PermissionChange>[];
    for (final role in _baselineRoleIds) {
      final label = DocuTrackerRoles.normalize(role);
      final specDraft = _baselineSpecificMatrixDraft[label] ?? {};
      final specExist = _baselineSpecificMatrixExisting[label] ?? {};
      changes.addAll(
        _diffChanges(
          scopeLabel: 'Role baseline ($label)',
          documentType: _documentType,
          desiredByAction: specDraft,
          existingByAction: specExist,
        ),
      );
      if (_editWildcardToo && _documentType != '*') {
        final wDraft = _baselineWildcardMatrixDraft[label] ?? {};
        final wExist = _baselineWildcardMatrixExisting[label] ?? {};
        changes.addAll(
          _diffChanges(
            scopeLabel: 'Role baseline ($label)',
            documentType: '*',
            desiredByAction: wDraft,
            existingByAction: wExist,
          ),
        );
      }
    }

    final ok = await _confirmBulkSave(changes);
    if (!ok) return;

    setState(() => _loading = true);
    try {
      for (final change in changes) {
        final roleLabel = change.scopeLabel
            .replaceFirst('Role baseline (', '')
            .replaceFirst(')', '');
        final wildcardRow = _baselineWildcardMatrixExisting[roleLabel];
        final specificRow = _baselineSpecificMatrixExisting[roleLabel];
        final existing = change.documentType == '*'
            ? (wildcardRow == null ? null : wildcardRow[change.action.name])
            : (specificRow == null ? null : specificRow[change.action.name]);
        await _repo.savePermission(
          DocumentPermission(
            id: existing?.id,
            roleId: roleLabel,
            userId: null,
            documentType: change.documentType,
            action: change.action,
            granted: change.after,
          ),
        );
      }

      await _refresh();
    } catch (e) {
      setState(() => _error = e.toString());
    }
    if (!mounted) return;
    setState(() => _loading = false);
  }

  Future<void> _saveOverrides() async {
    if (_userId == null) return;
    final changes = <_PermissionChange>[
      ..._diffChanges(
        scopeLabel: 'User override (${_userDisplayLabel()})',
        documentType: _documentType,
        desiredByAction: _overrideSpecificDraft,
        existingByAction: _overrideSpecificByAction,
      ),
      if (_editWildcardToo && _documentType != '*')
        ..._diffChanges(
          scopeLabel: 'User override (${_userDisplayLabel()})',
          documentType: '*',
          desiredByAction: _overrideWildcardDraft,
          existingByAction: _overrideWildcardByAction,
        ),
    ];

    final ok = await _confirmBulkSave(changes);
    if (!ok) return;

    setState(() => _loading = true);
    try {
      for (final change in changes) {
        final existing = change.documentType == '*'
            ? _overrideWildcardByAction[change.action.name]
            : _overrideSpecificByAction[change.action.name];
        await _repo.savePermission(
          DocumentPermission(
            id: existing?.id,
            roleId: null,
            userId: _userId,
            documentType: change.documentType,
            action: change.action,
            granted: change.after,
          ),
        );
      }

      await _refresh();
    } catch (e) {
      setState(() => _error = e.toString());
    }
    if (!mounted) return;
    setState(() => _loading = false);
  }

  Future<void> _resetBaseline() async {
    final targets = <String>[_documentType];
    if (_editWildcardToo && _documentType != '*') targets.add('*');

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset role baselines'),
        content: Text(
          'This will DELETE all baseline permission rows for every role in the matrix '
          'and document type(s): ${targets.join(", ")}.\n\n'
          'Effective access falls back to other rules (often default deny).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _loading = true);
    try {
      var deleted = 0;
      for (final role in _baselineRoleIds) {
        final label = DocuTrackerRoles.normalize(role);
        for (final dt in targets) {
          deleted += await _repo.resetPermissions(
            roleId: label,
            documentType: dt,
          );
        }
      }
      await _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Reset complete. Deleted $deleted row(s).')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resetOverrides() async {
    if (_userId == null) return;
    final targets = <String>[_documentType];
    if (_editWildcardToo && _documentType != '*') targets.add('*');

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset user overrides'),
        content: Text(
          'This will DELETE all user override permission rows for:\n${_userDisplayLabel()}\n\n'
          'Document type(s): ${targets.join(", ")}.\n\n'
          'They will follow the role baseline again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _loading = true);
    try {
      var deleted = 0;
      for (final dt in targets) {
        deleted += await _repo.resetPermissions(
          userId: _userId,
          documentType: dt,
        );
      }
      await _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Reset complete. Deleted $deleted row(s).')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _setBaselineCell(
    String roleLabel,
    DocumentAction action,
    bool value, {
    required bool wildcard,
  }) {
    setState(() {
      final map = wildcard
          ? _baselineWildcardMatrixDraft
          : _baselineSpecificMatrixDraft;
      final row = Map<String, bool>.from(
        map[roleLabel] ?? {for (final a in _editableActions) a.name: false},
      );
      row[action.name] = value;
      map[roleLabel] = row;
    });
  }

  String _docTypeLabel(String v) {
    if (v == '*') return 'All types';
    return documentTypeFromString(v).displayName;
  }

  String _roleRowTitle(String canonicalRole) {
    return switch (canonicalRole) {
      DocuTrackerRoles.admin => 'Admin',
      DocuTrackerRoles.hr => 'HR',
      DocuTrackerRoles.supervisor => 'Supervisor',
      DocuTrackerRoles.employee => 'Employee',
      _ => canonicalRole,
    };
  }

  Widget _buildFilterCard() {
    return Material(
      elevation: 0,
      color: AppTheme.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.black.withValues(alpha: 0.08)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Document type',
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('All types (*)'),
                  selected: _documentType == '*',
                  onSelected: _loading
                      ? null
                      : (sel) async {
                          if (!sel) return;
                          setState(() => _documentType = '*');
                          await _refresh();
                        },
                ),
                for (final t in DocumentType.values)
                  ChoiceChip(
                    label: Text(t.displayName),
                    selected: _documentType == t.value,
                    onSelected: _loading
                        ? null
                        : (sel) async {
                            if (!sel) return;
                            setState(() => _documentType = t.value);
                            await _refresh();
                          },
                  ),
              ],
            ),
            if (_documentType != '*') ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Text(
                      'Also edit wildcard (*) rows in this tab when saving',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Switch(
                    value: _editWildcardToo,
                    onChanged: _loading
                        ? null
                        : (v) => setState(() => _editWildcardToo = v),
                    activeTrackColor: DocuTrackerTokens.brand.withValues(
                      alpha: 0.55,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: _loading ? null : _refresh,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Reload'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoleMatrixSection({
    required String title,
    required String subtitle,
    required bool wildcard,
  }) {
    final draft = wildcard
        ? _baselineWildcardMatrixDraft
        : _baselineSpecificMatrixDraft;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 12,
            height: 1.25,
          ),
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: _PermissionRoleMatrix(
            roleIds: _baselineRoleIds.map(DocuTrackerRoles.normalize).toList(),
            roleTitle: _roleRowTitle,
            actions: _editableActions,
            draftByRole: draft,
            enabled: !_loading,
            onToggle: (roleLabel, action, v) =>
                _setBaselineCell(roleLabel, action, v, wildcard: wildcard),
          ),
        ),
      ],
    );
  }

  Widget _buildUserCompareMatrix() {
    final roleLabel = DocuTrackerRoles.normalize(
      _userRoleId ?? DocuTrackerRoles.employee,
    );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: _UserBaselineOverrideMatrix(
        actions: _editableActions,
        roleTitle: _roleRowTitle(roleLabel),
        userOverrideSubtitle: _userDisplayLabel(),
        baselineGranted: _userRoleBaselineGranted,
        overrideDraft: _overrideSpecificDraft,
        enabled: !_loading && _userId != null,
        onOverrideToggle: (action, v) {
          setState(() => _overrideSpecificDraft[action.name] = v);
        },
      ),
    );
  }

  Widget _buildUserWildcardRow() {
    if (!_editWildcardToo || _documentType == '*') {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Text(
          'Wildcard (*) overrides',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowHeight: 40,
            dataRowMinHeight: 44,
            dataRowMaxHeight: 48,
            columns: [
              const DataColumn(label: Text('Scope')),
              ..._editableActions.map(
                (a) => DataColumn(
                  label: Text(
                    a.displayName,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ],
            rows: [
              DataRow(
                cells: [
                  const DataCell(
                    Text(
                      'User override\n(all types)',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                  ..._editableActions.map(
                    (a) => DataCell(
                      Center(
                        child: Checkbox(
                          value: _overrideWildcardDraft[a.name] ?? false,
                          onChanged: (_loading || _userId == null)
                              ? null
                              : (v) => setState(
                                  () => _overrideWildcardDraft[a.name] =
                                      v ?? false,
                                ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEffectivePreview() {
    if (_userId == null || _userRoleId == null) {
      return const SizedBox.shrink();
    }
    if (_effectiveLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_effectiveRows.isEmpty) {
      return const SizedBox.shrink();
    }
    Widget chipsFor(String title, List<DocumentAction> actions) {
      final rows = _effectiveRows
          .where((row) => actions.any((a) => a == row.action))
          .toList();
      if (rows.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final r in rows)
                  Tooltip(
                    message: _permissionExplanationChipTooltip(r.explanation),
                    waitDuration: const Duration(milliseconds: 400),
                    child: Chip(
                      avatar: Icon(
                        r.explanation.granted
                            ? Icons.check_circle
                            : Icons.cancel,
                        size: 16,
                        color: r.explanation.granted
                            ? Colors.green.shade800
                            : Colors.red.shade800,
                      ),
                      label: Text(
                        r.action == DocumentAction.edit
                            ? 'Edit Own Draft'
                            : r.action == DocumentAction.delete
                            ? 'Delete Own Draft'
                            : r.action.displayName,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
              ],
            ),
          ],
        ),
      );
    }

    return Material(
      color: const Color(0xFFE8EAF6),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.visibility_rounded,
                  size: 18,
                  color: DocuTrackerTokens.brand,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Effective result (${_userDisplayLabel()} • ${_docTypeLabel(_documentType)})',
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            chipsFor('General access + Draft submit', _editableActions),
            chipsFor('Draft / WIP owner rules', _draftOwnerActions),
            chipsFor('Workflow-step actions', _workflowActions),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('DocuTracker permissions'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Role baseline'),
            Tab(text: 'User override'),
            Tab(text: 'Effective preview'),
          ],
        ),
      ),
      body: DocuTrackerResponsiveBody(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const DocuTrackerModuleHeader(
              title: 'DocuTracker permissions',
              subtitle:
                  'Role baseline applies to everyone in that role. User overrides win for that person only.',
            ),
            const SizedBox(height: 10),
            Text(
              'Use one source of truth per action to avoid conflicting grants/denies.',
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 12),
            _buildFilterCard(),
            const SizedBox(height: 12),
            if (_error != null) ...[
              DocuTrackerErrorBanner(
                message: _error!,
                onDismiss: () => setState(() => _error = null),
              ),
              const SizedBox(height: 8),
            ],
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  // Role baseline matrix
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.only(bottom: 12),
                          children: [
                            const _PermissionInfoCard(
                              title: 'Permission groups in this editor',
                              body:
                                  'General Access: View, Create Draft, Download.\n'
                                  'Draft / WIP: Submit.\n'
                                  'Workflow actions (Forward/Approve/Reject/Return) are runtime rules based on step assignment and allowed_actions.',
                            ),
                            const SizedBox(height: 12),
                            if (_editWildcardToo && _documentType != '*')
                              _buildRoleMatrixSection(
                                title: 'Wildcard (*) — all document types',
                                subtitle:
                                    'Same roles as below; these rows apply when no more specific type rule exists.',
                                wildcard: true,
                              ),
                            if (_editWildcardToo && _documentType != '*')
                              const SizedBox(height: 20),
                            _buildRoleMatrixSection(
                              title:
                                  'Type-specific: ${_docTypeLabel(_documentType)}',
                              subtitle:
                                  'Check = allow for every user in that role for this document type (or all types when filter is *).',
                              wildcard: false,
                            ),
                          ],
                        ),
                      ),
                      Wrap(
                        spacing: 10,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _loading ? null : _resetBaseline,
                            icon: const Icon(Icons.restart_alt_rounded),
                            label: const Text('Reset'),
                          ),
                          FilledButton.icon(
                            onPressed: _loading ? null : _saveBaseline,
                            icon: const Icon(Icons.save_rounded),
                            label: const Text('Save changes'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _loading
                                ? null
                                : () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.close_rounded),
                            label: const Text('Cancel'),
                          ),
                        ],
                      ),
                    ],
                  ),
                  // User override
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _PermissionInfoCard(
                        title: 'Override behavior',
                        body:
                            'This panel edits user-specific overrides. Any explicit user override beats role baseline. '
                            'If no override exists, effective permission inherits from role baseline; otherwise it defaults to deny.',
                      ),
                      const SizedBox(height: 8),
                      if (_employeesLoading)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else ...[
                        TextField(
                          enabled: !_loading,
                          decoration: const InputDecoration(
                            labelText: 'Search user (name, department, id)',
                            prefixIcon: Icon(Icons.search_rounded),
                          ),
                          onChanged: (value) {
                            setState(() => _userSearchQuery = value);
                          },
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String?>(
                          key: ValueKey(_userId ?? ''),
                          initialValue:
                              _userId != null &&
                                  _employees.any((e) => e.id == _userId)
                              ? _userId
                              : null,
                          decoration: DocuTrackerStyles.dropdownDecoration(
                            context,
                            'Employee',
                          ),
                          items: () {
                            final rows = _filteredEmployees();
                            final selected = _userId;
                            if (selected != null &&
                                selected.isNotEmpty &&
                                rows.every((e) => e.id != selected)) {
                              final fromAll = _employees.where(
                                (e) => e.id == selected,
                              );
                              if (fromAll.isNotEmpty) {
                                return [...fromAll, ...rows].map((e) {
                                  final line =
                                      _employeeDirectory[e.id]
                                          ?.nameAndDepartment ??
                                      e.fullName;
                                  return DropdownMenuItem<String?>(
                                    value: e.id,
                                    child: Text(
                                      line,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  );
                                }).toList();
                              }
                            }
                            return rows.map((e) {
                              final line =
                                  _employeeDirectory[e.id]?.nameAndDepartment ??
                                  e.fullName;
                              return DropdownMenuItem<String?>(
                                value: e.id,
                                child: Text(
                                  line,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              );
                            }).toList();
                          }(),
                          onChanged: _loading
                              ? null
                              : (v) async {
                                  if (v == null) return;
                                  final pick = _employees.firstWhere(
                                    (e) => e.id == v,
                                  );
                                  setState(() {
                                    _userId = pick.id;
                                    _userRoleId = pick.roleId;
                                  });
                                  await _employeeDirectory.ensureIds({pick.id});
                                  await _loadOverrides();
                                  await _loadEffectiveRows();
                                },
                        ),
                      ],
                      const SizedBox(height: 8),
                      Text(
                        'Top row = inherited role baseline (read-only). Bottom row = this user’s overrides (editable).',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: ListView(
                          children: [
                            _buildUserCompareMatrix(),
                            _buildUserWildcardRow(),
                          ],
                        ),
                      ),
                      Wrap(
                        spacing: 10,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: (_loading || _userId == null)
                                ? null
                                : _resetOverrides,
                            icon: const Icon(Icons.restart_alt_rounded),
                            label: const Text('Reset'),
                          ),
                          FilledButton.icon(
                            onPressed: (_loading || _userId == null)
                                ? null
                                : _saveOverrides,
                            icon: const Icon(Icons.save_rounded),
                            label: const Text('Save changes'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _loading
                                ? null
                                : () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.close_rounded),
                            label: const Text('Cancel'),
                          ),
                        ],
                      ),
                    ],
                  ),
                  // Effective preview
                  ListView(
                    children: [
                      _buildEffectivePreview(),
                      const SizedBox(height: 12),
                      _PermissionInfoCard(
                        title: 'Rules reference',
                        body:
                            'User-specific override wins over role baseline. '
                            'Role baseline wins over default deny. '
                            'Workflow actions (approve/forward/reject/return) are enforced by current holder and assigned primary/backup assignees with allowed_actions.',
                      ),
                      const SizedBox(height: 8),
                      _PermissionInfoCard(
                        title: 'Draft behavior',
                        body:
                            'Create Draft creates WIP only. Submit starts official routing. '
                            'Edit Own Draft and Delete Own Draft apply to the document creator while still in draft/WIP.',
                      ),
                    ],
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

/// Roles × actions matrix with sticky-style first column via DataTable.
class _PermissionRoleMatrix extends StatelessWidget {
  const _PermissionRoleMatrix({
    required this.roleIds,
    required this.roleTitle,
    required this.actions,
    required this.draftByRole,
    required this.enabled,
    required this.onToggle,
  });

  final List<String> roleIds;
  final String Function(String canonicalRole) roleTitle;
  final List<DocumentAction> actions;
  final Map<String, Map<String, bool>> draftByRole;
  final bool enabled;
  final void Function(String roleLabel, DocumentAction action, bool value)
  onToggle;

  @override
  Widget build(BuildContext context) {
    return DataTable(
      headingRowHeight: 44,
      dataRowMinHeight: 64, // Increased to fit switch + label
      dataRowMaxHeight: 72,
      horizontalMargin: 12,
      columnSpacing: 8,
      columns: [
        const DataColumn(
          label: Text('Role', style: TextStyle(fontWeight: FontWeight.w800)),
        ),
        ...actions.map(
          (a) => DataColumn(
            label: Text(
              a.displayName,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ],
      rows: [
        for (final role in roleIds)
          DataRow(
            cells: [
              DataCell(
                SizedBox(
                  width: 108,
                  child: Text(
                    roleTitle(role),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
              ...actions.map((a) {
                final v = draftByRole[role]?[a.name] ?? false;
                return DataCell(
                  Center(
                    child: _LabeledSwitch(
                      value: v,
                      onChanged: enabled ? (nv) => onToggle(role, a, nv) : null,
                    ),
                  ),
                );
              }),
            ],
          ),
      ],
    );
  }
}

class _LabeledSwitch extends StatelessWidget {
  const _LabeledSwitch({required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: Colors.white,
          activeTrackColor: Colors.green.shade600,
          inactiveThumbColor: Colors.white,
          inactiveTrackColor: Colors.red.shade600,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        Text(
          value ? 'Allow' : 'Deny',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: value ? Colors.green.shade700 : Colors.red.shade700,
          ),
        ),
      ],
    );
  }
}

/// Two logical rows: baseline (icons) vs override (checkboxes).
class _UserBaselineOverrideMatrix extends StatelessWidget {
  const _UserBaselineOverrideMatrix({
    required this.actions,
    required this.roleTitle,
    required this.userOverrideSubtitle,
    required this.baselineGranted,
    required this.overrideDraft,
    required this.enabled,
    required this.onOverrideToggle,
  });

  final List<DocumentAction> actions;
  final String roleTitle;
  final String userOverrideSubtitle;
  final Map<String, bool> baselineGranted;
  final Map<String, bool> overrideDraft;
  final bool enabled;
  final void Function(DocumentAction action, bool value) onOverrideToggle;

  @override
  Widget build(BuildContext context) {
    Widget cellLabel(bool granted) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: granted
              ? Colors.green.withValues(alpha: 0.1)
              : Colors.red.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: granted
                ? Colors.green.withValues(alpha: 0.3)
                : Colors.red.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              granted ? Icons.check_circle_rounded : Icons.cancel_rounded,
              size: 14,
              color: granted ? Colors.green.shade800 : Colors.red.shade800,
            ),
            const SizedBox(width: 4),
            Text(
              granted ? 'Allow' : 'Deny',
              style: TextStyle(
                color: granted ? Colors.green.shade800 : Colors.red.shade800,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      );
    }

    return DataTable(
      headingRowHeight: 44,
      dataRowMinHeight: 64,
      dataRowMaxHeight: 76,
      columns: [
        const DataColumn(
          label: Text('Scope', style: TextStyle(fontWeight: FontWeight.w800)),
        ),
        ...actions.map(
          (a) => DataColumn(
            label: Text(
              a.displayName,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ],
      rows: [
        DataRow(
          color: WidgetStateProperty.all(
            AppTheme.lightGray.withValues(alpha: 0.35),
          ),
          cells: [
            DataCell(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Role baseline',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  Text(
                    roleTitle,
                    style: TextStyle(
                      fontSize: 11,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            ...actions.map(
              (a) => DataCell(
                Center(child: cellLabel(baselineGranted[a.name] ?? false)),
              ),
            ),
          ],
        ),
        DataRow(
          cells: [
            DataCell(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'User override',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    userOverrideSubtitle,
                    style: TextStyle(
                      fontSize: 11,
                      color: AppTheme.textSecondary,
                      height: 1.2,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            ...actions.map(
              (a) => DataCell(
                Center(
                  child: _LabeledSwitch(
                    value: overrideDraft[a.name] ?? false,
                    onChanged: enabled ? (v) => onOverrideToggle(a, v) : null,
                  ),
                ),
              ),
            ),
          ],
        ),
        DataRow(
          color: WidgetStateProperty.all(
            DocuTrackerTokens.brand.withValues(alpha: 0.05),
          ),
          cells: [
            DataCell(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Effective result',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: DocuTrackerTokens.brand,
                    ),
                  ),
                  Text(
                    'What they actually get',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            ...actions.map((a) {
              final effective = overrideDraft[a.name] ?? false;
              return DataCell(Center(child: cellLabel(effective)));
            }),
          ],
        ),
      ],
    );
  }
}

class _PermissionInfoCard extends StatelessWidget {
  const _PermissionInfoCard({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              body,
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmployeeOption {
  const _EmployeeOption({
    required this.id,
    required this.fullName,
    required this.roleId,
  });

  final String id;
  final String fullName;
  final String roleId;
}

class _EffectiveRow {
  const _EffectiveRow({required this.action, required this.explanation});

  final DocumentAction action;
  final DocuTrackerPermissionExplanation explanation;
}

class _PermissionChange {
  const _PermissionChange({
    required this.scopeLabel,
    required this.documentType,
    required this.action,
    required this.before,
    required this.after,
  });

  final String scopeLabel;
  final String documentType;
  final DocumentAction action;
  final bool before;
  final bool after;
}
