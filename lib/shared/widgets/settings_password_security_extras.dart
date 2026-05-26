import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../api/client.dart';
import '../../landingpage/constants/app_theme.dart';
import 'profile_modern_ui.dart';

/// Sessions list, placeholder 2FA, and revoke-all for Settings → Password & Security.
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
        title: const Text('Log out everywhere?'),
        content: const Text(
          'This signs out every device tied to your account. '
          'You may need to sign in again on other browsers or phones.',
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
            child: const Text('Log out all'),
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
        const SnackBar(
          content: Text(
            'Other devices have been signed out.',
          ),
        ),
      );
      await _loadSessions();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Failed: $e')));
    } finally {
      if (mounted) setState(() => _revokingAll = false);
    }
  }

  String? _str(dynamic v) {
    if (v == null) return null;
    final t = v.toString().trim();
    return t.isEmpty ? null : t;
  }

  String _sessionLabel(Map<String, dynamic> row) {
    return _str(row['device_label']) ??
        _str(row['device_info']) ??
        'Unknown device';
  }

  String? _sessionUnit(Map<String, dynamic> row) {
    return _str(row['device_model']) ?? _str(row['client_unit']);
  }

  String? _sessionLocation(Map<String, dynamic> row) {
    return _str(row['location_label']);
  }

  String? _sessionSince(Map<String, dynamic> row) {
    final raw = row['created_at']?.toString();
    if (raw == null || raw.isEmpty) return null;
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) {
      return raw.length > 16 ? raw.substring(0, 16) : raw;
    }
    final l = parsed.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${l.year}-${two(l.month)}-${two(l.day)} · ${two(l.hour)}:${two(l.minute)}';
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
    final dark = AppTheme.dashIsDark(context);

    return ModernProfileCard(
      title: 'Two-factor & sessions',
      icon: Icons.verified_user_outlined,
      trailing: TextButton.icon(
        onPressed: _loadingSessions ? null : _loadSessions,
        icon: const Icon(Icons.refresh_rounded, size: 18),
        label: const Text('Refresh'),
        style: TextButton.styleFrom(
          foregroundColor: AppTheme.primaryNavy,
          padding: const EdgeInsets.symmetric(horizontal: 8),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ProfileInsetSurface(
            child: Column(
              children: [
                ProfileSettingTile(
                  icon: Icons.phonelink_lock_rounded,
                  title: 'Two-factor authentication',
                  subtitle:
                      'Extra sign-in protection. Contact HR for organization policy.',
                  trailing: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Switch.adaptive(
                        value: false,
                        onChanged: null,
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.dashTextSecondaryOf(context)
                              .withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'Soon',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.dashTextSecondaryOf(context),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Active login sessions',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
              color: AppTheme.dashTextPrimaryOf(context),
            ),
          ),
          const SizedBox(height: 10),
          if (_loadingSessions)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Center(
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              ),
            )
          else if (_sessionError != null)
            ProfileInsetSurface(
              child: Row(
                children: [
                  Icon(Icons.error_outline_rounded,
                      color: Colors.red.shade700, size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _sessionError!,
                      style: TextStyle(
                        color: Colors.red.shade700,
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else if (_sessions.isEmpty)
            ProfileInsetSurface(
              child: ProfileCardEmptyState(
                icon: Icons.devices_other_rounded,
                message:
                    'No other active sessions listed for this account, or only this device is signed in.',
              ),
            )
          else
            ..._sessions.map((s) {
              final unit = _sessionUnit(s);
              final location = _sessionLocation(s);
              final since = _sessionSince(s);
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: ProfileInsetSurface(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppTheme.primaryNavy.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          _sessionIcon(s),
                          color: AppTheme.primaryNavy,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _sessionLabel(s),
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13.5,
                                color: AppTheme.dashTextPrimaryOf(context),
                              ),
                            ),
                            if (unit != null) ...[
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(
                                    Icons.devices_rounded,
                                    size: 14,
                                    color: AppTheme.dashTextSecondaryOf(context),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      unit,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: AppTheme.dashTextSecondaryOf(
                                          context,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            if (location != null) ...[
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(
                                    Icons.place_outlined,
                                    size: 14,
                                    color: AppTheme.dashTextSecondaryOf(context),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      location,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: AppTheme.dashTextSecondaryOf(
                                          context,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            if (since != null) ...[
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(
                                    Icons.schedule_rounded,
                                    size: 14,
                                    color: AppTheme.dashTextSecondaryOf(context),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      'Active since $since',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: AppTheme.dashTextSecondaryOf(
                                          context,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          const SizedBox(height: 16),
          Material(
            color: dark
                ? const Color(0xFFC62828).withValues(alpha: 0.12)
                : const Color(0xFFFFEBEE),
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: _revokingAll ? null : _logoutAllDevices,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_revokingAll)
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.red.shade700,
                        ),
                      )
                    else
                      Icon(Icons.logout_rounded,
                          color: Colors.red.shade700, size: 20),
                    const SizedBox(width: 10),
                    Text(
                      _revokingAll
                          ? 'Signing out devices…'
                          : 'Log out all other devices',
                      style: TextStyle(
                        color: Colors.red.shade700,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
