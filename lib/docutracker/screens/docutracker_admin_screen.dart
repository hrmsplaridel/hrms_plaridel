import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../api/client.dart';
import '../../landingpage/constants/app_theme.dart';
import '../../widgets/rsp_form_header_footer.dart';
import '../docutracker_provider.dart';
import '../docutracker_repository.dart';
import '../docutracker_styles.dart';
import '../models/document_action.dart';
import '../models/document_permission.dart';
import '../models/document_routing_config.dart';
import '../models/document_type.dart';
import '../models/workflow_step.dart';
import '../security/docutracker_roles.dart';
import '../services/employee_directory_lookup.dart';
import '../widgets/docutracker_responsive_body.dart';
import 'docutracker_workflow_editor_screen.dart';
import 'docutracker_permission_editor_screen.dart';
import 'docutracker_setup_permissions_screen.dart';
import 'docutracker_step_assignees_editor_screen.dart';

/// Admin panel for DocuTracker (Step 4: Admin Privilege Management).
/// Manage per-role or per-user privileges: View, Edit, Download, Delete,
/// Return, Forward, Approve, Reject.
class DocuTrackerAdminScreen extends StatefulWidget {
  const DocuTrackerAdminScreen({super.key});

  @override
  State<DocuTrackerAdminScreen> createState() => _DocuTrackerAdminScreenState();
}

class _DocuTrackerAdminScreenState extends State<DocuTrackerAdminScreen> {
  // Per your request: permissions are edited per employee only.
  String _filterBy = 'user';
  String? _selectedRoleId;
  String? _selectedUserId;
  String? _selectedDocumentType;
  final _searchController = TextEditingController();
  final EmployeeDirectoryLookup _employeeDirectory = EmployeeDirectoryLookup();
  final Map<String, String> _departmentNameById = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadDepartmentNames() async {
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
      if (mounted) setState(() => _departmentNameById..clear()..addAll(map));
    } catch (_) {}
  }

  Future<void> _load() async {
    final provider = context.read<DocuTrackerProvider>();
    await Future.wait([
      provider.loadRoutingConfigs(),
      _employeeDirectory.load(),
      _loadDepartmentNames(),
    ]);
    if (!mounted) return;
    await provider.loadPermissions(
      roleId: null,
      userId: _selectedUserId,
      userOnly: true,
      documentType: _selectedDocumentType,
    );
    if (!mounted) return;
    final ids = provider.permissions.map((p) => p.userId).whereType<String>().toSet();
    await _employeeDirectory.ensureIds(ids);
    if (mounted) setState(() {});
  }

  String _formatPermissionTarget(DocumentPermission p) {
    if (p.roleId != null) return 'Role: ${p.roleId}';
    final uid = p.userId;
    if (uid == null || uid.isEmpty) return '—';
    return _employeeDirectory.formatUserLine(uid);
  }

  /// One row per document type (highest version wins if the API ever returns duplicates).
  List<DocumentRoutingConfig> _routingConfigsForDisplay(DocuTrackerProvider provider) {
    final byType = <String, DocumentRoutingConfig>{};
    for (final c in provider.routingConfigs) {
      final key = c.documentType.value;
      final prev = byType[key];
      if (prev == null || c.version > prev.version) {
        byType[key] = c;
      }
    }
    final out = byType.values.toList()
      ..sort((a, b) => a.documentType.displayName.toLowerCase().compareTo(b.documentType.displayName.toLowerCase()));
    return out;
  }

  Future<void> _createNewWorkflow(BuildContext context, DocuTrackerProvider provider) async {
    final type = await showDialog<DocumentType>(
      context: context,
      builder: (ctx) {
        var selected = DocumentType.values.first;
        return StatefulBuilder(
          builder: (ctx, setModal) {
            return AlertDialog(
              title: const Text('New workflow'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Pick a document type. Add steps in the editor; saving publishes the next workflow version for that type.',
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.3),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<DocumentType>(
                    key: ValueKey<DocumentType>(selected),
                    initialValue: selected,
                    decoration: DocuTrackerStyles.dropdownDecoration('Document type'),
                    items: [
                      for (final t in DocumentType.values)
                        DropdownMenuItem(value: t, child: Text(t.displayName)),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setModal(() => selected = v);
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, selected),
                  child: const Text('Continue'),
                ),
              ],
            );
          },
        );
      },
    );
    if (type == null || !context.mounted) return;
    final configs = _routingConfigsForDisplay(provider);
    DocumentRoutingConfig? existing;
    for (final c in configs) {
      if (c.documentType == type) {
        existing = c;
        break;
      }
    }
    final baseVersion = existing?.version ?? 1;
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => DocuTrackerWorkflowEditorScreen(
          initialConfig: DocumentRoutingConfig(
            documentType: type,
            steps: const [],
            reviewDeadlineHours: 24,
            version: baseVersion,
          ),
        ),
      ),
    );
    if (saved == true && mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DocuTrackerProvider>();
    final isNarrow = MediaQuery.of(context).size.width < 700;

    return DocuTrackerResponsiveBody(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Admin',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Workflows (who moves the document) and permissions (view / create / download) are separate. '
            'Use the workflows card to edit routes or start an additional workflow version.',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 14, height: 1.35),
          ),
          const SizedBox(height: 24),
          isNarrow ? _buildNarrowLayout(provider) : _buildWideLayout(provider),
        ],
      ),
    );
  }

  Widget _buildWideLayout(DocuTrackerProvider provider) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 2, child: _buildLeftPanel(provider)),
        const SizedBox(width: 24),
        SizedBox(width: 280, child: _buildRightPanel(provider)),
      ],
    );
  }

  Widget _buildNarrowLayout(DocuTrackerProvider provider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildLeftPanel(provider),
        const SizedBox(height: 24),
        _buildRightPanel(provider),
      ],
    );
  }

  Widget _buildLeftPanel(DocuTrackerProvider provider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildWorkflowsManagementCard(context, provider),
        const SizedBox(height: 16),
        _buildPermissionsManagementCard(provider),
      ],
    );
  }

  Widget _buildWorkflowsManagementCard(BuildContext context, DocuTrackerProvider provider) {
    final configs = _routingConfigsForDisplay(provider);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: DocuTrackerStyles.listCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.account_tree_rounded, color: AppTheme.primaryNavy, size: 24),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Workflows',
                      style: TextStyle(color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Routes are per document type. Use Edit on a card to change steps; use New workflow to draft another version from scratch.',
                      style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, height: 1.35),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                onPressed: provider.loading ? null : () => _createNewWorkflow(context, provider),
                icon: const Icon(Icons.add_rounded, size: 20),
                label: const Text('New workflow'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (configs.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'No workflow definitions loaded. Tap New workflow to create one, or Refresh if you expect data from the server.',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
              ),
            )
          else
            ...configs.map(
              (config) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _RoutingConfigCard(
                  config: config,
                  employeeDirectory: _employeeDirectory,
                  departmentNameById: _departmentNameById,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPermissionsManagementCard(DocuTrackerProvider provider) {
    final search = _searchController.text.toLowerCase();
    final filtered = provider.permissions.where((p) {
      if (search.isEmpty) return true;
      final target = p.roleId != null
          ? 'role ${p.roleId}'
          : '${p.userId ?? ''} ${_formatPermissionTarget(p)}';
      return target.toLowerCase().contains(search) ||
          p.documentType.toLowerCase().contains(search) ||
          p.action.displayName.toLowerCase().contains(search);
    }).toList();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: DocuTrackerStyles.listCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.description_outlined, color: AppTheme.primaryNavy, size: 24),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Document permissions',
                      style: TextStyle(color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Who may view, create, or download documents by type. Workflow approve/forward rules are managed under Workflows and Step assignees.',
                      style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, height: 1.35),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(width: 200, child: _buildSearchField()),
              _buildFilterDropdown<String>(
                'By User',
                'By User',
                ['By User'],
                (v) {
                  if (v != null) {
                    setState(() {
                      _filterBy = 'user';
                      _selectedRoleId = null;
                      _selectedUserId = null;
                    });
                    _load();
                  }
                },
              ),
              if (_filterBy == 'role')
                SizedBox(
                  width: 140,
                  child: _buildFilterDropdown<String?>(
                    _selectedRoleId == null
                        ? 'All roles'
                        : (_userGroups[_selectedRoleId] ?? _selectedRoleId ?? 'All'),
                    _selectedRoleId,
                    [null, ..._userGroups.keys],
                    (v) {
                      setState(() => _selectedRoleId = v);
                      _load();
                    },
                    labels: ['All roles', ..._userGroups.values],
                  ),
                ),
              if (_filterBy == 'user')
                SizedBox(
                  width: 200,
                  child: TextField(
                    decoration: DocuTrackerStyles.inputDecoration(
                      'User ID (optional)',
                      Icons.person_outline_rounded,
                    ),
                    onChanged: (v) {
                      setState(() => _selectedUserId = v.isEmpty ? null : v);
                      _load();
                    },
                  ),
                ),
              SizedBox(
                width: 140,
                child: _buildFilterDropdown<String?>(
                  _selectedDocumentType == null ? 'All types' : (_selectedDocumentType == '*' ? 'All (*)' : _selectedDocumentType ?? 'All'),
                  _selectedDocumentType,
                  [null, '*', ...DocumentType.values.map((t) => t.value)],
                  (v) {
                    setState(() => _selectedDocumentType = v);
                    _load();
                  },
                  labels: <String>['All types', 'All (*)', ...DocumentType.values.map((t) => t.displayName)],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: AppTheme.lightGray.withOpacity(0.4),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Text('Person / role', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppTheme.textPrimary)),
                ),
                Expanded(child: Text('Document Type', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppTheme.textPrimary))),
                Expanded(child: Text('Action', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppTheme.textPrimary))),
                SizedBox(
                  width: 92,
                  child: Text(
                    'Granted',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppTheme.textPrimary),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (provider.loading)
            const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
          else if (filtered.isEmpty)
            Container(
              constraints: const BoxConstraints(minHeight: 120),
              alignment: Alignment.center,
              child: Text(
                'No permissions yet',
                style: TextStyle(color: AppTheme.textSecondary.withOpacity(0.8), fontSize: 14),
              ),
            )
          else
            ...filtered.map(
              (p) => _PermissionRow(
                permission: p,
                targetLabel: _formatPermissionTarget(p),
                onEdit: () => _openSetupForPermission(p),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    return TextField(
      controller: _searchController,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        hintText: 'Search',
        hintStyle: TextStyle(color: AppTheme.textSecondary.withOpacity(0.8), fontSize: 14),
        prefixIcon: Icon(Icons.search_rounded, size: 20, color: AppTheme.textSecondary.withOpacity(0.7)),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        filled: true,
        fillColor: AppTheme.lightGray.withOpacity(0.5),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
      ),
    );
  }

  Widget _buildFilterDropdown<T>(String displayValue, T? value, List<T> options, ValueChanged<T?> onChanged, {List<String>? labels}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.lightGray.withOpacity(0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.transparent),
      ),
      child: DropdownButton<T>(
        value: value,
        hint: Text(displayValue, style: TextStyle(fontSize: 14, color: AppTheme.textPrimary)),
        underline: const SizedBox.shrink(),
        isDense: true,
        isExpanded: true,
        items: options.asMap().entries.map((e) {
          final label = labels != null && e.key < labels.length ? labels[e.key] : e.value?.toString() ?? 'All';
          return DropdownMenuItem(value: e.value, child: Text(label));
        }).toList(),
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildRightPanel(DocuTrackerProvider provider) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: DocuTrackerStyles.listCardDecoration(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 24),
          CircleAvatar(
            radius: 48,
            backgroundColor: AppTheme.primaryNavy.withOpacity(0.12),
            child: Icon(
              Icons.security_rounded,
              size: 48,
              color: AppTheme.primaryNavy,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'User Permissions',
            style: TextStyle(
              color: AppTheme.textSecondary.withOpacity(0.9),
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const DocuTrackerPermissionEditorScreen(),
                  ),
                );
                if (mounted) _load();
              },
              icon: const Icon(Icons.add_rounded, size: 20),
              label: const Text('Manage Permissions'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF4CAF50),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const DocuTrackerStepAssigneesEditorScreen(),
                  ),
                );
                if (mounted) _load();
              },
              icon: const Icon(Icons.group_rounded, size: 20),
              label: const Text('Manage Step Assignees'),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primaryNavy,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: provider.loading ? null : _load,
              icon: Icon(
                Icons.refresh_rounded,
                size: 20,
                color: provider.loading ? AppTheme.textSecondary.withOpacity(0.5) : AppTheme.textPrimary,
              ),
              label: const Text('Refresh'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.textPrimary,
                side: BorderSide(color: AppTheme.primaryNavy.withOpacity(0.6)),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openSetupForPermission(DocumentPermission permission) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => DocuTrackerSetupPermissionsScreen(
          initialUserId: permission.userId ?? _selectedUserId,
          initialDocumentType: permission.documentType,
        ),
      ),
    );

    if (saved == true && mounted) _load();
  }

  // ignore: unused_element
  void _showAddPermissionDialog(BuildContext context, DocuTrackerProvider provider) {
    DocumentAction action = DocumentAction.view;
    String documentType = '*';
    bool granted = true;
    String? roleId;
    String? userId;

    final size = MediaQuery.of(context).size;
    final dialogWidth = (size.width * 0.5).clamp(420.0, 560.0);
    final dialogHeight = (size.height * 0.55).clamp(400.0, 580.0);

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          clipBehavior: Clip.antiAlias,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: dialogWidth,
              height: dialogHeight,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          RspFormHeader(
                            formTitle: 'Add Permission',
                            subtitle: 'DocuTracker - Municipality of Plaridel',
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  'Action',
                                  style: TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                DropdownButtonFormField<DocumentAction>(
                                  value: action,
                                  decoration: DocuTrackerStyles.dropdownDecoration('Select action'),
                                  items: DocumentAction.values
                                      .map((a) => DropdownMenuItem(
                                            value: a,
                                            child: Text(a.displayName),
                                          ))
                                      .toList(),
                                  onChanged: (v) => v != null ? setState(() => action = v) : null,
                                ),
                                const SizedBox(height: 20),
                                Text(
                                  'Document Type',
                                  style: TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                DropdownButtonFormField<String>(
                                  value: documentType,
                                  decoration: DocuTrackerStyles.dropdownDecoration('Select type'),
                                  items: [
                                    const DropdownMenuItem(value: '*', child: Text('All (*)')),
                                    ...DocumentType.values.map(
                                      (t) => DropdownMenuItem(
                                        value: t.value,
                                        child: Text(t.displayName),
                                      ),
                                    ),
                                  ],
                                  onChanged: (v) => v != null ? setState(() => documentType = v) : null,
                                ),
                                const SizedBox(height: 20),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  decoration: BoxDecoration(
                                    color: AppTheme.offWhite,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Colors.black.withOpacity(0.08)),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'Granted',
                                        style: TextStyle(
                                          color: AppTheme.textPrimary,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      Switch(
                                        value: granted,
                                        onChanged: (v) => setState(() => granted = v),
                                        activeTrackColor: AppTheme.primaryNavy.withOpacity(0.6),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 20),
                                Text(
                                  'Specify Role or User (at least one required)',
                                  style: TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                TextField(
                                  decoration: DocuTrackerStyles.inputDecoration('Role ID (e.g. admin, hr_staff)', Icons.badge_outlined),
                                  onChanged: (v) => roleId = v.trim().isEmpty ? null : v.trim(),
                                ),
                                const SizedBox(height: 16),
                                TextField(
                                  decoration: DocuTrackerStyles.inputDecoration('User ID (optional)', Icons.person_outline_rounded),
                                  onChanged: (v) => userId = v.trim().isEmpty ? null : v.trim(),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      border: Border(top: BorderSide(color: Colors.black.withOpacity(0.06))),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        OutlinedButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          style: DocuTrackerStyles.outlinedButtonStyle(),
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 12),
                        FilledButton(
                          onPressed: () async {
                            if (roleId == null && userId == null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Specify Role ID or User ID')),
                              );
                              return;
                            }
                            final perm = DocumentPermission(
                              roleId: roleId,
                              userId: userId,
                              documentType: documentType,
                              action: action,
                              granted: granted,
                            );
                            await provider.savePermission(perm);
                            if (ctx.mounted) {
                              Navigator.of(ctx).pop();
                              _load();
                            }
                          },
                          style: DocuTrackerStyles.primaryButtonStyle(),
                          child: const Text('Add'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static const _userGroups = <String, String>{
    DocuTrackerRoles.admin: 'Administrator',
    DocuTrackerRoles.hr: 'HR',
    DocuTrackerRoles.supervisor: 'Supervisor',
    DocuTrackerRoles.employee: 'Employee',
  };

  static const _restrictionItems = <_RestrictionItem>[
    _RestrictionItem(
      action: DocumentAction.create,
      title: 'Create documents',
      icon: Icons.add_circle_outline_rounded,
    ),
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

class _UserPermissionsDialog extends StatefulWidget {
  const _UserPermissionsDialog({
    required this.onSaved,
  });

  final Future<void> Function() onSaved;

  @override
  State<_UserPermissionsDialog> createState() => _UserPermissionsDialogState();
}

class _UserPermissionsDialogState extends State<_UserPermissionsDialog> {
  final _repo = DocuTrackerRepository.instance;

  String _selectedRoleId = _DocuTrackerAdminScreenState._userGroups.keys.first;

  bool _loading = true;
  Map<String, DocumentPermission> _existingByActionName = const {};
  late Map<String, bool> _grantedByActionName;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    final perms = <DocumentPermission>[];
    for (final r in DocuTrackerRoles.equivalentsForRead(_selectedRoleId)) {
      perms.addAll(
        await _repo.listPermissions(
          roleId: r,
          documentType: '*',
        ),
      );
    }

    _existingByActionName = {
      for (final p in perms) p.action.name: p,
    };

    _grantedByActionName = {
      for (final item in _DocuTrackerAdminScreenState._restrictionItems)
        item.action.name:
            _existingByActionName[item.action.name]?.granted ?? false,
    };

    if (!mounted) return;
    setState(() => _loading = false);
  }

  Future<void> _save() async {
    setState(() => _loading = true);

    for (final item in _DocuTrackerAdminScreenState._restrictionItems) {
      final actionName = item.action.name;
      final granted = _grantedByActionName[actionName] ?? false;
      final existing = _existingByActionName[actionName];

      if (existing == null) {
        // Strict default-deny: insert explicit allows (and explicit denies if you want them visible).
        if (granted) {
          await _repo.savePermission(
            DocumentPermission(
              roleId: _selectedRoleId,
              userId: null,
              documentType: '*',
              action: item.action,
              granted: true,
            ),
          );
        }
      } else if (existing.granted != granted) {
        await _repo.savePermission(
          DocumentPermission(
            id: existing.id,
            roleId: existing.roleId,
            userId: existing.userId,
            documentType: existing.documentType,
            action: existing.action,
            granted: granted,
          ),
        );
      }
    }

    await widget.onSaved();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final roleLabel = _DocuTrackerAdminScreenState._userGroups[_selectedRoleId] ?? _selectedRoleId;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: (MediaQuery.of(context).size.width * 0.55).clamp(420.0, 560.0),
        height: (MediaQuery.of(context).size.height * 0.62).clamp(440.0, 620.0),
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      RspFormHeader(
                        formTitle: 'User Permissions',
                        subtitle: 'Permission list will change when select user group',
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'User Group',
                        style: TextStyle(
                          color: AppTheme.textSecondary.withOpacity(0.9),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: _selectedRoleId,
                        decoration: DocuTrackerStyles.dropdownDecoration('Select user group'),
                        items: _DocuTrackerAdminScreenState._userGroups.entries
                            .map(
                              (e) => DropdownMenuItem(
                                value: e.key,
                                child: Text(e.value),
                              ),
                            )
                            .toList(),
                        onChanged: (v) async {
                          if (v == null || v == _selectedRoleId) return;
                          setState(() {
                            _selectedRoleId = v;
                            _loading = true;
                          });
                          await _load();
                        },
                      ),
                      const SizedBox(height: 14),
                      Text(
                        roleLabel,
                        style: TextStyle(
                          color: AppTheme.textSecondary.withOpacity(0.8),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 18),
                      if (_loading)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else
                        ..._DocuTrackerAdminScreenState._restrictionItems.map(
                          (item) => Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: AppTheme.lightGray.withOpacity(0.25),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.black.withOpacity(0.06)),
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
                                  value: _grantedByActionName[item.action.name] ?? true,
                                  onChanged: (v) {
                                    setState(() {
                                      _grantedByActionName[item.action.name] = v;
                                    });
                                  },
                                  activeTrackColor: AppTheme.primaryNavy.withOpacity(0.6),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                border: Border(top: BorderSide(color: Colors.black.withOpacity(0.06))),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: _loading ? null : () => Navigator.of(context).pop(),
                    style: DocuTrackerStyles.outlinedButtonStyle(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: _loading ? null : _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF4CAF50),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Save changes'),
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

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({
    required this.permission,
    required this.targetLabel,
    required this.onEdit,
  });

  final DocumentPermission permission;
  final String targetLabel;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              targetLabel,
              style: TextStyle(fontSize: 13, color: AppTheme.textPrimary),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            child: Text(
              permission.documentType,
              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            child: Text(
              permission.action.displayName,
              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(
            width: 92,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(
                  permission.granted ? Icons.check_circle : Icons.cancel,
                  color: permission.granted ? Colors.green : Colors.red,
                  size: 20,
                ),
                IconButton(
                  tooltip: 'Edit this grant set',
                  icon: const Icon(Icons.edit_rounded, size: 20),
                  onPressed: onEdit,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RoutingConfigCard extends StatelessWidget {
  const _RoutingConfigCard({
    required this.config,
    required this.employeeDirectory,
    required this.departmentNameById,
  });

  final DocumentRoutingConfig config;
  final EmployeeDirectoryLookup employeeDirectory;
  final Map<String, String> departmentNameById;

  String _stepChipLabel(WorkflowStep s) {
    final title = (s.label ?? '').trim().isNotEmpty ? s.label!.trim() : 'Step';
    final t = s.assigneeType.trim().toLowerCase();
    switch (t) {
      case 'user':
        final ids = s.userIds?.where((e) => e.trim().isNotEmpty).toList() ?? [];
        if (ids.isNotEmpty) {
          final line = employeeDirectory.formatUserLine(ids.first);
          return '${s.stepOrder}. $title · $line';
        }
        final did = s.departmentId?.trim();
        final dn = (did != null && did.isNotEmpty) ? (departmentNameById[did] ?? did) : null;
        return '${s.stepOrder}. $title · ${dn ?? 'Choose department & people'}';
      case 'department':
        final did = s.departmentId?.trim();
        final dn = (did != null && did.isNotEmpty) ? (departmentNameById[did] ?? did) : '—';
        return '${s.stepOrder}. $title · Dept pool: $dn';
      case 'office':
        return '${s.stepOrder}. $title · Office routing';
      case 'role':
        final r = s.roleId?.trim();
        return '${s.stepOrder}. $title · Role: ${r?.isNotEmpty == true ? r : '—'}';
      default:
        return '${s.stepOrder}. $title';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.lightGray.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                config.documentType.displayName,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '• v${config.version} • ${config.reviewDeadlineHours}h deadline',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Edit workflow',
                icon: const Icon(Icons.edit_rounded, size: 20),
                onPressed: () async {
                  final saved = await Navigator.of(context).push<bool>(
                    MaterialPageRoute<bool>(
                      builder: (_) => DocuTrackerWorkflowEditorScreen(
                        initialConfig: config,
                      ),
                    ),
                  );
                  if (saved == true && context.mounted) {
                    await context.read<DocuTrackerProvider>().loadRoutingConfigs();
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: config.steps
                .map((s) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppTheme.offWhite,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
                      ),
                      child: Text(
                        _stepChipLabel(s),
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.25,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }
}
