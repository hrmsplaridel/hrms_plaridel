import 'package:flutter/material.dart';

import '../../api/client.dart';
import '../../landingpage/constants/app_theme.dart';
import '../../widgets/rsp_form_header_footer.dart';
import '../docutracker_repository.dart';
import '../docutracker_styles.dart';
import '../models/document_action.dart';
import '../models/document_permission.dart';
import '../models/document_type.dart';

/// Per-user DocuTracker action permission editor.
///
/// This intentionally does *not* allow editing role-based grants.
/// It creates/updates explicit `docutracker_permissions` rows for a single
/// employee (`user_id`) so the UI matches your "per employee" requirement.
class DocuTrackerSetupPermissionsScreen extends StatefulWidget {
  const DocuTrackerSetupPermissionsScreen({
    super.key,
    this.initialUserId,
    this.initialDocumentType,
  });

  final String? initialUserId;
  final String? initialDocumentType;

  @override
  State<DocuTrackerSetupPermissionsScreen> createState() =>
      _DocuTrackerSetupPermissionsScreenState();
}

class _DocuTrackerSetupPermissionsScreenState
    extends State<DocuTrackerSetupPermissionsScreen> {
  final _repo = DocuTrackerRepository.instance;

  static const _restrictionItems = <_RestrictionItem>[
    _RestrictionItem(
      action: DocumentAction.view,
      title: 'Auditing',
      icon: Icons.history_rounded,
    ),
    _RestrictionItem(
      action: DocumentAction.forward,
      title: 'Allocate a job authority',
      icon: Icons.assignment_turned_in_rounded,
    ),
    _RestrictionItem(
      action: DocumentAction.approve,
      title: 'Candidate activation',
      icon: Icons.how_to_vote_rounded,
    ),
    _RestrictionItem(
      action: DocumentAction.edit,
      title: 'Candidate documents',
      icon: Icons.description_rounded,
    ),
    _RestrictionItem(
      action: DocumentAction.download,
      title: 'Financial information',
      icon: Icons.account_balance_wallet_rounded,
    ),
    _RestrictionItem(
      action: DocumentAction.delete,
      title: 'Job posting',
      icon: Icons.post_add_rounded,
    ),
  ];

  final List<_EmployeeOption> _employees = [];
  bool _employeesLoading = true;

  String? _selectedUserId;
  String? _selectedUserRoleId;
  String _selectedDocumentType = '*';

  bool _loading = true;

  // Explicit user rows, used to update/insert only `user_id` permissions.
  Map<String, DocumentPermission> _existingUserPermByActionName = const {};

  // Effective toggle state (uses RBAC precedence) but saved as explicit
  // user-specific grants/denies.
  Map<String, bool> _grantedByActionName = const {};

  @override
  void initState() {
    super.initState();
    _selectedUserId = widget.initialUserId;
    _selectedDocumentType = widget.initialDocumentType ?? '*';
    _init();
  }

  Future<void> _init() async {
    await _loadEmployees();
    await _pickUserIfMissing();
    await _loadPermissions();
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
        ..addAll(data.map((e) {
          final m = e as Map;
          final id = m['id']?.toString() ?? '';
          final fullName = (m['full_name']?.toString() ?? '').isEmpty
              ? 'Unknown'
              : m['full_name'].toString();
          final roleId = m['role']?.toString() ?? 'employee';
          return _EmployeeOption(id: id, fullName: fullName, roleId: roleId);
        }).where((e) => e.id.isNotEmpty));
    } catch (_) {
      _employees.clear();
    }

    if (!mounted) return;
    setState(() => _employeesLoading = false);
  }

  Future<void> _pickUserIfMissing() async {
    if (_selectedUserId != null) return;
    if (_employees.isEmpty) return;

    final first = _employees.first;
    setState(() {
      _selectedUserId = first.id;
      _selectedUserRoleId = first.roleId;
    });
  }

  Future<void> _loadPermissions() async {
    // Avoid reading maps before they're initialized.
    setState(() => _loading = true);

    if (_selectedUserId == null || _selectedUserRoleId == null) {
      setState(() {
        _existingUserPermByActionName = const {};
        _grantedByActionName = const {};
        _loading = false;
      });
      return;
    }

    // 1) Explicit user rows (so Save updates the correct row, if present).
    final explicit = await _repo.listPermissions(
      userId: _selectedUserId,
      documentType: _selectedDocumentType,
    );
    _existingUserPermByActionName = {
      for (final p in explicit) p.action.name: p,
    };

    // 2) Effective grants (for toggle initial state).
    final grantedByAction = <String, bool>{};
    for (final item in _restrictionItems) {
      grantedByAction[item.action.name] = await _repo.hasPermission(
        userId: _selectedUserId!,
        roleId: _selectedUserRoleId,
        documentType: _selectedDocumentType,
        action: item.action.name,
      );
    }
    _grantedByActionName = grantedByAction;

    if (!mounted) return;
    setState(() => _loading = false);
  }

  Future<void> _save() async {
    if (_loading) return;
    if (_selectedUserId == null || _selectedUserRoleId == null) return;

    setState(() => _loading = true);

    for (final item in _restrictionItems) {
      final actionName = item.action.name;
      final desiredGranted = _grantedByActionName[actionName] ?? true;
      final existing = _existingUserPermByActionName[actionName];

      await _repo.savePermission(
        DocumentPermission(
          id: existing?.id,
          roleId: null, // user-only override
          userId: _selectedUserId,
          documentType: _selectedDocumentType,
          action: item.action,
          granted: desiredGranted,
        ),
      );
    }

    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Container(
              decoration: DocuTrackerStyles.listCardDecoration(),
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_rounded),
                        onPressed: _loading
                            ? null
                            : () => Navigator.of(context).pop(false),
                        style: DocuTrackerStyles.iconButtonStyle(),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: _loading
                            ? null
                            : () => Navigator.of(context).pop(false),
                        style: DocuTrackerStyles.iconButtonStyle(),
                      ),
                    ],
                  ),

                  Text(
                    'Setup permissions',
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),

                  RspFormHeader(
                    formTitle: 'User Permissions',
                    subtitle:
                        'Edit explicit permissions for a single employee',
                  ),
                  const SizedBox(height: 12),

                  Text(
                    'Employee',
                    style: TextStyle(
                      color: AppTheme.textSecondary.withOpacity(0.9),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),

                  if (_employeesLoading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 18),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_employees.isEmpty)
                    const Padding(
                      padding:
                          EdgeInsets.symmetric(vertical: 16),
                      child: Text('No employees found.',
                          style: TextStyle(fontSize: 14)),
                    )
                  else
                    DropdownButtonFormField<String>(
                      value: _selectedUserId,
                      decoration:
                          DocuTrackerStyles.dropdownDecoration('Select user'),
                      items: _employees
                          .map(
                            (e) => DropdownMenuItem(
                              value: e.id,
                              child: Text(
                                e.fullName,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) async {
                        if (v == null) return;
                        final pick = _employees.where((e) => e.id == v).firstOrNull;
                        if (pick == null) return;

                        setState(() {
                          _selectedUserId = pick.id;
                          _selectedUserRoleId = pick.roleId;
                          _loading = true;
                        });
                        await _loadPermissions();
                      },
                    ),

                  const SizedBox(height: 14),

                  Text(
                    'Document Type',
                    style: TextStyle(
                      color: AppTheme.textSecondary.withOpacity(0.9),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),

                  DropdownButtonFormField<String>(
                    value: _selectedDocumentType,
                    decoration:
                        DocuTrackerStyles.dropdownDecoration('Select type'),
                    items: [
                      const DropdownMenuItem(value: '*', child: Text('All (*)')),
                      ...DocumentType.values.map(
                        (t) => DropdownMenuItem(
                          value: t.value,
                          child: Text(t.displayName),
                        ),
                      ),
                    ],
                    onChanged: (v) async {
                      if (v == null) return;
                      setState(() {
                        _selectedDocumentType = v;
                        _loading = true;
                      });
                      await _loadPermissions();
                    },
                  ),

                  const SizedBox(height: 18),

                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_selectedUserId == null)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        'Select an employee to edit permissions.',
                        style: TextStyle(fontSize: 14),
                      ),
                    )
                  else
                    ..._restrictionItems.map(
                      (item) => Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.lightGray.withOpacity(0.25),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.black.withOpacity(0.06),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color: AppTheme.primaryNavy.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                item.icon,
                                color: AppTheme.primaryNavy,
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                item.title,
                                style: TextStyle(
                                  color: AppTheme.textPrimary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Switch(
                              value:
                                  _grantedByActionName[item.action.name] ??
                                      true,
                              onChanged: (v) {
                                setState(() {
                                  _grantedByActionName[item.action.name] = v;
                                });
                              },
                              activeTrackColor:
                                  AppTheme.primaryNavy.withOpacity(0.6),
                            ),
                          ],
                        ),
                      ),
                    ),

                  const SizedBox(height: 8),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      FilledButton(
                        onPressed: (_loading || _selectedUserId == null)
                            ? null
                            : _save,
                        style: DocuTrackerStyles.primaryButtonStyle(),
                        child: const Text('Save changes'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RestrictionItem {
  const _RestrictionItem({
    required this.action,
    required this.title,
    required this.icon,
  });

  final DocumentAction action;
  final String title;
  final IconData icon;
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

extension _FirstOrNullExt<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

