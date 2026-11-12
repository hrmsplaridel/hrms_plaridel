import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;

import 'package:hrms_plaridel/features/docutracker/models/document_table.dart';
import 'package:hrms_plaridel/features/docutracker/theme/docutracker_tokens.dart';

class DocuTrackerDocumentTableEmbedBuilder extends quill.EmbedBuilder {
  const DocuTrackerDocumentTableEmbedBuilder({required this.editable});

  final bool editable;

  @override
  String get key => DocumentTable.embedType;

  @override
  Widget build(BuildContext context, quill.EmbedContext embedContext) {
    DocumentTable table;
    try {
      table = DocumentTable.decode(embedContext.node.value.data);
    } on FormatException {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text(
          'This table could not be read. Reload the document before editing.',
        ),
      );
    }

    final canEdit = editable && !embedContext.readOnly;
    return DocuTrackerDocumentTableView(
      key: ValueKey('docutracker-table-${embedContext.node.documentOffset}'),
      table: table,
      editable: canEdit,
      onChanged: !canEdit
          ? null
          : (updated) {
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

/// Ruled table with optional inline cell editors and Tab navigation.
class DocuTrackerDocumentTableView extends StatefulWidget {
  const DocuTrackerDocumentTableView({
    super.key,
    required this.table,
    required this.editable,
    this.onChanged,
  });

  final DocumentTable table;
  final bool editable;
  final ValueChanged<DocumentTable>? onChanged;

  @override
  State<DocuTrackerDocumentTableView> createState() =>
      _DocuTrackerDocumentTableViewState();
}

class _DocuTrackerDocumentTableViewState
    extends State<DocuTrackerDocumentTableView> {
  late List<List<TextEditingController>> _controllers;
  late List<List<FocusNode>> _focusNodes;

  @override
  void initState() {
    super.initState();
    _buildEditors(widget.table);
  }

  @override
  void didUpdateWidget(covariant DocuTrackerDocumentTableView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameShape(oldWidget.table, widget.table) ||
        !_sameValues(oldWidget.table, widget.table)) {
      _disposeEditors();
      _buildEditors(widget.table);
    }
  }

  @override
  void dispose() {
    _disposeEditors();
    super.dispose();
  }

  bool _sameShape(DocumentTable a, DocumentTable b) =>
      a.rowCount == b.rowCount && a.columnCount == b.columnCount;

  bool _sameValues(DocumentTable a, DocumentTable b) {
    if (!_sameShape(a, b)) return false;
    for (var r = 0; r < a.rowCount; r++) {
      for (var c = 0; c < a.columnCount; c++) {
        if (a.cells[r][c] != b.cells[r][c]) return false;
      }
    }
    return true;
  }

  void _buildEditors(DocumentTable table) {
    _controllers = [
      for (final row in table.cells)
        [for (final cell in row) TextEditingController(text: cell)],
    ];
    _focusNodes = [
      for (var r = 0; r < table.rowCount; r++)
        [for (var c = 0; c < table.columnCount; c++) FocusNode()],
    ];
  }

  void _disposeEditors() {
    for (final row in _controllers) {
      for (final controller in row) {
        controller.dispose();
      }
    }
    for (final row in _focusNodes) {
      for (final node in row) {
        node.dispose();
      }
    }
  }

  void _commit() {
    final onChanged = widget.onChanged;
    if (onChanged == null) return;
    final next = DocumentTable(
      cells: [
        for (final row in _controllers)
          [for (final controller in row) controller.text],
      ],
    );
    if (_sameValues(widget.table, next)) return;
    onChanged(next);
  }

  void _moveFocus(int row, int col, {required bool reverse}) {
    final total = widget.table.rowCount * widget.table.columnCount;
    final index = row * widget.table.columnCount + col;
    final nextIndex = reverse
        ? (index - 1 + total) % total
        : (index + 1) % total;
    final nextRow = nextIndex ~/ widget.table.columnCount;
    final nextCol = nextIndex % widget.table.columnCount;
    _focusNodes[nextRow][nextCol].requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final borderColor = DocuTrackerTokens.borderSubtleOf(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Table(
        key: const ValueKey('docutracker-document-table'),
        border: TableBorder.all(color: borderColor, width: 0.9),
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: [
          for (var row = 0; row < widget.table.rowCount; row++)
            TableRow(
              children: [
                for (var col = 0; col < widget.table.columnCount; col++)
                  _cell(row, col),
              ],
            ),
        ],
      ),
    );
  }

  Widget _cell(int row, int col) {
    if (!widget.editable || widget.onChanged == null) {
      return ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 28),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: Text(
            widget.table.cells[row][col],
            style: const TextStyle(
              color: Colors.black,
              fontSize: 13,
              height: 1.25,
            ),
          ),
        ),
      );
    }

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.tab): () {
          _commit();
          _moveFocus(row, col, reverse: false);
        },
        const SingleActivator(LogicalKeyboardKey.tab, shift: true): () {
          _commit();
          _moveFocus(row, col, reverse: true);
        },
      },
      child: Focus(
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          if (event.logicalKey != LogicalKeyboardKey.tab) {
            return KeyEventResult.ignored;
          }
          _commit();
          _moveFocus(
            row,
            col,
            reverse: HardwareKeyboard.instance.isShiftPressed,
          );
          return KeyEventResult.handled;
        },
        child: TextField(
          key: ValueKey('docutracker-table-cell-$row-$col'),
          controller: _controllers[row][col],
          focusNode: _focusNodes[row][col],
          maxLines: null,
          style: const TextStyle(
            color: Colors.black,
            fontSize: 13,
            height: 1.25,
          ),
          decoration: const InputDecoration(
            isDense: true,
            border: InputBorder.none,
            contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          ),
          onChanged: (_) => _commit(),
          onEditingComplete: _commit,
        ),
      ),
    );
  }
}

/// Asks for a compact row × column size, then returns a blank table.
Future<DocumentTable?> showDocuTrackerInsertTableDialog(BuildContext context) {
  return showDialog<DocumentTable>(
    context: context,
    builder: (dialogContext) => const _InsertTableDialog(),
  );
}

class _InsertTableDialog extends StatefulWidget {
  const _InsertTableDialog();

  @override
  State<_InsertTableDialog> createState() => _InsertTableDialogState();
}

class _InsertTableDialogState extends State<_InsertTableDialog> {
  int _rows = 3;
  int _cols = 3;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Insert table'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Choose how many rows and columns to insert at the cursor.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            _stepper(
              label: 'Rows',
              value: _rows,
              min: DocumentTable.minRows,
              max: DocumentTable.maxRows,
              onChanged: (value) => setState(() => _rows = value),
            ),
            const SizedBox(height: 12),
            _stepper(
              label: 'Columns',
              value: _cols,
              min: DocumentTable.minCols,
              max: DocumentTable.maxCols,
              onChanged: (value) => setState(() => _cols = value),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('docutracker-insert-table-confirm'),
          onPressed: () => Navigator.of(
            context,
          ).pop(DocumentTable.blank(rows: _rows, cols: _cols)),
          child: const Text('Insert'),
        ),
      ],
    );
  }

  Widget _stepper({
    required String label,
    required int value,
    required int min,
    required int max,
    required ValueChanged<int> onChanged,
  }) {
    return Row(
      children: [
        Expanded(child: Text(label)),
        IconButton(
          tooltip: 'Fewer $label',
          onPressed: value <= min ? null : () => onChanged(value - 1),
          icon: const Icon(Icons.remove_circle_outline),
        ),
        SizedBox(
          width: 36,
          child: Text(
            '$value',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        IconButton(
          tooltip: 'More $label',
          onPressed: value >= max ? null : () => onChanged(value + 1),
          icon: const Icon(Icons.add_circle_outline),
        ),
      ],
    );
  }
}
