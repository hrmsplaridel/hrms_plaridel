import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/providers/theme_mode_provider.dart';
import 'profile_modern_ui.dart';
import 'settings_about_panel.dart';

/// Shared preference keys for notification toggles.
abstract final class ProfileAppSettingsKeys {
  static const notifEmail = 'settings_notif_email_v1';
  static const notifAttendance = 'settings_notif_attendance_v1';
  static const notifLeave = 'settings_notif_leave_v1';
  static const notifAnnounce = 'settings_notif_announcements_v1';
  static const notifTask = 'settings_notif_tasks_v1';
  static const notifPayroll = 'settings_notif_payroll_v1';
  static const prefPayroll = 'settings_pref_payroll_v1';
}

class ProfileNotificationSettingsPanel extends StatefulWidget {
  const ProfileNotificationSettingsPanel({super.key});

  @override
  State<ProfileNotificationSettingsPanel> createState() =>
      _ProfileNotificationSettingsPanelState();
}

class _ProfileNotificationSettingsPanelState
    extends State<ProfileNotificationSettingsPanel> {
  bool _loading = true;
  bool _savedHint = false;
  bool _nEmail = true;
  bool _nAttendance = true;
  bool _nLeave = true;
  bool _nAnnounce = true;
  bool _nTask = true;
  bool _nPayroll = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _nEmail = p.getBool(ProfileAppSettingsKeys.notifEmail) ?? true;
        _nAttendance =
            p.getBool(ProfileAppSettingsKeys.notifAttendance) ?? true;
        _nLeave = p.getBool(ProfileAppSettingsKeys.notifLeave) ?? true;
        _nAnnounce = p.getBool(ProfileAppSettingsKeys.notifAnnounce) ?? true;
        _nTask = p.getBool(ProfileAppSettingsKeys.notifTask) ?? true;
        _nPayroll =
            p.getBool(ProfileAppSettingsKeys.notifPayroll) ??
            p.getBool(ProfileAppSettingsKeys.prefPayroll) ??
            true;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _setBool(String key, bool value) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(key, value);
    } catch (_) {}
    if (!mounted) return;
    setState(() => _savedHint = true);
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _savedHint = false);
    });
  }

  Widget _row({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14.5,
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
          const SizedBox(width: 12),
          Semantics(
            label: title,
            toggled: value,
            child: Switch.adaptive(
              value: value,
              activeThumbColor: AppTheme.primaryNavy,
              onChanged: (v) {
                setState(() => onChanged(v));
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return ModernProfileCard(
      title: 'Notifications',
      subtitle: 'Choose which HRMS activities you want to be notified about.',
      trailing: AnimatedOpacity(
        opacity: _savedHint ? 1 : 0,
        duration: const Duration(milliseconds: 150),
        child: Text(
          '✓ Saved',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Colors.green.shade700,
          ),
        ),
      ),
      child: Column(
        children: [
          _row(
            title: 'Email notifications',
            subtitle: 'Receive important HRMS updates through email.',
            value: _nEmail,
            onChanged: (v) {
              _nEmail = v;
              _setBool(ProfileAppSettingsKeys.notifEmail, v);
            },
          ),
          _row(
            title: 'Attendance alerts',
            subtitle: 'Missed punches, tardiness and DTR updates.',
            value: _nAttendance,
            onChanged: (v) {
              _nAttendance = v;
              _setBool(ProfileAppSettingsKeys.notifAttendance, v);
            },
          ),
          _row(
            title: 'Leave request updates',
            subtitle: 'Status changes related to leave requests.',
            value: _nLeave,
            onChanged: (v) {
              _nLeave = v;
              _setBool(ProfileAppSettingsKeys.notifLeave, v);
            },
          ),
          _row(
            title: 'Payroll notifications',
            subtitle: 'Payslip availability and payroll notices.',
            value: _nPayroll,
            onChanged: (v) {
              _nPayroll = v;
              _setBool(ProfileAppSettingsKeys.notifPayroll, v);
            },
          ),
          _row(
            title: 'System announcements',
            subtitle: 'Municipality-wide HR announcements.',
            value: _nAnnounce,
            onChanged: (v) {
              _nAnnounce = v;
              _setBool(ProfileAppSettingsKeys.notifAnnounce, v);
            },
          ),
          _row(
            title: 'Task reminders',
            subtitle: 'Upcoming deadlines and assigned activities.',
            value: _nTask,
            onChanged: (v) {
              _nTask = v;
              _setBool(ProfileAppSettingsKeys.notifTask, v);
            },
          ),
        ],
      ),
    );
  }
}

class ProfilePreferenceSettingsPanel extends StatelessWidget {
  const ProfilePreferenceSettingsPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final modeNotifier = context.watch<ThemeModeNotifier>();
    final isDark = modeNotifier.mode == ThemeMode.dark;

    return ModernProfileCard(
      title: 'Appearance',
      subtitle: 'Choose how HRMS looks on this device.',
      child: Row(
        children: [
          Expanded(
            child: ProfileThemeChoice(
              label: 'Light',
              icon: Icons.light_mode_outlined,
              selected: !isDark,
              onTap: () => modeNotifier.setMode(ThemeMode.light),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ProfileThemeChoice(
              label: 'Dark',
              icon: Icons.dark_mode_outlined,
              selected: isDark,
              onTap: () => modeNotifier.setMode(ThemeMode.dark),
            ),
          ),
        ],
      ),
    );
  }
}

class ProfileAboutSettingsPanel extends StatelessWidget {
  const ProfileAboutSettingsPanel({super.key});

  @override
  Widget build(BuildContext context) => const SettingsAboutPanel();
}
