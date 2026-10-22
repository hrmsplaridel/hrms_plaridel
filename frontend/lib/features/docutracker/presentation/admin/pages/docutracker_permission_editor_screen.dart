import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:hrms_plaridel/features/docutracker/data/providers/docutracker_provider.dart';

import 'package:hrms_plaridel/features/docutracker/data/repositories/docutracker_repository.dart';
import 'package:hrms_plaridel/features/docutracker/data/styles/docutracker_styles.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_type.dart';
import 'package:hrms_plaridel/features/docutracker/models/docutracker_governance_audit_entry.dart';
import 'package:hrms_plaridel/features/docutracker/models/docutracker_permission_policy.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/admin/pages/docutracker_governance_audit_screen.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/widgets/docutracker_error_banner.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/widgets/docutracker_responsive_body.dart';
import 'package:hrms_plaridel/features/docutracker/security/docutracker_roles.dart';
import 'package:hrms_plaridel/features/docutracker/security/docutracker_system_access_warnings.dart';
import 'package:hrms_plaridel/features/docutracker/services/employee_directory_lookup.dart';
import 'package:hrms_plaridel/features/docutracker/theme/docutracker_tokens.dart';

enum _AccessView { roleDefaults, employeeExceptions }

enum _EmployeeDecision { inherit, allow, block }

class _AccessAction {
  const _AccessAction(this.key, this.label, this.description, this.icon);

  final String key;
  final String label;
  final String description;
  final IconData icon;
}

const _accessActions = <_AccessAction>[
  _AccessAction(
    'view',
    'Open related documents',
    'Documents are still limited by creator, assignee, and routing rules.',
    Icons.visibility_outlined,
  ),
  _AccessAction(
    'create_draft',
    'Create document drafts',
    'Start a new DocuTracker document for this type.',
    Icons.note_add_outlined,
  ),
  _AccessAction(
    'submit',
    'Submit own drafts',
    'Send a completed draft into its configured workflow.',
    Icons.send_outlined,
  ),
  _AccessAction(
    'download',
    'Download attachments',
    'Download attachments from submitted documents of this type. Files on '
        'documents the person can open stay downloadable.',
    Icons.download_outlined,
  ),
  _AccessAction(
    'release',
    'Release approved documents',
    'Distribute approved documents of this type to a receiving department. '
        'Applies only to types that require release; administrators need '
        'an employee exception.',
    Icons.outbox_outlined,
  ),
];

/// Admin-only DocuTracker system-access editor.
///
/// Workflow actions are intentionally absent: Approve, Forward, Return, and
/// Reject are controlled by the current workflow step's assignees.
class DocuTrackerPermissionEditorScreen extends StatefulWidget {
  const DocuTrackerPermissionEditorScreen({
    super.key,
    this.initialUserId,
    this.initialDocumentType,
    this.initialTabIsUserOverride = false,
  });

  final String? initialUserId;
  final String? initialDocumentType;
  final bool initialTabIsUserOverride;

  @override
  State<DocuTrackerPermissionEditorScreen> createState() =>
      _DocuTrackerPermissionEditorScreenState();
}

class _DocuTrackerPermissionEditorScreenState
    extends State<DocuTrackerPermissionEditorScreen> {
  final _repository = DocuTrackerRepository.instance;
  late final DocuTrackerProvider _provider;
  late final Map<String, Object?> _viewState;
  final _employeeSearchController = TextEditingController();

  _AccessView _view = _AccessView.roleDefaults;
  String _selectedRole = DocuTrackerRoles.hr;
  String _documentType = '*';
  String? _selectedUserId;
  List<String> _documentTypes = const ['*'];
  DocuTrackerPermissionPolicy? _policy;
  Map<String, Map<String, bool>> _roleDraft = {};
  Map<String, Map<String, bool>> _roleBaseline = {};
  Map<String, bool?> _overrideDraft = {};
  Map<String, bool?> _overrideBaseline = {};
  bool _loading = true;
  bool _saving = false;
  String? _error;
  DateTime? _savedAt;
  int? _exceptionCount;
  bool _matrixExpanded = true;
  bool _rolePickerOpen = false;
  final _roleSearchController = TextEditingController();

  static const _employeePageSize = 10;
  static const _bulkUsersPerRequest = 25;
  String? _departmentFilter;
  String? _roleFilter;
  bool _exceptionsOnly = false;
  int _employeePage = 0;
  final Set<String> _bulkSelection = {};
  Set<String> _exceptionUserIds = const {};

  static const _roleOrder = <String>[
    DocuTrackerRoles.admin,
    DocuTrackerRoles.hr,
    DocuTrackerRoles.supervisor,
    DocuTrackerRoles.employee,
  ];

  EmployeeDirectoryLookup get _directory => _provider.employeeDirectory;

  @override
  void initState() {
    super.initState();
    _provider = context.read<DocuTrackerProvider>();
    _viewState = _provider.viewState('permissionEditor');
    final deepLinked =
        widget.initialUserId != null ||
        widget.initialDocumentType?.trim().isNotEmpty == true ||
        widget.initialTabIsUserOverride;
    if (deepLinked) {
      _view = widget.initialTabIsUserOverride
          ? _AccessView.employeeExceptions
          : _AccessView.roleDefaults;
      _documentType = widget.initialDocumentType?.trim().isNotEmpty == true
          ? widget.initialDocumentType!.trim()
          : '*';
      _selectedUserId = widget.initialUserId;
    } else {
      _view = _viewState['view'] as _AccessView? ?? _AccessView.roleDefaults;
      _documentType = _viewState['documentType'] as String? ?? '*';
      _selectedUserId = _viewState['selectedUserId'] as String?;
    }
    _documentTypes = {'*', _documentType}.toList();
    _selectedRole = _viewState['selectedRole'] as String? ?? _selectedRole;
    _matrixExpanded = _viewState['matrixExpanded'] as bool? ?? true;
    _departmentFilter = _viewState['departmentFilter'] as String?;
    _roleFilter = _viewState['roleFilter'] as String?;
    _exceptionsOnly = _viewState['exceptionsOnly'] as bool? ?? false;
    _employeePage = _viewState['employeePage'] as int? ?? 0;
    _employeeSearchController.text = _viewState['search'] as String? ?? '';
    _initialise();
  }

  @override
  void dispose() {
    _viewState
      ..['view'] = _view
      ..['documentType'] = _documentType
      ..['selectedUserId'] = _selectedUserId
      ..['selectedRole'] = _selectedRole
      ..['matrixExpanded'] = _matrixExpanded
      ..['departmentFilter'] = _departmentFilter
      ..['roleFilter'] = _roleFilter
      ..['exceptionsOnly'] = _exceptionsOnly
      ..['employeePage'] = _employeePage
      ..['search'] = _employeeSearchController.text;
    _employeeSearchController.dispose();
    _roleSearchController.dispose();
    super.dispose();
  }

  Map<String, Map<String, bool>> _copyRoleValues(
    Map<String, Map<String, bool>> source,
  ) => source.map((role, values) => MapEntry(role, Map.of(values)));

  bool get _hasUnsavedChanges => _collectChanges().isNotEmpty;

  bool get _hasUnsavedEmployeeChanges => _accessActions.any(
    (action) => _overrideDraft[action.key] != _overrideBaseline[action.key],
  );

  Future<void> _initialise() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    await Future.wait([
      _provider.loadEmployeeDirectory(
        ids: [if (_selectedUserId != null) _selectedUserId!],
      ),
      _provider.loadRoutingConfigs(),
    ]);
    final configs = _provider.routingConfigs;
    final types = [
      '*',
      ...docuTrackerManuallyCreatableTypes([
        ...DocumentType.values,
        ...configs.map((config) => config.documentType),
      ]).map((type) => type.value),
    ];
    if (!mounted) return;
    setState(() {
      _documentTypes = types;
      if (!types.contains(_documentType)) _documentType = '*';
    });
    await _loadPolicy(showLoading: false);
  }

  Future<void> _loadPolicy({bool showLoading = true}) async {
    if (showLoading) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final policy = await _repository.getPermissionPolicy(
        documentType: _documentType,
        userId: _selectedUserId,
      );
      final roleValues = <String, Map<String, bool>>{};
      for (final role in policy.roleDefaults) {
        roleValues[role.roleId] = {
          for (final action in _accessActions)
            action.key: role.permissions[action.key]?.granted ?? false,
        };
      }
      for (final role in _roleOrder) {
        roleValues.putIfAbsent(
          role,
          () => {for (final action in _accessActions) action.key: false},
        );
      }
      if (!mounted) return;
      setState(() {
        _policy = policy;
        _roleDraft = _copyRoleValues(roleValues);
        _roleBaseline = _copyRoleValues(roleValues);
        _overrideDraft = {
          for (final action in _accessActions)
            action.key: policy.userOverrides[action.key],
        };
        _overrideBaseline = Map.of(_overrideDraft);
        _savedAt = policy.updatedAt;
        _loading = false;
        _error = null;
      });
      await _loadExceptionCount();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _friendlyError(
          error,
          'System access settings could not be loaded.',
        );
      });
    }
  }

  Future<void> _loadExceptionCount() async {
    final documentType = _documentType;
    try {
      final rows = await _repository.listPermissions(
        documentType: documentType,
        userOnly: true,
      );
      if (!mounted || documentType != _documentType) return;
      final ids = rows.map((row) => row.userId).whereType<String>().toSet();
      setState(() {
        _exceptionUserIds = ids;
        _exceptionCount = ids.length;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _exceptionCount = null;
          _exceptionUserIds = const {};
        });
      }
    }
  }

  String _friendlyError(Object error, String fallback) {
    final text = error
        .toString()
        .replaceFirst(RegExp(r'^Exception:\s*'), '')
        .trim();
    return text.isEmpty ? fallback : text;
  }

  String _documentTypeLabel(String value) => value == '*'
      ? 'All document types'
      : DocumentType.fromValue(value).displayName;

  String _roleLabel(String roleId) => switch (roleId) {
    DocuTrackerRoles.admin => 'Administrator',
    DocuTrackerRoles.hr => 'HR',
    DocuTrackerRoles.supervisor => 'Supervisor',
    DocuTrackerRoles.employee => 'Employee',
    _ => roleId,
  };

  List<DocuTrackerPermissionPolicyChange> _collectChanges() {
    final changes = <DocuTrackerPermissionPolicyChange>[];
    for (final role in _roleOrder.where(
      (role) => role != DocuTrackerRoles.admin,
    )) {
      for (final action in _accessActions) {
        final before = _roleBaseline[role]?[action.key] ?? false;
        final after = _roleDraft[role]?[action.key] ?? false;
        if (before != after) {
          changes.add(
            DocuTrackerPermissionPolicyChange.role(
              roleId: role,
              action: action.key,
              granted: after,
            ),
          );
        }
      }
    }
    final userId = _selectedUserId;
    if (userId != null) {
      for (final action in _accessActions) {
        final before = _overrideBaseline[action.key];
        final after = _overrideDraft[action.key];
        if (before != after) {
          changes.add(
            DocuTrackerPermissionPolicyChange.user(
              userId: userId,
              action: action.key,
              granted: after,
            ),
          );
        }
      }
    }
    return changes;
  }

  String get _selectedEmployeeName =>
      _directory[_selectedUserId ?? '']?.fullName ??
      _policy?.selectedUser?.fullName ??
      'Selected employee';

  String _changeValueLabel(bool? value) => switch (value) {
    true => 'Allowed',
    false => 'Blocked',
    null => _documentType == '*' ? 'Use role default' : 'Use broader setting',
  };

  void _undoChange(DocuTrackerPermissionPolicyChange change) {
    if (_saving || _loading) return;
    setState(() {
      final roleId = change.roleId;
      if (roleId != null) {
        _roleDraft[roleId]?[change.action] =
            _roleBaseline[roleId]?[change.action] ?? false;
      } else {
        _overrideDraft[change.action] = _overrideBaseline[change.action];
      }
    });
  }

  Future<void> _reviewChanges() async {
    if (_saving || _loading || !_hasUnsavedChanges) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, updateReview) {
          final changes = _collectChanges();
          return AlertDialog(
            title: const Text('Pending changes'),
            content: SizedBox(
              width: 520,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.55,
                ),
                child: changes.isEmpty
                    ? const Text('No pending changes.')
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: changes.length,
                        separatorBuilder: (_, _) => const Divider(height: 24),
                        itemBuilder: (context, index) {
                          final change = changes[index];
                          final roleId = change.roleId;
                          final target = roleId == null
                              ? _selectedEmployeeName
                              : _roleLabel(roleId);
                          final before = roleId == null
                              ? _overrideBaseline[change.action]
                              : _roleBaseline[roleId]?[change.action];
                          final action = _accessActions.firstWhere(
                            (action) => action.key == change.action,
                          );
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '$target · ${_documentTypeLabel(_documentType)}',
                                      style: DocuTrackerTokens.subtitleStyle(
                                        context,
                                      ),
                                    ),
                                    Text(
                                      action.label,
                                      style: DocuTrackerTokens.titleStyle(
                                        context,
                                      ),
                                    ),
                                    Text(
                                      '${_changeValueLabel(before)} → '
                                      '${_changeValueLabel(change.granted)}',
                                    ),
                                  ],
                                ),
                              ),
                              TextButton(
                                key: ValueKey(
                                  'permission-undo-${roleId ?? change.userId}-${change.action}',
                                ),
                                onPressed: () {
                                  _undoChange(change);
                                  updateReview(() {});
                                },
                                child: const Text('Undo'),
                              ),
                            ],
                          );
                        },
                      ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Done'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _save() async {
    final changes = _collectChanges();
    if (_saving || changes.isEmpty) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final savedAt = await _repository.savePermissionPolicy(
        documentType: _documentType,
        changes: changes,
      );
      if (!mounted) return;
      _savedAt = savedAt ?? DateTime.now();
      await _loadPolicy(showLoading: false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('System access settings saved.')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = _friendlyError(
          error,
          'System access settings could not be saved.',
        );
      });
      return;
    }
    if (mounted) setState(() => _saving = false);
  }

  Future<bool> _confirmDiscard() async {
    if (!_hasUnsavedChanges) return true;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Discard unsaved changes?'),
            content: const Text('Your permission changes have not been saved.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Keep editing'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Discard'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _changeDocumentType(String next) async {
    if (next == _documentType || _saving) return;
    if (!await _confirmDiscard()) return;
    setState(() {
      _documentType = next;
      _error = null;
    });
    await _loadPolicy();
  }

  Future<void> _selectEmployee(String userId) async {
    if (userId == _selectedUserId || _saving) return;
    if (!await _confirmDiscard()) return;
    setState(() {
      _selectedUserId = userId;
      _employeeSearchController.clear();
      _error = null;
    });
    await _loadPolicy();
  }

  Future<void> _clearSelectedEmployee() async {
    if (_saving) return;
    if (_hasUnsavedEmployeeChanges) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Discard employee changes?'),
          content: const Text(
            'The selected employee has unsaved permission changes.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep editing'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Discard'),
            ),
          ],
        ),
      );
      if (discard != true || !mounted) return;
    }
    setState(() {
      _selectedUserId = null;
      _overrideDraft = {};
      _overrideBaseline = {};
    });
  }

  Future<void> _resetCurrentView() async {
    if (_saving || _loading || _hasUnsavedChanges || _policy == null) return;
    final isRoles = _view == _AccessView.roleDefaults;
    if (!isRoles && _selectedUserId == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(
          isRoles
              ? 'Remove custom role settings?'
              : 'Remove employee exceptions?',
        ),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              isRoles
                  ? 'Roles: HR, Supervisor, Employee'
                  : 'Employee: $_selectedEmployeeName',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text('Document type: ${_documentTypeLabel(_documentType)}'),
            const SizedBox(height: 12),
            Text(
              'Removes saved settings for:\n${_accessActions.map((action) => '• ${action.label}').join('\n')}',
            ),
            const SizedBox(height: 12),
            Text(
              isRoles
                  ? _documentType == '*'
                        ? 'These roles return to the system default policy for all document types. Document-specific settings and employee exceptions stay in place.'
                        : 'These roles return to the system default policy for this document type and otherwise use their All document types settings. Employee exceptions stay in place.'
                  : _documentType == '*'
                  ? 'Role settings will apply. Document-specific employee exceptions stay in place.'
                  : 'All document types exceptions and role settings will apply.',
            ),
            const SizedBox(height: 12),
            const Text('Removal takes effect immediately after confirmation.'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove settings'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final changes = <DocuTrackerPermissionPolicyChange>[];
    if (isRoles) {
      for (final role in _roleOrder.where(
        (role) => role != DocuTrackerRoles.admin,
      )) {
        for (final action in _accessActions) {
          changes.add(
            DocuTrackerPermissionPolicyChange.role(
              roleId: role,
              action: action.key,
              granted: null,
            ),
          );
        }
      }
    } else {
      for (final action in _accessActions) {
        changes.add(
          DocuTrackerPermissionPolicyChange.user(
            userId: _selectedUserId!,
            action: action.key,
            granted: null,
          ),
        );
      }
    }
    setState(() => _saving = true);
    try {
      await _repository.savePermissionPolicy(
        documentType: _documentType,
        changes: changes,
      );
      if (!mounted) return;
      await _loadPolicy(showLoading: false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isRoles
                ? 'Custom role settings removed.'
                : 'Employee exceptions removed.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = _friendlyError(error, 'The settings could not be removed.');
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _discardChanges() async {
    if (_saving || !_hasUnsavedChanges) return;
    if (!await _confirmDiscard() || !mounted) return;
    setState(() {
      _roleDraft = _copyRoleValues(_roleBaseline);
      _overrideDraft = Map.of(_overrideBaseline);
    });
  }

  Future<void> _openAuditLog({
    String? targetUserId,
    String? targetRoleId,
    String? targetLabel,
  }) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DocuTrackerGovernanceAuditScreen(
          initialCategory: DocuTrackerAuditCategory.access,
          targetUserId: targetUserId,
          targetRoleId: targetRoleId,
          targetLabel: targetLabel,
        ),
      ),
    );
  }

  Widget _historyButton({
    required Key key,
    String? targetUserId,
    String? targetRoleId,
    required String targetLabel,
  }) => TextButton.icon(
    key: key,
    onPressed: _saving
        ? null
        : () => _openAuditLog(
            targetUserId: targetUserId,
            targetRoleId: targetRoleId,
            targetLabel: targetLabel,
          ),
    icon: const Icon(Icons.history_rounded, size: 18),
    label: const Text('History'),
    style: TextButton.styleFrom(foregroundColor: DocuTrackerTokens.brand),
  );

  Future<void> _refresh() async {
    if (_saving || !await _confirmDiscard()) return;
    await _loadPolicy();
  }

  Future<void> _goBack() async {
    if (_saving || !await _confirmDiscard() || !mounted) return;
    Navigator.of(context).pop(_savedAt != null);
  }

  String _savedLabel() {
    final changes = _collectChanges().length;
    if (changes > 0) {
      return '$changes unsaved change${changes == 1 ? '' : 's'}';
    }
    final value = _savedAt?.toLocal();
    if (value == null) return 'No unsaved changes';
    String two(int number) => number.toString().padLeft(2, '0');
    return 'Saved ${value.year}-${two(value.month)}-${two(value.day)} '
        '${two(value.hour)}:${two(value.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_hasUnsavedChanges && !_saving,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop) await _goBack();
      },
      child: Scaffold(
        backgroundColor: DocuTrackerTokens.canvasOf(context),
        appBar: AppBar(
          backgroundColor: DocuTrackerTokens.surfaceOf(context),
          foregroundColor: DocuTrackerTokens.textPrimaryOf(context),
          surfaceTintColor: Colors.transparent,
          leading: IconButton(
            tooltip: 'Back',
            onPressed: _saving ? null : _goBack,
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          title: const Text('System Access'),
          actions: [
            TextButton.icon(
              key: const ValueKey('permission-audit-log'),
              onPressed: _saving ? null : _openAuditLog,
              icon: const Icon(Icons.history_rounded, size: 18),
              label: const Text('Audit log'),
              style: TextButton.styleFrom(
                foregroundColor: DocuTrackerTokens.brand,
              ),
            ),
            PopupMenuButton<String>(
              tooltip: 'More',
              enabled: !_saving,
              onSelected: (value) async {
                switch (value) {
                  case 'refresh':
                    await _refresh();
                  case 'reset':
                    await _resetCurrentView();
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'refresh', child: Text('Refresh')),
                PopupMenuItem(
                  value: 'reset',
                  enabled:
                      !_loading &&
                      _policy != null &&
                      !_hasUnsavedChanges &&
                      (_view == _AccessView.roleDefaults ||
                          _selectedUserId != null),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _view == _AccessView.roleDefaults
                            ? 'Remove custom role settings'
                            : 'Remove employee exceptions',
                      ),
                      if (_hasUnsavedChanges)
                        const Text(
                          'Save or undo pending changes first.',
                          style: TextStyle(fontSize: 12),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: DocuTrackerResponsiveBody(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(),
                const SizedBox(height: 20),
                _buildTopControls(),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  DocuTrackerErrorBanner(
                    message: _error!,
                    onDismiss: () => setState(() => _error = null),
                  ),
                ],
                const SizedBox(height: 20),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 64),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_view == _AccessView.roleDefaults)
                  _buildRoleDefaults()
                else
                  _buildEmployeeExceptions(),
              ],
            ),
          ),
        ),
        bottomNavigationBar: _buildSaveBar(),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Pill(
          icon: Icons.shield_outlined,
          label: 'ROLE-BASED ACCESS',
          tone: _Tone.brand,
        ),
        const SizedBox(height: 12),
        Text(
          'System Access & Permissions',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: DocuTrackerTokens.textPrimaryOf(context),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Control who can open, create, submit, and download DocuTracker '
          'documents. Approvals are handled by each workflow step.',
          style: DocuTrackerTokens.subtitleStyle(context),
        ),
      ],
    );
  }

  Widget _buildTopControls() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final switcher = Row(
          key: const ValueKey('system-access-view-selector'),
          mainAxisSize: MainAxisSize.min,
          children: [
            _ViewTab(
              icon: Icons.groups_outlined,
              label: 'Role access',
              count: _roleOrder.length,
              selected: _view == _AccessView.roleDefaults,
              onTap: _saving
                  ? null
                  : () => setState(() => _view = _AccessView.roleDefaults),
            ),
            const SizedBox(width: 24),
            _ViewTab(
              icon: Icons.person_outline_rounded,
              label: 'Employee exceptions',
              count: _exceptionCount,
              selected: _view == _AccessView.employeeExceptions,
              onTap: _saving
                  ? null
                  : () =>
                        setState(() => _view = _AccessView.employeeExceptions),
            ),
          ],
        );
        final type = DropdownButtonFormField<String>(
          key: ValueKey('permission-document-type-$_documentType'),
          initialValue: _documentType,
          isExpanded: true,
          decoration: DocuTrackerStyles.dropdownDecoration(
            context,
            'Document scope',
          ),
          items: _documentTypes
              .map(
                (value) => DropdownMenuItem(
                  value: value,
                  child: Text(_documentTypeLabel(value)),
                ),
              )
              .toList(),
          onChanged: _saving
              ? null
              : (value) => value == null ? null : _changeDocumentType(value),
        );

        final tabBar = Container(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: DocuTrackerTokens.borderSubtleOf(context),
              ),
            ),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: switcher,
          ),
        );
        if (constraints.maxWidth < 720) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [tabBar, const SizedBox(height: 16), type],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(child: tabBar),
            const SizedBox(width: 24),
            SizedBox(width: 280, child: type),
          ],
        );
      },
    );
  }

  bool get _canReset =>
      !_loading &&
      !_saving &&
      _policy != null &&
      !_hasUnsavedChanges &&
      (_view == _AccessView.roleDefaults || _selectedUserId != null);

  Widget _buildRoleDefaults() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildRoleSelection(),
        const SizedBox(height: 16),
        const _HierarchyNotice(
          message:
              'Role rules apply to everyone with the role. Employee exceptions '
              'always take priority over role rules, and a setting for a '
              'specific document type overrides the All document types setting.',
        ),
        const SizedBox(height: 24),
        _SectionHeading(
          title: 'Access by role: ${_roleLabel(_selectedRole)}',
          subtitle:
              'Applies to everyone with this role, unless they have an employee exception.',
          action: _selectedRole == DocuTrackerRoles.admin
              ? null
              : Wrap(
                  spacing: 4,
                  children: [
                    _historyButton(
                      key: const ValueKey('permission-role-history'),
                      targetRoleId: _selectedRole,
                      targetLabel: '${_roleLabel(_selectedRole)} role',
                    ),
                    TextButton.icon(
                      key: const ValueKey('permission-reset-view'),
                      onPressed: _canReset ? _resetCurrentView : null,
                      icon: const Icon(Icons.restart_alt_rounded, size: 18),
                      label: const Text('Reset to default'),
                      style: TextButton.styleFrom(
                        foregroundColor: DocuTrackerTokens.brand,
                      ),
                    ),
                  ],
                ),
        ),
        ..._buildWarnings(
          key: const ValueKey('permission-role-warnings'),
          warnings: _selectedRole == DocuTrackerRoles.admin
              ? const []
              : docuTrackerAccessWarnings(
                  effective: Map.of(_roleDraft[_selectedRole] ?? const {}),
                  roleId: _selectedRole,
                  documentType: _documentType,
                  isRoleDefault: true,
                  actionLabel: _actionLabel,
                ),
        ),
        const SizedBox(height: 12),
        _buildRoleCard(_selectedRole),
      ],
    );
  }

  String _actionLabel(String key) =>
      _accessActions.where((action) => action.key == key).firstOrNull?.label ??
      key;

  List<Widget> _buildWarnings({
    required Key key,
    required List<DocuTrackerAccessWarning> warnings,
  }) {
    if (warnings.isEmpty) return const [];
    return [
      const SizedBox(height: 12),
      Column(
        key: key,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final warning in warnings)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _WarningNotice(warning: warning),
            ),
        ],
      ),
    ];
  }

  int _personnelCount(String roleId) => _directory.entries
      .where(
        (employee) => DocuTrackerRoles.normalize(employee.roleId) == roleId,
      )
      .length;

  IconData _roleIcon(String roleId) => switch (roleId) {
    DocuTrackerRoles.admin => Icons.admin_panel_settings_outlined,
    DocuTrackerRoles.hr => Icons.badge_outlined,
    DocuTrackerRoles.supervisor => Icons.supervisor_account_outlined,
    _ => Icons.person_outline_rounded,
  };

  String _roleDescription(String roleId) => switch (roleId) {
    DocuTrackerRoles.admin => 'Full system access',
    DocuTrackerRoles.hr => 'Human resources staff',
    DocuTrackerRoles.supervisor => 'Department heads and supervisors',
    _ => 'Regular employees',
  };

  void _toggleRolePicker([bool? open]) {
    setState(() {
      _rolePickerOpen = open ?? !_rolePickerOpen;
      if (!_rolePickerOpen) _roleSearchController.clear();
    });
  }

  void _pickRole(String role) {
    setState(() {
      _selectedRole = role;
      _rolePickerOpen = false;
      _roleSearchController.clear();
    });
  }

  Widget _buildRoleSelection() {
    final open = _rolePickerOpen;
    final isAdmin = _selectedRole == DocuTrackerRoles.admin;
    final radius = BorderRadius.circular(DocuTrackerTokens.radiusMd);
    final header = Material(
      color: DocuTrackerTokens.surfaceOf(context),
      borderRadius: radius,
      child: InkWell(
        key: const ValueKey('permission-role-selector'),
        borderRadius: radius,
        onTap: _saving ? null : _toggleRolePicker,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(
              color: open
                  ? DocuTrackerTokens.brand
                  : DocuTrackerTokens.borderSubtleOf(context),
              width: open ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              _IconTile(icon: _roleIcon(_selectedRole), active: true),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          _roleLabel(_selectedRole),
                          style: DocuTrackerTokens.titleStyle(
                            context,
                          ).copyWith(fontSize: 16, fontWeight: FontWeight.w800),
                        ),
                        _Pill(
                          label: isAdmin ? 'Full access' : 'Standard role',
                          tone: isAdmin ? _Tone.brand : _Tone.success,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Applies to ${_personnelCount(_selectedRole)} active '
                      'personnel · ${_roleDescription(_selectedRole)}',
                      style: DocuTrackerTokens.metaStyle(context),
                    ),
                  ],
                ),
              ),
              if (MediaQuery.sizeOf(context).width >= 560) ...[
                const SizedBox(width: 12),
                Text(
                  'Role key: $_selectedRole',
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: DocuTrackerTokens.brand,
                  ),
                ),
              ],
              const SizedBox(width: 8),
              Icon(
                open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                color: DocuTrackerTokens.textMutedOf(context),
              ),
            ],
          ),
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Eyebrow('TARGET ROLE SELECTION'),
        const SizedBox(height: 8),
        header,
        if (open) ...[const SizedBox(height: 6), _buildRoleMenu()],
      ],
    );
  }

  Widget _buildRoleMenu() {
    final query = _roleSearchController.text.trim().toLowerCase();
    bool matches(String role) =>
        query.isEmpty ||
        [
          _roleLabel(role),
          _roleDescription(role),
          role,
        ].any((value) => value.toLowerCase().contains(query));
    final groups = <(String, List<String>)>[
      (
        'STANDARD ROLES',
        [
          DocuTrackerRoles.hr,
          DocuTrackerRoles.supervisor,
          DocuTrackerRoles.employee,
        ].where(matches).toList(),
      ),
      (
        'ADMINISTRATIVE ROLES',
        [DocuTrackerRoles.admin].where(matches).toList(),
      ),
    ].where((group) => group.$2.isNotEmpty).toList();

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            _toggleRolePicker(false),
      },
      child: Container(
        key: const ValueKey('permission-role-menu'),
        decoration: DocuTrackerTokens.cardDecoration(context: context),
        clipBehavior: Clip.antiAlias,
        child: Material(
          type: MaterialType.transparency,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const ValueKey('permission-role-search'),
                        controller: _roleSearchController,
                        autofocus: true,
                        decoration: DocuTrackerTokens.warmSearchDecoration(
                          context,
                          'Search roles',
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () => _toggleRolePicker(false),
                      style: TextButton.styleFrom(
                        foregroundColor: DocuTrackerTokens.textMutedOf(context),
                      ),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              ),
              if (groups.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  child: Text(
                    'No matching roles.',
                    style: DocuTrackerTokens.metaStyle(context),
                  ),
                ),
              for (final group in groups) ...[
                Divider(
                  height: 1,
                  color: DocuTrackerTokens.borderSubtleOf(context),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                  child: Row(
                    children: [
                      Expanded(child: _Eyebrow(group.$1)),
                      _Eyebrow(
                        '${group.$2.length} '
                        'ROLE${group.$2.length == 1 ? '' : 'S'}',
                      ),
                    ],
                  ),
                ),
                for (final role in group.$2) _buildRoleOption(role),
                const SizedBox(height: 6),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRoleOption(String role) {
    final selected = role == _selectedRole;
    final isAdmin = role == DocuTrackerRoles.admin;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color: selected ? _brandTint(context) : Colors.transparent,
        borderRadius: BorderRadius.circular(DocuTrackerTokens.radiusSm),
        child: InkWell(
          key: ValueKey('permission-role-option-$role'),
          borderRadius: BorderRadius.circular(DocuTrackerTokens.radiusSm),
          onTap: () => _pickRole(role),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(DocuTrackerTokens.radiusSm),
              border: Border.all(
                color: selected
                    ? DocuTrackerTokens.brand.withValues(alpha: 0.45)
                    : Colors.transparent,
              ),
            ),
            child: Row(
              children: [
                _IconTile(icon: _roleIcon(role), active: selected),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            _roleLabel(role),
                            style: DocuTrackerTokens.titleStyle(context),
                          ),
                          _Pill(
                            label: isAdmin ? 'Full access' : 'Standard role',
                            tone: selected
                                ? (isAdmin ? _Tone.brand : _Tone.success)
                                : _Tone.neutral,
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${_personnelCount(role)} active personnel · '
                        '${_roleDescription(role)}',
                        style: DocuTrackerTokens.metaStyle(context),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (selected)
                  const Icon(
                    Icons.check_rounded,
                    size: 20,
                    color: DocuTrackerTokens.brand,
                  )
                else
                  Text(
                    role,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: DocuTrackerTokens.textMutedOf(context),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMatrixCard({
    required Key key,
    required String subtitle,
    required List<Widget> rows,
  }) {
    final muted = DocuTrackerTokens.textMutedOf(context);
    return Container(
      key: key,
      decoration: DocuTrackerTokens.cardDecoration(context: context),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              key: const ValueKey('permission-matrix-toggle'),
              onTap: () => setState(() => _matrixExpanded = !_matrixExpanded),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
                child: Row(
                  children: [
                    Icon(Icons.grid_view_rounded, size: 18, color: muted),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const _Eyebrow('DOCUMENT OPERATION MATRIX'),
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            style: DocuTrackerTokens.metaStyle(context),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      _matrixExpanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      color: muted,
                    ),
                  ],
                ),
              ),
            ),
            if (_matrixExpanded)
              for (final row in rows) ...[
                Divider(
                  height: 1,
                  color: DocuTrackerTokens.borderSubtleOf(context),
                ),
                row,
              ],
          ],
        ),
      ),
    );
  }

  Widget _buildRoleCard(String roleId) {
    final isAdmin = roleId == DocuTrackerRoles.admin;
    final rolePolicy = _policy?.roleDefaults
        .where((role) => role.roleId == roleId)
        .firstOrNull;
    return _buildMatrixCard(
      key: ValueKey('permission-role-$roleId'),
      subtitle: isAdmin
          ? 'Full system access'
          : '${_accessActions.length} operations · ${_documentTypeLabel(_documentType)}',
      rows: [
        if (isAdmin)
          const _OperationRow(
            icon: Icons.verified_user_outlined,
            title: 'Administrator access is always enabled.',
            badges: [_Pill(label: 'Granted', tone: _Tone.success)],
            description:
                'Workflow approvals still require assignment to the current step. '
                'Releasing approved documents requires an employee exception.',
          )
        else
          for (final action in _accessActions)
            _buildRoleActionRow(roleId, action, rolePolicy),
      ],
    );
  }

  Widget _buildRoleActionRow(
    String roleId,
    _AccessAction action,
    DocuTrackerRolePermissionPolicy? rolePolicy,
  ) {
    final allowed = _roleDraft[roleId]?[action.key] ?? false;
    final changed = allowed != (_roleBaseline[roleId]?[action.key] ?? false);
    void toggle(bool value) =>
        setState(() => _roleDraft[roleId]?[action.key] = value);
    return _OperationRow(
      key: ValueKey('permission-role-$roleId-${action.key}'),
      icon: action.icon,
      active: allowed,
      title: action.label,
      code: action.key,
      badges: [
        _Pill(
          label: allowed ? 'Granted' : 'Restricted',
          tone: allowed ? _Tone.success : _Tone.danger,
        ),
        if (changed) const _Pill(label: 'Unsaved', tone: _Tone.brand),
      ],
      description: action.description,
      footnote: _roleSourceNote(
        rolePolicy?.permissions[action.key]?.source,
        changed,
      ),
      onTap: _saving ? null : () => toggle(!allowed),
      trailing: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            allowed ? 'Active' : 'Disabled',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: allowed
                  ? DocuTrackerTokens.brand
                  : DocuTrackerTokens.textMutedOf(context),
            ),
          ),
          Switch(
            value: allowed,
            activeTrackColor: DocuTrackerTokens.brand,
            activeThumbColor: Colors.white,
            onChanged: _saving ? null : toggle,
          ),
        ],
      ),
    );
  }

  String _roleSourceNote(String? source, bool changed) {
    if (changed) return 'Changed here · not saved yet';
    return switch (source) {
      'this_document_type' => 'Set for ${_documentTypeLabel(_documentType)}',
      'all_document_types' when _documentType != '*' =>
        'Inherited from All document types',
      'all_document_types' => 'Set for all document types',
      'not_configured' => 'No rule configured · blocked by default',
      _ => 'Role rule',
    };
  }

  List<String> get _departmentOptions =>
      _directory.entries
          .map((employee) => employee.departmentName?.trim() ?? '')
          .where((name) => name.isNotEmpty)
          .toSet()
          .toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

  List<EmployeeDirectoryEntry> _filteredEmployees() {
    final query = _employeeSearchController.text.trim().toLowerCase();
    return _directory.entries
        .where((employee) {
          if (_departmentFilter != null &&
              employee.departmentName?.trim() != _departmentFilter) {
            return false;
          }
          if (_roleFilter != null &&
              DocuTrackerRoles.normalize(employee.roleId) != _roleFilter) {
            return false;
          }
          if (_exceptionsOnly && !_exceptionUserIds.contains(employee.id)) {
            return false;
          }
          if (query.isEmpty) return true;
          return [
            employee.fullName,
            employee.departmentName,
            employee.positionName,
            employee.roleId,
          ].whereType<String>().any(
            (value) => value.toLowerCase().contains(query),
          );
        })
        .toList(growable: false);
  }

  void _updateEmployeeFilters(VoidCallback change) => setState(() {
    change();
    _employeePage = 0;
  });

  int _pageCount(int total) =>
      total == 0 ? 1 : (total + _employeePageSize - 1) ~/ _employeePageSize;

  Widget _buildEmployeeExceptions() {
    final selected = _selectedUserId == null
        ? null
        : _directory[_selectedUserId!];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _Eyebrow('EMPLOYEE DIRECTORY'),
              const SizedBox(height: 4),
              Text(
                'Use exceptions when only selected employees need different '
                'access from their role — for example, letting two clerks '
                'create Purchase Requests without a new role.',
                style: DocuTrackerTokens.metaStyle(context),
              ),
              const SizedBox(height: 12),
              ..._buildEmployeePicker(selected),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const _HierarchyNotice(
          message:
              'Employee exceptions take priority over the employee\'s role '
              'rules. Choose "Use role default" to go back to the role setting.',
        ),
        if (_selectedUserId != null) ...[
          const SizedBox(height: 24),
          _SectionHeading(
            title: 'Exceptions for: $_selectedEmployeeName',
            subtitle: _documentTypeLabel(_documentType),
            action: Wrap(
              spacing: 4,
              children: [
                _historyButton(
                  key: const ValueKey('permission-user-history'),
                  targetUserId: _selectedUserId,
                  targetLabel: _selectedEmployeeName,
                ),
                TextButton.icon(
                  key: const ValueKey('permission-reset-view'),
                  onPressed: _canReset ? _resetCurrentView : null,
                  icon: const Icon(Icons.restart_alt_rounded, size: 18),
                  label: const Text('Reset to role rules'),
                  style: TextButton.styleFrom(
                    foregroundColor: DocuTrackerTokens.brand,
                  ),
                ),
              ],
            ),
          ),
          ..._buildWarnings(
            key: const ValueKey('permission-user-warnings'),
            warnings: _employeeWarnings(),
          ),
          const SizedBox(height: 12),
          _buildMatrixCard(
            key: const ValueKey('permission-user-matrix'),
            subtitle:
                '${_accessActions.length} operations · ${_documentTypeLabel(_documentType)}',
            rows: [
              for (final action in _accessActions) _buildEmployeeAction(action),
            ],
          ),
        ],
      ],
    );
  }

  List<Widget> _buildEmployeePicker(EmployeeDirectoryEntry? selected) {
    return [
      TextField(
        key: const ValueKey('permission-employee-search'),
        controller: _employeeSearchController,
        enabled: !_saving,
        decoration: DocuTrackerTokens.warmSearchDecoration(
          context,
          'Search employee, department, position, or role',
        ),
        onChanged: (_) => _updateEmployeeFilters(() {}),
      ),
      const SizedBox(height: 12),
      _buildEmployeeFilters(),
      const SizedBox(height: 12),
      _buildEmployeeList(),
      if (_selectedUserId != null) ...[
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: DocuTrackerTokens.canvasOf(context),
            borderRadius: BorderRadius.circular(DocuTrackerTokens.radiusMd),
            border: Border.all(
              color: DocuTrackerTokens.borderSubtleOf(context),
            ),
          ),
          child: Row(
            children: [
              const _IconTile(icon: Icons.person_outline_rounded, active: true),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      selected?.fullName ??
                          _policy?.selectedUser?.fullName ??
                          'Selected employee',
                      style: DocuTrackerTokens.titleStyle(
                        context,
                      ).copyWith(fontSize: 16, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      selected == null
                          ? _roleLabel(
                              _policy?.selectedUser?.roleId ?? 'employee',
                            )
                          : _employeeDetails(selected),
                      style: DocuTrackerTokens.metaStyle(context),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: _saving ? null : _clearSelectedEmployee,
                style: TextButton.styleFrom(
                  foregroundColor: DocuTrackerTokens.brand,
                ),
                child: const Text('Change'),
              ),
            ],
          ),
        ),
      ],
    ];
  }

  Widget _buildEmployeeFilters() {
    final departments = _departmentOptions;
    final department = DropdownButtonFormField<String?>(
      key: ValueKey('permission-filter-department-$_departmentFilter'),
      initialValue: departments.contains(_departmentFilter)
          ? _departmentFilter
          : null,
      isExpanded: true,
      decoration: DocuTrackerStyles.dropdownDecoration(context, 'Department'),
      items: [
        const DropdownMenuItem<String?>(child: Text('All departments')),
        for (final name in departments)
          DropdownMenuItem<String?>(
            value: name,
            child: Text(name, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: _saving
          ? null
          : (value) => _updateEmployeeFilters(() => _departmentFilter = value),
    );
    final role = DropdownButtonFormField<String?>(
      key: ValueKey('permission-filter-role-$_roleFilter'),
      initialValue: _roleFilter,
      isExpanded: true,
      decoration: DocuTrackerStyles.dropdownDecoration(context, 'Role'),
      items: [
        const DropdownMenuItem<String?>(child: Text('All roles')),
        for (final roleId in _roleOrder)
          DropdownMenuItem<String?>(
            value: roleId,
            child: Text(_roleLabel(roleId)),
          ),
      ],
      onChanged: _saving
          ? null
          : (value) => _updateEmployeeFilters(() => _roleFilter = value),
    );
    final exceptionsOnly = FilterChip(
      key: const ValueKey('permission-filter-exceptions'),
      label: Text(
        'Has exceptions'
        '${_exceptionCount == null ? '' : ' ($_exceptionCount)'}',
      ),
      selected: _exceptionsOnly,
      onSelected: _saving
          ? null
          : (value) => _updateEmployeeFilters(() => _exceptionsOnly = value),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 620) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              department,
              const SizedBox(height: 12),
              role,
              const SizedBox(height: 8),
              Align(alignment: Alignment.centerLeft, child: exceptionsOnly),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: department),
            const SizedBox(width: 12),
            SizedBox(width: 200, child: role),
            const SizedBox(width: 12),
            exceptionsOnly,
          ],
        );
      },
    );
  }

  Widget _buildEmployeeList() {
    final employees = _filteredEmployees();
    final pages = _pageCount(employees.length);
    final page = _employeePage.clamp(0, pages - 1);
    final start = page * _employeePageSize;
    final visible = employees
        .skip(start)
        .take(_employeePageSize)
        .toList(growable: false);
    final visibleIds = visible.map((employee) => employee.id).toSet();
    final pageSelected =
        visibleIds.isNotEmpty && _bulkSelection.containsAll(visibleIds);
    final muted = DocuTrackerTokens.textMutedOf(context);

    return Container(
      key: const ValueKey('permission-employee-list'),
      decoration: DocuTrackerTokens.cardDecoration(context: context),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
              child: Row(
                children: [
                  Checkbox(
                    key: const ValueKey('permission-select-page'),
                    value: pageSelected,
                    onChanged: _saving || visible.isEmpty
                        ? null
                        : (value) => setState(() {
                            if (value == true) {
                              _bulkSelection.addAll(visibleIds);
                            } else {
                              _bulkSelection.removeAll(visibleIds);
                            }
                          }),
                  ),
                  Expanded(
                    child: Text(
                      _bulkSelection.isEmpty
                          ? '${employees.length} employee${employees.length == 1 ? '' : 's'}'
                          : '${_bulkSelection.length} selected',
                      key: const ValueKey('permission-bulk-count'),
                      style: DocuTrackerTokens.titleStyle(context),
                    ),
                  ),
                  if (_bulkSelection.isNotEmpty) ...[
                    TextButton(
                      key: const ValueKey('permission-bulk-clear'),
                      onPressed: _saving
                          ? null
                          : () => setState(_bulkSelection.clear),
                      child: const Text('Clear'),
                    ),
                    const SizedBox(width: 4),
                    FilledButton.icon(
                      key: const ValueKey('permission-bulk-assign'),
                      onPressed: _saving ? null : _openBulkAssign,
                      icon: const Icon(Icons.playlist_add_check_rounded),
                      label: const Text('Set access'),
                      style: DocuTrackerTokens.brandFilledStyle(),
                    ),
                  ],
                ],
              ),
            ),
            Divider(
              height: 1,
              color: DocuTrackerTokens.borderSubtleOf(context),
            ),
            if (visible.isEmpty)
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  'No active employees match these filters.',
                  textAlign: TextAlign.center,
                  style: DocuTrackerTokens.metaStyle(context),
                ),
              )
            else
              for (final employee in visible) _buildEmployeeRow(employee),
            Divider(
              height: 1,
              color: DocuTrackerTokens.borderSubtleOf(context),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      employees.isEmpty
                          ? 'No results'
                          : 'Showing ${start + 1}–${start + visible.length} of ${employees.length}',
                      key: const ValueKey('permission-employee-page-label'),
                      style: TextStyle(fontSize: 12, color: muted),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('permission-employee-prev'),
                    tooltip: 'Previous page',
                    onPressed: page > 0
                        ? () => setState(() => _employeePage = page - 1)
                        : null,
                    icon: const Icon(Icons.chevron_left_rounded),
                  ),
                  Text(
                    '${page + 1} / $pages',
                    style: TextStyle(fontSize: 12, color: muted),
                  ),
                  IconButton(
                    key: const ValueKey('permission-employee-next'),
                    tooltip: 'Next page',
                    onPressed: page < pages - 1
                        ? () => setState(() => _employeePage = page + 1)
                        : null,
                    icon: const Icon(Icons.chevron_right_rounded),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmployeeRow(EmployeeDirectoryEntry employee) {
    final selected = employee.id == _selectedUserId;
    final checked = _bulkSelection.contains(employee.id);
    return InkWell(
      key: ValueKey('permission-employee-row-${employee.id}'),
      onTap: _saving ? null : () => _selectEmployee(employee.id),
      child: Container(
        color: selected ? _brandTint(context) : null,
        padding: const EdgeInsets.fromLTRB(4, 6, 12, 6),
        child: Row(
          children: [
            Checkbox(
              key: ValueKey('permission-employee-check-${employee.id}'),
              value: checked,
              onChanged: _saving
                  ? null
                  : (value) => setState(() {
                      if (value == true) {
                        _bulkSelection.add(employee.id);
                      } else {
                        _bulkSelection.remove(employee.id);
                      }
                    }),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    employee.fullName,
                    style: DocuTrackerTokens.titleStyle(context),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    _employeeDetails(employee),
                    style: DocuTrackerTokens.metaStyle(context),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (_exceptionUserIds.contains(employee.id)) ...[
              const SizedBox(width: 8),
              const _Pill(label: 'Exceptions', tone: _Tone.info),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _openBulkAssign() async {
    if (_bulkSelection.isEmpty || _saving) return;
    if (_hasUnsavedChanges) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Save or discard pending changes before bulk edits.'),
        ),
      );
      return;
    }
    final userIds = _bulkSelection.toList(growable: false);
    final choices = <String, _EmployeeDecision?>{
      for (final action in _accessActions) action.key: null,
    };
    final inheritLabel = _documentType == '*'
        ? 'Use role default'
        : 'Use broader setting';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) {
          final picked = <String, bool>{
            for (final entry in choices.entries)
              if (entry.value == _EmployeeDecision.allow)
                entry.key: true
              else if (entry.value == _EmployeeDecision.block)
                entry.key: false,
          };
          final warnings = docuTrackerAccessWarnings(
            effective: picked,
            exceptions: picked,
            documentType: _documentType,
            actionLabel: _actionLabel,
          );
          final hasChoice = choices.values.any((value) => value != null);
          return AlertDialog(
            key: const ValueKey('permission-bulk-dialog'),
            scrollable: true,
            title: Text(
              'Set access for ${userIds.length} employee${userIds.length == 1 ? '' : 's'}',
            ),
            content: SizedBox(
              width: 520,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Document scope: ${_documentTypeLabel(_documentType)}. '
                    'These are saved as employee exceptions and take priority '
                    'over role defaults.',
                    style: DocuTrackerTokens.metaStyle(context),
                  ),
                  const SizedBox(height: 12),
                  for (final action in _accessActions) ...[
                    DropdownButtonFormField<_EmployeeDecision?>(
                      key: ValueKey('permission-bulk-${action.key}'),
                      initialValue: choices[action.key],
                      isExpanded: true,
                      decoration: DocuTrackerStyles.dropdownDecoration(
                        context,
                        action.label,
                      ),
                      items: [
                        const DropdownMenuItem<_EmployeeDecision?>(
                          child: Text('No change'),
                        ),
                        const DropdownMenuItem(
                          value: _EmployeeDecision.allow,
                          child: Text('Allow'),
                        ),
                        const DropdownMenuItem(
                          value: _EmployeeDecision.block,
                          child: Text('Block'),
                        ),
                        DropdownMenuItem(
                          value: _EmployeeDecision.inherit,
                          child: Text(inheritLabel),
                        ),
                      ],
                      onChanged: (value) =>
                          update(() => choices[action.key] = value),
                    ),
                    const SizedBox(height: 12),
                  ],
                  for (final warning in warnings)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _WarningNotice(warning: warning),
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
                key: const ValueKey('permission-bulk-apply'),
                onPressed: hasChoice
                    ? () => Navigator.pop(dialogContext, true)
                    : null,
                style: DocuTrackerTokens.brandFilledStyle(),
                child: Text('Apply to ${userIds.length}'),
              ),
            ],
          );
        },
      ),
    );
    if (confirmed != true || !mounted) return;

    final selectedChoices = choices.entries
        .where((entry) => entry.value != null)
        .toList(growable: false);
    var savedUsers = 0;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      for (var i = 0; i < userIds.length; i += _bulkUsersPerRequest) {
        final batch = userIds.skip(i).take(_bulkUsersPerRequest);
        await _repository.savePermissionPolicy(
          documentType: _documentType,
          changes: [
            for (final userId in batch)
              for (final entry in selectedChoices)
                DocuTrackerPermissionPolicyChange.user(
                  userId: userId,
                  action: entry.key,
                  granted: switch (entry.value) {
                    _EmployeeDecision.allow => true,
                    _EmployeeDecision.block => false,
                    _ => null,
                  },
                ),
          ],
        );
        savedUsers += batch.length;
      }
      if (!mounted) return;
      setState(() => _bulkSelection.clear());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Access updated for $savedUsers employee${savedUsers == 1 ? '' : 's'}.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = savedUsers == 0
            ? _friendlyError(error, 'Bulk access changes could not be saved.')
            : 'Saved $savedUsers of ${userIds.length} employees, then stopped: '
                  '${_friendlyError(error, 'the remaining changes failed')}';
        _bulkSelection.removeAll(userIds.take(savedUsers));
      });
    } finally {
      if (mounted) {
        await _loadPolicy(showLoading: false);
        if (mounted) setState(() => _saving = false);
      }
    }
  }

  List<DocuTrackerAccessWarning> _employeeWarnings() {
    final effective = <String, bool>{};
    final inherited = <String, bool>{};
    final exceptions = <String, bool?>{};
    for (final action in _accessActions) {
      effective[action.key] = _effectiveDecision(action.key).$1;
      inherited[action.key] = _inheritedDecision(action.key).$1;
      final direct = _overrideDraft[action.key];
      if (direct != null) exceptions[action.key] = direct;
    }
    return docuTrackerAccessWarnings(
      effective: effective,
      roleId: _selectedEmployeeRole,
      documentType: _documentType,
      exceptions: exceptions,
      inherited: inherited,
      actionLabel: _actionLabel,
    );
  }

  String _employeeDetails(EmployeeDirectoryEntry employee) {
    final parts = <String>[
      if (employee.departmentName?.trim().isNotEmpty == true)
        employee.departmentName!.trim(),
      if (employee.positionName?.trim().isNotEmpty == true)
        employee.positionName!.trim(),
      if (employee.roleId?.trim().isNotEmpty == true)
        _roleLabel(DocuTrackerRoles.normalize(employee.roleId)),
    ];
    return parts.isEmpty ? 'Active employee' : parts.join(' · ');
  }

  Widget _buildEmployeeAction(_AccessAction action) {
    final raw = _overrideDraft[action.key];
    final decision = raw == null
        ? _EmployeeDecision.inherit
        : raw
        ? _EmployeeDecision.allow
        : _EmployeeDecision.block;
    final changed = raw != _overrideBaseline[action.key];
    final effective = _effectiveDecision(action.key);
    final selector = DropdownButtonFormField<_EmployeeDecision>(
      key: ValueKey('permission-user-decision-${action.key}-$decision'),
      initialValue: decision,
      isExpanded: true,
      decoration: DocuTrackerStyles.dropdownDecoration(context, 'Access'),
      items: [
        DropdownMenuItem(
          value: _EmployeeDecision.inherit,
          child: Text(
            _documentType == '*' ? 'Use role default' : 'Use broader setting',
          ),
        ),
        const DropdownMenuItem(
          value: _EmployeeDecision.allow,
          child: Text('Allow'),
        ),
        const DropdownMenuItem(
          value: _EmployeeDecision.block,
          child: Text('Block'),
        ),
      ],
      onChanged: _saving
          ? null
          : (value) => setState(() {
              _overrideDraft[action.key] = switch (value) {
                _EmployeeDecision.allow => true,
                _EmployeeDecision.block => false,
                _ => null,
              };
            }),
    );
    return _OperationRow(
      key: ValueKey('permission-user-${action.key}'),
      icon: action.icon,
      active: effective.$1,
      title: action.label,
      code: action.key,
      badges: [
        _Pill(
          label: effective.$1 ? 'Granted' : 'Restricted',
          tone: effective.$1 ? _Tone.success : _Tone.danger,
        ),
        if (decision != _EmployeeDecision.inherit)
          const _Pill(label: 'Exception', tone: _Tone.info),
        if (changed) const _Pill(label: 'Unsaved', tone: _Tone.brand),
      ],
      description: action.description,
      footnote:
          'Effective: ${effective.$1 ? 'Allowed' : 'Blocked'} · ${effective.$2}',
      trailing: selector,
      trailingWidth: 220,
    );
  }

  String get _selectedEmployeeRole => DocuTrackerRoles.normalize(
    _policy?.selectedUser?.roleId ?? _directory[_selectedUserId ?? '']?.roleId,
  );

  String _roleScopeLabel(String role, String action) {
    final changed =
        (_roleDraft[role]?[action] ?? false) !=
        (_roleBaseline[role]?[action] ?? false);
    if (changed) return 'Role default · ${_roleLabel(role)} · unsaved change';
    final source = _policy?.roleDefaults
        .where((policy) => policy.roleId == role)
        .firstOrNull
        ?.permissions[action]
        ?.source;
    final scope = switch (source) {
      'this_document_type' => _documentTypeLabel(_documentType),
      'all_document_types' => 'All document types',
      _ => 'no rule, blocked by default',
    };
    return 'Role default · ${_roleLabel(role)} · $scope';
  }

  /// The decision this employee gets without an exception for this scope.
  (bool, String) _inheritedDecision(String action) {
    final inherited = _policy?.inheritedUserOverrides[action];
    if (inherited != null) {
      return (inherited, 'Employee exception · All document types');
    }
    final role = _selectedEmployeeRole;
    if (role == DocuTrackerRoles.admin && action != 'release') {
      return (true, 'Administrator');
    }
    return (_roleDraft[role]?[action] ?? false, _roleScopeLabel(role, action));
  }

  (bool, String) _effectiveDecision(String action) {
    final server = _policy?.effective[action];
    if (server != null && !_hasUnsavedChanges) {
      return switch (server.matchedScope) {
        'user' => (
          server.granted,
          'Employee exception · ${_documentTypeLabel(server.matchedDocumentType ?? _documentType)}',
        ),
        'role' => (
          server.granted,
          'Role default · ${_roleLabel(DocuTrackerRoles.normalize(server.matchedRoleId))} · '
              '${_documentTypeLabel(server.matchedDocumentType ?? _documentType)}',
        ),
        _ when server.source == 'admin_override' => (true, 'Administrator'),
        _ => (server.granted, 'No rule · blocked by default'),
      };
    }
    final direct = _overrideDraft[action];
    if (direct != null) {
      return (
        direct,
        'Employee exception · ${_documentTypeLabel(_documentType)}',
      );
    }
    return _inheritedDecision(action);
  }

  Widget _buildSaveBar() {
    final canSave = _hasUnsavedChanges && !_saving && !_loading;
    final statusColor = _hasUnsavedChanges
        ? DocuTrackerTokens.brand
        : DocuTrackerTokens.textMutedOf(context);
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: DocuTrackerTokens.surfaceOf(context),
          border: Border(
            top: BorderSide(color: DocuTrackerTokens.borderSubtleOf(context)),
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 560;
            return Row(
              children: [
                Icon(
                  _hasUnsavedChanges
                      ? Icons.edit_note_rounded
                      : Icons.cloud_done_outlined,
                  color: statusColor,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _savedLabel(),
                        key: const ValueKey('permission-save-status'),
                        style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (_hasUnsavedChanges)
                        TextButton(
                          key: const ValueKey('permission-review'),
                          onPressed: _saving || _loading
                              ? null
                              : _reviewChanges,
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(0, 32),
                            foregroundColor: DocuTrackerTokens.brand,
                          ),
                          child: const Text('Review changes'),
                        ),
                    ],
                  ),
                ),
                if (_hasUnsavedChanges) ...[
                  if (compact)
                    IconButton(
                      key: const ValueKey('permission-discard'),
                      tooltip: 'Discard changes',
                      onPressed: _saving ? null : _discardChanges,
                      icon: const Icon(Icons.undo_rounded),
                    )
                  else
                    OutlinedButton(
                      key: const ValueKey('permission-discard'),
                      onPressed: _saving ? null : _discardChanges,
                      style: DocuTrackerTokens.brandOutlinedStyle(
                        context: context,
                      ),
                      child: const Text('Discard changes'),
                    ),
                  const SizedBox(width: 8),
                ],
                FilledButton.icon(
                  key: const ValueKey('permission-save'),
                  onPressed: canSave ? _save : null,
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check_rounded),
                  label: Text(_saving ? 'Saving…' : 'Save changes'),
                  style: DocuTrackerTokens.brandFilledStyle(),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

Color _brandTint(BuildContext context) => DocuTrackerTokens.isDark(context)
    ? DocuTrackerTokens.brand.withValues(alpha: 0.18)
    : DocuTrackerTokens.brandSoftOf(context);

enum _Tone { brand, success, danger, info, neutral }

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.tone, this.icon});

  final String label;
  final _Tone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final dark = DocuTrackerTokens.isDark(context);
    final base = switch (tone) {
      _Tone.brand => DocuTrackerTokens.brand,
      _Tone.success => const Color(0xFF16A34A),
      _Tone.danger => DocuTrackerTokens.overdueAccent,
      _Tone.info => DocuTrackerTokens.escalatedBlue,
      _Tone.neutral => DocuTrackerTokens.textMutedOf(context),
    };
    final foreground = dark && tone != _Tone.neutral
        ? Color.lerp(base, Colors.white, 0.25)!
        : base;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: base.withValues(alpha: dark ? 0.18 : 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: base.withValues(alpha: dark ? 0.40 : 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: foreground),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.3,
                color: foreground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Eyebrow extends StatelessWidget {
  const _Eyebrow(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w800,
      letterSpacing: 1.1,
      color: DocuTrackerTokens.textMutedOf(context),
    ),
  );
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: DocuTrackerTokens.cardDecoration(context: context),
    child: child,
  );
}

class _IconTile extends StatelessWidget {
  const _IconTile({required this.icon, required this.active});

  final IconData icon;
  final bool active;

  @override
  Widget build(BuildContext context) => Container(
    width: 40,
    height: 40,
    decoration: BoxDecoration(
      color: active ? _brandTint(context) : DocuTrackerTokens.canvasOf(context),
      borderRadius: BorderRadius.circular(DocuTrackerTokens.radiusSm),
      border: Border.all(
        color: active
            ? DocuTrackerTokens.brand.withValues(alpha: 0.25)
            : DocuTrackerTokens.borderSubtleOf(context),
      ),
    ),
    child: Icon(
      icon,
      size: 20,
      color: active
          ? DocuTrackerTokens.brand
          : DocuTrackerTokens.textMutedOf(context),
    ),
  );
}

class _ViewTab extends StatelessWidget {
  const _ViewTab({
    required this.icon,
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final int? count;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? DocuTrackerTokens.brand
        : DocuTrackerTokens.textMutedOf(context);
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(4, 10, 4, 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? DocuTrackerTokens.brand : Colors.transparent,
              width: 2.5,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(fontWeight: FontWeight.w700, color: color),
            ),
            if (count != null) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                decoration: BoxDecoration(
                  color: selected
                      ? _brandTint(context)
                      : DocuTrackerTokens.canvasOf(context),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _HierarchyNotice extends StatelessWidget {
  const _HierarchyNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: _brandTint(context),
      borderRadius: BorderRadius.circular(DocuTrackerTokens.radiusMd),
      border: Border.all(
        color: DocuTrackerTokens.brand.withValues(alpha: 0.35),
      ),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.account_tree_outlined,
          color: DocuTrackerTokens.brand,
          size: 20,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Hierarchy notice',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: DocuTrackerTokens.brand,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                message,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: DocuTrackerTokens.textSecondaryOf(context),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _WarningNotice extends StatelessWidget {
  const _WarningNotice({required this.warning});

  final DocuTrackerAccessWarning warning;

  @override
  Widget build(BuildContext context) {
    final caution = warning.level == DocuTrackerAccessWarningLevel.caution;
    final color = DocuTrackerTokens.toneOf(
      context,
      caution ? const Color(0xFFB45309) : DocuTrackerTokens.escalatedBlue,
    );
    return Container(
      key: ValueKey('permission-warning-${warning.code}'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(
          alpha: DocuTrackerTokens.isDark(context) ? 0.16 : 0.08,
        ),
        borderRadius: BorderRadius.circular(DocuTrackerTokens.radiusMd),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            caution ? Icons.warning_amber_rounded : Icons.info_outline_rounded,
            color: color,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              warning.message,
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: DocuTrackerTokens.textSecondaryOf(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({
    required this.title,
    required this.subtitle,
    this.action,
  });

  final String title;
  final String subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
            color: DocuTrackerTokens.textPrimaryOf(context),
          ),
        ),
        const SizedBox(height: 4),
        Text(subtitle, style: DocuTrackerTokens.subtitleStyle(context)),
      ],
    );
    if (action == null) return heading;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 560) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              heading,
              const SizedBox(height: 4),
              Align(alignment: Alignment.centerLeft, child: action),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(child: heading),
            const SizedBox(width: 12),
            action!,
          ],
        );
      },
    );
  }
}

class _OperationRow extends StatelessWidget {
  const _OperationRow({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    this.active = true,
    this.code,
    this.badges = const [],
    this.footnote,
    this.trailing,
    this.trailingWidth,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final bool active;
  final String? code;
  final List<Widget> badges;
  final String? footnote;
  final Widget? trailing;

  /// When set, [trailing] gets this fixed width and wraps below the details
  /// on narrow screens.
  final double? trailingWidth;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final muted = DocuTrackerTokens.textMutedOf(context);
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              title,
              style: DocuTrackerTokens.titleStyle(
                context,
              ).copyWith(fontWeight: FontWeight.w800),
            ),
            ...badges,
          ],
        ),
        if (code != null) ...[
          const SizedBox(height: 4),
          Text(
            code!,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: muted,
            ),
          ),
        ],
        const SizedBox(height: 6),
        Text(description, style: DocuTrackerTokens.subtitleStyle(context)),
        if (footnote != null) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.info_outline_rounded, size: 14, color: muted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  footnote!,
                  style: TextStyle(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: muted,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final stack = trailingWidth != null && constraints.maxWidth < 620;
            final head = Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _IconTile(icon: icon, active: active),
                const SizedBox(width: 14),
                Expanded(child: details),
                if (trailing != null && !stack) ...[
                  const SizedBox(width: 16),
                  trailingWidth == null
                      ? trailing!
                      : SizedBox(width: trailingWidth, child: trailing),
                ],
              ],
            );
            if (!stack) return head;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [head, const SizedBox(height: 12), trailing!],
            );
          },
        ),
      ),
    );
  }
}
