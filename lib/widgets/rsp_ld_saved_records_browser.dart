import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../landingpage/constants/app_theme.dart';
import 'read_only_saved_entry_dialog.dart';

/// One row in the saved-records browser (view read-only summary + print).
class SavedRecordListItem {
  SavedRecordListItem({
    required this.title,
    this.subtitle,
    required this.detailDialogTitle,
    this.previewSections = const [],
    this.previewBuilder,
    this.previewContentWidth,
    required this.onPrint,
  }) : assert(
         previewBuilder != null || previewSections.isNotEmpty,
         'Use previewBuilder (form layout) or non-empty previewSections',
       );

  final String title;
  final String? subtitle;
  final String detailDialogTitle;

  /// Fallback summary list when [previewBuilder] is null.
  final List<Widget> previewSections;

  /// When set, "View" shows the same widget tree as the data-entry form (`readOnly: true`).
  final Widget Function()? previewBuilder;
  final double? previewContentWidth;
  final Future<void> Function() onPrint;
}

/// Soft panel background for RSP / L&D saved-record pickers.
const Color _kSavedRecordsPanelBg = Color(0xFFFFF8F4);
const Color _kSavedRecordsCardBg = Color(0xFFFFFFFF);

/// Lists completed/saved form entries so admins can review and print without scanning the table.
Future<void> showRspLdSavedRecordsBrowser(
  BuildContext context, {
  required String sheetTitle,
  required String emptyMessage,
  required bool loading,
  required List<SavedRecordListItem> items,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (dialogContext) {
      final size = MediaQuery.sizeOf(dialogContext);
      final viewPad = MediaQuery.viewPaddingOf(dialogContext);
      final maxW = math.min(560.0, size.width - 40);
      final maxDialogH = math.max(
        280.0,
        math.min(560.0, size.height - viewPad.vertical - 52),
      );

      return Dialog(
        backgroundColor: _kSavedRecordsPanelBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        elevation: 12,
        shadowColor: Colors.black.withValues(alpha: 0.2),
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxW, maxHeight: maxDialogH),
          child: Column(
            mainAxisSize: MainAxisSize.max,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 20, 16, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryNavy.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        Icons.folder_open_rounded,
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
                            sheetTitle,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.textPrimary,
                              height: 1.2,
                            ),
                          ),
                          if (!loading && items.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              '${items.length} ${items.length == 1 ? 'saved record' : 'saved records'}',
                              style: TextStyle(
                                fontSize: 13,
                                color: AppTheme.textSecondary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: () => Navigator.of(dialogContext).pop(),
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
                child: loading
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    : items.isEmpty
                    ? Center(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(28),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.inbox_outlined,
                                size: 48,
                                color: AppTheme.textSecondary.withValues(
                                  alpha: 0.45,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                emptyMessage,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontSize: 14,
                                  height: 1.45,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (ctx, i) {
                          final it = items[i];
                          return Material(
                            color: _kSavedRecordsCardBg,
                            elevation: 0,
                            shadowColor: Colors.transparent,
                            borderRadius: BorderRadius.circular(16),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () {
                                showReadOnlySavedEntryDialog(
                                  context,
                                  title: it.detailDialogTitle,
                                  sections: it.previewSections,
                                  previewBuilder: it.previewBuilder,
                                  contentWidth: it.previewContentWidth ?? 520,
                                );
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: AppTheme.lightGray),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 44,
                                      height: 44,
                                      decoration: BoxDecoration(
                                        color: AppTheme.primaryNavy.withValues(
                                          alpha: 0.1,
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Icon(
                                        Icons.description_outlined,
                                        color: AppTheme.primaryNavy,
                                        size: 22,
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            it.title,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 15,
                                              color: AppTheme.textPrimary,
                                            ),
                                          ),
                                          if (it.subtitle != null) ...[
                                            const SizedBox(height: 4),
                                            Text(
                                              it.subtitle!,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 12,
                                                height: 1.3,
                                                color: AppTheme.textSecondary,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    IconButton(
                                      tooltip: 'View',
                                      style: IconButton.styleFrom(
                                        backgroundColor: AppTheme.primaryNavy
                                            .withValues(alpha: 0.1),
                                        foregroundColor: AppTheme.primaryNavy,
                                      ),
                                      onPressed: () {
                                        showReadOnlySavedEntryDialog(
                                          context,
                                          title: it.detailDialogTitle,
                                          sections: it.previewSections,
                                          previewBuilder: it.previewBuilder,
                                          contentWidth:
                                              it.previewContentWidth ?? 520,
                                        );
                                      },
                                      icon: const Icon(
                                        Icons.visibility_rounded,
                                        size: 22,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    IconButton(
                                      tooltip: 'Print',
                                      style: IconButton.styleFrom(
                                        backgroundColor: AppTheme.primaryNavy
                                            .withValues(alpha: 0.1),
                                        foregroundColor: AppTheme.primaryNavy,
                                      ),
                                      onPressed: () async {
                                        try {
                                          await it.onPrint();
                                        } catch (e) {
                                          if (dialogContext.mounted) {
                                            ScaffoldMessenger.of(
                                              dialogContext,
                                            ).showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  'Print failed: $e',
                                                ),
                                              ),
                                            );
                                          }
                                        }
                                      },
                                      icon: const Icon(
                                        Icons.print_rounded,
                                        size: 22,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
