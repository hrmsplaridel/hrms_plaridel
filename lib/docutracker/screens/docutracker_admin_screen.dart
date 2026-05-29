import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../api/client.dart';
import '../../landingpage/constants/app_theme.dart';
import '../docutracker_provider.dart';
import '../docutracker_repository.dart';
import '../docutracker_styles.dart';
import '../models/document_action.dart';
import '../models/document_permission.dart';
import '../models/document_routing_config.dart';
import '../models/document_type.dart';
import '../security/docutracker_roles.dart';
import '../services/employee_directory_lookup.dart';
import '../theme/docutracker_tokens.dart';
import '../widgets/docutracker_module_header.dart';
import '../widgets/docutracker_warm_widgets.dart';
import '../widgets/docutracker_admin_ui.dart';
import 'docutracker_escalation_config_screen.dart';
import 'docutracker_workflow_editor_screen.dart';
import 'docutracker_permission_editor_screen.dart';
import 'docutracker_step_assignees_editor_screen.dart';

/// Groups list rows by role/user only (one row per person, all document types combined).
String _permissionGroupKey(DocumentPermission p) =>
    '${p.roleId ?? ''}\x1F${p.userId ?? ''}';

/// Stable order: action name, then document type.
List<DocumentPermission> _sortPermissionsForDisplay(
  List<DocumentPermission> items,
) {
  final out = [...items];
  out.sort((a, b) {
    final byAction = a.action.name.compareTo(b.action.name);
    if (byAction != 0) return byAction;
    final aWild = a.documentType == '*' ? 0 : 1;
    final bWild = b.documentType == '*' ? 0 : 1;
    if (aWild != bWild) return aWild.compareTo(bWild);
    return a.documentType.compareTo(b.documentType);
  });
  return out;
}

/// Admin panel for DocuTracker (Step 4: Admin Privilege Management).
/// Manage per-role or per-user privileges: View, Edit, Download, Delete,
/// Return, Forward, Approve, Reject.
class DocuTrackerAdminScreen extends StatefulWidget {
  const DocuTrackerAdminScreen({
    super.key,
    this.showHeader = false,
    this.contentPadding = EdgeInsets.zero,
  });

  /// Keep false when embedded inside DocuTrackerMain (it already has module header).
  final bool showHeader;

  /// Optional host-level padding when used standalone.
  final EdgeInsetsGeometry contentPadding;

  @override
  State<DocuTrackerAdminScreen> createState() => _DocuTrackerAdminScreenState();
}

class _DocuTrackerAdminScreenState extends State<DocuTrackerAdminScreen> {
  /// Permissions table: filter rows by employee role (null = all).
  String? _permissionsRoleFilter;
  final _searchController = TextEditingController();
  final EmployeeDirectoryLookup _employeeDirectory = EmployeeDirectoryLookup();
  final Map<String, String> _departmentNameById = {};

  /// Narrow layout: 0 = workflows card, 1 = permissions card.
  int _adminTab = 0;
  bool _panelBusy = false;

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
        setState(
          () => _departmentNameById
            ..clear()
            ..addAll(map),
        );
      }
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
      userId: null,
      userOnly: true,
      documentType: null,
    );
    if (!mounted) return;
    final ids = provider.permissions
        .map((p) => p.userId)
        .whereType<String>()
        .toSet();
    await _employeeDirectory.ensureIds(ids);
    if (mounted) setState(() {});
  }

  Future<void> _openAdminTool(Future<void> Function() action) async {
    if (_panelBusy) return;
    setState(() => _panelBusy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _panelBusy = false);
    }
  }

  String _formatPermissionTarget(DocumentPermission p) {
    if (p.roleId != null) return 'Role: ${p.roleId}';
    final uid = p.userId;
    if (uid == null || uid.isEmpty) return '—';
    return _employeeDirectory.formatUserLine(uid);
  }

  /// One row per person/role in a document-type matrix (mockup table).
  List<Widget> _buildGroupedPermissionRows(List<DocumentPermission> filtered) {
    final buckets = <String, List<DocumentPermission>>{};
    for (final p in filtered) {
      buckets.putIfAbsent(_permissionGroupKey(p), () => []).add(p);
    }
    final sortedKeys = buckets.keys.toList()
      ..sort((ka, kb) {
        final aa = buckets[ka]!.first;
        final bb = buckets[kb]!.first;
        return _formatPermissionTarget(
          aa,
        ).toLowerCase().compareTo(_formatPermissionTarget(bb).toLowerCase());
      });

    var columnTypes = permissionMatrixColumnTypes(filtered);
    if (columnTypes.isEmpty) columnTypes = ['*'];

    return sortedKeys.asMap().entries.map((e) {
      final perms = _sortPermissionsForDisplay(buckets[e.value]!);
      final first = perms.first;
      final label = _formatPermissionTarget(first);
      final parts = label.split(' · ');
      final name = parts.first;
      final subtitle = parts.length > 1 ? parts.sublist(1).join(' · ') : null;

      return DocuTrackerPermissionMatrixRow(
        targetLabel: name,
        subtitle: subtitle,
        permissions: perms,
        columnTypes: columnTypes,
        onEdit: () => _openPermissionEditorForRow(first),
        isEven: e.key.isEven,
      );
    }).toList();
  }

  int _groupedPermissionUserCount(List<DocumentPermission> filtered) {
    return filtered.map(_permissionGroupKey).toSet().length;
  }

  /// One row per document type (highest version wins if the API ever returns duplicates).
  List<DocumentRoutingConfig> _routingConfigsForDisplay(
    DocuTrackerProvider provider,
  ) {
    final byType = <String, DocumentRoutingConfig>{};
    for (final c in provider.routingConfigs) {
      final key = c.documentType.value;
      final prev = byType[key];
      if (prev == null || c.version > prev.version) {
        byType[key] = c;
      }
    }
    final out = byType.values.toList()
      ..sort(
        (a, b) => a.documentType.displayName.toLowerCase().compareTo(
          b.documentType.displayName.toLowerCase(),
        ),
      );
    return out;
  }

  Future<void> _createNewWorkflow(
    BuildContext context,
    DocuTrackerProvider provider,
  ) async {
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
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 13,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<DocumentType>(
                    key: ValueKey<DocumentType>(selected),
                    initialValue: selected,
                    decoration: DocuTrackerStyles.dropdownDecoration(
                      context,
                      'Document type',
                    ),
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
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 640;
        return Padding(
          padding: widget.contentPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.showHeader) ...[
                const DocuTrackerModuleHeader(
                  title: 'Admin',
                  subtitle:
                      'Workflows define who routes each step; permissions control view / create / download by document type. '
                      'Use the toggle below to switch between the two.',
                ),
                const SizedBox(height: 16),
              ],
              _buildAdminSectionToggle(),
              const SizedBox(height: 16),
              isNarrow
                  ? _buildNarrowLayout(context, provider)
                  : _buildWideLayout(context, provider),
            ],
          ),
        );
      },
    );
  }

  /// Switch between workflow routing UI and document permission matrix (single focus area).
  Widget _buildAdminSectionToggle() {
    return DocuTrackerWarmSurfaceCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: SizedBox(
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Admin controls',
              style: TextStyle(
                color: DocuTrackerTokens.textPrimaryOf(context),
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              'Switch between routing workflows and access permissions.',
              style: DocuTrackerTokens.subtitleStyle(
                context,
              ).copyWith(fontSize: 11.5),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                DocuTrackerWarmFilterChip(
                  label: 'Workflows',
                  icon: Icons.account_tree_outlined,
                  selected: _adminTab == 0,
                  onTap: () => setState(() => _adminTab = 0),
                ),
                DocuTrackerWarmFilterChip(
                  label: 'Permissions',
                  icon: Icons.lock_outline_rounded,
                  selected: _adminTab == 1,
                  onTap: () => setState(() => _adminTab = 1),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWideLayout(BuildContext context, DocuTrackerProvider provider) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 4,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: KeyedSubtree(
              key: ValueKey<int>(_adminTab),
              child: _adminTab == 0
                  ? _buildWorkflowsManagementCard(context, provider)
                  : _buildPermissionsManagementCard(provider),
            ),
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          flex: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 280, maxWidth: 380),
            child: _HoverLift(
              child: _adminTab == 0
                  ? _buildWorkflowsSidebar(provider)
                  : _buildPermissionsSidebar(provider),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNarrowLayout(
    BuildContext context,
    DocuTrackerProvider provider,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: KeyedSubtree(
            key: ValueKey<int>(_adminTab),
            child: _adminTab == 0
                ? _buildWorkflowsManagementCard(context, provider)
                : _buildPermissionsManagementCard(provider),
          ),
        ),
        const SizedBox(height: 24),
        _HoverLift(
          child: _adminTab == 0
              ? _buildWorkflowsSidebar(provider)
              : _buildPermissionsSidebar(provider),
        ),
      ],
    );
  }

  Widget _buildWorkflowsManagementCard(
    BuildContext context,
    DocuTrackerProvider provider,
  ) {
    final configs = _routingConfigsForDisplay(provider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DocuTrackerAdminSectionHeader(
          title: 'Active Workflows',
          subtitle: 'Manage enterprise routing and approval cycles.',
          trailing: DocuTrackerAdminPrimaryButton(
            label: 'New workflow',
            enabled: !provider.loading,
            onPressed: () => _createNewWorkflow(context, provider),
          ),
        ),
        const SizedBox(height: 20),
        if (provider.loading)
          const Padding(
            padding: EdgeInsets.all(40),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (configs.isEmpty)
          DocuTrackerPeachDashedBox(
            child: Text(
              'No workflow definitions loaded. Tap New workflow to create one.',
              style: DocuTrackerTokens.subtitleStyle(context),
            ),
          )
        else
          ...configs.map(
            (config) => Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: _HoverLift(
                child: DocuTrackerActiveWorkflowCard(
                  config: config,
                  onEdit: () async {
                    final saved = await Navigator.of(context).push<bool>(
                      MaterialPageRoute<bool>(
                        builder: (_) => DocuTrackerWorkflowEditorScreen(
                          initialConfig: config,
                        ),
                      ),
                    );
                    if (saved == true && mounted) await _load();
                  },
                  onMenu: () => _showWorkflowCardMenu(context, config),
                ),
              ),
            ),
          ),
      ],
    );
  }

  void _showWorkflowCardMenu(
    BuildContext context,
    DocumentRoutingConfig config,
  ) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit workflow'),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(
                  MaterialPageRoute<bool>(
                    builder: (_) =>
                        DocuTrackerWorkflowEditorScreen(initialConfig: config),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.group_outlined),
              title: const Text('Step assignees'),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        const DocuTrackerStepAssigneesEditorScreen(),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionsManagementCard(DocuTrackerProvider provider) {
    final search = _searchController.text.toLowerCase();
    var filtered = provider.permissions.where((p) {
      if (_permissionsRoleFilter != null) {
        if (p.roleId != null && p.roleId != _permissionsRoleFilter) {
          return false;
        }
        if (p.userId != null) {
          final roleLine = _employeeDirectory.formatUserLine(p.userId!);
          if (!roleLine.toLowerCase().contains(
            _permissionsRoleFilter!.toLowerCase(),
          )) {
            return false;
          }
        }
      }
      if (search.isEmpty) return true;
      final target = p.roleId != null
          ? 'role ${p.roleId}'
          : '${p.userId ?? ''} ${_formatPermissionTarget(p)}';
      return target.toLowerCase().contains(search) ||
          p.documentType.toLowerCase().contains(search) ||
          p.action.displayName.toLowerCase().contains(search);
    }).toList();

    var columnTypes = permissionMatrixColumnTypes(filtered);
    if (columnTypes.isEmpty && filtered.isNotEmpty) {
      columnTypes = ['*'];
    }
    final userCount = _groupedPermissionUserCount(filtered);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DocuTrackerAdminSectionHeader(
          title: 'Document Permissions',
          subtitle: 'One row per person; columns show access by document type.',
          trailing: DocuTrackerAdminFilterPill(
            label: 'Filter by Role:',
            value: _permissionsRoleFilter,
            options: [null, ..._userGroups.keys],
            optionLabels: ['All Roles', ..._userGroups.values],
            onChanged: (v) => setState(() => _permissionsRoleFilter = v),
          ),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final stackButtons = constraints.maxWidth < 520;
            final search = SizedBox(
              width: stackButtons ? double.infinity : 220,
              child: _buildSearchField(),
            );
            final auditBtn = DocuTrackerAdminTonalButton(
              label: 'Audit Logs',
              icon: Icons.history_rounded,
              onPressed: () => _openAdminTool(() async {
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const DocuTrackerPermissionEditorScreen(),
                  ),
                );
                if (mounted) await _load();
              }),
            );
            final manageBtn = DocuTrackerAdminPrimaryButton(
              label: 'Manage Permissions',
              icon: Icons.shield_outlined,
              enabled: !_panelBusy,
              onPressed: () => _openAdminTool(() async {
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const DocuTrackerPermissionEditorScreen(),
                  ),
                );
                if (mounted) await _load();
              }),
            );

            if (stackButtons) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  search,
                  const SizedBox(height: 10),
                  auditBtn,
                  const SizedBox(height: 8),
                  manageBtn,
                ],
              );
            }

            return Row(
              children: [
                Expanded(child: search),
                const SizedBox(width: 12),
                auditBtn,
                const SizedBox(width: 8),
                manageBtn,
              ],
            );
          },
        ),
        const SizedBox(height: 20),
        DocuTrackerWarmSurfaceCard(
          padding: EdgeInsets.zero,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final minW = 200.0 + columnTypes.length * 110 + 48;
              final useHScroll = constraints.maxWidth < minW + 40;

              Widget tableBlock() {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: DocuTrackerTokens.highlightPeach.withValues(
                          alpha: 0.5,
                        ),
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(DocuTrackerTokens.radiusLg),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Expanded(
                            flex: 2,
                            child: Text(
                              'User / Role',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                                color: DocuTrackerTokens.textSecondary,
                              ),
                            ),
                          ),
                          for (final col in columnTypes)
                            Expanded(
                              flex: 1,
                              child: Text(
                                permissionColumnHeader(col),
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12,
                                  color: DocuTrackerTokens.textSecondary,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          const SizedBox(
                            width: 40,
                            child: Text(
                              'Actions',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                                color: DocuTrackerTokens.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (provider.loading)
                      const Padding(
                        padding: EdgeInsets.all(40),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (filtered.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(32),
                        child: Center(
                          child: Text(
                            'No permissions yet',
                            style: DocuTrackerTokens.subtitleStyle(context),
                          ),
                        ),
                      )
                    else
                      ..._buildGroupedPermissionRows(filtered),
                    if (!provider.loading && filtered.isNotEmpty)
                      _buildPermissionsTableFooter(userCount),
                  ],
                );
              }

              if (!useHScroll) return tableBlock();
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: minW),
                  child: tableBlock(),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPermissionsTableFooter(int userCount) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: DocuTrackerTokens.borderSubtle)),
      ),
      child: Row(
        children: [
          Text(
            'Showing 1–$userCount of $userCount users',
            style: DocuTrackerTokens.metaStyle(context),
          ),
          const Spacer(),
          _PaginationPill(label: '‹', onTap: null),
          const SizedBox(width: 6),
          _PaginationPill(label: '1', selected: true, onTap: null),
          const SizedBox(width: 6),
          _PaginationPill(label: '›', onTap: null),
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
        hintStyle: TextStyle(
          color: AppTheme.textSecondary.withValues(alpha: 0.8),
          fontSize: 14,
        ),
        prefixIcon: Icon(
          Icons.search_rounded,
          size: 20,
          color: AppTheme.textSecondary.withValues(alpha: 0.7),
        ),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        filled: true,
        fillColor: AppTheme.lightGray.withValues(alpha: 0.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _buildPermissionsSidebar(DocuTrackerProvider provider) {
    final totalRules = provider.permissions.length;
    final grantedCount = provider.permissions.where((p) => p.granted).length;
    final deniedCount = totalRules - grantedCount;
    final usagePct = totalRules == 0
        ? 0.0
        : (grantedCount / totalRules).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DocuTrackerAdminSidebarCard(
          title: 'Access Control',
          titleIcon: Icons.shield_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: DocuTrackerAdminStatTile(
                      label: 'Total Rules',
                      value: '$totalRules',
                      color: DocuTrackerTokens.brand,
                      icon: Icons.rule_folder_outlined,
                    ),
                  ),
                  Expanded(
                    child: DocuTrackerAdminStatTile(
                      label: 'Granted',
                      value: '$grantedCount',
                      color: const Color(0xFF4CAF50),
                    ),
                  ),
                  Expanded(
                    child: DocuTrackerAdminStatTile(
                      label: 'Denied',
                      value: '$deniedCount',
                      color: const Color(0xFFE53935),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Usage Health',
                style: DocuTrackerTokens.metaStyle(
                  context,
                ).copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: usagePct,
                  minHeight: 8,
                  backgroundColor: DocuTrackerTokens.borderSubtle,
                  color: DocuTrackerTokens.brand,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                totalRules == 0
                    ? 'No rules loaded yet.'
                    : '${(usagePct * 100).round()}% of rules grant access.',
                style: DocuTrackerTokens.metaStyle(
                  context,
                ).copyWith(fontSize: 11),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        DocuTrackerAdminSidebarCard(
          title: 'Role Hierarchy',
          child: Column(
            children: [
              _RoleHierarchyRow(
                label: 'Super Admin',
                color: DocuTrackerTokens.brand,
              ),
              _RoleHierarchyRow(
                label: 'Department Manager',
                color: const Color(0xFF64B5F6),
              ),
              _RoleHierarchyRow(
                label: 'Standard User',
                color: const Color(0xFFF48FB1),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.open_in_new_rounded, size: 16),
                label: const Text('View Full Schema'),
                style: TextButton.styleFrom(
                  foregroundColor: DocuTrackerTokens.brand,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        DocuTrackerAdminSidebarCard(
          title: 'Security Tip',
          titleIcon: Icons.security_rounded,
          backgroundColor: DocuTrackerTokens.highlightPeach,
          child: Text(
            "Review 'Denied' permissions weekly to ensure orphan access is removed from terminated accounts.",
            style: DocuTrackerTokens.subtitleStyle(
              context,
            ).copyWith(fontSize: 13),
          ),
        ),
      ],
    );
  }

  Widget _buildWorkflowsSidebar(DocuTrackerProvider provider) {
    final configs = _routingConfigsForDisplay(provider);
    final totalSteps = configs.fold<int>(
      0,
      (n, c) => n + c.steps.where((s) => s.enabled).length,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DocuTrackerAdminSidebarCard(
          title: 'Workflow Tools',
          backgroundColor: DocuTrackerTokens.highlightPeach,
          child: Column(
            children: [
              DocuTrackerAdminToolRow(
                icon: Icons.group_outlined,
                label: 'Step Assignees',
                onTap: () => _openAdminTool(() async {
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          const DocuTrackerStepAssigneesEditorScreen(),
                    ),
                  );
                  if (mounted) await _load();
                }),
              ),
              DocuTrackerAdminToolRow(
                icon: Icons.trending_up_rounded,
                label: 'Escalation rules',
                onTap: () => _openAdminTool(() async {
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const DocuTrackerEscalationConfigScreen(),
                    ),
                  );
                }),
              ),
              DocuTrackerAdminToolRow(
                icon: Icons.refresh_rounded,
                label: 'Refresh data',
                onTap: provider.loading || _panelBusy ? () {} : _load,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        DocuTrackerAdminSidebarCard(
          title: 'System Efficiency',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _EfficiencyRow(
                label: 'Active workflows',
                value: '${configs.length}',
                progress: configs.isEmpty ? 0 : 0.75,
              ),
              const SizedBox(height: 12),
              _EfficiencyRow(
                label: 'Configured steps',
                value: '$totalSteps',
                progress: totalSteps == 0 ? 0 : 0.85,
              ),
              const SizedBox(height: 8),
              Text('Throughput', style: DocuTrackerTokens.metaStyle(context)),
              Text(
                configs.length >= 2 ? 'High' : 'Building',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: DocuTrackerTokens.brand,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: DocuTrackerTokens.brandDark,
            borderRadius: BorderRadius.circular(DocuTrackerTokens.radiusLg),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: DocuTrackerTokens.brand,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'PRO TIP',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Define at least one reviewer per step before employees submit documents — routing will fail without assignees.',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _openPermissionEditorForRow(
    DocumentPermission permission,
  ) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => DocuTrackerPermissionEditorScreen(
          initialUserId: permission.userId,
          initialDocumentType: permission.documentType,
          initialTabIsUserOverride: true,
        ),
      ),
    );
    if (mounted) _load();
  }

  static const _userGroups = <String, String>{
    DocuTrackerRoles.admin: 'Administrator',
    DocuTrackerRoles.hr: 'HR',
    DocuTrackerRoles.supervisor: 'Supervisor',
    DocuTrackerRoles.employee: 'Employee',
  };

  static const _restrictionItems = <_RestrictionItem>[
    _RestrictionItem(
      action: DocumentAction.createDraft,
      title: 'Create drafts',
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
  const _UserPermissionsDialog({required this.onSaved});

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
      perms.addAll(await _repo.listPermissions(roleId: r, documentType: '*'));
    }

    _existingByActionName = {for (final p in perms) p.action.name: p};

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
    final roleLabel =
        _DocuTrackerAdminScreenState._userGroups[_selectedRoleId] ??
        _selectedRoleId;

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
                      Container(
                        padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border(
                            bottom: BorderSide(
                              color: Colors.black.withValues(alpha: 0.06),
                            ),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'User permissions',
                              style: TextStyle(
                                color: AppTheme.textPrimary,
                                fontSize: 19,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Permission toggles update based on the selected user group.',
                              style: TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 12,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'User Group',
                        style: TextStyle(
                          color: AppTheme.textSecondary.withValues(alpha: 0.9),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue: _selectedRoleId,
                        decoration: DocuTrackerStyles.dropdownDecoration(
                          context,
                          'Select user group',
                        ),
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
                          color: AppTheme.textSecondary.withValues(alpha: 0.8),
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
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.lightGray.withValues(alpha: 0.25),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.black.withValues(alpha: 0.06),
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 34,
                                  height: 34,
                                  decoration: BoxDecoration(
                                    color: DocuTrackerTokens.terracotta
                                        .withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    item.icon,
                                    color: DocuTrackerTokens.terracotta,
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
                                      _grantedByActionName[item.action.name] =
                                          v;
                                    });
                                  },
                                  activeTrackColor: DocuTrackerTokens.terracotta
                                      .withValues(alpha: 0.6),
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
                border: Border(
                  top: BorderSide(color: Colors.black.withValues(alpha: 0.06)),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: _loading
                        ? null
                        : () => Navigator.of(context).pop(),
                    style: DocuTrackerStyles.outlinedButtonStyle(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: _loading ? null : _save,
                    style: DocuTrackerTokens.terracottaFilledStyle().copyWith(
                      padding: WidgetStateProperty.all(
                        const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 12,
                        ),
                      ),
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

class _HoverLift extends StatefulWidget {
  const _HoverLift({required this.child});

  final Widget child;

  @override
  State<_HoverLift> createState() => _HoverLiftState();
}

class _HoverLiftState extends State<_HoverLift> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: AnimatedScale(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        scale: _hovering ? 1.01 : 1.0,
        child: widget.child,
      ),
    );
  }
}

class _PaginationPill extends StatelessWidget {
  const _PaginationPill({
    required this.label,
    this.selected = false,
    this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? DocuTrackerTokens.brand : DocuTrackerTokens.surface,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: selected
                ? null
                : Border.all(color: DocuTrackerTokens.borderSubtle),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : DocuTrackerTokens.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

class _RoleHierarchyRow extends StatelessWidget {
  const _RoleHierarchyRow({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 28,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: DocuTrackerTokens.textPrimaryOf(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _EfficiencyRow extends StatelessWidget {
  const _EfficiencyRow({
    required this.label,
    required this.value,
    required this.progress,
  });

  final String label;
  final String value;
  final double progress;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: DocuTrackerTokens.metaStyle(context)),
            Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: DocuTrackerTokens.textPrimaryOf(context),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 6,
            backgroundColor: DocuTrackerTokens.borderSubtle,
            color: DocuTrackerTokens.brand,
          ),
        ),
      ],
    );
  }
}
