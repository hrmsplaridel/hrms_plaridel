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
  static const _features = {
    'corrections_allowed': 'DTR Corrections',
    'employees_allowed': 'Employees',
    'leave_allowed': 'Leave Management',
    'approvals_allowed': 'Approvals & Signatories',
    'locator_allowed': 'Locator Slip Management',
  };
  List<Map<String, dynamic>> _admins = [];
  final Set<String> _saving = {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
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
      });
    } catch (error) {
      if (mounted) setState(() => _error = userFacingApiError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _setAccess(
    Map<String, dynamic> admin, {
    required bool reports,
    required bool manage,
    String? feature,
    bool? featureValue,
  }) async {
    final id = admin['id'].toString();
    if (_saving.contains(id)) return;
    setState(() => _saving.add(id));
    try {
      final permissions = {
        'reports_allowed': reports,
        'manage_allowed': manage,
        for (final field in _features.keys) field: admin[field] == true,
      };
      if (feature != null) permissions[feature] = featureValue == true;
      await ApiClient.instance.put<Map<String, dynamic>>(
        '/api/dtr-access/$id',
        data: permissions,
      );
      if (!mounted) return;
      setState(() {
        admin['reports_allowed'] = reports;
        admin['manage_allowed'] = manage;
        if (feature != null) admin[feature] = featureValue;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('DTR access updated.')));
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
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: hairline),
                borderRadius: BorderRadius.circular(6),
              ),
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? Center(child: Text(_error!))
                  : _admins.isEmpty
                  ? const Center(child: Text('No administrator accounts'))
                  : ListView.separated(
                      itemCount: _admins.length,
                      separatorBuilder: (_, _) =>
                          Divider(height: 1, color: hairline),
                      itemBuilder: (context, index) {
                        final admin = _admins[index];
                        final id = admin['id'].toString();
                        final active = admin['is_active'] == true;
                        final reports = admin['reports_allowed'] == true;
                        final manage = admin['manage_allowed'] == true;
                        final busy = _saving.contains(id);
                        final name =
                            admin['full_name']?.toString().trim() ?? '';
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: Wrap(
                            spacing: 20,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              SizedBox(
                                width: 240,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      name.isEmpty
                                          ? admin['email'].toString()
                                          : name,
                                    ),
                                    Text(
                                      '${admin['email']}${active ? '' : '  |  Inactive'}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: muted,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              _accessSwitch(
                                label: 'View reports',
                                value: reports,
                                enabled: active && !busy,
                                onChanged: (value) => _setAccess(
                                  admin,
                                  reports: value,
                                  manage: manage,
                                ),
                              ),
                              _accessSwitch(
                                label: 'Manage DTR',
                                value: manage,
                                enabled: active && !busy,
                                onChanged: (value) => _setAccess(
                                  admin,
                                  reports: reports,
                                  manage: value,
                                ),
                              ),
                              for (final entry in _features.entries)
                                _accessSwitch(
                                  label: entry.value,
                                  value: admin[entry.key] == true,
                                  enabled: active && !busy,
                                  onChanged: (value) => _setAccess(
                                    admin,
                                    reports: reports,
                                    manage: manage,
                                    feature: entry.key,
                                    featureValue: value,
                                  ),
                                ),
                              if (busy)
                                const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _accessSwitch({
    required String label,
    required bool value,
    required bool enabled,
    required ValueChanged<bool> onChanged,
  }) {
    return SizedBox(
      width: 170,
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Switch(value: value, onChanged: enabled ? onChanged : null),
        ],
      ),
    );
  }
}
