import 'package:flutter/material.dart';

import '../../../landingpage/constants/app_theme.dart';

/// Reusable settings content (sections only, no scaffold).
/// Currently simplified: we hide all advanced settings.
class SettingsContent extends StatelessWidget {
  const SettingsContent({super.key});

  @override
  Widget build(BuildContext context) {
    // Empty placeholder so the Profile & Settings page only shows profile info.
    return const SizedBox.shrink();
  }
}

/// Standalone Settings page for admin and employee dashboards.
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
        child: const SettingsContent(),
      ),
    );
  }
}

// _SettingsSection removed since all advanced settings were hidden.
