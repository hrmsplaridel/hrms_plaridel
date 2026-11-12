import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/notifications/data/notification_preference_store.dart';
import 'package:hrms_plaridel/features/notifications/data/notification_provider.dart';
import 'package:hrms_plaridel/providers/theme_mode_provider.dart';
import 'profile_modern_ui.dart';
import 'settings_about_panel.dart';

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
  Map<String, bool> _prefs = {
    for (final c in NotificationPreferenceStore.managedCategories) c: true,
  };

  static const _rows = <({String category, String title, String subtitle})>[
    (
      category: NotificationPreferenceStore.leave,
      title: 'Leave request updates',
      subtitle: 'Status changes related to leave requests.',
    ),
    (
      category: NotificationPreferenceStore.locator,
      title: 'Locator slip updates',
      subtitle: 'Locator requests and approval status changes.',
    ),
    (
      category: NotificationPreferenceStore.overtime,
      title: 'Overtime updates',
      subtitle: 'Overtime request status and approvals.',
    ),
    (
      category: NotificationPreferenceStore.recruitment,
      title: 'Recruitment updates',
      subtitle: 'Recruitment and hiring notifications.',
    ),
    (
      category: NotificationPreferenceStore.training,
      title: 'Training updates',
      subtitle: 'Learning and development training notices.',
    ),
    (
      category: NotificationPreferenceStore.formSignature,
      title: 'E-signature requests',
      subtitle: 'Forms that need your electronic signature.',
    ),
    (
      category: NotificationPreferenceStore.general,
      title: 'System alerts',
      subtitle: 'Important HRMS alerts such as approval setup notices.',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await NotificationPreferenceStore.load();
      if (!mounted) return;
      setState(() {
        _prefs = prefs;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _setCategory(String category, bool value) async {
    setState(() => _prefs[category] = value);
    try {
      await NotificationPreferenceStore.setCategory(category, value);
      if (!mounted) return;
      await context.read<NotificationProvider>().reloadPreferences();
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
              onChanged: onChanged,
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
      subtitle:
          'Choose which HRMS alerts appear in your notification bell.',
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
          for (final row in _rows)
            _row(
              title: row.title,
              subtitle: row.subtitle,
              value: _prefs[row.category] ?? true,
              onChanged: (v) => _setCategory(row.category, v),
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
