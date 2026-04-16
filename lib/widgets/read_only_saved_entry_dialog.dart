import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../landingpage/constants/app_theme.dart';

/// Scrollable read-only view of a previously saved form (RSP / L&D).
///
/// Pass either [sections] (label/value summary) or [previewBuilder] (same layout
/// as the fillable form, built with `readOnly: true` on the editor widget).
void showReadOnlySavedEntryDialog(
  BuildContext context, {
  required String title,
  List<Widget> sections = const [],
  Widget Function()? previewBuilder,
  double contentWidth = 520,
}) {
  assert(
    previewBuilder != null || sections.isNotEmpty,
    'Provide previewBuilder or non-empty sections',
  );

  showDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierColor: Colors.black.withValues(alpha: 0.48),
    builder: (ctx) {
      final mq = MediaQuery.of(ctx);
      final maxW = math.min(contentWidth, mq.size.width - 32);
      final viewPad = mq.viewPadding;
      // Leave room for dialog insetPadding (~44) and system chrome so Column + Expanded never exceed viewport.
      final maxDialogH = math.max(
        220.0,
        mq.size.height -
            viewPad.vertical -
            mq.viewInsets.bottom -
            52,
      );

      final buildPreview = previewBuilder;
      final scrollChild = buildPreview != null
          ? buildPreview()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: sections,
            );

      return Dialog(
        backgroundColor: const Color(0xFFFFFBF8),
        elevation: 14,
        shadowColor: Colors.black.withValues(alpha: 0.22),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
        ),
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 22),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: maxW + 48,
            maxHeight: maxDialogH,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.max,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 18, 12, 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textPrimary,
                          height: 1.25,
                        ),
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
                color: AppTheme.primaryNavy.withValues(alpha: 0.1),
              ),
              Expanded(
                child: Scrollbar(
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: maxW),
                      child: scrollChild,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.primaryNavy,
                      textStyle: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    child: const Text('Close'),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

String roDash(String? s) {
  if (s == null) return '—';
  final t = s.trim();
  return t.isEmpty ? '—' : t;
}

/// Label + value block for [showReadOnlySavedEntryDialog] sections.
List<Widget> roField(String label, String? value) {
  return [
    Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: AppTheme.textSecondary,
        ),
      ),
    ),
    Text(
      roDash(value),
      style: const TextStyle(
        fontSize: 14,
        height: 1.45,
        color: AppTheme.textPrimary,
      ),
    ),
  ];
}

Widget roSectionTitle(String text) {
  return Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 8),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w800,
        color: AppTheme.textPrimary,
      ),
    ),
  );
}
