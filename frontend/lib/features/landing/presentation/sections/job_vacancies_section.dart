import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'package:hrms_plaridel/features/recruitment/models/job_vacancy_announcement.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/landing/presentation/widgets/section_container.dart';

enum _VacancyCardStatus { nowOpen, slotsFull, closed }

/// Compact requirement chip (education / experience / training).
class _RequirementChip extends StatelessWidget {
  const _RequirementChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppTheme.primaryNavy.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.primaryNavy.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppTheme.primaryNavy),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                height: 1.25,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

Widget? _requirementChips(JobVacancyItem vacancy) {
  final chips = <Widget>[];
  void add(String? raw, IconData icon) {
    final text = raw?.trim();
    if (text == null || text.isEmpty) return;
    chips.add(_RequirementChip(icon: icon, label: text));
  }

  add(vacancy.education, Icons.school_outlined);
  add(vacancy.experience, Icons.schedule_outlined);
  add(vacancy.training, Icons.cast_for_education_outlined);

  if (chips.isEmpty) return null;
  return Wrap(spacing: 8, runSpacing: 8, children: chips);
}

IconData _iconForVacancyTitle(String title) {
  final t = title.toLowerCase();
  if (t.contains('account') ||
      t.contains('finance') ||
      t.contains('budget') ||
      t.contains('cash')) {
    return Icons.calculate_outlined;
  }
  if (t.contains('assistant') ||
      t.contains('clerk') ||
      t.contains('admin') ||
      t.contains('secretary')) {
    return Icons.groups_outlined;
  }
  if (t.contains('engineer') || t.contains('technical')) {
    return Icons.engineering_outlined;
  }
  if (t.contains('nurse') || t.contains('health') || t.contains('medical')) {
    return Icons.medical_services_outlined;
  }
  return Icons.work_outline_rounded;
}

_VacancyCardStatus _statusFor({
  required bool hasVacancies,
  required bool quotaFull,
  required bool closed,
}) {
  if (!hasVacancies || closed) return _VacancyCardStatus.closed;
  if (quotaFull) return _VacancyCardStatus.slotsFull;
  return _VacancyCardStatus.nowOpen;
}

/// Job Vacancies as announcement area (controlled by HR Head/Admin via RSP module).
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

  final bool hasVacancies;
  final String? headline;
  final String? body;
  final List<JobVacancyItem>? vacancies;
  final VoidCallback? onGoToRecruitmentTap;
  final void Function(JobVacancyItem vacancy)? onApplyForVacancyTap;

  String _displayHeadline(String? h) {
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
    final isWide = MediaQuery.sizeOf(context).width > 800;
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppTheme.primaryNavy.withValues(alpha: 0.18),
                      AppTheme.primaryNavy.withValues(alpha: 0.08),
                    ],
                  ),
                  border: Border.all(
                    color: AppTheme.primaryNavy.withValues(alpha: 0.15),
                  ),
                ),
                child: const Icon(
                  Icons.work_outline_rounded,
                  color: AppTheme.primaryNavy,
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Job Vacancies',
                          style: TextStyle(
                            color: AppTheme.primaryNavy,
                            fontSize: isWide ? 28 : 24,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.35,
                            height: 1.15,
                          ),
                        ),
                        if (hasVacancies && list.isNotEmpty) ...[
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFD1FAE5),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '${list.length} open',
                              style: const TextStyle(
                                color: Color(0xFF047857),
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: 72,
                      height: 4,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        gradient: LinearGradient(
                          colors: [
                            AppTheme.primaryNavy,
                            AppTheme.primaryNavyLight.withValues(alpha: 0.7),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
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
                    : MediaQuery.sizeOf(context).width;
                final twoColumns = maxWidth >= 900;
                const gap = 20.0;
                final cardFlexWidth = twoColumns
                    ? (maxWidth - gap) / 2
                    : maxWidth;

                Widget cardFor(JobVacancyItem v) {
                  final headlineText = _displayHeadline(v.headline);
                  final max = v.maxApplicants;
                  final active = v.applicationCount ?? 0;
                  final total = v.totalApplicationCount ?? active;
                  final quotaFull = v.isApplicationQuotaFull;
                  final closed = v.isClosed == true;
                  final status = _statusFor(
                    hasVacancies: hasVacancies,
                    quotaFull: quotaFull,
                    closed: closed,
                  );
                  String? slotDetailLine;
                  if (max != null && max >= 1) {
                    if (total > active) {
                      final removed = total - active;
                      slotDetailLine =
                          '$total submitted · $removed no longer in pipeline '
                          '(hired, declined, failed exam, or failed final interview)';
                    } else if (total == 0) {
                      slotDetailLine =
                          'Counts applicants still being processed for this exact job title';
                    }
                  }
                  final canApply =
                      hasVacancies &&
                      !quotaFull &&
                      !closed &&
                      onApplyForVacancyTap != null;
                  return _VacancyCard(
                    headline: headlineText,
                    fallbackBody: _displayBody(v.body),
                    requirementChips: _requirementChips(v),
                    hasVacancies: hasVacancies,
                    minTall: twoColumns,
                    status: status,
                    roleIcon: _iconForVacancyTitle(headlineText),
                    slotsFilled: active,
                    slotsMax: max,
                    slotDetailLine: slotDetailLine,
                    onApplyTap: canApply
                        ? () => onApplyForVacancyTap!.call(v)
                        : null,
                  );
                }

                if (!twoColumns) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < list.length; i++) ...[
                        if (i > 0) const SizedBox(height: gap),
                        cardFor(list[i]),
                      ],
                    ],
                  );
                }

                final rows = <Widget>[];
                for (var i = 0; i < list.length; i += 2) {
                  if (i > 0) rows.add(const SizedBox(height: gap));
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
                            const SizedBox(width: gap),
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
              fallbackBody: _displayBody(body),
              requirementChips: null,
              hasVacancies: hasVacancies,
              minTall: false,
              status: hasVacancies
                  ? _VacancyCardStatus.nowOpen
                  : _VacancyCardStatus.closed,
              roleIcon: Icons.work_outline_rounded,
              slotsFilled: null,
              slotsMax: null,
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
      icon: const Icon(Icons.arrow_forward_rounded, size: 16),
      label: const Text('Go to recruitment'),
      style: FilledButton.styleFrom(
        backgroundColor: AppTheme.primaryNavy,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        elevation: 1,
        shadowColor: AppTheme.primaryNavy.withValues(alpha: 0.3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final _VacancyCardStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, bg, fg) = switch (status) {
      _VacancyCardStatus.nowOpen => (
        'Now open',
        const Color(0xFFD1FAE5),
        const Color(0xFF047857),
      ),
      _VacancyCardStatus.slotsFull => (
        'Slots full',
        const Color(0xFFFEF3C7),
        const Color(0xFFB45309),
      ),
      _VacancyCardStatus.closed => (
        'Closed',
        const Color(0xFFE9ECEF),
        AppTheme.textSecondary,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: fg.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _SlotProgressBar extends StatelessWidget {
  const _SlotProgressBar({
    required this.filled,
    required this.max,
    this.detailLine,
  });

  final int filled;
  final int max;
  final String? detailLine;

  @override
  Widget build(BuildContext context) {
    final progress = max > 0 ? (filled / max).clamp(0.0, 1.0) : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 6,
            width: double.infinity,
            child: Stack(
              children: [
                Container(color: const Color(0xFFE9ECEF)),
                FractionallySizedBox(
                  widthFactor: progress,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppTheme.primaryNavy,
                          AppTheme.primaryNavyLight,
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '$filled of $max slots filled',
          style: TextStyle(
            color: AppTheme.textSecondary.withValues(alpha: 0.9),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (detailLine != null) ...[
          const SizedBox(height: 4),
          Text(
            detailLine!,
            style: TextStyle(
              color: AppTheme.textSecondary.withValues(alpha: 0.82),
              fontSize: 11,
              height: 1.35,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ],
    );
  }
}

class _VacancyCard extends StatefulWidget {
  const _VacancyCard({
    required this.headline,
    required this.fallbackBody,
    this.requirementChips,
    required this.hasVacancies,
    this.minTall = false,
    required this.status,
    required this.roleIcon,
    this.slotsFilled,
    this.slotsMax,
    this.slotDetailLine,
    this.onApplyTap,
  });

  final String headline;
  final String fallbackBody;
  final Widget? requirementChips;
  final bool hasVacancies;
  final bool minTall;
  final _VacancyCardStatus status;
  final IconData roleIcon;
  final int? slotsFilled;
  final int? slotsMax;
  final String? slotDetailLine;
  final VoidCallback? onApplyTap;

  @override
  State<_VacancyCard> createState() => _VacancyCardState();
}

class _VacancyCardState extends State<_VacancyCard> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final accent = widget.hasVacancies
        ? AppTheme.primaryNavy
        : AppTheme.textSecondary;
    const radius = 18.0;
    final showSlots =
        widget.hasVacancies &&
        widget.slotsMax != null &&
        widget.slotsMax! >= 1 &&
        widget.slotsFilled != null;

    final iconTile = Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.primaryNavy.withValues(alpha: 0.16),
            AppTheme.primaryNavy.withValues(alpha: 0.06),
          ],
        ),
        border: Border.all(color: AppTheme.primaryNavy.withValues(alpha: 0.14)),
      ),
      child: Icon(widget.roleIcon, size: 22, color: accent),
    );

    final detailsSection = widget.hasVacancies
        ? (widget.requirementChips ??
              (widget.fallbackBody.trim().isNotEmpty
                  ? Text(
                      widget.fallbackBody,
                      style: TextStyle(
                        color: AppTheme.textPrimary.withValues(alpha: 0.9),
                        fontSize: 14,
                        height: 1.5,
                      ),
                    )
                  : null))
        : Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: AppTheme.offWhite,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE2E6EA)),
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
                        widget.fallbackBody,
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 14,
                          height: 1.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );

    final applyButton = widget.onApplyTap != null
        ? FilledButton.icon(
            onPressed: widget.onApplyTap,
            icon: const Icon(Icons.arrow_forward_rounded, size: 16),
            label: const Text('Apply now'),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.primaryNavy,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              elevation: _hovering ? 2 : 0,
            ),
          )
        : OutlinedButton(
            onPressed: null,
            style: OutlinedButton.styleFrom(
              disabledForegroundColor: AppTheme.textSecondary,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              side: const BorderSide(color: Color(0xFFE2E6EA)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'Applications closed',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          );

    final content = Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              iconTile,
              const Spacer(),
              if (widget.hasVacancies) _StatusBadge(status: widget.status),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            widget.headline,
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: widget.hasVacancies ? 18 : 17,
              fontWeight: FontWeight.w800,
              height: 1.2,
              letterSpacing: -0.15,
            ),
          ),
          if (detailsSection != null) ...[
            const SizedBox(height: 12),
            detailsSection,
          ],
          if (showSlots) ...[
            const SizedBox(height: 14),
            _SlotProgressBar(
              filled: widget.slotsFilled!,
              max: widget.slotsMax!,
              detailLine: widget.slotDetailLine,
            ),
          ],
          if (widget.hasVacancies) ...[
            const SizedBox(height: 14),
            Align(alignment: Alignment.centerRight, child: applyButton),
          ],
        ],
      ),
    );

    return MouseRegion(
      onEnter: kIsWeb && widget.onApplyTap != null
          ? (_) => setState(() => _hovering = true)
          : null,
      onExit: kIsWeb && widget.onApplyTap != null
          ? (_) => setState(() => _hovering = false)
          : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        constraints: BoxConstraints(
          minHeight: widget.minTall && widget.hasVacancies ? 248 : 0,
        ),
        decoration: BoxDecoration(
          color: AppTheme.white,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(
            color: widget.hasVacancies
                ? AppTheme.primaryNavy.withValues(
                    alpha: _hovering ? 0.28 : 0.14,
                  )
                : const Color(0xFFE2E6EA),
          ),
          boxShadow: [
            BoxShadow(
              color: AppTheme.primaryNavy.withValues(
                alpha: _hovering ? 0.12 : 0.06,
              ),
              blurRadius: _hovering ? 20 : 14,
              offset: Offset(0, _hovering ? 8 : 5),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 6,
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
              if (widget.hasVacancies)
                Container(
                  height: 3,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [AppTheme.primaryNavy, AppTheme.primaryNavyLight],
                    ),
                  ),
                ),
              content,
            ],
          ),
        ),
      ),
    );
  }
}
