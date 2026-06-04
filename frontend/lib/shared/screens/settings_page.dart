import 'package:flutter/material.dart';

import 'package:hrms_plaridel/core/utils/platform_layout.dart';
import 'package:hrms_plaridel/shared/screens/desktop/settings_desktop_page.dart';
import 'package:hrms_plaridel/shared/screens/mobile/settings_mobile_page.dart';
import 'package:hrms_plaridel/shared/widgets/profile_modern_ui.dart';

/// App settings (notification, preference, about) live in [ProfileContent].
/// This page is a thin standalone route for deep links or legacy navigation.
class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    this.initialTab = ProfilePageTab.notification,
  });

  final ProfilePageTab initialTab;

  @override
  Widget build(BuildContext context) {
    if (PlatformLayout.isMobile(context)) {
      return SettingsMobilePage(initialTab: initialTab);
    }
    return SettingsDesktopPage(initialTab: initialTab);
  }
}
