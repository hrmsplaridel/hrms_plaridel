import 'package:flutter/material.dart';
import '../../data/job_vacancy_announcement.dart';
import '../constants/app_theme.dart';
import '../widgets/section_container.dart';

/// When [vacancy] has education / experience / training, show labeled blocks; otherwise null.
Widget? _structuredVacancyBody(JobVacancyItem vacancy) {
  if (!vacancy.hasStructuredDetails) return null;

  Widget? block(String title, String? raw) {
    final text = raw?.trim();
    if (text == null || text.isEmpty) return null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: AppTheme.textSecondary.withValues(alpha: 0.88),
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.55,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            text,
            style: TextStyle(
              color: AppTheme.textPrimary.withValues(alpha: 0.92),
              fontSize: 14.5,
              height: 1.55,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  final children = [
    block('Education', vacancy.education),
    block('Experience', vacancy.experience),
    block('Training', vacancy.training),
  ].whereType<Widget>().toList();

  if (children.isEmpty) return null;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: children,
  );
}

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
    if (!hasVacancies) return 'No openings right now';
    if (h != null && h.trim().isNotEmpty) return h.trim();
    return 'We are currently accepting applications.';
  }

  String _displayBody(String? b) {
    if (!hasVacancies) {
      return 'When HR publishes a vacancy, it will appear here. You can then apply via Job application or the recruitment steps on this page.';
    }
    if (b != null && b.trim().isNotEmpty) return b.trim();
    return 'There are job openings you may apply to. Follow the recruitment process below to start your application.';
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 800;
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
              fontSize: isWide ? 30 : 26,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            width: 56,
            height: 4,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              gradient: LinearGradient(
                colors: [
                  AppTheme.primaryNavy,
                  AppTheme.primaryNavy.withValues(alpha: 0.55),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Text(
              hasVacancies
                  ? 'Open positions you can apply for online. Each role lists a short summary—full details and required documents are in the application form.'
                  : 'Vacancies are posted here when HR opens a role. Visit again soon—active listings will appear in the card below.',
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: isWide ? 17 : 15,
                height: 1.55,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          SizedBox(height: isWide ? 28 : 22),
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
                  final structured = _structuredVacancyBody(v);
                  final max = v.maxApplicants;
                  final count = v.applicationCount ?? 0;
                  final slotLine = (max != null && max >= 1)
                      ? '$count of $max active applicants'
                      : null;
                  final quotaFull = v.isApplicationQuotaFull;
                  final closed = v.isClosed == true;
                  return _VacancyCard(
                    headline: headlineText,
                    body: structured != null
                        ? ''
                        : _displayBody(v.body),
                    bodyChild: structured,
                    hasVacancies: hasVacancies,
                    minTall: twoColumns,
                    slotSummaryLine: slotLine,
                    applicationQuotaFull: quotaFull || closed,
                    onApplyTap: hasVacancies && !quotaFull && !closed
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
              bodyChild: null,
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
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: AppTheme.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFE2E6EA)),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primaryNavy.withValues(alpha: 0.06),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: _RecruitmentCtaBanner(
                hasVacancies: hasVacancies,
                stackVertical: !isWide,
                onTap: onGoToRecruitmentTap!,
              ),
            ),
        ],
      ),
    );
  }
}

class _RecruitmentCtaBanner extends StatelessWidget {
  const _RecruitmentCtaBanner({
    required this.hasVacancies,
    required this.stackVertical,
    required this.onTap,
  });

  final bool hasVacancies;
  final bool stackVertical;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final iconBox = Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.primaryNavy.withValues(alpha: 0.14),
            AppTheme.primaryNavy.withValues(alpha: 0.06),
          ],
        ),
        border: Border.all(color: AppTheme.primaryNavy.withValues(alpha: 0.12)),
      ),
      child: Icon(
        Icons.how_to_reg_rounded,
        color: AppTheme.primaryNavy,
        size: 22,
      ),
    );

    final message = Text(
      hasVacancies
          ? 'Ready to apply? Continue with the recruitment process below.'
          : 'No listing yet? You can still open the recruitment flow to check status or review steps.',
      style: TextStyle(
        color: AppTheme.textSecondary,
        fontSize: 14,
        height: 1.45,
        fontWeight: FontWeight.w600,
      ),
    );

    final button = FilledButton.icon(
      onPressed: onTap,
      icon: const Icon(Icons.arrow_forward_rounded, size: 18),
      label: const Text('Go to recruitment'),
      style: FilledButton.styleFrom(
        backgroundColor: AppTheme.primaryNavy,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        elevation: 2,
        shadowColor: AppTheme.primaryNavy.withValues(alpha: 0.35),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );

    if (stackVertical) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              iconBox,
              const SizedBox(width: 14),
              Expanded(child: message),
            ],
          ),
          const SizedBox(height: 16),
          button,
        ],
      );
    }

    return Row(
      children: [
        iconBox,
        const SizedBox(width: 14),
        Expanded(child: message),
        const SizedBox(width: 12),
        button,
      ],
    );
  }
}

class _VacancyCard extends StatelessWidget {
  const _VacancyCard({
    required this.headline,
    required this.body,
    this.bodyChild,
    required this.hasVacancies,
    this.minTall = false,
    this.slotSummaryLine,
    this.applicationQuotaFull = false,
    this.onApplyTap,
  });

  final String headline;
  final String body;
  /// When set (e.g. education / experience / training), replaces [body] text in the open card.
  final Widget? bodyChild;
  final bool hasVacancies;

  /// When true (wide two-column layout), cards share a minimum height so rows align cleanly.
  final bool minTall;
  final String? slotSummaryLine;
  final bool applicationQuotaFull;
  final VoidCallback? onApplyTap;

  @override
  Widget build(BuildContext context) {
    final accent = hasVacancies ? AppTheme.primaryNavy : AppTheme.textSecondary;
    const radius = 20.0;

    final iconTile = Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: hasVacancies
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  accent.withValues(alpha: 0.16),
                  accent.withValues(alpha: 0.06),
                ],
              )
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppTheme.textSecondary.withValues(alpha: 0.12),
                  AppTheme.primaryNavy.withValues(alpha: 0.06),
                ],
              ),
        border: Border.all(
          color: hasVacancies
              ? accent.withValues(alpha: 0.14)
              : AppTheme.textSecondary.withValues(alpha: 0.12),
        ),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.1),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Icon(
        hasVacancies ? Icons.work_outline_rounded : Icons.work_off_outlined,
        size: 26,
        color: accent,
      ),
    );

    final bodyBlock = hasVacancies
        ? Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: AppTheme.sectionAlt,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
              boxShadow: AppTheme.cardShadow,
            ),
            child: bodyChild ??
                Text(
                  body,
                  style: TextStyle(
                    color: AppTheme.textPrimary.withValues(alpha: 0.9),
                    fontSize: 14.5,
                    height: 1.55,
                  ),
                ),
          )
        : Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: AppTheme.offWhite,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE2E6EA)),
              boxShadow: AppTheme.cardShadow,
            ),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: 4,
                    margin: const EdgeInsets.only(
                      left: 12,
                      top: 12,
                      bottom: 12,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryNavy,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 14, 16, 14),
                      child: Text(
                        body,
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 14.5,
                          height: 1.55,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );

    final content = Padding(
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              iconTile,
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (hasVacancies)
                      Text(
                        'Open position',
                        style: TextStyle(
                          color: AppTheme.textSecondary.withValues(alpha: 0.85),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                        ),
                      ),
                    if (hasVacancies) const SizedBox(height: 4),
                    Text(
                      headline,
                      style: TextStyle(
                        color: hasVacancies
                            ? AppTheme.primaryNavy
                            : AppTheme.textPrimary,
                        fontSize: hasVacancies ? 20 : 18,
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
          const SizedBox(height: 18),
          bodyBlock,
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
          if (onApplyTap != null) ...[
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 14,
                  ),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ] else if (!hasVacancies || applicationQuotaFull) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: null,
                icon: const Icon(Icons.arrow_forward_rounded, size: 20),
                label: const Text('Apply now'),
                style: FilledButton.styleFrom(
                  disabledBackgroundColor: AppTheme.textSecondary.withValues(
                    alpha: 0.32,
                  ),
                  disabledForegroundColor: Colors.white.withValues(alpha: 0.85),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 14,
                  ),
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
                  ? AppTheme.primaryNavy.withValues(alpha: 0.14)
                  : const Color(0xFFE2E6EA),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primaryNavy.withValues(alpha: 0.08),
                blurRadius: 28,
                offset: const Offset(0, 12),
              ),
              BoxShadow(
                color: Colors.black.withValues(
                  alpha: hasVacancies ? 0.065 : 0.055,
                ),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
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
                          AppTheme.primaryNavyLight.withValues(alpha: 0.95),
                        ],
                      ),
                    ),
                  )
                else
                  Container(
                    height: 4,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppTheme.primaryNavy.withValues(alpha: 0.85),
                          AppTheme.primaryNavy.withValues(alpha: 0.2),
                        ],
                      ),
                    ),
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
