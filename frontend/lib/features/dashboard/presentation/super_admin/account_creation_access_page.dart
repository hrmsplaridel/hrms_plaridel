import 'package:flutter/material.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/core/api/user_facing_api_error.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';

class AccountCreationAccessPage extends StatefulWidget {
  const AccountCreationAccessPage({super.key});

  @override
  State<AccountCreationAccessPage> createState() =>
      _AccountCreationAccessPageState();
}

class _AccountCreationAccessPageState extends State<AccountCreationAccessPage> {
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
        '/api/account-creation-access',
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

  Future<void> _setAccess(Map<String, dynamic> admin, bool allowed) async {
    final id = admin['id'].toString();
    if (_saving.contains(id)) return;
    setState(() => _saving.add(id));
    try {
      await ApiClient.instance.put<Map<String, dynamic>>(
        '/api/account-creation-access/$id',
        data: {'allowed': allowed},
      );
      if (!mounted) return;
      setState(() => admin['allowed'] = allowed);
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
                  'Account Creation Access',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              IconButton(
                tooltip: 'Refresh access list',
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Choose which administrators can create employee and admin accounts.',
            style: TextStyle(color: muted),
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
                        final allowed = admin['allowed'] == true;
                        final name =
                            (admin['full_name']?.toString().trim() ?? '');
                        return ListTile(
                          title: Text(
                            name.isEmpty ? admin['email'].toString() : name,
                          ),
                          subtitle: Text(
                            '${admin['email']}${active ? '' : '  |  Inactive'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: _saving.contains(id)
                              ? const SizedBox(
                                  width: 48,
                                  height: 24,
                                  child: Center(
                                    child: SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  ),
                                )
                              : Switch(
                                  value: allowed,
                                  onChanged: active
                                      ? (value) => _setAccess(admin, value)
                                      : null,
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
}
