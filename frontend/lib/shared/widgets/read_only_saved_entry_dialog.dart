import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:hrms_plaridel/core/theme/app_theme.dart';

const Color _kSavedFormDialogBg = Color(0xFFFFF8F4);
const Color _kSavedFormContentBg = Color(0xFFFFFFFF);

/// Scrollable read-only view of a previously saved form (RSP / L&D).
///
/// Pass either [sections] (label/value summary) or [previewBuilder] (same layout
/// as the fillable form, built with `readOnly: true` on the editor widget).
void showReadOnlySavedEntryDialog(
  BuildContext context, {
  required String title,
  String? subtitle,
  List<String> metadataChips = const [],
  List<Widget> sections = const [],
  Widget Function()? previewBuilder,
  double contentWidth = 520,
  Future<void> Function()? onPrint,
  IconData? icon,
}) {
  assert(
    previewBuilder != null || sections.isNotEmpty,
    'Provide previewBuilder or non-empty sections',
  );

  final scrollController = ScrollController();
  showDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierColor: Colors.black.withValues(alpha: 0.5),
    builder: (ctx) {
      final mq = MediaQuery.of(ctx);
      final maxW = math.min(contentWidth, mq.size.width - 32);
      final viewPad = mq.viewPadding;
      final maxDialogH = math.max(
        280.0,
        mq.size.height - viewPad.vertical - mq.viewInsets.bottom - 40,
      );
      final headerIcon = icon ?? _iconForSavedFormTitle(title);

      final buildPreview = previewBuilder;
      final scrollChild = buildPreview != null
          ? buildPreview()
          : _SavedFormSectionsBody(sections: sections);

      return Dialog(
        backgroundColor: _kSavedFormDialogBg,
        elevation: 16,
        shadowColor: Colors.black.withValues(alpha: 0.24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: maxW + 56,
            maxHeight: maxDialogH,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.max,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                height: 3,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppTheme.primaryNavy, AppTheme.primaryNavyLight],
                  ),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryNavy.withValues(alpha: 0.11),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: AppTheme.primaryNavy.withValues(alpha: 0.16),
                        ),
                      ),
                      child: Icon(
                        headerIcon,
                        color: AppTheme.primaryNavy,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.textPrimary,
                              height: 1.25,
                            ),
                          ),
                          if (subtitle != null &&
                              subtitle.trim().isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              subtitle.trim(),
                              style: TextStyle(
                                fontSize: 13,
                                color: AppTheme.textSecondary,
                                fontWeight: FontWeight.w500,
                                height: 1.35,
                              ),
                            ),
                          ],
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              _ReadOnlyBadge(),
                              ...metadataChips.map(_MetadataChip.new),
                            ],
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: () => Navigator.of(ctx).pop(),
                      icon: Icon(
                        Icons.close_rounded,
                        color: AppTheme.textSecondary.withValues(alpha: 0.85),
                      ),
                      tooltip: 'Close',
                    ),
                  ],
                ),
              ),
              Divider(
                height: 1,
                thickness: 1,
                color: AppTheme.primaryNavy.withValues(alpha: 0.08),
              ),
              Expanded(
                child: Scrollbar(
                  controller: scrollController,
                  thumbVisibility: true,
                  radius: const Radius.circular(4),
                  child: SingleChildScrollView(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: maxW),
                        child: buildPreview != null
                            ? scrollChild
                            : DecoratedBox(
                                decoration: BoxDecoration(
                                  color: _kSavedFormContentBg,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: AppTheme.primaryNavy.withValues(
                                      alpha: 0.1,
                                    ),
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.04,
                                      ),
                                      blurRadius: 10,
                                      offset: const Offset(0, 3),
                                    ),
                                  ],
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    14,
                                    16,
                                    16,
                                  ),
                                  child: scrollChild,
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                decoration: BoxDecoration(
                  color: AppTheme.dashPanelOf(ctx),
                  border: Border(
                    top: BorderSide(
                      color: AppTheme.primaryNavy.withValues(alpha: 0.08),
                    ),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (onPrint != null) ...[
                      OutlinedButton.icon(
                        onPressed: () async {
                          try {
                            await onPrint();
                          } catch (e) {
                            if (ctx.mounted) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                SnackBar(content: Text('Print failed: $e')),
                              );
                            }
                          }
                        },
                        icon: const Icon(Icons.print_rounded, size: 20),
                        label: const Text('Print'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.primaryNavy,
                          side: BorderSide(
                            color: AppTheme.primaryNavy.withValues(alpha: 0.4),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    FilledButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.primaryNavy,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 22,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Close',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  ).whenComplete(scrollController.dispose);
}

IconData _iconForSavedFormTitle(String title) {
  final t = title.toLowerCase();
  if (t.contains('bi') || t.contains('background')) {
    return Icons.fact_check_outlined;
  }
  if (t.contains('performance')) return Icons.assessment_outlined;
  if (t.contains('idp') || t.contains('development plan')) {
    return Icons.trending_up_rounded;
  }
  if (t.contains('applicant')) return Icons.people_outline_rounded;
  if (t.contains('comparative')) return Icons.compare_arrows_rounded;
  if (t.contains('promotion')) return Icons.workspace_premium_outlined;
  if (t.contains('selection') || t.contains('line-up')) {
    return Icons.list_alt_rounded;
  }
  if (t.contains('turn-around') || t.contains('turnaround')) {
    return Icons.schedule_rounded;
  }
  if (t.contains('training')) return Icons.school_outlined;
  if (t.contains('brainstorm') || t.contains('coaching')) {
    return Icons.lightbulb_outline_rounded;
  }
  return Icons.description_outlined;
}

class _ReadOnlyBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.primaryNavy.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.primaryNavy.withValues(alpha: 0.2)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.lock_outline_rounded,
            size: 13,
            color: AppTheme.primaryNavy,
          ),
          SizedBox(width: 5),
          Text(
            'Read-only preview',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppTheme.primaryNavy,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetadataChip extends StatelessWidget {
  const _MetadataChip(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.primaryNavy.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppTheme.textSecondary,
        ),
      ),
    );
  }
}

class _SavedFormSectionsBody extends StatelessWidget {
  const _SavedFormSectionsBody({required this.sections});

  final List<Widget> sections;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: sections,
    );
  }
}

String roDash(String? s) {
  if (s == null) return '—';
  final t = s.trim();
  return t.isEmpty ? '—' : t;
}

/// Label + value block for [showReadOnlySavedEntryDialog] sections.
List<Widget> roField(String label, String? value) {
  return [roFieldCard(label, value)];
}

/// Single card field for summary sections.
Widget roFieldCard(String label, String? value) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _kSavedFormContentBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primaryNavy.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
              color: AppTheme.primaryNavy.withValues(alpha: 0.85),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            roDash(value),
            style: const TextStyle(
              fontSize: 14,
              height: 1.45,
              fontWeight: FontWeight.w500,
              color: AppTheme.textPrimary,
            ),
          ),
        ],
      ),
    ),
  );
}

Widget roSectionTitle(String text) {
  return Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 12),
    child: Row(
      children: [
        Container(
          width: 4,
          height: 22,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(2),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                AppTheme.primaryNavyLight,
                AppTheme.primaryNavy.withValues(alpha: 0.9),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: AppTheme.letterheadNavy,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ],
    ),
  );
}

/// Groups related fields under a titled card (RSP / L&D summary previews).
Widget roFieldsGroup({required String title, required List<Widget> children}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: _kSavedFormContentBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.primaryNavy.withValues(alpha: 0.1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [roSectionTitle(title), ...children],
        ),
      ),
    ),
  );
}
