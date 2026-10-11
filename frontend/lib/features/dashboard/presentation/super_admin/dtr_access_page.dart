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
  static const _permissions = {
    'reports_allowed': 'View DTR reports',
    'manage_allowed': 'Manage DTR logs',
    'employees_allowed': 'Employee profiles',
    'leave_allowed': 'Leave management',
    'approvals_allowed': 'Approvals & signatories',
    'locator_allowed': 'Locator slip management',
  };

  List<Map<String, dynamic>> _admins = [];
  Map<String, bool> _accountAccess = {};
  final Map<String, Map<String, bool>> _drafts = {};
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
    if (!_admins.any(_isDirty)) return true;
    _confirmingLeave = true;
    try {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Discard unsaved changes?'),
          content: const Text(
            'Leaving will discard DTR permission changes that have not been saved.',
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

  bool _isDirty(Map<String, dynamic> admin) {
    final draft = _drafts[admin['id'].toString()];
    return draft != null &&
        _permissions.keys.any(
          (field) => draft[field] != (admin[field] == true),
        );
  }

  Future<void> _load({bool confirmDiscard = false}) async {
    if (confirmDiscard && _admins.any(_isDirty)) {
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
      if (!mounted) return;
      setState(() {
        _admins = (response.data?['admins'] as List? ?? [])
            .map((value) => Map<String, dynamic>.from(value as Map))
            .toList();
        _accountAccess = {
          for (final row in accountResponse.data?['admins'] as List? ?? [])
            (row as Map)['id'].toString(): row['allowed'] == true,
        };
        _drafts.clear();
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

  Future<void> _save(Map<String, dynamic> admin) async {
    final id = admin['id'].toString();
    if (_saving.contains(id) || !_isDirty(admin)) return;
    final permissions = Map<String, bool>.from(_drafts[id]!);
    setState(() => _saving.add(id));
    try {
      final response = await ApiClient.instance.put<Map<String, dynamic>>(
        '/api/dtr-access/$id',
        data: {...permissions, 'expected_revision': admin['revision']},
      );
      if (!mounted) return;
      setState(() {
        admin.addAll(permissions);
        admin['revision'] = response.data?['revision'];
        _drafts.remove(id);
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('DTR permissions saved.')));
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
    } finally {
      if (mounted) setState(() => _saving.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final hairline = AppTheme.dashHairlineOf(context);
    final muted = AppTheme.dashTextSecondaryOf(context);
    final accent = Theme.of(context).colorScheme.primary;
    return PopScope<Object?>(
      canPop:
          _allowPop ||
          (!_admins.any(_isDirty) && _saving.isEmpty && _accountSaving.isEmpty),
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
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Manage Access',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh administrator access',
                  onPressed:
                      _loading ||
                          _saving.isNotEmpty ||
                          _accountSaving.isNotEmpty
                      ? null
                      : () => _load(confirmDiscard: true),
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Set who can create accounts and which DTR features each administrator can use.',
              style: TextStyle(color: muted),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? Center(child: Text(_error!))
                  : _admins.isEmpty
                  ? const Center(child: Text('No administrator accounts'))
                  : ListView.separated(
                      itemCount: _admins.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final admin = _admins[index];
                        final id = admin['id'].toString();
                        final active = admin['is_active'] == true;
                        final busy = _saving.contains(id);
                        final dirty = _isDirty(admin);
                        final draft = _drafts[id] ?? _accessOf(admin);
                        final name =
                            admin['full_name']?.toString().trim() ?? '';
                        final email = admin['email']?.toString() ?? '';
                        final displayName = name.isEmpty ? email : name;
                        final tileShape = RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        );
                        return Material(
                          color: AppTheme.dashCanvasOf(context),
                          shape: tileShape.copyWith(
                            side: BorderSide(color: hairline),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: ExpansionTile(
                            key: ValueKey(id),
                            shape: tileShape,
                            collapsedShape: tileShape,
                            clipBehavior: Clip.antiAlias,
                            tilePadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 4,
                            ),
                            childrenPadding: const EdgeInsets.fromLTRB(
                              16,
                              0,
                              16,
                              16,
                            ),
                            leading: CircleAvatar(
                              radius: 19,
                              backgroundColor: accent.withValues(alpha: 0.15),
                              child: Text(
                                displayName.isEmpty
                                    ? '?'
                                    : displayName[0].toUpperCase(),
                                style: TextStyle(color: accent),
                              ),
                            ),
                            title: Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    displayName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (dirty) ...[
                                  const SizedBox(width: 10),
                                  Text(
                                    'Unsaved',
                                    style: TextStyle(
                                      color: accent,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            subtitle: Text(
                              '$email${active ? '' : '  |  Inactive'}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: muted, fontSize: 12),
                            ),
                            children: [
                              Divider(height: 20, color: hairline),
                              CheckboxListTile(
                                dense: true,
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                                contentPadding: EdgeInsets.zero,
                                title: const Text('Account creation'),
                                subtitle: const Text(
                                  'Can create employee and administrator accounts. Changes save immediately.',
                                ),
                                value: _accountAccess[id] ?? false,
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
                                    : null,
                              ),
                              Divider(height: 20, color: hairline),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  'DTR permissions',
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                              ),
                              const SizedBox(height: 10),
                              LayoutBuilder(
                                builder: (context, constraints) {
                                  final columns = constraints.maxWidth >= 1000
                                      ? 3
                                      : constraints.maxWidth >= 600
                                      ? 2
                                      : 1;
                                  const gap = 10.0;
                                  final width =
                                      (constraints.maxWidth -
                                          gap * (columns - 1)) /
                                      columns;
                                  return Wrap(
                                    spacing: gap,
                                    runSpacing: gap,
                                    children: [
                                      for (final entry in _permissions.entries)
                                        SizedBox(
                                          width: width,
                                          child: CheckboxListTile(
                                            value: draft[entry.key] ?? false,
                                            onChanged: active && !busy
                                                ? (value) => setState(() {
                                                    _drafts.putIfAbsent(
                                                          id,
                                                          () =>
                                                              _accessOf(admin),
                                                        )[entry.key] =
                                                        value == true;
                                                  })
                                                : null,
                                            title: Text(
                                              entry.value,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            controlAffinity:
                                                ListTileControlAffinity.leading,
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                                  horizontal: 8,
                                                ),
                                            dense: true,
                                            shape: RoundedRectangleBorder(
                                              side: BorderSide(color: hairline),
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                          ),
                                        ),
                                    ],
                                  );
                                },
                              ),
                              if (active) ...[
                                const SizedBox(height: 16),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    TextButton(
                                      onPressed: dirty && !busy
                                          ? () => setState(
                                              () => _drafts.remove(id),
                                            )
                                          : null,
                                      child: const Text('Cancel'),
                                    ),
                                    const SizedBox(width: 8),
                                    FilledButton.icon(
                                      onPressed: dirty && !busy
                                          ? () => _save(admin)
                                          : null,
                                      icon: busy
                                          ? const SizedBox(
                                              width: 16,
                                              height: 16,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : const Icon(Icons.save_outlined),
                                      label: const Text('Save permissions'),
                                    ),
                                  ],
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
