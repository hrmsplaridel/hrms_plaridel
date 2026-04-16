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

  String _displayHeadline(String? h) {
    // When hiring is off, never show saved titles/descriptions—only the closed state.
    if (!hasVacancies) return 'There is no job hiring right now.';
    if (h != null && h.trim().isNotEmpty) return h.trim();
    return 'We are currently accepting applications.';
  }

  String _displayBody(String? b) {
    if (!hasVacancies) {
      return 'There are no open positions at the moment. Please check back later for updates. When vacancies are posted, you may apply through the Recruitment Process below.';
    }
    if (b != null && b.trim().isNotEmpty) return b.trim();
    return 'There are job openings you may apply to. Follow the recruitment process below to start your application.';
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
            width: 64,
            height: 5,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(3),
              gradient: LinearGradient(
                colors: [
                  AppTheme.primaryNavy,
                  AppTheme.primaryNavyLight,
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            hasVacancies
                ? 'Open positions you can apply for online. Each role lists a short summary—full details and required documents are in the application form.'
                : 'We are not accepting applications at this time. Please check back later when new positions are announced.',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 15,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 22),
          if (useMultiple)
            LayoutBuilder(
              builder: (context, constraints) {
                final maxWidth = constraints.maxWidth.isFinite
                    ? constraints.maxWidth
                    : MediaQuery.of(context).size.width;
                final twoColumns = maxWidth >= 900;
                final gap = 20.0;
                final cardFlexWidth = twoColumns
                    ? (maxWidth - gap) / 2
                    : maxWidth;

                Widget cardFor(JobVacancyItem v) {
                  final headlineText = _displayHeadline(v.headline);
                  final max = v.maxApplicants;
                  final count = v.applicationCount ?? 0;
                  final slotLine = (max != null && max >= 1)
                      ? '$count of $max active applicants'
                      : null;
                  final quotaFull = v.isApplicationQuotaFull;
                  return _VacancyCard(
                    headline: headlineText,
                    body: _displayBody(v.body),
                    hasVacancies: hasVacancies,
                    minTall: twoColumns,
                    slotSummaryLine: slotLine,
                    applicationQuotaFull: quotaFull,
                    onApplyTap: hasVacancies && !quotaFull
                        ? () => onApplyForVacancyTap?.call(v)
                        : null,
                  );
                }

                if (!twoColumns) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < list.length; i++) ...[
                        if (i > 0) SizedBox(height: gap),
                        cardFor(list[i]),
                      ],
                    ],
                  );
                }

                final rows = <Widget>[];
                for (var i = 0; i < list.length; i += 2) {
                  if (i > 0) rows.add(SizedBox(height: gap));
                  if (i + 1 < list.length) {
                    rows.add(
                      IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(
                              width: cardFlexWidth,
                              child: cardFor(list[i]),
                            ),
                            SizedBox(width: gap),
                            SizedBox(
                              width: cardFlexWidth,
                              child: cardFor(list[i + 1]),
                            ),
                          ],
                        ),
                      ),
                    );
                  } else {
                    rows.add(
                      Row(
                        children: [
                          SizedBox(
                            width: cardFlexWidth,
                            child: cardFor(list[i]),
                          ),
                        ],
                      ),
                    );
                  }
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: rows,
                );
              },
            )
          else
            _VacancyCard(
              headline: _displayHeadline(headline),
              body: _displayBody(body),
              hasVacancies: hasVacancies,
              minTall: false,
              slotSummaryLine: null,
              applicationQuotaFull: false,
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
    this.minTall = false,
    this.slotSummaryLine,
    this.applicationQuotaFull = false,
    this.onApplyTap,
  });

  final String headline;
  final String body;
  final bool hasVacancies;
  /// When true (wide two-column layout), cards share a minimum height so rows align cleanly.
  final bool minTall;
  final String? slotSummaryLine;
  final bool applicationQuotaFull;
  final VoidCallback? onApplyTap;

  @override
  Widget build(BuildContext context) {
    final accent = hasVacancies ? AppTheme.primaryNavy : AppTheme.textSecondary;
    final iconBg = accent.withOpacity(0.1);
    const radius = 18.0;

    final content = Padding(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: accent.withOpacity(0.12),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Icon(
                  hasVacancies ? Icons.work_outline_rounded : Icons.work_off_rounded,
                  size: 28,
                  color: accent,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (hasVacancies)
                      Text(
                        'Open position',
                        style: TextStyle(
                          color: AppTheme.textSecondary.withOpacity(0.85),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                        ),
                      ),
                    if (hasVacancies) const SizedBox(height: 4),
                    Text(
                      headline,
                      style: TextStyle(
                        color: hasVacancies ? AppTheme.primaryNavy : AppTheme.textSecondary,
                        fontSize: hasVacancies ? 20 : AppTheme.cardTitleSize,
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: AppTheme.sectionAlt,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.black.withOpacity(0.05),
              ),
            ),
            child: Text(
              body,
              style: TextStyle(
                color: AppTheme.textPrimary.withOpacity(0.88),
                fontSize: 14.5,
                height: 1.55,
              ),
            ),
          ),
          if (slotSummaryLine != null) ...[
            const SizedBox(height: 12),
            Text(
              slotSummaryLine!,
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (hasVacancies && applicationQuotaFull) ...[
            const SizedBox(height: 12),
            Text(
              'Application limit reached for this position.',
              style: TextStyle(
                color: Colors.orange.shade800,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (hasVacancies && onApplyTap != null) ...[
            const SizedBox(height: 14),
            Text(
              'You will submit your profile, contact details, and required PDF documents in the next steps.',
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12.5,
                height: 1.4,
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onApplyTap,
                icon: const Icon(Icons.arrow_forward_rounded, size: 20),
                label: const Text('Apply now'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primaryNavy,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );

    return Material(
      color: Colors.transparent,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: minTall && hasVacancies ? 300 : 0,
        ),
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: AppTheme.white,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: hasVacancies
                  ? AppTheme.primaryNavy.withOpacity(0.12)
                  : Colors.grey.shade300,
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(hasVacancies ? 0.07 : 0.04),
                blurRadius: 22,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (hasVacancies)
                  Container(
                    height: 5,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppTheme.primaryNavy,
                          AppTheme.primaryNavyLight.withOpacity(0.95),
                        ],
                      ),
                    ),
                  )
                else
                  Container(
                    height: 4,
                    color: Colors.grey.shade300,
                  ),
                content,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
