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
    this.onApplyForVacancyTap,
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

  /// When provided, each vacancy card shows a job-specific "Apply" button.
  final void Function(JobVacancyItem vacancy)? onApplyForVacancyTap;

  String _truncate(String s, int maxLen) {
    final v = s.trim();
    if (v.length <= maxLen) return v;
    if (maxLen <= 1) return '…';
    return v.substring(0, maxLen) + '…';
  }

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
      borderRadius: 20,
      withShadow: true,
      margin: const EdgeInsets.symmetric(vertical: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Job Vacancies',
            style: TextStyle(
              color: AppTheme.primaryNavy,
              fontSize: AppTheme.sectionTitleSize + 2,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            width: 48,
            height: 4,
            decoration: BoxDecoration(
              color: AppTheme.primaryNavy.withOpacity(0.8),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 18),
          if (useMultiple)
            LayoutBuilder(
              builder: (context, constraints) {
                final maxWidth = constraints.maxWidth.isFinite
                    ? constraints.maxWidth
                    : MediaQuery.of(context).size.width;
                final twoColumns = maxWidth >= 980;
                final cardWidth = twoColumns ? (maxWidth - 16) / 2 : maxWidth;
                return Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: List.generate(list.length, (i) {
                    final v = list[i];
                    final headlineText = _displayHeadline(v.headline);
                    final applyLabel = headlineText.isNotEmpty
                        ? 'Apply to: ${_truncate(headlineText, 26)}'
                        : 'Apply Now';

                    return SizedBox(
                      width: cardWidth,
                      child: _VacancyCard(
                        headline: headlineText,
                        body: _displayBody(v.body),
                        hasVacancies: hasVacancies,
                        applyLabel: applyLabel,
                        onApplyTap: hasVacancies
                            ? () => onApplyForVacancyTap?.call(v)
                            : null,
                      ),
                    );
                  }),
                );
              },
            )
          else
            _VacancyCard(
              headline: _displayHeadline(headline),
              body: _displayBody(body),
              hasVacancies: hasVacancies,
              applyLabel: 'Apply Now',
              onApplyTap: hasVacancies
                  ? () => onApplyForVacancyTap?.call(
                        JobVacancyItem(headline: headline, body: body),
                      )
                  : null,
            ),
          const SizedBox(height: 22),
          if (onGoToRecruitmentTap != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                color: AppTheme.primaryNavy.withOpacity(0.06),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.primaryNavy.withOpacity(0.14)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded,
                      color: AppTheme.primaryNavy, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Want to apply? Complete the recruitment process below.',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: onGoToRecruitmentTap,
                    icon: const Icon(Icons.how_to_reg_rounded, size: 18),
                    label: const Text('Start'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.primaryNavy,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
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

class _VacancyCard extends StatelessWidget {
  const _VacancyCard({
    required this.headline,
    required this.body,
    required this.hasVacancies,
    this.applyLabel,
    this.onApplyTap,
  });
  final String headline;
  final String body;
  final bool hasVacancies;
  final String? applyLabel;
  final VoidCallback? onApplyTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(16),
        border: hasVacancies ? null : Border.all(color: Colors.grey.shade300, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(hasVacancies ? 0.06 : 0.03),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: (hasVacancies ? AppTheme.primaryNavy : AppTheme.textSecondary).withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              hasVacancies ? Icons.campaign_rounded : Icons.work_off_rounded,
              size: 26,
              color: hasVacancies ? AppTheme.primaryNavy : AppTheme.textSecondary,
            ),
          ),
          const SizedBox(width: 18),
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
                if (hasVacancies && onApplyTap != null) ...[
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: onApplyTap,
                    icon: const Icon(Icons.how_to_reg_rounded, size: 18),
                    label: Text(
                      applyLabel ?? 'Apply Now',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.primaryNavy,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
