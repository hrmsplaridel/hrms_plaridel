import 'package:flutter/material.dart';
import '../constants/app_theme.dart';
import '../widgets/section_container.dart';

/// Job Vacancies as announcement area (controlled by HR Head/Admin via RSP module).
/// Shows only whether there is hiring or no vacancies; applicants see status only.
/// Optional [headline] and [body] from admin form; otherwise default text by [hasVacancies].
/// Keeps "Want to apply? Go to Recruitment Process" for when they want to apply.
class JobVacanciesSection extends StatelessWidget {
  const JobVacanciesSection({
    super.key,
    required this.hasVacancies,
    this.headline,
    this.body,
    this.onGoToRecruitmentTap,
  });

  /// Whether there are job openings. Controlled by HR Head/Admin (e.g. from backend).
  final bool hasVacancies;

  /// Custom headline (from RSP form). If null, uses default by [hasVacancies].
  final String? headline;

  /// Custom body/description (from RSP form). If null, uses default by [hasVacancies].
  final String? body;

  final VoidCallback? onGoToRecruitmentTap;

  String get _displayHeadline {
    if (headline != null && headline!.trim().isNotEmpty) return headline!.trim();
    return hasVacancies
        ? 'We are currently accepting applications.'
        : 'There are no job vacancies at the moment.';
  }

  String get _displayBody {
    if (body != null && body!.trim().isNotEmpty) return body!.trim();
    return hasVacancies
        ? 'There are job openings you may apply to. Follow the recruitment process below to start your application.'
        : 'Please check back later for updates. When vacancies are posted, you may apply through the Recruitment Process.';
  }

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
                            _displayHeadline,
                            style: TextStyle(
                              color: AppTheme.primaryNavy,
                              fontSize: AppTheme.cardTitleSize,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _displayBody,
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
