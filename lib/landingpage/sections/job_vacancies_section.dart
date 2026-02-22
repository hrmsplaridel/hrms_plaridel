import 'package:flutter/material.dart';
import '../constants/app_theme.dart';
import '../widgets/section_container.dart';

/// Job Vacancies as announcement area (controlled by HR Head/Admin).
/// Shows only whether there is hiring or no vacancies; applicants see status only.
/// Keeps "Want to apply? Go to Recruitment Process" for when they want to apply.
class JobVacanciesSection extends StatelessWidget {
  const JobVacanciesSection({
    super.key,
    required this.hasVacancies,
    this.onGoToRecruitmentTap,
  });

  /// Whether there are job openings. Controlled by HR Head/Admin (e.g. from backend).
  final bool hasVacancies;

  final VoidCallback? onGoToRecruitmentTap;

  @override
  Widget build(BuildContext context) {
    return SectionContainer(
      backgroundColor: AppTheme.sectionAlt,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Job Vacancies',
            style: TextStyle(
              color: AppTheme.primaryNavy,
              fontSize: AppTheme.sectionTitleSize,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppTheme.white,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      hasVacancies ? Icons.campaign_rounded : Icons.info_outline_rounded,
                      size: 28,
                      color: hasVacancies ? AppTheme.primaryNavy : AppTheme.textSecondary,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            hasVacancies
                                ? 'We are currently accepting applications.'
                                : 'There are no job vacancies at the moment.',
                            style: TextStyle(
                              color: AppTheme.primaryNavy,
                              fontSize: AppTheme.cardTitleSize,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            hasVacancies
                                ? 'There are job openings you may apply to. Follow the recruitment process below to start your application.'
                                : 'Please check back later for updates. When vacancies are posted, you may apply through the Recruitment Process.',
                            style: TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: AppTheme.smallSize,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Center(
            child: TextButton.icon(
              onPressed: onGoToRecruitmentTap,
              icon: const Icon(Icons.how_to_reg, size: 18),
              label: const Text('Want to apply? Go to Recruitment Process'),
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.primaryNavy,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
