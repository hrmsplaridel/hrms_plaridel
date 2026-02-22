import 'package:flutter/material.dart';
import '../constants/app_theme.dart';
import '../widgets/section_container.dart';

/// About the HR Office: mission and CSC compliance.
class AboutHrSection extends StatelessWidget {
  const AboutHrSection({super.key});

  @override
  Widget build(BuildContext context) {
    return SectionContainer(
      backgroundColor: AppTheme.offWhite,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'About the HR Office',
            style: TextStyle(
              color: AppTheme.primaryNavy,
              fontSize: AppTheme.sectionTitleSize,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'The Human Resource Management Office of the Municipality of Plaridel ensures '
            'efficient, merit-based recruitment and selection of personnel, and provides '
            'continuous learning and development opportunities to build a competent, ethical, '
            'and service-oriented workforce. Our policies and practices are aligned with '
            'Civil Service Commission (CSC) rules and standards and the Prime HRM roadmap.',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: AppTheme.bodySize,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}
