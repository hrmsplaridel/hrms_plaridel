import 'package:flutter/material.dart';

import 'package:hrms_plaridel/core/theme/app_theme.dart';

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
      border: Border.all(color: AppTheme.primaryNavy.withValues(alpha: 0.1)),
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
                    backgroundColor: AppTheme.primaryNavy.withValues(
                      alpha: 0.1,
                    ),
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
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
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
                          color: selected ? RspApplicantExamUi.accent : primary,
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
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w500,
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
            final letter = useLetterPrefix ? String.fromCharCode(97 + j) : null;
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
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
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
    this.scorePercent,
    this.showScore = false,
  });

  final bool passed;
  final double? scorePercent;
  final bool showScore;

  @override
  Widget build(BuildContext context) {
    final accent = passed
        ? const Color(0xFF2E7D32)
        : Colors.deepOrange.shade700;
    final body = passed
        ? 'You have completed screening. HR will record the deliberation outcome.'
        : 'Thank you for completing the recruitment assessments. Your application did not proceed to Final Hiring.';

    return RspApplicantStatusCard(
      icon: passed ? Icons.check_circle_rounded : Icons.cancel_rounded,
      title: passed ? 'Passed' : 'Application result',
      body: showScore && scorePercent != null
          ? 'Score: ${scorePercent!.toStringAsFixed(0)}%'
          : body,
      accentColor: accent,
    );
  }
}

class RspApplicantExamSessionHeader extends StatelessWidget {
  const RspApplicantExamSessionHeader({
    super.key,
    required this.title,
    required this.questionIndex,
    required this.total,
    this.timeLabel,
    this.urgent = false,
  });

  final String title;
  final int questionIndex;
  final int total;
  final String? timeLabel;
  final bool urgent;

  @override
  Widget build(BuildContext context) {
    final ratio = total <= 0 ? 0.0 : (questionIndex / total).clamp(0.0, 1.0);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.dashHairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppTheme.dashTextPrimaryOf(context),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Question $questionIndex of $total',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                  ),
                ),
              ),
              if (timeLabel != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: urgent
                        ? const Color(0xFFFFEBEE)
                        : AppTheme.primaryNavy.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.timer_outlined,
                        size: 16,
                        color: urgent
                            ? const Color(0xFFC62828)
                            : AppTheme.primaryNavy,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        timeLabel!,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13.5,
                          fontFeatures: const [FontFeature.tabularFigures()],
                          color: urgent
                              ? const Color(0xFFC62828)
                              : AppTheme.dashTextPrimaryOf(context),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 7,
              backgroundColor: AppTheme.primaryNavy.withValues(alpha: 0.12),
              color: AppTheme.primaryNavy,
            ),
          ),
        ],
      ),
    );
  }
}

class RspApplicantExamPagerNav extends StatelessWidget {
  const RspApplicantExamPagerNav({
    super.key,
    required this.canGoBack,
    required this.isLast,
    required this.onBack,
    required this.onForward,
    this.forwardLabel,
  });

  final bool canGoBack;
  final bool isLast;
  final VoidCallback? onBack;
  final VoidCallback? onForward;
  final String? forwardLabel;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: canGoBack ? onBack : null,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 48),
              foregroundColor: AppTheme.primaryNavy,
            ),
            child: const Text('Previous'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton(
            onPressed: onForward,
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 48),
              backgroundColor: AppTheme.primaryNavy,
            ),
            child: Text(forwardLabel ?? (isLast ? 'Review answers' : 'Next')),
          ),
        ),
      ],
    );
  }
}

Future<bool> showRspApplicantExamSubmitDialog({
  required BuildContext context,
  required String examTitle,
  required int answered,
  required int total,
}) async {
  final unanswered = (total - answered).clamp(0, total);
  final complete = unanswered == 0 && total > 0;
  final ratio = total <= 0 ? 0.0 : (answered / total).clamp(0.0, 1.0);
  final ok = await showDialog<bool>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (ctx) {
      return Dialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppTheme.primaryNavy.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.send_rounded,
                        color: AppTheme.primaryNavy,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Submit $examTitle?',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              height: 1.25,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            complete
                                ? 'All questions have answers. Submit when you are ready.'
                                : 'Some questions are still unanswered.',
                            style: const TextStyle(
                              fontSize: 13.5,
                              height: 1.4,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: ratio,
                    minHeight: 8,
                    backgroundColor: AppTheme.primaryNavy.withValues(
                      alpha: 0.12,
                    ),
                    color: complete
                        ? const Color(0xFF2E7D32)
                        : AppTheme.primaryNavy,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _SubmitStatChip(
                        icon: Icons.check_circle_rounded,
                        label: 'Answered',
                        value: '$answered / $total',
                        color: const Color(0xFF2E7D32),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _SubmitStatChip(
                        icon: unanswered > 0
                            ? Icons.radio_button_unchecked_rounded
                            : Icons.check_circle_outline_rounded,
                        label: 'Unanswered',
                        value: '$unanswered',
                        color: unanswered > 0
                            ? const Color(0xFFC62828)
                            : AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3E8),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppTheme.primaryNavy.withValues(alpha: 0.28),
                    ),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        size: 20,
                        color: AppTheme.primaryNavy,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Once submitted, answers cannot be changed.',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            height: 1.4,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 46),
                          foregroundColor: AppTheme.textPrimary,
                          side: const BorderSide(color: AppTheme.dashHairline),
                        ),
                        child: const Text('Go back'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 46),
                          backgroundColor: AppTheme.primaryNavy,
                        ),
                        child: const Text('Submit'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
  return ok == true;
}

class _SubmitStatChip extends StatelessWidget {
  const _SubmitStatChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSecondary,
                  ),
                ),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: color,
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
