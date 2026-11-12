import 'package:flutter/material.dart';

import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/shared/screens/legal_page.dart';
import 'profile_modern_ui.dart';

/// Compact About content. Only links that actually exist in the app.
class SettingsAboutPanel extends StatelessWidget {
  const SettingsAboutPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return ModernProfileCard(
      title: 'About Unity Pillar',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Human Resource Management System',
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
              color: AppTheme.dashTextPrimaryOf(context),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Municipality of Plaridel',
            style: TextStyle(
              fontSize: 13,
              color: AppTheme.dashTextSecondaryOf(context),
            ),
          ),
          const SizedBox(height: 14),
          const ProfileInfoRow(label: 'Version', value: '1.0'),
          const SizedBox(height: 8),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => LegalPage.openTerms(context),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Terms & Conditions',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.dashTextPrimaryOf(context),
                        ),
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: AppTheme.dashTextSecondaryOf(context),
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
