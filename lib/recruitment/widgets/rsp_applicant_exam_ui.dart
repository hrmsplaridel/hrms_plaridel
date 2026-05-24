import 'package:flutter/material.dart';

import '../../landingpage/constants/app_theme.dart';

/// Shared modern UI for applicant-facing RSP exams (BEI, MCQ, results, hiring).
class RspApplicantExamUi {
  RspApplicantExamUi._();

  static const double radiusLg = 20;
  static const double radiusMd = 16;
  static const Color accent = Color(0xFFE85D04);

  static BoxDecoration stepShell(BuildContext context) {
    return BoxDecoration(
      color: AppTheme.dashSurfaceCard(context, radius: radiusLg).color,
      borderRadius: BorderRadius.circular(radiusLg),
      border: Border.all(
        color: AppTheme.primaryNavy.withValues(alpha: 0.1),
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.05),
          blurRadius: 24,
          offset: const Offset(0, 10),
        ),
      ],
    );
  }

  static InputDecoration answerFieldDecoration(BuildContext context) {
    return AppTheme.dashInputDecoration(
      context,
      hintText: 'Type your answer here…',
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      radius: 14,
    ).copyWith(
      alignLabelWithHint: true,
      filled: true,
      fillColor: AppTheme.dashIsDark(context)
          ? const Color(0xFF1E2430)
          : Colors.white,
    );
  }
}

/// Step title block (Steps 3–8).
class RspApplicantStepHeader extends StatelessWidget {
  const RspApplicantStepHeader({
    super.key,
    required this.stepNumber,
    required this.title,
    required this.subtitle,
    this.icon = Icons.assignment_rounded,
  });

  final int stepNumber;
  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final primary = AppTheme.dashTextPrimaryOf(context);
    final secondary = AppTheme.dashTextSecondaryOf(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(RspApplicantExamUi.radiusLg),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFFFFF3E8),
            Colors.white,
            const Color(0xFFF8FAFF),
          ],
        ),
        border: Border.all(
          color: RspApplicantExamUi.accent.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: RspApplicantExamUi.accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: RspApplicantExamUi.accent, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Step $stepNumber',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: RspApplicantExamUi.accent,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: primary,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.45,
                    color: secondary,
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

/// Progress for multi-question exams.
class RspApplicantExamProgress extends StatelessWidget {
  const RspApplicantExamProgress({
    super.key,
    required this.answeredCount,
    required this.totalCount,
    this.label,
  });

  final int answeredCount;
  final int totalCount;
  final String? label;

  @override
  Widget build(BuildContext context) {
    if (totalCount <= 0) return const SizedBox.shrink();
    final ratio = (answeredCount / totalCount).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: ratio,
                    minHeight: 8,
                    backgroundColor:
                        AppTheme.primaryNavy.withValues(alpha: 0.1),
                    color: RspApplicantExamUi.accent,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '$answeredCount / $totalCount',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.dashTextSecondaryOf(context),
                ),
              ),
            ],
          ),
          if (label != null) ...[
            const SizedBox(height: 6),
            Text(
              label!,
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.dashTextSecondaryOf(context),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class RspApplicantExamLoading extends StatelessWidget {
  const RspApplicantExamLoading({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 48),
      child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
    );
  }
}

class RspApplicantExamEmpty extends StatelessWidget {
  const RspApplicantExamEmpty({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(RspApplicantExamUi.radiusMd),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, color: Colors.orange.shade800),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 14,
                color: AppTheme.dashTextSecondaryOf(context),
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Countdown banner for timed MCQ sections.
class RspApplicantExamTimerBanner extends StatelessWidget {
  const RspApplicantExamTimerBanner({
    super.key,
    required this.timeLabel,
    required this.urgent,
  });

  final String timeLabel;
  final bool urgent;

  @override
  Widget build(BuildContext context) {
    final bg = urgent
        ? Colors.red.shade50
        : RspApplicantExamUi.accent.withValues(alpha: 0.1);
    final fg = urgent ? Colors.red.shade900 : AppTheme.textPrimary;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(RspApplicantExamUi.radiusMd),
        border: Border.all(
          color: urgent
              ? Colors.red.shade300
              : RspApplicantExamUi.accent.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          Icon(
            urgent ? Icons.warning_amber_rounded : Icons.timer_outlined,
            color: urgent ? Colors.red.shade800 : RspApplicantExamUi.accent,
            size: 26,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Time remaining',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.dashTextSecondaryOf(context),
                  ),
                ),
                Text(
                  timeLabel,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: fg,
                    fontFeatures: const [FontFeature.tabularFigures()],
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

/// BEI free-text question card.
class RspApplicantBeiQuestionCard extends StatelessWidget {
  const RspApplicantBeiQuestionCard({
    super.key,
    required this.index,
    required this.question,
    required this.controller,
    required this.onChanged,
  });

  final int index;
  final String question;
  final TextEditingController controller;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final answered = controller.text.trim().isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.dashIsDark(context)
            ? const Color(0xFF242A36)
            : const Color(0xFFFAFBFC),
        borderRadius: BorderRadius.circular(RspApplicantExamUi.radiusMd),
        border: Border.all(
          color: answered
              ? RspApplicantExamUi.accent.withValues(alpha: 0.35)
              : AppTheme.primaryNavy.withValues(alpha: 0.12),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: RspApplicantExamUi.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: RspApplicantExamUi.accent,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  question,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                    color: AppTheme.dashTextPrimaryOf(context),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: controller,
            onChanged: (_) => onChanged(),
            maxLines: 5,
            minLines: 3,
            decoration: RspApplicantExamUi.answerFieldDecoration(context),
          ),
        ],
      ),
    );
  }
}

/// Single MCQ option tile.
class RspApplicantMcqOptionTile extends StatelessWidget {
  const RspApplicantMcqOptionTile({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.optionLetter,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final String? optionLetter;

  @override
  Widget build(BuildContext context) {
    final primary = AppTheme.dashTextPrimaryOf(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Ink(
            decoration: BoxDecoration(
              color: selected
                  ? RspApplicantExamUi.accent.withValues(alpha: 0.12)
                  : (AppTheme.dashIsDark(context)
                      ? const Color(0xFF1E2430)
                      : Colors.white),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected
                    ? RspApplicantExamUi.accent
                    : AppTheme.primaryNavy.withValues(alpha: 0.15),
                width: selected ? 2 : 1,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Icon(
                    selected
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_off_rounded,
                    size: 22,
                    color: selected
                        ? RspApplicantExamUi.accent
                        : AppTheme.dashTextSecondaryOf(context),
                  ),
                  const SizedBox(width: 12),
                  if (optionLetter != null) ...[
                    Container(
                      width: 26,
                      height: 26,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: selected
                            ? RspApplicantExamUi.accent.withValues(alpha: 0.2)
                            : AppTheme.primaryNavy.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        optionLetter!,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          color: selected
                              ? RspApplicantExamUi.accent
                              : primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w500,
                        color: primary,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// MCQ question card (General, Math, General Info).
class RspApplicantMcqQuestionCard extends StatelessWidget {
  const RspApplicantMcqQuestionCard({
    super.key,
    required this.index,
    required this.questionText,
    required this.options,
    required this.selectedIndex,
    required this.onSelect,
    this.useLetterPrefix = false,
  });

  final int index;
  final String questionText;
  final List<dynamic> options;
  final int selectedIndex;
  final void Function(int optionIndex) onSelect;
  final bool useLetterPrefix;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.dashIsDark(context)
            ? const Color(0xFF242A36)
            : const Color(0xFFFAFBFC),
        borderRadius: BorderRadius.circular(RspApplicantExamUi.radiusMd),
        border: Border.all(
          color: selectedIndex >= 0
              ? RspApplicantExamUi.accent.withValues(alpha: 0.3)
              : AppTheme.primaryNavy.withValues(alpha: 0.1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppTheme.primaryNavy.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${index + 1}',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppTheme.primaryNavy,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  questionText,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                    color: AppTheme.dashTextPrimaryOf(context),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...List.generate(options.length, (j) {
            final letter =
                useLetterPrefix ? String.fromCharCode(97 + j) : null;
            final label = useLetterPrefix
                ? options[j].toString()
                : options[j].toString();
            return RspApplicantMcqOptionTile(
              optionLetter: letter,
              label: label,
              selected: selectedIndex == j,
              onTap: () => onSelect(j),
            );
          }),
        ],
      ),
    );
  }
}

class RspApplicantSubmitButton extends StatelessWidget {
  const RspApplicantSubmitButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.enabled = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: enabled ? onPressed : null,
        icon: const Icon(Icons.send_rounded, size: 20),
        label: Text(label),
        style: FilledButton.styleFrom(
          backgroundColor: AppTheme.primaryNavy,
          disabledBackgroundColor: AppTheme.primaryNavy.withValues(alpha: 0.35),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(RspApplicantExamUi.radiusMd),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class RspApplicantBeiMotivationQuote extends StatelessWidget {
  const RspApplicantBeiMotivationQuote({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(
        '"Make you MOVE". Your answer is an extension of yourself. Make one that\'s truly you.',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 13,
          fontStyle: FontStyle.italic,
          height: 1.45,
          color: AppTheme.dashTextSecondaryOf(context),
        ),
      ),
    );
  }
}

/// Status / result card for Steps 7–8.
class RspApplicantStatusCard extends StatelessWidget {
  const RspApplicantStatusCard({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    required this.accentColor,
    this.child,
  });

  final IconData icon;
  final String title;
  final String body;
  final Color accentColor;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(RspApplicantExamUi.radiusLg),
        border: Border.all(color: accentColor.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: accentColor, size: 32),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.dashTextPrimaryOf(context),
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      body,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.45,
                        color: AppTheme.dashTextSecondaryOf(context),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (child != null) ...[const SizedBox(height: 16), child!],
        ],
      ),
    );
  }
}

/// Large pass/fail result hero (Step 7).
class RspApplicantExamResultHero extends StatelessWidget {
  const RspApplicantExamResultHero({
    super.key,
    required this.passed,
    required this.scorePercent,
  });

  final bool passed;
  final double scorePercent;

  @override
  Widget build(BuildContext context) {
    final accent = passed ? const Color(0xFF2E7D32) : Colors.deepOrange.shade700;

    return RspApplicantStatusCard(
      icon: passed ? Icons.check_circle_rounded : Icons.cancel_rounded,
      title: passed ? 'Passed' : 'Not passed',
      body: 'Score: ${scorePercent.toStringAsFixed(0)}%'
          '${passed ? '' : ' — You need 60% or higher. You may try again with a new application.'}',
      accentColor: accent,
    );
  }
}
