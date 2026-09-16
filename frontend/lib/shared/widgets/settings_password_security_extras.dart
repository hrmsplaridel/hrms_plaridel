import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'profile_modern_ui.dart';

String _formatSecurityWhen(String? raw) {
  if (raw == null || raw.trim().isEmpty) return '';
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) {
    return raw.length > 16 ? raw.substring(0, 16) : raw;
  }
  final local = parsed.toLocal();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(local.year, local.month, local.day);
  final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  final ampm = local.hour >= 12 ? 'PM' : 'AM';
  final time = '$hour:$minute $ampm';
  if (day == today) return 'Today, $time';
  if (day == today.subtract(const Duration(days: 1))) {
    return 'Yesterday, $time';
  }
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return '${months[local.month - 1]} ${local.day}, ${local.year}';
}

class SettingsAccountProtectionCard extends StatelessWidget {
  const SettingsAccountProtectionCard({super.key});

  @override
  Widget build(BuildContext context) {
    final muted = AppTheme.dashTextSecondaryOf(context);
    return ModernProfileCard(
      title: 'Account Protection',
      subtitle: 'How this account is signed in.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                'Account security',
                style: TextStyle(
                  fontSize: 13,
                  color: AppTheme.dashTextPrimaryOf(context),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                'Good',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.green.shade700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _ProtectionRow(
            icon: Icons.password_rounded,
            title: 'Password sign-in',
            subtitle: 'Email and password are required to access HRMS.',
            trailing: Text(
              'Enabled',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: Colors.green.shade700,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Divider(height: 1, color: AppTheme.dashHairlineOf(context)),
          const SizedBox(height: 12),
          _ProtectionRow(
            icon: Icons.verified_user_outlined,
            title: 'Two-factor authentication',
            subtitle:
                'An extra verification step is not available in this HRMS yet.',
            trailing: Text(
              'Not available',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: muted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProtectionRow extends StatelessWidget {
  const _ProtectionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: AppTheme.dashTextSecondaryOf(context)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.dashTextPrimaryOf(context),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.35,
                  color: AppTheme.dashTextSecondaryOf(context),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        trailing,
      ],
    );
  }
}

/// Active refresh-token sessions from GET /auth/sessions.
class SettingsPasswordSecurityExtras extends StatefulWidget {
  const SettingsPasswordSecurityExtras({super.key});

  @override
  State<SettingsPasswordSecurityExtras> createState() =>
      _SettingsPasswordSecurityExtrasState();
}

class _SettingsPasswordSecurityExtrasState
    extends State<SettingsPasswordSecurityExtras> {
  bool _loadingSessions = true;
  bool _revokingAll = false;
  String? _revokingId;
  String? _sessionError;
  List<Map<String, dynamic>> _sessions = [];

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    setState(() {
      _loadingSessions = true;
      _sessionError = null;
    });
    try {
      final res = await ApiClient.instance.get<Map<String, dynamic>>(
        '/auth/sessions',
      );
      final raw = res.data?['sessions'];
      final list = <Map<String, dynamic>>[];
      if (raw is List) {
        for (final item in raw) {
          if (item is Map<String, dynamic>) list.add(item);
        }
      }
      if (!mounted) return;
      setState(() {
        _sessions = list;
        _loadingSessions = false;
      });
    } catch (e) {
      if (!mounted) return;
      String msg = 'Could not load sessions';
      if (e is DioException && e.response?.statusCode != null) {
        msg = 'Sessions unavailable (${e.response!.statusCode})';
      }
      setState(() {
        _sessions = [];
        _sessionError = msg;
        _loadingSessions = false;
      });
    }
  }

  Future<void> _logoutAllDevices() async {
    final messenger = ScaffoldMessenger.of(context);
    final proceed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        icon: Icon(Icons.logout_rounded, color: Colors.red.shade700, size: 28),
        title: const Text('Log out other devices?'),
        content: const Text(
          'This signs out every other device tied to your account. '
          'This device will stay signed in.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFC62828),
              foregroundColor: Colors.white,
            ),
            child: const Text('Log out others'),
          ),
        ],
      ),
    );
    if (proceed != true || !mounted) return;
    setState(() => _revokingAll = true);
    try {
      await ApiClient.instance.post<void>('/auth/logout-all');
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Other devices have been signed out.')),
      );
      await _loadSessions();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Failed: $e')));
    } finally {
      if (mounted) setState(() => _revokingAll = false);
    }
  }

  Future<void> _logoutSession(Map<String, dynamic> row) async {
    final id = _str(row['id']);
    if (id == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final proceed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('End this session?'),
        content: Text('Sign out ${_sessionLabel(row)}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFC62828),
              foregroundColor: Colors.white,
            ),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (proceed != true || !mounted) return;
    setState(() => _revokingId = id);
    try {
      await ApiClient.instance.delete<void>('/auth/sessions/$id');
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Session signed out.')),
      );
      await _loadSessions();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Failed: $e')));
    } finally {
      if (mounted) setState(() => _revokingId = null);
    }
  }

  String? _str(dynamic v) {
    if (v == null) return null;
    final t = v.toString().trim();
    return t.isEmpty ? null : t;
  }

  bool _isCurrent(Map<String, dynamic> row) => row['is_current'] == true;

  String _sessionLabel(Map<String, dynamic> row) {
    return _str(row['device_label']) ??
        _str(row['device_info']) ??
        'Unknown device';
  }

  String? _sessionLocation(Map<String, dynamic> row) {
    final label = _str(row['location_label']);
    if (label == null || label.toLowerCase() == 'location unknown') {
      return null;
    }
    return label;
  }

  IconData _sessionIcon(Map<String, dynamic> row) {
    final type = (_str(row['device_type']) ?? '').toLowerCase();
    switch (type) {
      case 'mobile':
        return Icons.smartphone_rounded;
      case 'tablet':
        return Icons.tablet_mac_rounded;
      case 'desktop':
        return Icons.computer_rounded;
      default:
        return Icons.devices_other_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ModernProfileCard(
      title: 'Active sessions',
      subtitle: 'Devices currently signed in to your account.',
      trailing: IconButton(
        tooltip: 'Refresh',
        onPressed: _loadingSessions ? null : _loadSessions,
        icon: const Icon(Icons.refresh_rounded, size: 20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_loadingSessions)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (_sessionError != null)
            Text(
              _sessionError!,
              style: TextStyle(color: Colors.red.shade700, fontSize: 13),
            )
          else if (_sessions.isEmpty)
            Text(
              'Only this device appears to be signed in.',
              style: TextStyle(
                fontSize: 13,
                color: AppTheme.dashTextSecondaryOf(context),
              ),
            )
          else
            ..._sessions.map((s) {
              final current = _isCurrent(s);
              final since = _formatSecurityWhen(_str(s['created_at']));
              final location = _sessionLocation(s);
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      _sessionIcon(s),
                      size: 20,
                      color: AppTheme.dashTextSecondaryOf(context),
                    ),
                    const SizedBox(width: 10),
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
                                _sessionLabel(s),
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13.5,
                                  color: AppTheme.dashTextPrimaryOf(context),
                                ),
                              ),
                              if (current)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF2E7D32)
                                        .withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: const Text(
                                    'Current device',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF2E7D32),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          if (since.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              'Signed in $since',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppTheme.dashTextSecondaryOf(context),
                              ),
                            ),
                          ],
                          if (location != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              location,
                              style: TextStyle(
                                fontSize: 12,
                                color: AppTheme.dashTextSecondaryOf(context),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (!current && _str(s['id']) != null)
                      TextButton(
                        onPressed: _revokingId != null
                            ? null
                            : () => _logoutSession(s),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.red.shade700,
                          visualDensity: VisualDensity.compact,
                        ),
                        child: Text(
                          _revokingId == _str(s['id']) ? '…' : 'Log out',
                        ),
                      ),
                  ],
                ),
              );
            }),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              onPressed: _revokingAll ? null : _logoutAllDevices,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red.shade700,
                side: BorderSide(color: Colors.red.shade300),
              ),
              child: Text(
                _revokingAll ? 'Signing out…' : 'Log out all other devices',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SettingsSecurityActivityCard extends StatefulWidget {
  const SettingsSecurityActivityCard({super.key});

  @override
  State<SettingsSecurityActivityCard> createState() =>
      _SettingsSecurityActivityCardState();
}

class _SettingsSecurityActivityCardState
    extends State<SettingsSecurityActivityCard> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _events = [];

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
      final res = await ApiClient.instance.get<Map<String, dynamic>>(
        '/auth/security-activity',
      );
      final raw = res.data?['events'];
      final list = <Map<String, dynamic>>[];
      if (raw is List) {
        for (final item in raw) {
          if (item is Map<String, dynamic>) list.add(item);
        }
      }
      if (!mounted) return;
      setState(() {
        _events = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _events = [];
        _error = 'Could not load security activity';
        _loading = false;
      });
    }
  }

  IconData _iconFor(String? type) {
    switch (type) {
      case 'password_changed':
        return Icons.key_rounded;
      case 'password_reset_requested':
        return Icons.sms_outlined;
      case 'session_revoked':
        return Icons.logout_rounded;
      case 'session_created':
      default:
        return Icons.login_rounded;
    }
  }

  Color _colorFor(String? type, BuildContext context) {
    switch (type) {
      case 'password_changed':
        return const Color(0xFFE65100);
      case 'session_revoked':
        return Colors.red.shade700;
      case 'session_created':
        return const Color(0xFF2E7D32);
      default:
        return AppTheme.dashTextSecondaryOf(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ModernProfileCard(
      title: 'Recent Security Activity',
      subtitle: 'Sign-in and password events from this account.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Colors.red.shade700, fontSize: 13),
            )
          else if (_events.isEmpty)
            Text(
              'No recent security activity.',
              style: TextStyle(
                fontSize: 13,
                color: AppTheme.dashTextSecondaryOf(context),
              ),
            )
          else
            for (var i = 0; i < _events.length; i++) ...[
              if (i > 0) const SizedBox(height: 10),
              _ActivityTile(
                icon: _iconFor(_events[i]['type']?.toString()),
                color: _colorFor(_events[i]['type']?.toString(), context),
                title: _events[i]['title']?.toString() ?? 'Activity',
                subtitle: _events[i]['subtitle']?.toString(),
                when: _formatSecurityWhen(_events[i]['at']?.toString()),
              ),
            ],
        ],
      ),
    );
  }
}

class _ActivityTile extends StatelessWidget {
  const _ActivityTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.when,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String? subtitle;
  final String when;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.dashTextPrimaryOf(context),
                ),
              ),
              if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: AppTheme.dashTextSecondaryOf(context),
                  ),
                ),
              ],
              if (when.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  when,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.dashTextSecondaryOf(context),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
