import 'package:flutter/material.dart';
import '../../../landingpage/constants/app_theme.dart';
import 'profile_page.dart';
import 'settings_page.dart';

/// Single screen that combines My Profile and Settings. Used when the user
/// chooses "Profile & Settings" from the dashboard menu.
class ProfileAndSettingsPage extends StatelessWidget {
  const ProfileAndSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWeb = width >= 900;
    final padding = isWeb ? 32.0 : 16.0;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
          color: AppTheme.textPrimary,
        ),
        title: Text(
          'Profile & Settings',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: isWeb ? 22 : 20,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.symmetric(
          horizontal: padding,
          vertical: isWeb ? 32 : 20,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: isWeb ? 1000 : double.infinity,
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ProfileContent(),
                SizedBox(height: 32),
                SettingsContent(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
