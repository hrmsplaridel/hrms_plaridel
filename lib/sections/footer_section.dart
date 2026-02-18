import 'package:flutter/material.dart';
import '../constants/app_theme.dart';
import '../widgets/section_container.dart';

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
          vertical: 32,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              'Municipality of Plaridel - Human Resource Management Office',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppTheme.white,
                fontSize: isWide ? 18 : 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                TextButton(
                  onPressed: () => _handlePrivacyPolicy(context),
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.white,
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text(
                    'Privacy Policy',
                    style: TextStyle(
                      decoration: TextDecoration.underline,
                      fontSize: 14,
                    ),
                  ),
                ),
                Text(
                  '|',
                  style: TextStyle(
                    color: AppTheme.white.withOpacity(0.8),
                    fontSize: 14,
                  ),
                ),
                TextButton(
                  onPressed: () => _handleTermsOfService(context),
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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                'This portal complies with Republic Act No. 10173 or the Data Privacy Act of 2012. All personal information collected is processed in accordance with the provisions of the law.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppTheme.white.withOpacity(0.9),
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '© 2026 Municipality of Plaridel. All rights reserved.',
              style: TextStyle(
                color: AppTheme.white.withOpacity(0.85),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _handlePrivacyPolicy(BuildContext context) {
    // Ready for backend integration
  }

  void _handleTermsOfService(BuildContext context) {
    // Ready for backend integration
  }
}
