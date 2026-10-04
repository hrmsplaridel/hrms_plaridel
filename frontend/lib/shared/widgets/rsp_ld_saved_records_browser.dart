import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:hrms_plaridel/core/theme/app_theme.dart';
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
    this.onDocumentPreview,
    this.onEdit,
    this.onDelete,
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

  /// Opens the printable document preview. Does not save the record.
  final Future<void> Function()? onDocumentPreview;

  /// Opens the record in the form editor.
  final VoidCallback? onEdit;

  /// Deletes the record. The panel confirms first.
  final VoidCallback? onDelete;
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
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close records',
    barrierColor: Colors.black.withValues(alpha: 0.35),
    transitionDuration: const Duration(milliseconds: 240),
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      final size = MediaQuery.sizeOf(dialogContext);
      final panelWidth = math.min(420.0, math.max(300.0, size.width - 24));

      return Align(
        alignment: Alignment.centerRight,
        child: Material(
          color: _kSavedRecordsPanelBg,
          elevation: 16,
          shadowColor: Colors.black.withValues(alpha: 0.2),
          borderRadius: const BorderRadius.horizontal(
            left: Radius.circular(20),
          ),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: panelWidth,
            height: size.height,
            child: SafeArea(
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
                padding: const EdgeInsets.fromLTRB(22, 18, 16, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryNavy.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: AppTheme.primaryNavy.withValues(alpha: 0.18),
                        ),
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
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (ctx, i) {
                          final it = items[i];
                          final subtitleParts = it.subtitle
                              ?.split('·')
                              .map((s) => s.trim())
                              .where((s) => s.isNotEmpty)
                              .toList();
                          return Material(
                            color: _kSavedRecordsCardBg,
                            elevation: 0,
                            shadowColor: Colors.transparent,
                            borderRadius: BorderRadius.circular(16),
                            clipBehavior: Clip.antiAlias,
                            child: Container(
                                width: double.infinity,
                                decoration: BoxDecoration(
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
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    InkWell(
                                      onTap: () {
                                        if (it.onEdit != null) {
                                          Navigator.of(dialogContext).pop();
                                          it.onEdit!();
                                          return;
                                        }
                                        showReadOnlySavedEntryDialog(
                                          context,
                                          title: it.detailDialogTitle,
                                          subtitle: it.subtitle,
                                          sections: it.previewSections,
                                          previewBuilder: it.previewBuilder,
                                          contentWidth:
                                              it.previewContentWidth ?? 520,
                                          onPrint: it.onPrint,
                                          onDocumentPreview:
                                              it.onDocumentPreview,
                                        );
                                      },
                                      child: Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        14,
                                        14,
                                        14,
                                        12,
                                      ),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Container(
                                            width: 42,
                                            height: 42,
                                            decoration: BoxDecoration(
                                              color: AppTheme.primaryNavy
                                                  .withValues(alpha: 0.1),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            child: const Icon(
                                              Icons.description_outlined,
                                              color: AppTheme.primaryNavy,
                                              size: 22,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  it.title,
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w800,
                                                    fontSize: 15.5,
                                                    color: AppTheme.textPrimary,
                                                    height: 1.25,
                                                  ),
                                                ),
                                                if (subtitleParts != null &&
                                                    subtitleParts
                                                        .isNotEmpty) ...[
                                                  const SizedBox(height: 8),
                                                  Wrap(
                                                    spacing: 6,
                                                    runSpacing: 6,
                                                    children: subtitleParts
                                                        .map(
                                                          (part) => Container(
                                                            padding:
                                                                const EdgeInsets.symmetric(
                                                                  horizontal: 8,
                                                                  vertical: 3,
                                                                ),
                                                            decoration:
                                                                BoxDecoration(
                                                                  color: AppTheme
                                                                      .primaryNavy
                                                                      .withValues(
                                                                        alpha:
                                                                            0.07,
                                                                      ),
                                                                  borderRadius:
                                                                      BorderRadius.circular(
                                                                        20,
                                                                      ),
                                                                ),
                                                            child: Text(
                                                              part,
                                                              style: TextStyle(
                                                                fontSize: 11.5,
                                                                fontWeight:
                                                                    FontWeight.w600,
                                                                color: AppTheme
                                                                    .textSecondary,
                                                              ),
                                                            ),
                                                          ),
                                                        )
                                                        .toList(),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    ),
                                    _SavedRecordActionBar(
                                      onEdit: it.onEdit == null
                                          ? null
                                          : () {
                                              Navigator.of(dialogContext).pop();
                                              it.onEdit!();
                                            },
                                      onView: () {
                                        showReadOnlySavedEntryDialog(
                                          context,
                                          title: it.detailDialogTitle,
                                          subtitle: it.subtitle,
                                          sections: it.previewSections,
                                          previewBuilder: it.previewBuilder,
                                          contentWidth:
                                              it.previewContentWidth ?? 520,
                                          onPrint: it.onPrint,
                                          onDocumentPreview:
                                              it.onDocumentPreview,
                                        );
                                      },
                                      onDocumentPreview: it.onDocumentPreview,
                                      onPrint: () async {
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
                                      onDelete: it.onDelete == null
                                          ? null
                                          : () async {
                                              final ok = await showDialog<bool>(
                                                context: dialogContext,
                                                builder: (ctx) => AlertDialog(
                                                  title: const Text(
                                                    'Delete record?',
                                                  ),
                                                  content: Text(
                                                    'Delete "${it.title}"? This cannot be undone.',
                                                  ),
                                                  actions: [
                                                    TextButton(
                                                      onPressed: () =>
                                                          Navigator.of(
                                                            ctx,
                                                          ).pop(false),
                                                      child: const Text(
                                                        'Cancel',
                                                      ),
                                                    ),
                                                    FilledButton(
                                                      style:
                                                          FilledButton.styleFrom(
                                                            backgroundColor:
                                                                const Color(
                                                                  0xFFC62828,
                                                                ),
                                                          ),
                                                      onPressed: () =>
                                                          Navigator.of(
                                                            ctx,
                                                          ).pop(true),
                                                      child: const Text(
                                                        'Delete',
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              );
                                              if (ok != true) return;
                                              if (dialogContext.mounted) {
                                                Navigator.of(
                                                  dialogContext,
                                                ).pop();
                                              }
                                              it.onDelete!();
                                            },
                                    ),
                                  ],
                                ),
                              ),
                          );
                        },
                      ),
              ),
            ],
              ),
            ),
          ),
        ),
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      );
    },
  );
}

/// Labeled action row under a saved-record card. Shared by every RSP and L&D form.
class _SavedRecordActionBar extends StatelessWidget {
  const _SavedRecordActionBar({
    required this.onView,
    required this.onPrint,
    this.onEdit,
    this.onDocumentPreview,
    this.onDelete,
  });

  final VoidCallback? onEdit;
  final VoidCallback onView;
  final Future<void> Function()? onDocumentPreview;
  final Future<void> Function() onPrint;
  final Future<void> Function()? onDelete;

  @override
  Widget build(BuildContext context) {
    final actions = <Widget>[
      if (onEdit != null)
        _SavedRecordActionButton(
          label: 'Edit',
          icon: Icons.edit_outlined,
          onPressed: onEdit!,
        ),
      _SavedRecordActionButton(
        label: 'View',
        icon: Icons.visibility_outlined,
        onPressed: onView,
      ),
      if (onDocumentPreview != null)
        _SavedRecordActionButton(
          label: 'Preview',
          icon: Icons.article_outlined,
          busyLabel: 'Opening…',
          onPressed: onDocumentPreview!,
        ),
      _SavedRecordActionButton(
        label: 'Print',
        icon: Icons.print_outlined,
        busyLabel: 'Printing…',
        onPressed: onPrint,
      ),
      if (onDelete != null)
        _SavedRecordActionButton(
          label: 'Delete',
          icon: Icons.delete_outline_rounded,
          color: const Color(0xFFC62828),
          onPressed: onDelete!,
        ),
    ];

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.primaryNavy.withValues(alpha: 0.045),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(15)),
        border: Border(
          top: BorderSide(color: AppTheme.primaryNavy.withValues(alpha: 0.08)),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Row(
        children: [for (final action in actions) Expanded(child: action)],
      ),
    );
  }
}

class _SavedRecordActionButton extends StatefulWidget {
  const _SavedRecordActionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.color,
    this.busyLabel,
  });

  final String label;
  final IconData icon;
  final FutureOr<void> Function() onPressed;
  final Color? color;
  final String? busyLabel;

  @override
  State<_SavedRecordActionButton> createState() =>
      _SavedRecordActionButtonState();
}

class _SavedRecordActionButtonState extends State<_SavedRecordActionButton> {
  var _busy = false;

  Future<void> _run() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = widget.onPressed();
      if (result is Future) await result;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? AppTheme.primaryNavy;
    return Tooltip(
      message: _busy ? (widget.busyLabel ?? widget.label) : widget.label,
      child: InkWell(
        onTap: _busy ? null : _run,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: _busy ? 0.16 : 0.1),
                  shape: BoxShape.circle,
                ),
                child: _busy
                    ? SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: color,
                        ),
                      )
                    : Icon(widget.icon, size: 16, color: color),
              ),
              const SizedBox(height: 4),
              Text(
                widget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: color,
                  height: 1.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
