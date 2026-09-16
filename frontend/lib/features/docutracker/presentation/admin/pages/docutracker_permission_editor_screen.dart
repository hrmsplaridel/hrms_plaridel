import 'package:flutter/material.dart';

import 'package:hrms_plaridel/features/docutracker/data/repositories/docutracker_repository.dart';
import 'package:hrms_plaridel/features/docutracker/data/styles/docutracker_styles.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_routing_config.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_type.dart';
import 'package:hrms_plaridel/features/docutracker/models/docutracker_permission_policy.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/admin/pages/docutracker_governance_audit_screen.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/widgets/docutracker_error_banner.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/widgets/docutracker_responsive_body.dart';
import 'package:hrms_plaridel/features/docutracker/security/docutracker_roles.dart';
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
    'Download files from documents the employee can already access.',
    Icons.download_outlined,
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
  final _directory = EmployeeDirectoryLookup();
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

  static const _roleOrder = <String>[
    DocuTrackerRoles.admin,
    DocuTrackerRoles.hr,
    DocuTrackerRoles.supervisor,
    DocuTrackerRoles.employee,
  ];

  @override
  void initState() {
    super.initState();
    _view = widget.initialTabIsUserOverride
        ? _AccessView.employeeExceptions
        : _AccessView.roleDefaults;
    _documentType = widget.initialDocumentType?.trim().isNotEmpty == true
        ? widget.initialDocumentType!.trim()
        : '*';
    _documentTypes = {'*', _documentType}.toList();
    _selectedUserId = widget.initialUserId;
    _initialise();
  }

  @override
  void dispose() {
    _employeeSearchController.dispose();
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
    await _directory.load();
    if (_selectedUserId != null) {
      await _directory.ensureIds({_selectedUserId!});
    }

    List<DocumentRoutingConfig> configs = const [];
    try {
      configs = await _repository.getRoutingConfigs();
    } catch (_) {}
    final types =
        <String>{
          '*',
          ...DocumentType.values.map((type) => type.value),
          ...configs.map((config) => config.documentType.value),
          _documentType,
        }.toList()..sort((a, b) {
          if (a == '*') return -1;
          if (b == '*') return 1;
          return _documentTypeLabel(a).compareTo(_documentTypeLabel(b));
        });
    if (!mounted) return;
    setState(() => _documentTypes = types);
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
                        ? 'These role defaults will be blocked. Document-specific settings and employee exceptions stay in place.'
                        : 'These roles will use their All document types settings. Access is blocked if no setting exists. Employee exceptions stay in place.'
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
          surfaceTintColor: Colors.transparent,
          leading: IconButton(
            tooltip: 'Back',
            onPressed: _saving ? null : _goBack,
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          title: const Text('System Access'),
          actions: [
            PopupMenuButton<String>(
              tooltip: 'More',
              enabled: !_saving,
              onSelected: (value) async {
                switch (value) {
                  case 'audit':
                    await Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            const DocuTrackerGovernanceAuditScreen(),
                      ),
                    );
                  case 'refresh':
                    await _refresh();
                  case 'reset':
                    await _resetCurrentView();
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'audit', child: Text('Audit log')),
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
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildTopControls(),
              if (_error != null) ...[
                const SizedBox(height: 12),
                DocuTrackerErrorBanner(
                  message: _error!,
                  onDismiss: () => setState(() => _error = null),
                ),
              ],
              const SizedBox(height: 12),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : SingleChildScrollView(
                        padding: const EdgeInsets.only(bottom: 24),
                        child: _view == _AccessView.roleDefaults
                            ? _buildRoleDefaults()
                            : _buildEmployeeExceptions(),
                      ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: _buildSaveBar(),
      ),
    );
  }

  Widget _buildTopControls() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final switcher = SegmentedButton<_AccessView>(
          key: const ValueKey('system-access-view-selector'),
          segments: const [
            ButtonSegment(
              value: _AccessView.roleDefaults,
              icon: Icon(Icons.groups_outlined),
              label: Text('Role access'),
            ),
            ButtonSegment(
              value: _AccessView.employeeExceptions,
              icon: Icon(Icons.person_outline_rounded),
              label: Text('Employee exceptions'),
            ),
          ],
          selected: {_view},
          showSelectedIcon: false,
          onSelectionChanged: _saving
              ? null
              : (selection) => setState(() => _view = selection.first),
        );
        final type = DropdownButtonFormField<String>(
          key: ValueKey('permission-document-type-$_documentType'),
          initialValue: _documentType,
          isExpanded: true,
          decoration: DocuTrackerStyles.dropdownDecoration(
            context,
            'Document type',
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

        if (constraints.maxWidth < 720) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: switcher,
              ),
              const SizedBox(height: 12),
              type,
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: switcher),
            const SizedBox(width: 16),
            SizedBox(width: 260, child: type),
          ],
        );
      },
    );
  }

  Widget _buildRoleDefaults() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Access by role',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(
          'Applies to everyone with this role, unless they have an employee exception.',
          style: DocuTrackerTokens.subtitleStyle(context),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          key: const ValueKey('permission-role-selector'),
          initialValue: _selectedRole,
          isExpanded: true,
          decoration: DocuTrackerStyles.dropdownDecoration(context, 'Role'),
          items: _roleOrder
              .map(
                (role) => DropdownMenuItem(
                  value: role,
                  child: Text(_roleLabel(role)),
                ),
              )
              .toList(),
          onChanged: _saving
              ? null
              : (role) {
                  if (role != null) setState(() => _selectedRole = role);
                },
        ),
        const SizedBox(height: 12),
        _buildRoleCard(_selectedRole),
      ],
    );
  }

  Widget _buildRoleCard(String roleId) {
    final isAdmin = roleId == DocuTrackerRoles.admin;
    final rolePolicy = _policy?.roleDefaults
        .where((role) => role.roleId == roleId)
        .firstOrNull;
    return Container(
      key: ValueKey('permission-role-$roleId'),
      decoration: DocuTrackerTokens.cardDecoration(context: context),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              title: Text(
                '${_roleLabel(roleId)} access',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text(
                _documentType == '*'
                    ? 'Default for all document types'
                    : 'Applies to ${_documentTypeLabel(_documentType)} only',
              ),
            ),
            if (isAdmin)
              const ListTile(
                leading: Icon(Icons.verified_user_outlined),
                title: Text('Administrator access is always enabled.'),
                subtitle: Text(
                  'Workflow approvals still require assignment to the current step.',
                ),
              )
            else
              for (final action in _accessActions)
                SwitchListTile(
                  key: ValueKey('permission-role-$roleId-${action.key}'),
                  secondary: Icon(action.icon),
                  title: Text(action.label),
                  subtitle: Text(
                    _roleSettingSubtitle(
                      rolePolicy?.permissions[action.key]?.source,
                      action.description,
                      roleId,
                      action.key,
                    ),
                  ),
                  value: _roleDraft[roleId]?[action.key] ?? false,
                  onChanged: _saving
                      ? null
                      : (value) => setState(() {
                          _roleDraft[roleId]?[action.key] = value;
                        }),
                ),
          ],
        ),
      ),
    );
  }

  String _roleSettingSubtitle(
    String? source,
    String description,
    String roleId,
    String action,
  ) {
    final allowed = _roleDraft[roleId]?[action] ?? false;
    final changed = allowed != (_roleBaseline[roleId]?[action] ?? false);
    final status = allowed ? 'Allowed' : 'Blocked';
    if (changed) return '$status (unsaved). $description';
    final sourceLabel = switch (source) {
      'all_document_types' when _documentType != '*' =>
        'From All document types',
      'not_configured' => 'No access granted',
      _ => null,
    };
    return sourceLabel == null
        ? '$status. $description'
        : '$status · $sourceLabel. $description';
  }

  List<EmployeeDirectoryEntry> _filteredEmployees() {
    final query = _employeeSearchController.text.trim().toLowerCase();
    final rows = _directory.entries.where((employee) {
      if (query.isEmpty) return true;
      return [
        employee.fullName,
        employee.departmentName,
        employee.positionName,
        employee.roleId,
      ].whereType<String>().any((value) => value.toLowerCase().contains(query));
    }).toList();
    return rows.take(12).toList(growable: false);
  }

  Widget _buildEmployeeExceptions() {
    final selected = _selectedUserId == null
        ? null
        : _directory[_selectedUserId!];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Employee Exceptions',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(
          'Only use an exception when this employee needs different access from their role.',
          style: DocuTrackerTokens.subtitleStyle(context),
        ),
        const SizedBox(height: 16),
        TextField(
          key: const ValueKey('permission-employee-search'),
          controller: _employeeSearchController,
          enabled: !_saving,
          decoration: DocuTrackerTokens.warmSearchDecoration(
            context,
            'Search employee, department, position, or role',
          ),
          onChanged: (_) => setState(() {}),
        ),
        if (_employeeSearchController.text.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            constraints: const BoxConstraints(maxHeight: 300),
            decoration: DocuTrackerTokens.cardDecoration(context: context),
            child: _filteredEmployees().isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('No matching active employees.'),
                  )
                : Material(
                    type: MaterialType.transparency,
                    child: ListView(
                      shrinkWrap: true,
                      children: _filteredEmployees()
                          .map(
                            (employee) => ListTile(
                              title: Text(employee.fullName),
                              subtitle: Text(_employeeDetails(employee)),
                              onTap: () => _selectEmployee(employee.id),
                            ),
                          )
                          .toList(),
                    ),
                  ),
          ),
        ],
        const SizedBox(height: 12),
        if (_selectedUserId == null)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: DocuTrackerTokens.cardDecoration(context: context),
            child: const Center(
              child: Text(
                'Search and select an employee to review exceptions.',
              ),
            ),
          )
        else ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: DocuTrackerTokens.cardDecoration(context: context),
            child: Row(
              children: [
                const CircleAvatar(child: Icon(Icons.person_outline_rounded)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        selected?.fullName ??
                            _policy?.selectedUser?.fullName ??
                            'Selected employee',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        selected == null
                            ? _roleLabel(
                                _policy?.selectedUser?.roleId ?? 'employee',
                              )
                            : _employeeDetails(selected),
                        style: DocuTrackerTokens.subtitleStyle(context),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: _saving ? null : _clearSelectedEmployee,
                  child: const Text('Change'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          for (final action in _accessActions) _buildEmployeeAction(action),
        ],
      ],
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
    final effective = _effectiveDecision(action.key);
    return Container(
      key: ValueKey('permission-user-${action.key}'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: DocuTrackerTokens.cardDecoration(context: context),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final heading = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(action.icon, color: DocuTrackerTokens.brand),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      action.label,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      action.description,
                      style: DocuTrackerTokens.subtitleStyle(context),
                    ),
                  ],
                ),
              ),
            ],
          );
          final selector = DropdownButtonFormField<_EmployeeDecision>(
            key: ValueKey('permission-user-decision-${action.key}-$decision'),
            initialValue: decision,
            isExpanded: true,
            decoration: DocuTrackerStyles.dropdownDecoration(context, 'Access'),
            items: [
              DropdownMenuItem(
                value: _EmployeeDecision.inherit,
                child: Text(
                  _documentType == '*'
                      ? 'Use role default'
                      : 'Use broader setting',
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
          final badge = Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: effective.$1
                  ? DocuTrackerTokens.brandSoft
                  : DocuTrackerTokens.surfaceCream,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: DocuTrackerTokens.borderSubtle),
            ),
            child: Text(
              '${effective.$1 ? 'Allowed' : 'Blocked'} · ${effective.$2}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          );
          if (constraints.maxWidth < 620) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                heading,
                const SizedBox(height: 12),
                selector,
                const SizedBox(height: 10),
                Align(alignment: Alignment.centerLeft, child: badge),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: heading),
              const SizedBox(width: 16),
              SizedBox(width: 220, child: selector),
              const SizedBox(width: 12),
              badge,
            ],
          );
        },
      ),
    );
  }

  (bool, String) _effectiveDecision(String action) {
    final direct = _overrideDraft[action];
    if (direct != null) return (direct, 'Employee exception');
    final inherited = _policy?.inheritedUserOverrides[action];
    if (inherited != null) {
      return (inherited, 'All document types exception');
    }
    final role = DocuTrackerRoles.normalize(
      _policy?.selectedUser?.roleId ??
          _directory[_selectedUserId ?? '']?.roleId,
    );
    if (role == DocuTrackerRoles.admin) return (true, 'Administrator');
    return (_roleDraft[role]?[action] ?? false, 'Role default');
  }

  Widget _buildSaveBar() {
    final canSave = _hasUnsavedChanges && !_saving && !_loading;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: DocuTrackerTokens.surfaceOf(context),
          border: Border(
            top: BorderSide(color: DocuTrackerTokens.borderSubtle),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _savedLabel(),
                    key: const ValueKey('permission-save-status'),
                    style: TextStyle(
                      color: _hasUnsavedChanges
                          ? DocuTrackerTokens.brand
                          : DocuTrackerTokens.textMuted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (_hasUnsavedChanges)
                    TextButton(
                      key: const ValueKey('permission-review'),
                      onPressed: _saving || _loading ? null : _reviewChanges,
                      child: const Text('Review changes'),
                    ),
                ],
              ),
            ),
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
        ),
      ),
    );
  }
}
