import 'package:flutter/material.dart';
import '../../data/job_vacancy_announcement.dart';
import '../constants/app_theme.dart';
import '../widgets/section_container.dart';

/// Job Vacancies as announcement area (controlled by HR Head/Admin via RSP module).
/// When [vacancies] is non-empty, shows each entry as a card; otherwise uses single [headline]/[body] or defaults.
class JobVacanciesSection extends StatelessWidget {
  const JobVacanciesSection({
    super.key,
    required this.hasVacancies,
    this.headline,
    this.body,
    this.vacancies,
    this.onGoToRecruitmentTap,
  });

  /// Whether there are job openings. Controlled by HR Head/Admin (e.g. from backend).
  final bool hasVacancies;

  /// Custom headline (from RSP form). If null, uses default by [hasVacancies].
  final String? headline;

  /// Custom body/description (from RSP form). If null, uses default by [hasVacancies].
  final String? body;

  /// Multiple job vacancy entries. When non-empty, each is shown as a card.
  final List<JobVacancyItem>? vacancies;

  final VoidCallback? onGoToRecruitmentTap;

  String _displayHeadline(String? h) {
    if (h != null && h.trim().isNotEmpty) return h.trim();
    return hasVacancies
        ? 'We are currently accepting applications.'
        : 'There is no job hiring right now.';
  }

  String _displayBody(String? b) {
    if (b != null && b.trim().isNotEmpty) return b.trim();
    return hasVacancies
        ? 'There are job openings you may apply to. Follow the recruitment process below to start your application.'
        : 'There are no open positions at the moment. Please check back later for updates. When vacancies are posted, you may apply through the Recruitment Process below.';
  }

  @override
  Widget build(BuildContext context) {
    final list = vacancies ?? [];
    final useMultiple = hasVacancies && list.isNotEmpty;
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
          if (useMultiple)
            ...List.generate(list.length, (i) {
              final v = list[i];
              return Padding(
                padding: EdgeInsets.only(bottom: i < list.length - 1 ? 16 : 0),
                child: _VacancyCard(
                  headline: _displayHeadline(v.headline),
                  body: _displayBody(v.body),
                  hasVacancies: hasVacancies,
                ),
              );
            })
          else
            _VacancyCard(
              headline: _displayHeadline(headline),
              body: _displayBody(body),
              hasVacancies: hasVacancies,
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

class _VacancyCard extends StatelessWidget {
  const _VacancyCard({required this.headline, required this.body, required this.hasVacancies});
  final String headline;
  final String body;
  final bool hasVacancies;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(8),
        border: hasVacancies ? null : Border.all(color: Colors.grey.shade300, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(hasVacancies ? 0.04 : 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            hasVacancies ? Icons.campaign_rounded : Icons.work_off_rounded,
            size: 28,
            color: hasVacancies ? AppTheme.primaryNavy : AppTheme.textSecondary,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  headline,
                  style: TextStyle(
                    color: hasVacancies ? AppTheme.primaryNavy : AppTheme.textSecondary,
                    fontSize: AppTheme.cardTitleSize,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  body,
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
    );
  }
}
