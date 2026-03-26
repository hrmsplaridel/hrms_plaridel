import 'package:flutter/material.dart';
import '../constants/app_theme.dart';
import '../widgets/section_container.dart';

/// Footer: Data Privacy Notice, Terms of Service, Copyright, Municipality branding.
class FooterSection extends StatelessWidget {
  const FooterSection({super.key});

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 800;

    return Container(
      width: double.infinity,
      color: AppTheme.primaryNavy,
      child: SectionContainer(
        backgroundColor: AppTheme.primaryNavy,
        padding: EdgeInsets.symmetric(
          horizontal: isWide ? 80 : 24,
          vertical: 28,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              'Municipality of Plaridel',
              style: TextStyle(
                color: AppTheme.white,
                fontSize: isWide ? 22 : 20,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Human Resource Management System (HRMS)',
              style: TextStyle(
                color: AppTheme.white.withOpacity(0.9),
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 20),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                TextButton(
                  onPressed: () => _onDataPrivacy(context),
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.white,
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text(
                    'Data Privacy Notice',
                    style: TextStyle(
                      decoration: TextDecoration.underline,
                      fontSize: 14,
                    ),
                  ),
                ),
                Text(
                  '|',
                  style: TextStyle(
                    color: AppTheme.white.withOpacity(0.7),
                    fontSize: 14,
                  ),
                ),
                TextButton(
                  onPressed: () => _onTermsOfService(context),
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.white,
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text(
                    'Terms of Service',
                    style: TextStyle(
                      decoration: TextDecoration.underline,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              '© ${DateTime.now().year} Municipality of Plaridel. All rights reserved.',
              style: TextStyle(
                color: AppTheme.white.withOpacity(0.85),
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onDataPrivacy(BuildContext context) {
    // Ready for backend / policy page
  }

  void _onTermsOfService(BuildContext context) {
    // Ready for backend / terms page
  }
}
