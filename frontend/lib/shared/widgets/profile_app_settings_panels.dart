import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/providers/theme_mode_provider.dart';
import 'profile_modern_ui.dart';
import 'settings_about_panel.dart';

/// Shared preference keys for notification & app preference toggles.
abstract final class ProfileAppSettingsKeys {
  static const notifEmail = 'settings_notif_email_v1';
  static const notifAttendance = 'settings_notif_attendance_v1';
  static const notifLeave = 'settings_notif_leave_v1';
  static const notifAnnounce = 'settings_notif_announcements_v1';
  static const notifTask = 'settings_notif_tasks_v1';

  static const prefEmail = 'settings_pref_email_v1';
  static const prefAttendance = 'settings_pref_attendance_v1';
  static const prefLeave = 'settings_pref_leave_v1';
  static const prefPayroll = 'settings_pref_payroll_v1';
  static const prefAnnounce = 'settings_pref_announcements_v1';
  static const prefTask = 'settings_pref_tasks_v1';
  static const prefLanguage = 'settings_pref_language_v1';
}

/// Notification toggles (moved from Settings → My Profile).
class ProfileNotificationSettingsPanel extends StatefulWidget {
  const ProfileNotificationSettingsPanel({super.key});

  @override
  State<ProfileNotificationSettingsPanel> createState() =>
      _ProfileNotificationSettingsPanelState();
}

class _ProfileNotificationSettingsPanelState
    extends State<ProfileNotificationSettingsPanel> {
  bool _loading = true;
  bool _nEmail = true;
  bool _nAttendance = true;
  bool _nLeave = true;
  bool _nAnnounce = true;
  bool _nTask = true;

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
  }

  void _showSavedHint(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _setAllNotifications(bool enabled) async {
    setState(() {
      _nEmail = enabled;
      _nAttendance = enabled;
      _nLeave = enabled;
      _nAnnounce = enabled;
      _nTask = enabled;
    });
    try {
      final p = await SharedPreferences.getInstance();
      await Future.wait([
        p.setBool(ProfileAppSettingsKeys.notifEmail, enabled),
        p.setBool(ProfileAppSettingsKeys.notifAttendance, enabled),
        p.setBool(ProfileAppSettingsKeys.notifLeave, enabled),
        p.setBool(ProfileAppSettingsKeys.notifAnnounce, enabled),
        p.setBool(ProfileAppSettingsKeys.notifTask, enabled),
      ]);
    } catch (_) {}
    _showSavedHint(
      enabled
          ? 'All notification channels enabled.'
          : 'All notification channels disabled.',
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    Widget toggle(
      String key,
      bool value,
      ValueChanged<bool> onChanged,
      String title,
      String subtitle,
    ) {
      return SwitchListTile.adaptive(
        value: value,
        onChanged: (v) {
          setState(() => onChanged(v));
          _setBool(key, v);
        },
        title: Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: AppTheme.dashTextPrimaryOf(context),
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            fontSize: 13,
            color: AppTheme.dashTextSecondaryOf(context),
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      );
    }

    return ModernProfileCard(
      title: 'Notification',
      icon: Icons.notifications_none_rounded,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Quick actions',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.dashTextSecondaryOf(context),
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () => _setAllNotifications(true),
                icon: const Icon(Icons.done_all_rounded, size: 18),
                label: const Text('Enable all'),
              ),
              TextButton.icon(
                onPressed: () => _setAllNotifications(false),
                icon: const Icon(Icons.notifications_off_outlined, size: 18),
                label: const Text('Disable all'),
              ),
            ],
          ),
          const Divider(height: 1),
          toggle(
            ProfileAppSettingsKeys.notifEmail,
            _nEmail,
            (v) => _nEmail = v,
            'Email notifications',
            'Messages about approvals, HR updates, and system mail.',
          ),
          const Divider(height: 1),
          toggle(
            ProfileAppSettingsKeys.notifAttendance,
            _nAttendance,
            (v) => _nAttendance = v,
            'Attendance alerts',
            'Missed punches, tardiness summaries, and DTR anomalies.',
          ),
          const Divider(height: 1),
          toggle(
            ProfileAppSettingsKeys.notifLeave,
            _nLeave,
            (v) => _nLeave = v,
            'Leave request updates',
            'Statuses and comments on your filings.',
          ),
          const Divider(height: 1),
          toggle(
            ProfileAppSettingsKeys.notifAnnounce,
            _nAnnounce,
            (v) => _nAnnounce = v,
            'System announcements',
            'Memos and HR-wide broadcasts.',
          ),
          const Divider(height: 1),
          toggle(
            ProfileAppSettingsKeys.notifTask,
            _nTask,
            (v) => _nTask = v,
            'Task reminders',
            'Upcoming deadlines and assigned activities.',
          ),
        ],
      ),
    );
  }
}

/// App preferences (moved from Settings → My Profile).
class ProfilePreferenceSettingsPanel extends StatefulWidget {
  const ProfilePreferenceSettingsPanel({super.key});

  @override
  State<ProfilePreferenceSettingsPanel> createState() =>
      _ProfilePreferenceSettingsPanelState();
}

class _ProfilePreferenceSettingsPanelState
    extends State<ProfilePreferenceSettingsPanel> {
  bool _loading = true;
  bool _pEmail = true;
  bool _pAttendance = true;
  bool _pLeave = true;
  bool _pPayroll = true;
  bool _pAnnounce = true;
  bool _pTask = true;
  String _prefLanguage = 'en';

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
        _pEmail = p.getBool(ProfileAppSettingsKeys.prefEmail) ?? true;
        _pAttendance = p.getBool(ProfileAppSettingsKeys.prefAttendance) ?? true;
        _pLeave = p.getBool(ProfileAppSettingsKeys.prefLeave) ?? true;
        _pPayroll = p.getBool(ProfileAppSettingsKeys.prefPayroll) ?? true;
        _pAnnounce = p.getBool(ProfileAppSettingsKeys.prefAnnounce) ?? true;
        _pTask = p.getBool(ProfileAppSettingsKeys.prefTask) ?? true;
        _prefLanguage =
            p.getString(ProfileAppSettingsKeys.prefLanguage) ?? 'en';
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
  }

  Future<void> _setString(String key, String value) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(key, value);
    } catch (_) {}
  }

  void _showSavedHint(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _setAllPreferences(bool enabled) async {
    setState(() {
      _pEmail = enabled;
      _pAttendance = enabled;
      _pLeave = enabled;
      _pPayroll = enabled;
      _pAnnounce = enabled;
      _pTask = enabled;
    });
    try {
      final p = await SharedPreferences.getInstance();
      await Future.wait([
        p.setBool(ProfileAppSettingsKeys.prefEmail, enabled),
        p.setBool(ProfileAppSettingsKeys.prefAttendance, enabled),
        p.setBool(ProfileAppSettingsKeys.prefLeave, enabled),
        p.setBool(ProfileAppSettingsKeys.prefPayroll, enabled),
        p.setBool(ProfileAppSettingsKeys.prefAnnounce, enabled),
        p.setBool(ProfileAppSettingsKeys.prefTask, enabled),
      ]);
    } catch (_) {}
    _showSavedHint(
      enabled
          ? 'All feed preferences enabled.'
          : 'All feed preferences disabled.',
    );
  }

  Future<void> _resetDefaults() async {
    setState(() {
      _pEmail = true;
      _pAttendance = true;
      _pLeave = true;
      _pPayroll = true;
      _pAnnounce = true;
      _pTask = true;
      _prefLanguage = 'en';
    });
    try {
      final p = await SharedPreferences.getInstance();
      await Future.wait([
        p.setBool(ProfileAppSettingsKeys.prefEmail, true),
        p.setBool(ProfileAppSettingsKeys.prefAttendance, true),
        p.setBool(ProfileAppSettingsKeys.prefLeave, true),
        p.setBool(ProfileAppSettingsKeys.prefPayroll, true),
        p.setBool(ProfileAppSettingsKeys.prefAnnounce, true),
        p.setBool(ProfileAppSettingsKeys.prefTask, true),
        p.setString(ProfileAppSettingsKeys.prefLanguage, 'en'),
      ]);
    } catch (_) {}
    if (mounted) {
      context.read<ThemeModeNotifier>().setMode(ThemeMode.light);
    }
    _showSavedHint('Preferences reset to defaults.');
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final modeNotifier = context.watch<ThemeModeNotifier>();
    final selectedTheme = modeNotifier.mode == ThemeMode.dark
        ? ThemeMode.dark
        : ThemeMode.light;

    Widget toggle(
      String key,
      bool value,
      ValueChanged<bool> onChanged,
      String title,
      String subtitle,
    ) {
      return SwitchListTile.adaptive(
        value: value,
        onChanged: (v) {
          setState(() => onChanged(v));
          _setBool(key, v);
        },
        title: Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: AppTheme.dashTextPrimaryOf(context),
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            fontSize: 13,
            color: AppTheme.dashTextSecondaryOf(context),
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      );
    }

    return ModernProfileCard(
      title: 'Preference',
      icon: Icons.tune_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Appearance',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: AppTheme.dashTextPrimaryOf(context),
            ),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<ThemeMode>(
            initialValue: selectedTheme,
            items: const [
              DropdownMenuItem(
                value: ThemeMode.light,
                child: Text('Light mode'),
              ),
              DropdownMenuItem(
                value: ThemeMode.dark,
                child: Text('Dark mode'),
              ),
            ],
            onChanged: (v) {
              if (v == null) return;
              modeNotifier.setMode(v);
              _showSavedHint(
                v == ThemeMode.dark
                    ? 'Dark mode enabled.'
                    : 'Light mode enabled.',
              );
            },
            decoration: AppTheme.dashInputDecoration(
              context,
              labelText: 'Theme',
            ),
            style: AppTheme.dashFieldTextStyle(context),
            dropdownColor: AppTheme.dashPanelOf(context),
          ),
          const Divider(height: 24),
          Text(
            'Language',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: AppTheme.dashTextPrimaryOf(context),
            ),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _prefLanguage,
            items: [
              DropdownMenuItem(
                value: 'en',
                child: Text(
                  'English',
                  style: AppTheme.dashFieldTextStyle(context),
                ),
              ),
              DropdownMenuItem(
                value: 'fil',
                child: Text(
                  'Filipino',
                  style: AppTheme.dashFieldTextStyle(context),
                ),
              ),
            ],
            onChanged: (v) {
              if (v == null) return;
              setState(() => _prefLanguage = v);
              _setString(ProfileAppSettingsKeys.prefLanguage, v);
            },
            decoration: AppTheme.dashInputDecoration(
              context,
              labelText: 'Language',
            ),
            style: AppTheme.dashFieldTextStyle(context),
            dropdownColor: AppTheme.dashPanelOf(context),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              TextButton.icon(
                onPressed: () => _setAllPreferences(true),
                icon: const Icon(Icons.done_all_rounded, size: 18),
                label: const Text('Enable all'),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: () => _setAllPreferences(false),
                icon: const Icon(Icons.visibility_off_outlined, size: 18),
                label: const Text('Disable all'),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _resetDefaults,
                icon: const Icon(Icons.restart_alt_rounded, size: 18),
                label: const Text('Reset defaults'),
              ),
            ],
          ),
          const Divider(height: 24),
          toggle(
            ProfileAppSettingsKeys.prefEmail,
            _pEmail,
            (v) => _pEmail = v,
            'Email notifications',
            'How you prefer to receive email digests.',
          ),
          const Divider(height: 1),
          toggle(
            ProfileAppSettingsKeys.prefAttendance,
            _pAttendance,
            (v) => _pAttendance = v,
            'Attendance alerts',
            'Highlight attendance items in your feed.',
          ),
          const Divider(height: 1),
          toggle(
            ProfileAppSettingsKeys.prefLeave,
            _pLeave,
            (v) => _pLeave = v,
            'Leave request updates',
            'Surface leave workflow in quick access.',
          ),
          const Divider(height: 1),
          toggle(
            ProfileAppSettingsKeys.prefPayroll,
            _pPayroll,
            (v) => _pPayroll = v,
            'Payroll notifications',
            'Payslip availability and payroll cut-off notices.',
          ),
          const Divider(height: 1),
          toggle(
            ProfileAppSettingsKeys.prefAnnounce,
            _pAnnounce,
            (v) => _pAnnounce = v,
            'System announcements',
            'Pin important municipality-wide notices.',
          ),
          const Divider(height: 1),
          toggle(
            ProfileAppSettingsKeys.prefTask,
            _pTask,
            (v) => _pTask = v,
            'Task reminders',
            'Nudges for pending HR or office tasks.',
          ),
        ],
      ),
    );
  }
}

/// About panel for profile tab.
class ProfileAboutSettingsPanel extends StatelessWidget {
  const ProfileAboutSettingsPanel({super.key});

  @override
  Widget build(BuildContext context) => const SettingsAboutPanel();
}
