import 'package:flutter/material.dart';

import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/shared/widgets/rsp_ld_record_actions.dart';

/// Column definition for [RspRecordsListTable].
class RspRecordsColumn {
  const RspRecordsColumn(
    this.label, {
    this.flex = 1.0,
    this.align = TextAlign.start,
  });

  final String label;
  final double flex;
  final TextAlign align;
}

/// Full-width records table (no horizontal scroll) with RSP card chrome.
class RspRecordsListTable extends StatelessWidget {
  const RspRecordsListTable({
    super.key,
    required this.columns,
    required this.rows,
  });

  final List<RspRecordsColumn> columns;
  final List<List<Widget>> rows;

  @override
  Widget build(BuildContext context) {
    assert(rows.every((r) => r.length == columns.length));

    final borderColor = AppTheme.dashHairlineOf(context);
    final headerBg = AppTheme.primaryNavy.withValues(alpha: 0.09);
    final panel = AppTheme.dashPanelOf(context);
    final muted = AppTheme.dashMutedSurfaceOf(context);

    final columnWidths = <int, TableColumnWidth>{
      for (var i = 0; i < columns.length; i++)
        i: FlexColumnWidth(columns[i].flex),
    };

    final tableRows = <TableRow>[
      TableRow(
        decoration: BoxDecoration(color: headerBg),
        children: columns
            .map(
              (c) => Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 14,
                ),
                child: Text(
                  c.label,
                  textAlign: c.align,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.letterheadNavy,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    letterSpacing: 0.4,
                    height: 1.2,
                  ),
                ),
              ),
            )
            .toList(),
      ),
      ...rows.asMap().entries.map((entry) {
        final rowBg = entry.key.isOdd ? muted : panel;
        return TableRow(
          decoration: BoxDecoration(color: rowBg),
          children: entry.value
              .map(
                (cell) => ColoredBox(
                  color: rowBg,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 12,
                    ),
                    child: cell,
                  ),
                ),
              )
              .toList(),
        );
      }),
    ];

    return SizedBox(
      width: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: muted,
          border: Border.all(color: borderColor),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                height: 3,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppTheme.primaryNavy, AppTheme.primaryNavyLight],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: panel,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: borderColor),
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return Table(
                        columnWidths: columnWidths,
                        defaultVerticalAlignment:
                            TableCellVerticalAlignment.middle,
                        border: TableBorder(
                          horizontalInside: BorderSide(color: borderColor),
                          verticalInside: BorderSide.none,
                        ),
                        children: tableRows,
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Standard text cell for [RspRecordsListTable].
Widget rspRecordsTextCell(
  String text, {
  bool bold = false,
  TextAlign align = TextAlign.start,
  int maxLines = 2,
}) {
  return Text(
    text.trim().isEmpty ? '—' : text,
    maxLines: maxLines,
    overflow: TextOverflow.ellipsis,
    textAlign: align,
    style: TextStyle(
      fontSize: bold ? 13.5 : 13,
      fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
      color: bold ? AppTheme.textPrimary : AppTheme.textSecondary,
      height: 1.3,
    ),
  );
}

/// View / Edit / Print / PDF / Delete action row for RSP record tables.
class RspRecordsCrudActions extends StatelessWidget {
  const RspRecordsCrudActions({
    super.key,
    this.onView,
    required this.onEdit,
    required this.onPrint,
    required this.onDownloadPdf,
    required this.onDelete,
    this.deleteDialogTitle = 'Delete record?',
    this.deleteDialogMessage = 'This cannot be undone.',
    this.showView = true,
    this.showEdit = true,
  });

  final VoidCallback? onView;
  final VoidCallback onEdit;
  final VoidCallback onPrint;
  final VoidCallback onDownloadPdf;
  final Future<void> Function() onDelete;
  final String deleteDialogTitle;
  final String deleteDialogMessage;
  final bool showView;
  final bool showEdit;

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(deleteDialogTitle),
        content: Text(deleteDialogMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) await onDelete();
  }

  @override
  Widget build(BuildContext context) {
    final navy = AppTheme.primaryNavy;
    final iconStyle = rspLdRecordIconButtonStyle(foreground: navy);
    return Wrap(
      spacing: kRspLdRecordActionGap,
      runSpacing: kRspLdRecordActionGap,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (showView && onView != null)
          TextButton(
            onPressed: onView,
            style: TextButton.styleFrom(
              foregroundColor: navy,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              minimumSize: const Size(0, 36),
            ),
            child: const Text(
              'View',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        if (showEdit)
          TextButton(
            onPressed: onEdit,
            style: TextButton.styleFrom(
              foregroundColor: navy,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              minimumSize: const Size(0, 36),
            ),
            child: const Text(
              'Edit',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        IconButton(
          onPressed: onPrint,
          icon: const Icon(Icons.print_rounded, size: 20),
          tooltip: 'Print',
          style: iconStyle,
        ),
        IconButton(
          onPressed: onDownloadPdf,
          icon: const Icon(Icons.picture_as_pdf_rounded, size: 20),
          tooltip: 'Download PDF',
          style: iconStyle,
        ),
        TextButton(
          onPressed: () => _confirmDelete(context),
          style: TextButton.styleFrom(
            foregroundColor: Colors.red.shade700,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            minimumSize: const Size(0, 36),
          ),
          child: const Text(
            'Delete',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

/// Empty-state panel for RSP form sections.
class RspFormEmptyState extends StatelessWidget {
  const RspFormEmptyState({super.key, required this.message, this.icon});

  final String message;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final borderColor = AppTheme.dashHairlineOf(context);
    final muted = AppTheme.dashMutedSurfaceOf(context);
    return SizedBox(
      width: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: muted,
          border: Border.all(color: borderColor),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon ?? Icons.inbox_outlined,
                size: 44,
                color: AppTheme.textSecondary.withValues(alpha: 0.45),
              ),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppTheme.textSecondary.withValues(alpha: 0.95),
                  fontSize: 14,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
