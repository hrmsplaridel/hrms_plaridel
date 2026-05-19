import 'package:flutter/material.dart';

import '../../landingpage/constants/app_theme.dart';
import '../widgets/profile_modern_ui.dart';
import 'profile_page.dart';

/// App settings (notification, preference, about) live in [ProfileContent].
/// This page is a thin standalone route for deep links or legacy navigation.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, this.initialTab = ProfilePageTab.notification});

  final ProfilePageTab initialTab;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.dashCanvasOf(context),
      appBar: AppBar(
        backgroundColor: AppTheme.dashIsDark(context)
            ? AppTheme.dashPanelOf(context)
            : AppTheme.white,
        elevation: 0,
        scrolledUnderElevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Settings',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 28),
        child: ProfileContent(
          showAccountSection: false,
          showPasswordSection: false,
          showAppSettings: true,
          initialTab: initialTab,
        ),
      ),
    );
  }
}
