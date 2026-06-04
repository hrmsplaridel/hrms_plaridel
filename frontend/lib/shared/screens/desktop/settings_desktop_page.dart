import 'package:flutter/material.dart';

import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/shared/screens/profile_page.dart';
import 'package:hrms_plaridel/shared/widgets/profile_modern_ui.dart';

class SettingsDesktopPage extends StatelessWidget {
  const SettingsDesktopPage({
    super.key,
    this.initialTab = ProfilePageTab.notification,
  });

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
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
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
