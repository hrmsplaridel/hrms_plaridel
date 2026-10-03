import 'package:flutter/material.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/core/api/user_facing_api_error.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';

class DtrAccessPage extends StatefulWidget {
  const DtrAccessPage({super.key});

  @override
  State<DtrAccessPage> createState() => _DtrAccessPageState();
}

class _DtrAccessPageState extends State<DtrAccessPage> {
  static const _permissions = {
    'reports_allowed': 'View DTR reports',
    'manage_allowed': 'Manage DTR logs',
    'corrections_allowed': 'DTR corrections',
    'employees_allowed': 'Employee profiles',
    'leave_allowed': 'Leave management',
    'approvals_allowed': 'Approvals & signatories',
    'locator_allowed': 'Locator slip management',
  };

  List<Map<String, dynamic>> _admins = [];
  final Map<String, Map<String, bool>> _drafts = {};
  final Set<String> _saving = {};
  bool _loading = true;
  String? _error;

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
      if (!mounted) return;
      setState(() {
        _admins = (response.data?['admins'] as List? ?? [])
            .map((value) => Map<String, dynamic>.from(value as Map))
            .toList();
        _drafts.clear();
      });
    } catch (error) {
      if (mounted) setState(() => _error = userFacingApiError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save(Map<String, dynamic> admin) async {
    final id = admin['id'].toString();
    if (_saving.contains(id) || !_isDirty(admin)) return;
    final permissions = Map<String, bool>.from(_drafts[id]!);
    setState(() => _saving.add(id));
    try {
      await ApiClient.instance.put<Map<String, dynamic>>(
        '/api/dtr-access/$id',
        data: permissions,
      );
      if (!mounted) return;
      setState(() {
        admin.addAll(permissions);
        _drafts.remove(id);
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('DTR permissions saved.')));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userFacingApiError(error))));
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
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'DTR Access',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              IconButton(
                tooltip: 'Refresh DTR access',
                onPressed: _loading || _saving.isNotEmpty
                    ? null
                    : () => _load(confirmDiscard: true),
                icon: const Icon(Icons.refresh),
              ),
            ],
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
                      final name = admin['full_name']?.toString().trim() ?? '';
                      final email = admin['email']?.toString() ?? '';
                      final displayName = name.isEmpty ? email : name;
                      return DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border.all(color: hairline),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: ExpansionTile(
                          key: ValueKey(id),
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
                                  style: TextStyle(color: accent, fontSize: 12),
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
                                                    () => _accessOf(admin),
                                                  )[entry.key] = value == true;
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
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
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
                                        ? () =>
                                              setState(() => _drafts.remove(id))
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
    );
  }
}
