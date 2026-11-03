import 'package:flutter/material.dart';

import 'package:hrms_plaridel/features/docutracker/theme/docutracker_tokens.dart';

/// Compact status chip used in the document builder app bar.
class DocuTrackerBuilderStatusChip extends StatelessWidget {
  const DocuTrackerBuilderStatusChip({
    super.key,
    required this.label,
    required this.tone,
  });

  final String label;
  final DocuTrackerBuilderStatusTone tone;

  @override
  Widget build(BuildContext context) {
    final (Color fg, Color bg, Color border) = switch (tone) {
      DocuTrackerBuilderStatusTone.dirty => (
        DocuTrackerTokens.brandDark,
        DocuTrackerTokens.brandSoftOf(context),
        DocuTrackerTokens.brand.withValues(alpha: 0.35),
      ),
      DocuTrackerBuilderStatusTone.saving => (
        DocuTrackerTokens.textSecondaryOf(context),
        DocuTrackerTokens.surfaceOf(context),
        DocuTrackerTokens.borderSubtleOf(context),
      ),
      DocuTrackerBuilderStatusTone.saved => (
        const Color(0xFF166534),
        const Color(0xFFDCFCE7),
        const Color(0xFF86EFAC),
      ),
      DocuTrackerBuilderStatusTone.readOnly => (
        DocuTrackerTokens.textMutedOf(context),
        DocuTrackerTokens.surfaceOf(context),
        DocuTrackerTokens.borderSubtleOf(context),
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }
}

enum DocuTrackerBuilderStatusTone { dirty, saving, saved, readOnly }

/// Guidance strip shown above the Memo canvas while drafting.
class DocuTrackerMemoEditorHintBanner extends StatelessWidget {
  const DocuTrackerMemoEditorHintBanner({
    super.key,
    required this.editable,
  });

  final bool editable;

  @override
  Widget build(BuildContext context) {
    final message = editable
        ? 'Edit To, Subject, Date, body, and Cc on the page. '
              'Prepared by and Approved by are fixed signatory slots. '
              'Use Save Draft here; submit the workflow from the document page.'
        : 'This Memo is view-only. Content and layout follow the official template.';

    return Material(
      color: editable
          ? DocuTrackerTokens.brandSoftOf(context).withValues(alpha: 0.55)
          : DocuTrackerTokens.surfaceOf(context),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              editable
                  ? Icons.edit_note_rounded
                  : Icons.lock_outline_rounded,
              size: 18,
              color: editable
                  ? DocuTrackerTokens.brand
                  : DocuTrackerTokens.textMutedOf(context),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: DocuTrackerTokens.metaStyle(context).copyWith(
                  height: 1.35,
                  color: DocuTrackerTokens.textSecondaryOf(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom page / zoom controls for the document canvas.
class DocuTrackerBuilderCanvasBar extends StatelessWidget {
  const DocuTrackerBuilderCanvasBar({
    super.key,
    required this.pageLabel,
    required this.zoomLabel,
    required this.canGoPrevious,
    required this.canGoNext,
    required this.onPrevious,
    required this.onNext,
    required this.onPickPage,
    required this.pageCount,
    required this.onZoomOut,
    required this.onZoomIn,
    required this.onFitPage,
    required this.onFitWidth,
    required this.canZoomOut,
    required this.canZoomIn,
    this.enabled = true,
  });

  final String pageLabel;
  final String zoomLabel;
  final bool canGoPrevious;
  final bool canGoNext;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final ValueChanged<int> onPickPage;
  final int pageCount;
  final VoidCallback? onZoomOut;
  final VoidCallback? onZoomIn;
  final VoidCallback onFitPage;
  final VoidCallback onFitWidth;
  final bool canZoomOut;
  final bool canZoomIn;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 720;
    return SafeArea(
      top: false,
      child: Material(
        color: DocuTrackerTokens.surfaceOf(context),
        elevation: 2,
        shadowColor: Colors.black26,
        child: Padding(
          padding: EdgeInsets.fromLTRB(compact ? 8 : 12, 6, compact ? 8 : 12, 8),
          child: Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 4,
            runSpacing: 4,
            children: [
              IconButton(
                tooltip: 'Previous page',
                onPressed: canGoPrevious ? onPrevious : null,
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              PopupMenuButton<int>(
                tooltip: 'Choose page',
                enabled: enabled,
                onSelected: onPickPage,
                itemBuilder: (_) => List.generate(
                  pageCount,
                  (index) => PopupMenuItem(
                    value: index,
                    child: Text('Page ${index + 1}'),
                  ),
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(
                      DocuTrackerTokens.radiusSm,
                    ),
                    border: Border.all(
                      color: DocuTrackerTokens.borderSubtleOf(context),
                    ),
                  ),
                  child: Text(
                    pageLabel,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: DocuTrackerTokens.textPrimaryOf(context),
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Next page',
                onPressed: canGoNext ? onNext : null,
                icon: const Icon(Icons.chevron_right_rounded),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Zoom out',
                onPressed: canZoomOut ? onZoomOut : null,
                icon: const Icon(Icons.zoom_out_rounded),
              ),
              Text(
                zoomLabel,
                style: DocuTrackerTokens.metaStyle(context).copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              IconButton(
                tooltip: 'Zoom in',
                onPressed: canZoomIn ? onZoomIn : null,
                icon: const Icon(Icons.zoom_in_rounded),
              ),
              IconButton(
                tooltip: 'Fit page',
                onPressed: enabled ? onFitPage : null,
                icon: const Icon(Icons.fit_screen_rounded),
              ),
              IconButton(
                tooltip: 'Fit width',
                onPressed: enabled ? onFitWidth : null,
                icon: const Icon(Icons.width_wide_rounded),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
