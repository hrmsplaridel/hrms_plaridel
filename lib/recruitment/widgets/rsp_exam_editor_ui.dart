import 'package:flutter/material.dart';

import '../../landingpage/constants/app_theme.dart';

/// Shared visual primitives for RSP exam / BEI question editors.
class RspExamEditorUi {
  RspExamEditorUi._();

  static const double radiusLg = 20;
  static const double radiusMd = 16;

  static BoxDecoration elevatedPanel(BuildContext context) {
    final base = AppTheme.dashSurfaceCard(context, radius: radiusLg);
    final dark = AppTheme.dashIsDark(context);
    return base.copyWith(
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: dark ? 0.28 : 0.06),
          blurRadius: 22,
          offset: const Offset(0, 8),
        ),
        BoxShadow(
          color: AppTheme.primaryNavy.withValues(alpha: dark ? 0.08 : 0.04),
          blurRadius: 28,
          offset: const Offset(0, 10),
        ),
      ],
    );
  }

  static BoxDecoration questionCard(BuildContext context) {
    final dark = AppTheme.dashIsDark(context);
    return BoxDecoration(
      color: dark ? const Color(0xFF242A36) : const Color(0xFFFAFBFC),
      borderRadius: BorderRadius.circular(radiusMd),
      border: Border.all(
        color: AppTheme.primaryNavy.withValues(alpha: dark ? 0.25 : 0.1),
      ),
    );
  }

  static InputDecoration inputDecoration(
    BuildContext context, {
    String? labelText,
    String? hintText,
    bool alignLabelWithHint = false,
  }) {
    return AppTheme.dashInputDecoration(
      context,
      labelText: labelText,
      hintText: hintText,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      radius: 14,
    ).copyWith(
      alignLabelWithHint: alignLabelWithHint,
      floatingLabelBehavior: FloatingLabelBehavior.auto,
    );
  }

  static ButtonStyle ghostAction(BuildContext context) {
    return TextButton.styleFrom(
      foregroundColor: AppTheme.primaryNavy,
      backgroundColor: AppTheme.primaryNavy.withValues(alpha: 0.06),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
    );
  }
}

/// Page title block for exam editors (below Back to RSP).
class RspExamPageHeader extends StatelessWidget {
  const RspExamPageHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.icon = Icons.quiz_rounded,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.sizeOf(context).width < 600;
    final primary = AppTheme.dashTextPrimaryOf(context);
    final secondary = AppTheme.dashTextSecondaryOf(context);

    return Container(
      padding: EdgeInsets.all(isNarrow ? 20 : 24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(RspExamEditorUi.radiusLg),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: AppTheme.dashIsDark(context)
              ? [
                  const Color(0xFF252D3D),
                  const Color(0xFF1E2430),
                ]
              : [
                  const Color(0xFFFFF8F3),
                  Colors.white,
                  const Color(0xFFF5F8FF),
                ],
        ),
        border: Border.all(
          color: AppTheme.primaryNavy.withValues(alpha: 0.14),
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryNavy.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppTheme.primaryNavy.withValues(alpha: 0.16),
                  AppTheme.letterheadNavy.withValues(alpha: 0.08),
                ],
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppTheme.primaryNavy.withValues(alpha: 0.14),
              ),
            ),
            child: Icon(icon, color: AppTheme.primaryNavy, size: 26),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: primary,
                    fontSize: isNarrow ? 20 : 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: secondary,
                    fontSize: isNarrow ? 13.5 : 14.5,
                    height: 1.45,
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

/// Applicant time limit strip (shared by MCQ exam editors).
class RspExamTimeLimitPanel extends StatelessWidget {
  const RspExamTimeLimitPanel({
    super.key,
    required this.minutesController,
    required this.saving,
    required this.loading,
    required this.onSave,
  });

  final TextEditingController minutesController;
  final bool saving;
  final bool loading;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(RspExamEditorUi.radiusMd),
          child: const LinearProgressIndicator(minHeight: 3),
        ),
      );
    }

    final primary = AppTheme.dashTextPrimaryOf(context);
    final secondary = AppTheme.dashTextSecondaryOf(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(RspExamEditorUi.radiusMd),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppTheme.primaryNavy.withValues(alpha: 0.1),
              AppTheme.primaryNavyLight.withValues(alpha: 0.05),
            ],
          ),
          border: Border.all(
            color: AppTheme.primaryNavy.withValues(alpha: 0.2),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.primaryNavy.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.timer_outlined,
                color: AppTheme.primaryNavy,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Applicant time limit',
                    style: TextStyle(
                      color: primary,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Minutes allowed for this exam (0 = no countdown). Applicants see a timer during the exam.',
                    style: TextStyle(
                      color: secondary,
                      fontSize: 12.5,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 12,
                    runSpacing: 10,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SizedBox(
                        width: 100,
                        child: TextField(
                          controller: minutesController,
                          keyboardType: TextInputType.number,
                          style: AppTheme.dashFieldTextStyle(context),
                          decoration: RspExamEditorUi.inputDecoration(
                            context,
                            labelText: 'Minutes',
                          ).copyWith(isDense: true),
                        ),
                      ),
                      FilledButton(
                        onPressed: saving ? null : onSave,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.primaryNavy,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Save limit'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Wraps one MCQ question block with card chrome and delete control.
class RspMcqQuestionCard extends StatelessWidget {
  const RspMcqQuestionCard({
    super.key,
    required this.index,
    required this.onRemove,
    required this.child,
  });

  final int index;
  final VoidCallback? onRemove;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final primary = AppTheme.dashTextPrimaryOf(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(18, 16, 12, 18),
      decoration: RspExamEditorUi.questionCard(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppTheme.primaryNavy.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(
                    color: AppTheme.primaryNavy,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Question',
                  style: TextStyle(
                    color: primary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (onRemove != null)
                IconButton(
                  onPressed: onRemove,
                  tooltip: 'Remove question',
                  icon: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.08),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.red.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Icon(
                      Icons.remove_rounded,
                      size: 18,
                      color: Colors.red.shade700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

/// One MCQ answer option row with radio and themed field.
class RspMcqOptionRow extends StatelessWidget {
  const RspMcqOptionRow({
    super.key,
    required this.index,
    required this.groupValue,
    required this.controller,
    required this.onSelected,
    required this.onChanged,
  });

  final int index;
  final int groupValue;
  final TextEditingController controller;
  final ValueChanged<int?> onSelected;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final selected = index == groupValue;
    final hint = 'Option ${String.fromCharCode(97 + index)}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => onSelected(index),
          borderRadius: BorderRadius.circular(12),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: selected
                  ? AppTheme.primaryNavy.withValues(alpha: 0.06)
                  : AppTheme.dashMutedSurfaceOf(context).withValues(alpha: 0.5),
              border: Border.all(
                color: selected
                    ? AppTheme.primaryNavy.withValues(alpha: 0.35)
                    : AppTheme.dashHairlineOf(context),
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Row(
                children: [
                  Radio<int>(
                    value: index,
                    groupValue: groupValue,
                    onChanged: onSelected,
                    activeColor: AppTheme.primaryNavy,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  Expanded(
                    child: TextField(
                      controller: controller,
                      onChanged: (_) => onChanged(),
                      style: AppTheme.dashFieldTextStyle(context),
                      decoration: RspExamEditorUi.inputDecoration(
                        context,
                        hintText: hint,
                      ).copyWith(
                        labelText: null,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
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

/// BEI question row with numbered badge.
class RspBeiQuestionRow extends StatelessWidget {
  const RspBeiQuestionRow({
    super.key,
    required this.index,
    required this.controller,
    required this.onChanged,
    required this.onRemove,
    required this.canRemove,
  });

  final int index;
  final TextEditingController controller;
  final VoidCallback onChanged;
  final VoidCallback onRemove;
  final bool canRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
      decoration: RspExamEditorUi.questionCard(context),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppTheme.primaryNavy.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '${index + 1}',
              style: const TextStyle(
                color: AppTheme.primaryNavy,
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: (_) => onChanged(),
              maxLines: 3,
              style: AppTheme.dashFieldTextStyle(context),
              decoration: RspExamEditorUi.inputDecoration(
                context,
                hintText: 'Question text…',
              ).copyWith(labelText: null),
            ),
          ),
          IconButton(
            onPressed: canRemove ? onRemove : null,
            tooltip: 'Remove question',
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: canRemove ? 0.08 : 0.03),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.red.withValues(alpha: canRemove ? 0.25 : 0.1),
                ),
              ),
              child: Icon(
                Icons.remove_rounded,
                size: 18,
                color: canRemove
                    ? Colors.red.shade700
                    : AppTheme.dashTextSecondaryOf(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Full-width gradient save button for exam editors.
class RspExamSaveButton extends StatelessWidget {
  const RspExamSaveButton({
    super.key,
    required this.label,
    required this.saving,
    required this.onPressed,
  });

  final String label;
  final bool saving;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: onPressed == null
              ? null
              : const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFFF0671A),
                    AppTheme.primaryNavy,
                    AppTheme.primaryNavyDark,
                  ],
                ),
          color: onPressed == null ? Colors.grey.shade400 : null,
          boxShadow: onPressed == null
              ? null
              : [
                  BoxShadow(
                    color: AppTheme.primaryNavy.withValues(alpha: 0.32),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
        ),
        child: FilledButton.icon(
          onPressed: onPressed,
          icon: saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.save_rounded, size: 20),
          label: Text(saving ? 'Saving…' : label),
          style: FilledButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      ),
    );
  }
}
