import 'package:flutter/material.dart';
import '../../landingpage/constants/app_theme.dart';

/// Shared Settings page for admin and employee dashboards.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        backgroundColor: AppTheme.white,
        elevation: 0,
        scrolledUnderElevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
          color: AppTheme.textPrimary,
        ),
        title: Text('Settings', style: TextStyle(color: AppTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SettingsSection(
              title: 'Account',
              children: [
                ListTile(
                  leading: Icon(Icons.person_outline_rounded, color: AppTheme.primaryNavy),
                  title: Text('Profile', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w500)),
                  subtitle: Text('Name, email, and contact', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                  trailing: const Icon(Icons.chevron_right_rounded, color: AppTheme.textSecondary),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  onTap: () {},
                ),
                ListTile(
                  leading: Icon(Icons.lock_outline_rounded, color: AppTheme.primaryNavy),
                  title: Text('Password', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w500)),
                  subtitle: Text('Change your password', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                  trailing: const Icon(Icons.chevron_right_rounded, color: AppTheme.textSecondary),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  onTap: () {},
                ),
              ],
            ),
            const SizedBox(height: 24),
            _SettingsSection(
              title: 'Preferences',
              children: [
                ListTile(
                  leading: Icon(Icons.notifications_outlined, color: AppTheme.primaryNavy),
                  title: Text('Notifications', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w500)),
                  subtitle: Text('Email and in-app notifications', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                  trailing: const Icon(Icons.chevron_right_rounded, color: AppTheme.textSecondary),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  onTap: () {},
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12),
          child: Text(title, style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
        ),
        Container(
          decoration: BoxDecoration(
            color: AppTheme.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.black.withOpacity(0.06)),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 12, offset: const Offset(0, 2))],
          ),
          child: Column(children: children),
        ),
      ],
    );
  }
}
