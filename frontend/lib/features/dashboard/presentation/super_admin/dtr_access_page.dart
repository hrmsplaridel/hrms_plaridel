import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/core/api/user_facing_api_error.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';

class DtrAccessPage extends StatefulWidget {
  const DtrAccessPage({super.key});

  @override
  State<DtrAccessPage> createState() => DtrAccessPageState();
}

class DtrAccessPageState extends State<DtrAccessPage> {
  /// Existing DTR feature labels — do not rename keys (API contract).
  static const _permissions = {
    'reports_allowed': 'View DTR reports',
    'manage_allowed': 'Manage DTR logs',
    'employees_allowed': 'Employee profiles',
    'leave_allowed': 'Leave management',
    'approvals_allowed': 'Approvals & signatories',
    'locator_allowed': 'Locator slip management',
  };

  /// All RSP API fields (includes parent toggles kept in sync from children).
  static const _rspPermissions = {
    'vacancies_allowed': 'Job vacancies',
    'exams_allowed': 'Exams',
    'recruitment_allowed': 'Recruitment management',
    'applications_allowed': 'Applications',
    'exam_results_allowed': 'Exam Results',
    'scheduling_allowed': 'Scheduling',
    'final_requirements_allowed': 'Final Requirements',
    'forms_allowed': 'Forms',
    'form_bi_allowed': 'Background Investigation (BI Form)',
    'form_applicants_profile_allowed': 'Applicants Profile',
    'form_selection_lineup_allowed': 'Selection Line-Up',
    'form_computation_of_points_allowed': 'Computation of Points',
    'form_work_experience_allowed': 'Work Experience Sheet',
    'form_turn_around_time_allowed': 'Turn Around Time',
    'form_ojt_allowed': 'OJT / Work Immersion Evaluation',
  };

  static const _rspRecruitmentFields = [
    'applications_allowed',
    'exam_results_allowed',
    'scheduling_allowed',
    'final_requirements_allowed',
  ];

  static const _rspFormFields = [
    'form_bi_allowed',
    'form_applicants_profile_allowed',
    'form_selection_lineup_allowed',
    'form_computation_of_points_allowed',
    'form_work_experience_allowed',
    'form_turn_around_time_allowed',
    'form_ojt_allowed',
  ];

  static const _rspPermissionGroups = <({String? title, Map<String, String> items})>[
    (
      title: null,
      items: {
        'vacancies_allowed': 'Job vacancies',
        'exams_allowed': 'Exams',
      },
    ),
    (
      title: 'Recruitment Management',
      items: {
        'applications_allowed': 'Applications',
        'exam_results_allowed': 'Exam Results',
        'scheduling_allowed': 'Scheduling',
        'final_requirements_allowed': 'Final Requirements',
      },
    ),
    (
      title: 'Forms',
      items: {
        'form_bi_allowed': 'Background Investigation (BI Form)',
        'form_applicants_profile_allowed': 'Applicants Profile',
        'form_selection_lineup_allowed': 'Selection Line-Up',
        'form_computation_of_points_allowed': 'Computation of Points',
        'form_work_experience_allowed': 'Work Experience Sheet',
        'form_turn_around_time_allowed': 'Turn Around Time',
        'form_ojt_allowed': 'OJT / Work Immersion Evaluation',
      },
    ),
  ];

  static const _ldPermissions = {
    'forms_allowed': 'Forms',
    'daily_reports_allowed': 'Training daily reports',
    'requirements_allowed': 'Training requirements',
    'form_tna_allowed': 'Training Need Analysis',
    'form_action_brainstorming_allowed': 'Action Brainstorming Worksheet',
    'form_idp_allowed': 'Individual Development Plan (IDP)',
    'form_lap_allowed': 'Learning Application Plan',
  };

  static const _ldFormFields = [
    'form_tna_allowed',
    'form_action_brainstorming_allowed',
    'form_idp_allowed',
    'form_lap_allowed',
  ];

  static const _ldPermissionGroups = <({String? title, Map<String, String> items})>[
    (
      title: null,
      items: {
        'daily_reports_allowed': 'Training daily reports',
        'requirements_allowed': 'Training requirements',
      },
    ),
    (
      title: 'Forms',
      items: {
        'form_tna_allowed': 'Training Need Analysis',
        'form_action_brainstorming_allowed': 'Action Brainstorming Worksheet',
        'form_idp_allowed': 'Individual Development Plan (IDP)',
        'form_lap_allowed': 'Learning Application Plan',
      },
    ),
  ];

  List<Map<String, dynamic>> _admins = [];
  Map<String, bool> _accountAccess = {};
  final Map<String, Map<String, dynamic>> _rspAccess = {};
  final Map<String, Map<String, dynamic>> _ldAccess = {};
  final Map<String, Map<String, bool>> _drafts = {};
  final Map<String, Map<String, bool>> _rspDrafts = {};
  final Map<String, Map<String, bool>> _ldDrafts = {};
  final Set<String> _saving = {};
  final Set<String> _accountSaving = {};
  bool _loading = true;
  String? _error;
  bool _confirmingLeave = false;
  bool _allowPop = false;

  Future<bool> confirmLeave() async {
    if (_confirmingLeave) return false;
    if (_saving.isNotEmpty || _accountSaving.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please wait for the permission save to finish.'),
        ),
      );
      return false;
    }
    if (!_admins.any(_isAnyDirty)) return true;
    _confirmingLeave = true;
    try {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Discard unsaved changes?'),
          content: const Text(
            'Leaving will discard permission changes that have not been saved.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep editing'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Discard and leave'),
            ),
          ],
        ),
      );
      return mounted && discard == true;
    } finally {
      _confirmingLeave = false;
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Map<String, bool> _accessOf(Map<String, dynamic> admin) => {
    for (final field in _permissions.keys) field: admin[field] == true,
  };

  Map<String, bool> _moduleAccessOf(
    Map<String, dynamic>? row,
    Map<String, String> labels,
  ) => {for (final field in labels.keys) field: row?[field] == true};

  bool _isDtrDirty(Map<String, dynamic> admin) {
    final draft = _drafts[admin['id'].toString()];
    return draft != null &&
        _permissions.keys.any(
          (field) => draft[field] != (admin[field] == true),
        );
  }

  bool _isModuleDirty({
    required String id,
    required Map<String, Map<String, bool>> drafts,
    required Map<String, Map<String, dynamic>> stored,
    required Map<String, String> labels,
  }) {
    final draft = drafts[id];
    if (draft == null) return false;
    final row = stored[id];
    return labels.keys.any((field) => draft[field] != (row?[field] == true));
  }

  bool _isRspDirty(String id) => _isModuleDirty(
    id: id,
    drafts: _rspDrafts,
    stored: _rspAccess,
    labels: _rspPermissions,
  );

  bool _isLdDirty(String id) => _isModuleDirty(
    id: id,
    drafts: _ldDrafts,
    stored: _ldAccess,
    labels: _ldPermissions,
  );

  bool _isAnyDirty(Map<String, dynamic> admin) {
    final id = admin['id'].toString();
    return _isDtrDirty(admin) || _isRspDirty(id) || _isLdDirty(id);
  }

  Future<void> _load({bool confirmDiscard = false}) async {
    if (confirmDiscard && _admins.any(_isAnyDirty)) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Discard unsaved changes?'),
          content: const Text(
            'Refreshing will discard permission changes that have not been saved.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep editing'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Discard and refresh'),
            ),
          ],
        ),
      );
      if (discard != true || !mounted) return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await ApiClient.instance.get<Map<String, dynamic>>(
        '/api/dtr-access',
      );
      final accountResponse = await ApiClient.instance
          .get<Map<String, dynamic>>('/api/account-creation-access');
      final rspResponse = await ApiClient.instance.get<Map<String, dynamic>>(
        '/api/rsp-access',
      );
      final ldResponse = await ApiClient.instance.get<Map<String, dynamic>>(
        '/api/ld-access',
      );
      if (!mounted) return;
      setState(() {
        _admins = (response.data?['admins'] as List? ?? [])
            .map((value) => Map<String, dynamic>.from(value as Map))
            .toList();
        _accountAccess = {
          for (final row in accountResponse.data?['admins'] as List? ?? [])
            (row as Map)['id'].toString(): row['allowed'] == true,
        };
        _rspAccess
          ..clear()
          ..addAll({
            for (final row in rspResponse.data?['admins'] as List? ?? [])
              (row as Map)['id'].toString(): Map<String, dynamic>.from(row),
          });
        _ldAccess
          ..clear()
          ..addAll({
            for (final row in ldResponse.data?['admins'] as List? ?? [])
              (row as Map)['id'].toString(): Map<String, dynamic>.from(row),
          });
        _drafts.clear();
        _rspDrafts.clear();
        _ldDrafts.clear();
      });
    } catch (error) {
      if (mounted) setState(() => _error = userFacingApiError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _setAccountAccess(
    Map<String, dynamic> admin,
    bool allowed,
  ) async {
    final id = admin['id'].toString();
    if (_accountSaving.contains(id)) return;
    setState(() => _accountSaving.add(id));
    try {
      await ApiClient.instance.put<Map<String, dynamic>>(
        '/api/account-creation-access/$id',
        data: {'allowed': allowed},
      );
      if (!mounted) return;
      setState(() => _accountAccess[id] = allowed);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Account creation ${allowed ? 'enabled' : 'disabled'} for ${admin['full_name'] ?? admin['email']}.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(userFacingApiError(error))));
    } finally {
      if (mounted) setState(() => _accountSaving.remove(id));
    }
  }

  Future<bool> _saveDtr(Map<String, dynamic> admin) async {
    final id = admin['id'].toString();
    if (!_isDtrDirty(admin)) return true;
    final permissions = Map<String, bool>.from(_drafts[id]!);
    try {
      final response = await ApiClient.instance.put<Map<String, dynamic>>(
        '/api/dtr-access/$id',
        data: {...permissions, 'expected_revision': admin['revision']},
      );
      if (!mounted) return false;
      setState(() {
        admin.addAll(permissions);
        admin['revision'] = response.data?['revision'];
        _drafts.remove(id);
      });
      return true;
    } catch (error) {
      if (mounted) {
        final body = error is DioException ? error.response?.data : null;
        final conflict = body is Map && body['code'] == 'DTR_ACCESS_CONFLICT';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(userFacingApiError(error)),
            duration: conflict
                ? const Duration(seconds: 10)
                : const Duration(seconds: 4),
            action: conflict
                ? SnackBarAction(
                    label: 'Refresh',
                    onPressed: () => _load(confirmDiscard: true),
                  )
                : null,
          ),
        );
      }
      return false;
    }
  }

  Map<String, bool> _withDerivedModuleParents(
    Map<String, bool> permissions, {
    required bool rsp,
  }) {
    final next = Map<String, bool>.from(permissions);
    if (rsp) {
      next['recruitment_allowed'] =
          _rspRecruitmentFields.any((field) => next[field] == true);
      next['forms_allowed'] =
          _rspFormFields.any((field) => next[field] == true);
    } else {
      next['forms_allowed'] =
          _ldFormFields.any((field) => next[field] == true);
    }
    return next;
  }

  Future<bool> _saveModule({
    required String id,
    required String apiPath,
    required Map<String, Map<String, bool>> drafts,
    required Map<String, Map<String, dynamic>> stored,
    required Map<String, String> labels,
    required String conflictCode,
    required String successLabel,
    required bool rsp,
  }) async {
    if (!_isModuleDirty(
      id: id,
      drafts: drafts,
      stored: stored,
      labels: labels,
    )) {
      return true;
    }
    final permissions = _withDerivedModuleParents(
      Map<String, bool>.from(drafts[id]!),
      rsp: rsp,
    );
    final revision = stored[id]?['revision'] ?? 'none';
    try {
      final response = await ApiClient.instance.put<Map<String, dynamic>>(
        '$apiPath/$id',
        data: {...permissions, 'expected_revision': revision},
      );
      if (!mounted) return false;
      setState(() {
        final row = Map<String, dynamic>.from(stored[id] ?? {'id': id});
        row.addAll(permissions);
        row['revision'] = response.data?['revision'];
        stored[id] = row;
        drafts.remove(id);
      });
      return true;
    } catch (error) {
      if (mounted) {
        final body = error is DioException ? error.response?.data : null;
        final conflict = body is Map && body['code'] == conflictCode;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(userFacingApiError(error)),
            duration: conflict
                ? const Duration(seconds: 10)
                : const Duration(seconds: 4),
            action: conflict
                ? SnackBarAction(
                    label: 'Refresh',
                    onPressed: () => _load(confirmDiscard: true),
                  )
                : null,
          ),
        );
      }
      return false;
    }
  }

  Future<void> _save(Map<String, dynamic> admin) async {
    final id = admin['id'].toString();
    if (_saving.contains(id) || !_isAnyDirty(admin)) return;
    setState(() => _saving.add(id));
    try {
      final savedParts = <String>[];
      if (_isDtrDirty(admin)) {
        if (!await _saveDtr(admin)) return;
        savedParts.add('DTR');
      }
      if (_isRspDirty(id)) {
        if (!await _saveModule(
          id: id,
          apiPath: '/api/rsp-access',
          drafts: _rspDrafts,
          stored: _rspAccess,
          labels: _rspPermissions,
          conflictCode: 'RSP_ACCESS_CONFLICT',
          successLabel: 'RSP',
          rsp: true,
        )) {
          return;
        }
        savedParts.add('RSP');
      }
      if (_isLdDirty(id)) {
        if (!await _saveModule(
          id: id,
          apiPath: '/api/ld-access',
          drafts: _ldDrafts,
          stored: _ldAccess,
          labels: _ldPermissions,
          conflictCode: 'LD_ACCESS_CONFLICT',
          successLabel: 'L&D',
          rsp: false,
        )) {
          return;
        }
        savedParts.add('L&D');
      }
      if (!mounted || savedParts.isEmpty) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            savedParts.length == 1 && savedParts.first == 'DTR'
                ? 'DTR permissions saved.'
                : '${savedParts.join(', ')} permissions saved.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving.remove(id));
    }
  }

  void _discardDrafts(String id) {
    setState(() {
      _drafts.remove(id);
      _rspDrafts.remove(id);
      _ldDrafts.remove(id);
    });
  }

  int _enabledCount(Map<String, bool> draft, Iterable<String> fields) =>
      fields.where((field) => draft[field] == true).length;

  Widget _statusChip({
    required String label,
    required Color color,
    IconData? icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _permissionTile({
    required BuildContext context,
    required String field,
    required String label,
    required bool value,
    required bool enabled,
    required VoidCallback? onToggle,
  }) {
    final navy = AppTheme.primaryNavy;
    final hairline = AppTheme.dashHairlineOf(context);
    final muted = AppTheme.dashTextSecondaryOf(context);
    return Material(
      key: ValueKey('access_perm_$field'),
      color: value
          ? navy.withValues(alpha: 0.07)
          : AppTheme.dashMutedSurfaceOf(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: value ? navy.withValues(alpha: 0.45) : hairline,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled ? onToggle : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
          child: Row(
            children: [
              Icon(
                value
                    ? Icons.check_box_rounded
                    : Icons.check_box_outline_blank_rounded,
                size: 22,
                color: value ? navy : muted.withValues(alpha: 0.75),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.25,
                    fontWeight: value ? FontWeight.w700 : FontWeight.w500,
                    color: value
                        ? AppTheme.dashTextPrimaryOf(context)
                        : muted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _permissionGrid({
    required BuildContext context,
    required bool active,
    required bool busy,
    required Map<String, bool> draft,
    required Map<String, String> labels,
    required void Function(String field, bool value) onChanged,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1000
            ? 3
            : constraints.maxWidth >= 600
            ? 2
            : 1;
        const gap = 10.0;
        final width =
            (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final entry in labels.entries)
              SizedBox(
                width: width,
                child: _permissionTile(
                  context: context,
                  field: entry.key,
                  label: entry.value,
                  value: draft[entry.key] ?? false,
                  enabled: active && !busy,
                  onToggle: () =>
                      onChanged(entry.key, !(draft[entry.key] ?? false)),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _modulePanel({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required int enabledCount,
    required int totalCount,
    required Widget child,
  }) {
    final navy = AppTheme.primaryNavy;
    final hairline = AppTheme.dashHairlineOf(context);
    final muted = AppTheme.dashTextSecondaryOf(context);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppTheme.dashPanelOf(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              color: navy.withValues(alpha: 0.05),
              border: Border(bottom: BorderSide(color: hairline)),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: navy.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 20, color: navy),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14.5,
                          color: AppTheme.dashTextPrimaryOf(context),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: muted,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                _statusChip(
                  label: '$enabledCount / $totalCount on',
                  color: enabledCount > 0 ? navy : muted,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            child: child,
          ),
        ],
      ),
    );
  }

  Widget _groupedPermissionSections({
    required BuildContext context,
    required bool active,
    required bool busy,
    required Map<String, bool> draft,
    required List<({String? title, Map<String, String> items})> groups,
    required void Function(String field, bool value) onChanged,
  }) {
    final muted = AppTheme.dashTextSecondaryOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < groups.length; i++) ...[
          if (i > 0) const SizedBox(height: 14),
          if (groups[i].title != null) ...[
            Row(
              children: [
                Text(
                  groups[i].title!,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                    color: AppTheme.dashTextPrimaryOf(context),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Divider(
                    height: 1,
                    color: AppTheme.dashHairlineOf(context),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${_enabledCount(draft, groups[i].items.keys)} selected',
                  style: TextStyle(fontSize: 11.5, color: muted),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          _permissionGrid(
            context: context,
            active: active,
            busy: busy,
            draft: draft,
            labels: groups[i].items,
            onChanged: onChanged,
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final hairline = AppTheme.dashHairlineOf(context);
    final muted = AppTheme.dashTextSecondaryOf(context);
    final navy = AppTheme.primaryNavy;
    final accent = Theme.of(context).colorScheme.primary;
    return PopScope<Object?>(
      canPop:
          _allowPop ||
          (!_admins.any(_isAnyDirty) &&
              _saving.isEmpty &&
              _accountSaving.isEmpty),
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (!await confirmLeave() || !mounted) return;
        setState(() => _allowPop = true);
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted || !context.mounted) return;
        await Navigator.of(context).maybePop(result);
        if (mounted) setState(() => _allowPop = false);
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: navy.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.admin_panel_settings_rounded,
                    color: navy,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Manage Access',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Grant account creation and module features for each administrator. Changes to DTR, RSP, and L&D save together.',
                        style: TextStyle(color: muted, height: 1.35),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed:
                      _loading ||
                          _saving.isNotEmpty ||
                          _accountSaving.isNotEmpty
                      ? null
                      : () => _load(confirmDiscard: true),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Refresh'),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? Center(child: Text(_error!))
                  : _admins.isEmpty
                  ? Center(
                      child: Text(
                        'No administrator accounts',
                        style: TextStyle(color: muted),
                      ),
                    )
                  : ListView.separated(
                      itemCount: _admins.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final admin = _admins[index];
                        final id = admin['id'].toString();
                        final active = admin['is_active'] == true;
                        final busy = _saving.contains(id);
                        final dirty = _isAnyDirty(admin);
                        final draft = _drafts[id] ?? _accessOf(admin);
                        final rspDraft =
                            _rspDrafts[id] ??
                            _moduleAccessOf(_rspAccess[id], _rspPermissions);
                        final ldDraft =
                            _ldDrafts[id] ??
                            _moduleAccessOf(_ldAccess[id], _ldPermissions);
                        final name =
                            admin['full_name']?.toString().trim() ?? '';
                        final email = admin['email']?.toString() ?? '';
                        final displayName = name.isEmpty ? email : name;
                        final accountAllowed = _accountAccess[id] ?? false;
                        final dtrEnabled = _enabledCount(
                          draft,
                          _permissions.keys,
                        );
                        final rspUiFields = _rspPermissionGroups
                            .expand((g) => g.items.keys);
                        final ldUiFields = _ldPermissionGroups
                            .expand((g) => g.items.keys);
                        final rspEnabled = _enabledCount(rspDraft, rspUiFields);
                        final ldEnabled = _enabledCount(ldDraft, ldUiFields);
                        final tileShape = RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        );
                        return Material(
                          color: AppTheme.dashPanelOf(context),
                          elevation: 0,
                          shape: tileShape.copyWith(
                            side: BorderSide(
                              color: dirty
                                  ? accent.withValues(alpha: 0.45)
                                  : hairline,
                              width: dirty ? 1.4 : 1,
                            ),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: ExpansionTile(
                            key: ValueKey(id),
                            shape: tileShape,
                            collapsedShape: tileShape,
                            clipBehavior: Clip.antiAlias,
                            tilePadding: const EdgeInsets.fromLTRB(
                              16,
                              10,
                              12,
                              10,
                            ),
                            childrenPadding: const EdgeInsets.fromLTRB(
                              16,
                              0,
                              16,
                              16,
                            ),
                            leading: CircleAvatar(
                              radius: 22,
                              backgroundColor: navy.withValues(alpha: 0.12),
                              child: Text(
                                displayName.isEmpty
                                    ? '?'
                                    : displayName[0].toUpperCase(),
                                style: TextStyle(
                                  color: navy,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                            title: Text(
                              displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                              ),
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Wrap(
                                spacing: 8,
                                runSpacing: 6,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text(
                                    email,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: muted,
                                      fontSize: 12.5,
                                    ),
                                  ),
                                  _statusChip(
                                    label: active ? 'Active' : 'Inactive',
                                    color: active
                                        ? const Color(0xFF2E7D32)
                                        : muted,
                                    icon: active
                                        ? Icons.check_circle_rounded
                                        : Icons.pause_circle_outline_rounded,
                                  ),
                                  if (dirty)
                                    _statusChip(
                                      label: 'Unsaved',
                                      color: accent,
                                      icon: Icons.edit_outlined,
                                    ),
                                  _statusChip(
                                    label:
                                        'DTR $dtrEnabled · RSP $rspEnabled · L&D $ldEnabled',
                                    color: navy,
                                  ),
                                ],
                              ),
                            ),
                            children: [
                              const SizedBox(height: 4),
                              Material(
                                color: accountAllowed
                                    ? navy.withValues(alpha: 0.06)
                                    : AppTheme.dashMutedSurfaceOf(context),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: BorderSide(
                                    color: accountAllowed
                                        ? navy.withValues(alpha: 0.28)
                                        : hairline,
                                  ),
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: CheckboxListTile(
                                  dense: true,
                                  controlAffinity:
                                      ListTileControlAffinity.leading,
                                  contentPadding: const EdgeInsets.fromLTRB(
                                    12,
                                    6,
                                    12,
                                    6,
                                  ),
                                  title: const Text(
                                    'Account creation',
                                    style: TextStyle(fontWeight: FontWeight.w700),
                                  ),
                                  subtitle: Text(
                                    'Can create employee and administrator accounts. Saves immediately.',
                                    style: TextStyle(
                                      color: muted,
                                      fontSize: 12.5,
                                    ),
                                  ),
                                  value: accountAllowed,
                                  onChanged:
                                      active && !_accountSaving.contains(id)
                                      ? (value) => _setAccountAccess(
                                          admin,
                                          value == true,
                                        )
                                      : null,
                                  secondary: _accountSaving.contains(id)
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : Icon(
                                          Icons.person_add_alt_1_rounded,
                                          color: navy,
                                        ),
                                ),
                              ),
                              const SizedBox(height: 14),
                              _modulePanel(
                                context: context,
                                title: 'DTR permissions',
                                subtitle:
                                    'Attendance, profiles, leave, approvals, and locator tools.',
                                icon: Icons.access_time_rounded,
                                enabledCount: dtrEnabled,
                                totalCount: _permissions.length,
                                child: _permissionGrid(
                                  context: context,
                                  active: active,
                                  busy: busy,
                                  draft: draft,
                                  labels: _permissions,
                                  onChanged: (field, value) => setState(() {
                                    _drafts.putIfAbsent(
                                          id,
                                          () => _accessOf(admin),
                                        )[field] =
                                        value;
                                  }),
                                ),
                              ),
                              const SizedBox(height: 12),
                              _modulePanel(
                                context: context,
                                title: 'RSP permissions',
                                subtitle:
                                    'Vacancies, exams, recruitment tabs, and RSP forms.',
                                icon: Icons.how_to_reg_rounded,
                                enabledCount: rspEnabled,
                                totalCount: rspUiFields.length,
                                child: _groupedPermissionSections(
                                  context: context,
                                  active: active,
                                  busy: busy,
                                  draft: rspDraft,
                                  groups: _rspPermissionGroups,
                                  onChanged: (field, value) => setState(() {
                                    final draftMap = _rspDrafts.putIfAbsent(
                                      id,
                                      () => _moduleAccessOf(
                                        _rspAccess[id],
                                        _rspPermissions,
                                      ),
                                    );
                                    draftMap[field] = value;
                                    draftMap['recruitment_allowed'] =
                                        _rspRecruitmentFields.any(
                                          (f) => draftMap[f] == true,
                                        );
                                    draftMap['forms_allowed'] = _rspFormFields
                                        .any((f) => draftMap[f] == true);
                                  }),
                                ),
                              ),
                              const SizedBox(height: 12),
                              _modulePanel(
                                context: context,
                                title: 'L&D permissions',
                                subtitle:
                                    'Daily reports, training requirements, and L&D forms.',
                                icon: Icons.school_rounded,
                                enabledCount: ldEnabled,
                                totalCount: ldUiFields.length,
                                child: _groupedPermissionSections(
                                  context: context,
                                  active: active,
                                  busy: busy,
                                  draft: ldDraft,
                                  groups: _ldPermissionGroups,
                                  onChanged: (field, value) => setState(() {
                                    final draftMap = _ldDrafts.putIfAbsent(
                                      id,
                                      () => _moduleAccessOf(
                                        _ldAccess[id],
                                        _ldPermissions,
                                      ),
                                    );
                                    draftMap[field] = value;
                                    draftMap['forms_allowed'] = _ldFormFields
                                        .any((f) => draftMap[f] == true);
                                  }),
                                ),
                              ),
                              if (active) ...[
                                const SizedBox(height: 14),
                                Container(
                                  padding: const EdgeInsets.fromLTRB(
                                    12,
                                    10,
                                    12,
                                    10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppTheme.dashMutedSurfaceOf(context),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: hairline),
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          dirty
                                              ? 'You have unsaved permission changes.'
                                              : 'All module permissions are up to date.',
                                          style: TextStyle(
                                            fontSize: 12.5,
                                            color: muted,
                                          ),
                                        ),
                                      ),
                                      TextButton(
                                        onPressed: dirty && !busy
                                            ? () => _discardDrafts(id)
                                            : null,
                                        child: const Text('Cancel'),
                                      ),
                                      const SizedBox(width: 6),
                                      FilledButton.icon(
                                        onPressed: dirty && !busy
                                            ? () => _save(admin)
                                            : null,
                                        style: FilledButton.styleFrom(
                                          backgroundColor: navy,
                                          foregroundColor: Colors.white,
                                        ),
                                        icon: busy
                                            ? const SizedBox(
                                                width: 16,
                                                height: 16,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                      color: Colors.white,
                                                    ),
                                              )
                                            : const Icon(
                                                Icons.save_outlined,
                                                size: 18,
                                              ),
                                        label: const Text('Save permissions'),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
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
