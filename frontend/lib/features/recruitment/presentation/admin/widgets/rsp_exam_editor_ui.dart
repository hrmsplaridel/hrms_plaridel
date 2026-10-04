import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/recruitment/data/exam_image_support.dart';
import 'package:hrms_plaridel/features/recruitment/models/recruitment_application.dart';
import 'package:hrms_plaridel/features/recruitment/presentation/shared/widgets/exam_image_widgets.dart';

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
              ? [const Color(0xFF252D3D), const Color(0xFF1E2430)]
              : [
                  const Color(0xFFFFF8F3),
                  Colors.white,
                  const Color(0xFFF5F8FF),
                ],
        ),
        border: Border.all(color: AppTheme.primaryNavy.withValues(alpha: 0.14)),
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

/// Applicant time limit strip (shared by all exam editors).
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

/// Wraps one MCQ question block with card chrome, delete control, and a
/// collapsible body. Collapsed cards show the question text and a short
/// summary so long exams stay readable.
class RspMcqQuestionCard extends StatelessWidget {
  const RspMcqQuestionCard({
    super.key,
    required this.index,
    required this.onRemove,
    required this.child,
    required this.collapsed,
    required this.onToggle,
    this.questionPreview = '',
    this.summary,
    this.isComplete = true,
  });

  final int index;
  final VoidCallback? onRemove;
  final Widget child;
  final bool collapsed;
  final VoidCallback onToggle;

  /// Question text shown as the title while collapsed.
  final String questionPreview;

  /// Secondary line while collapsed (option count, correct answer).
  final String? summary;

  /// False when the question text or options are still missing.
  final bool isComplete;

  @override
  Widget build(BuildContext context) {
    final primary = AppTheme.dashTextPrimaryOf(context);
    final secondary = AppTheme.dashTextSecondaryOf(context);
    final preview = questionPreview.trim();
    final title = collapsed
        ? (preview.isEmpty ? 'Untitled question' : preview)
        : 'Question';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: RspExamEditorUi.questionCard(context),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onToggle,
              child: Padding(
                padding: EdgeInsets.fromLTRB(18, collapsed ? 12 : 16, 8, collapsed ? 12 : 0),
                child: Row(
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: collapsed ? 2 : 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: collapsed && preview.isEmpty
                                  ? secondary
                                  : primary,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (collapsed &&
                              (summary != null || !isComplete)) ...[
                            const SizedBox(height: 3),
                            Text(
                              isComplete
                                  ? summary!
                                  : 'Incomplete — add the question and at least 2 options',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: isComplete
                                    ? secondary
                                    : Colors.orange.shade800,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
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
                    IconButton(
                      onPressed: onToggle,
                      tooltip: collapsed ? 'Expand question' : 'Collapse question',
                      icon: Icon(
                        collapsed
                            ? Icons.keyboard_arrow_down_rounded
                            : Icons.keyboard_arrow_up_rounded,
                        color: AppTheme.primaryNavy,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: collapsed
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.fromLTRB(18, 14, 12, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        child,
                        const SizedBox(height: 6),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: onToggle,
                            icon: const Icon(
                              Icons.keyboard_arrow_up_rounded,
                              size: 20,
                            ),
                            label: const Text('Done'),
                            style: RspExamEditorUi.ghostAction(context),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
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
    this.imagePath,
    this.onImageChanged,
  });

  final int index;
  final int groupValue;
  final TextEditingController controller;
  final ValueChanged<int?> onSelected;
  final VoidCallback onChanged;

  /// Optional image for this choice. The picker is shown only when
  /// [onImageChanged] is provided.
  final String? imagePath;
  final ValueChanged<String?>? onImageChanged;

  @override
  Widget build(BuildContext context) {
    final selected = index == groupValue;
    final hint = imagePath != null
        ? 'Label (optional)'
        : 'Option ${String.fromCharCode(97 + index)}';

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
                crossAxisAlignment: onImageChanged == null
                    ? CrossAxisAlignment.center
                    : CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: EdgeInsets.only(
                      top: onImageChanged == null ? 0 : 6,
                    ),
                    child: Radio<int>(
                      value: index,
                      activeColor: AppTheme.primaryNavy,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: controller,
                          onChanged: (_) => onChanged(),
                          style: AppTheme.dashFieldTextStyle(context),
                          decoration:
                              RspExamEditorUi.inputDecoration(
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
                        if (onImageChanged != null)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(0, 4, 8, 6),
                            child: RspExamImagePicker(
                              path: imagePath,
                              compact: true,
                              onChanged: onImageChanged!,
                            ),
                          ),
                      ],
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

/// BEI / open-ended question row with numbered badge. Rows that already have
/// text start collapsed; tap the row (or the arrow) to edit.
///
/// Give each row a stable key (e.g. `ObjectKey(controller)`) so the collapsed
/// state follows the question when others are removed.
class RspBeiQuestionRow extends StatefulWidget {
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
  State<RspBeiQuestionRow> createState() => _RspBeiQuestionRowState();
}

class _RspBeiQuestionRowState extends State<RspBeiQuestionRow> {
  late bool _collapsed = widget.controller.text.trim().isNotEmpty;

  void _toggle() => setState(() => _collapsed = !_collapsed);

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final canRemove = widget.canRemove;
    final secondary = AppTheme.dashTextSecondaryOf(context);
    final text = controller.text.trim();

    final badge = Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppTheme.primaryNavy.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '${widget.index + 1}',
        style: const TextStyle(
          color: AppTheme.primaryNavy,
          fontWeight: FontWeight.w800,
          fontSize: 14,
        ),
      ),
    );

    final removeButton = IconButton(
      onPressed: canRemove ? widget.onRemove : null,
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
          color: canRemove ? Colors.red.shade700 : secondary,
        ),
      ),
    );

    final toggleButton = IconButton(
      onPressed: _toggle,
      tooltip: _collapsed ? 'Expand question' : 'Collapse question',
      icon: Icon(
        _collapsed
            ? Icons.keyboard_arrow_down_rounded
            : Icons.keyboard_arrow_up_rounded,
        color: AppTheme.primaryNavy,
      ),
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: RspExamEditorUi.questionCard(context),
      clipBehavior: Clip.antiAlias,
      child: _collapsed
          ? InkWell(
              onTap: _toggle,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
                child: Row(
                  children: [
                    badge,
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        text.isEmpty ? 'Untitled question' : text,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: text.isEmpty
                              ? secondary
                              : AppTheme.dashTextPrimaryOf(context),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                        ),
                      ),
                    ),
                    removeButton,
                    toggleButton,
                  ],
                ),
              ),
            )
          : Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  badge,
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: controller,
                      onChanged: (_) => widget.onChanged(),
                      maxLines: 3,
                      style: AppTheme.dashFieldTextStyle(context),
                      decoration: RspExamEditorUi.inputDecoration(
                        context,
                        hintText: 'Question text…',
                      ).copyWith(labelText: null),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [removeButton, toggleButton],
                  ),
                ],
              ),
            ),
    );
  }
}

/// Optional image / diagram attachment for an exam question or answer choice.
///
/// Picks a PNG / JPG / WEBP file, validates it, uploads it through the API and
/// reports the stored relative path via [onChanged] (null = removed).
class RspExamImagePicker extends StatefulWidget {
  const RspExamImagePicker({
    super.key,
    required this.path,
    required this.onChanged,
    this.compact = false,
    this.addLabel,
  });

  final String? path;
  final ValueChanged<String?> onChanged;

  /// Small inline variant used inside answer-choice rows.
  final bool compact;
  final String? addLabel;

  @override
  State<RspExamImagePicker> createState() => _RspExamImagePickerState();
}

class _RspExamImagePickerState extends State<RspExamImagePicker> {
  bool _busy = false;
  String? _error;

  Future<void> _pick() async {
    if (_busy) return;
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: kExamImageExtensions,
        allowMultiple: false,
        withData: true,
      );
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not open the file picker.');
      return;
    }
    if (result == null || result.files.isEmpty) return;

    final picked = result.files.single;
    final bytes = picked.bytes;
    if (bytes == null) {
      setState(() => _error = 'Could not read the selected file.');
      return;
    }
    final problem = await validateExamImage(bytes: bytes, fileName: picked.name);
    if (!mounted) return;
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final stored = await RecruitmentRepo.instance.uploadExamImage(
        bytes: bytes,
        fileName: picked.name,
      );
      if (!mounted) return;
      widget.onChanged(stored);
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), ''),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _remove() {
    setState(() => _error = null);
    widget.onChanged(null);
  }

  @override
  Widget build(BuildContext context) {
    final path = widget.path;
    final compact = widget.compact;
    final secondary = AppTheme.dashTextSecondaryOf(context);

    final Widget body;
    if (_busy) {
      body = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 8),
          Text(
            'Uploading image…',
            style: TextStyle(color: secondary, fontSize: 12.5),
          ),
        ],
      );
    } else if (path == null) {
      body = compact
          ? TextButton.icon(
              onPressed: _pick,
              icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
              label: Text(widget.addLabel ?? 'Add image'),
              style: RspExamEditorUi.ghostAction(context).copyWith(
                padding: const WidgetStatePropertyAll(
                  EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                ),
                minimumSize: const WidgetStatePropertyAll(Size(0, 30)),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            )
          : OutlinedButton.icon(
              onPressed: _pick,
              icon: const Icon(Icons.add_photo_alternate_outlined, size: 20),
              label: Text(widget.addLabel ?? 'Add image / diagram'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.primaryNavy,
                side: BorderSide(
                  color: AppTheme.primaryNavy.withValues(alpha: 0.4),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            );
    } else {
      final actions = Wrap(
        spacing: 4,
        runSpacing: 0,
        children: [
          TextButton.icon(
            onPressed: _pick,
            icon: const Icon(Icons.swap_horiz_rounded, size: 18),
            label: const Text('Replace'),
            style: RspExamEditorUi.ghostAction(context),
          ),
          TextButton.icon(
            onPressed: _remove,
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
            label: const Text('Remove'),
            style: TextButton.styleFrom(
              foregroundColor: Colors.red.shade700,
              textStyle: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      );
      body = compact
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _thumb(path, 64, 64),
                const SizedBox(width: 10),
                Flexible(child: actions),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _thumb(path, double.infinity, 170),
                const SizedBox(height: 6),
                actions,
              ],
            );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Align(alignment: Alignment.centerLeft, child: body),
        if (_error != null) ...[
          const SizedBox(height: 4),
          Text(
            _error!,
            style: TextStyle(
              color: Colors.red.shade700,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }

  Widget _thumb(String path, double width, double height) {
    return Tooltip(
      message: 'Click to enlarge',
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => showExamImageViewer(context, path: path),
        child: Container(
          width: width,
          height: height,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: AppTheme.primaryNavy.withValues(alpha: 0.2),
            ),
          ),
          child: ExamImage(path: path, boxHeight: height - 8),
        ),
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
