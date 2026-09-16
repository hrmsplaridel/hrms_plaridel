import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;

import '../../../models/document_purchase_items.dart';

class DocuTrackerPurchaseItemsEmbedBuilder extends quill.EmbedBuilder {
  const DocuTrackerPurchaseItemsEmbedBuilder({required this.editable});
  final bool editable;

  @override
  String get key => DocumentPurchaseItems.embedType;

  @override
  Widget build(BuildContext context, quill.EmbedContext embedContext) {
    final DocumentPurchaseItems items;
    try {
      items = DocumentPurchaseItems.decode(embedContext.node.value.data);
    } on FormatException {
      return const Text(
        'This purchase table could not be read. Reload the document before editing.',
      );
    }
    return DocuTrackerPurchaseItemsTable(
      items: items,
      onEdit: !editable || embedContext.readOnly
          ? null
          : () async {
              final updated = await showDialog<DocumentPurchaseItems>(
                context: context,
                builder: (_) => _PurchaseItemsDialog(items: items),
              );
              if (updated == null ||
                  !context.mounted ||
                  embedContext.controller.readOnly) {
                return;
              }
              final offset = embedContext.node.documentOffset;
              embedContext.controller.replaceText(
                offset,
                1,
                quill.BlockEmbed(key, updated.encode()),
                TextSelection.collapsed(offset: offset + 1),
              );
            },
    );
  }
}

/// A real ruled table, so changing a cell never breaks column alignment.
class DocuTrackerPurchaseItemsTable extends StatelessWidget {
  const DocuTrackerPurchaseItemsTable({
    super.key,
    required this.items,
    this.onEdit,
  });
  final DocumentPurchaseItems items;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    Widget cell(String text, {bool heading = false}) => ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 32),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 7),
        child: Text(
          text,
          style: TextStyle(
            color: Colors.black,
            fontSize: 12,
            height: 1.1,
            fontWeight: heading ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
    final table = Table(
      key: const ValueKey('purchase-items-table'),
      border: TableBorder.all(color: Colors.black, width: 0.8),
      columnWidths: const {
        0: FlexColumnWidth(0.7),
        1: FlexColumnWidth(0.7),
        2: FlexColumnWidth(3),
        3: FlexColumnWidth(0.9),
        4: FlexColumnWidth(1.1),
        5: FlexColumnWidth(1.1),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        TableRow(
          decoration: const BoxDecoration(color: Color(0xFFF1F1F1)),
          children: DocumentPurchaseItems.headers
              .map((text) => cell(text, heading: true))
              .toList(),
        ),
        for (final row in items.rows)
          TableRow(children: row.map((text) => cell(text)).toList()),
        TableRow(
          children: [
            cell(''),
            cell(''),
            cell('TOTAL', heading: true),
            cell(''),
            cell(''),
            cell(items.total, heading: true),
          ],
        ),
      ],
    );
    if (onEdit == null) return table;
    return Tooltip(
      message: 'Click to edit purchase items',
      child: Semantics(
        button: true,
        label: 'Edit purchase items',
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onEdit,
            child: table,
          ),
        ),
      ),
    );
  }
}

class _PurchaseItemsDialog extends StatefulWidget {
  const _PurchaseItemsDialog({required this.items});
  final DocumentPurchaseItems items;
  @override
  State<_PurchaseItemsDialog> createState() => _PurchaseItemsDialogState();
}

class _PurchaseItemsDialogState extends State<_PurchaseItemsDialog> {
  late final List<List<TextEditingController>> _rows;
  late final TextEditingController _total;

  @override
  void initState() {
    super.initState();
    _rows = widget.items.rows
        .map(
          (row) =>
              row.map((value) => TextEditingController(text: value)).toList(),
        )
        .toList();
    _total = TextEditingController(text: widget.items.total);
  }

  @override
  void dispose() {
    for (final row in _rows) {
      for (final controller in row) {
        controller.dispose();
      }
    }
    _total.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Edit purchase items'),
    content: SizedBox(
      width: 680,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Enter the requested items and estimated costs. Amounts and total are editable; review them before saving.',
            ),
            for (var row = 0; row < _rows.length; row++) ...[
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Item ${row + 1}',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              const SizedBox(height: 8),
              LayoutBuilder(
                builder: (context, constraints) => Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  children: [
                    for (
                      var column = 0;
                      column < DocumentPurchaseItems.headers.length;
                      column++
                    )
                      SizedBox(
                        width: constraints.maxWidth >= 480 && column != 2
                            ? (constraints.maxWidth - 12) / 2
                            : constraints.maxWidth,
                        child: TextField(
                          key: ValueKey('purchase-cell-$row-$column'),
                          controller: _rows[row][column],
                          maxLines: column == 2 ? 3 : 1,
                          decoration: InputDecoration(
                            labelText: DocumentPurchaseItems.headers[column],
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
            TextField(
              controller: _total,
              key: const ValueKey('purchase-total'),
              decoration: const InputDecoration(
                labelText: 'Total estimated cost',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(
          DocumentPurchaseItems(
            rows: _rows
                .map((row) => row.map((controller) => controller.text).toList())
                .toList(),
            total: _total.text,
          ),
        ),
        child: const Text('Apply'),
      ),
    ],
  );
}
