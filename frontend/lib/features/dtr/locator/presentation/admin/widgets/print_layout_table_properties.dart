import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import '../../../models/locator_print_layout.dart';

class PrintLayoutTableProperties extends StatefulWidget {
  const PrintLayoutTableProperties({
    super.key,
    required this.element,
    required this.fields,
    required this.onChanged,
    this.enabled = true,
  });
  final LocatorPrintElement element;
  final Map<String, String> fields;
  final ValueChanged<LocatorPrintElement> onChanged;
  final bool enabled;
  @override
  State<PrintLayoutTableProperties> createState() =>
      _PrintLayoutTablePropertiesState();
}

class _PrintLayoutTablePropertiesState
    extends State<PrintLayoutTableProperties> {
  int _row = 0, _column = 0;
  final _text = TextEditingController();
  LocatorPrintTableCell get _cell => widget.element.cells[_row][_column];
  @override
  void initState() {
    super.initState();
    _text.text = _cell.text;
  }

  @override
  void didUpdateWidget(covariant PrintLayoutTableProperties oldWidget) {
    super.didUpdateWidget(oldWidget);
    _row = math.min(_row, widget.element.cells.length - 1);
    _column = math.min(_column, widget.element.cells.first.length - 1);
    if (_text.text != _cell.text) _text.text = _cell.text;
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _resize(int rows, int columns) {
    final old = widget.element;
    final cells = List.generate(
      rows,
      (r) => List.generate(
        columns,
        (c) => r < old.cells.length && c < old.cells.first.length
            ? old.cells[r][c]
            : const LocatorPrintTableCell(),
      ),
    );
    final widths = List.generate(
      columns,
      (c) => c < old.columnWidths.length ? old.columnWidths[c] : 1.0,
    );
    widget.onChanged(
      old.copyWith(
        cells: cells,
        columnWidths: widths,
        height: math.max(old.height, rows * (old.fontSize * 1.5 + 8)),
        width: math.max(old.width, columns * 40.0),
      ),
    );
  }

  void _edit(LocatorPrintTableCell cell) {
    widget.onChanged(
      widget.element.copyWith(
        cells: [
          for (var r = 0; r < widget.element.cells.length; r++)
            [
              for (var c = 0; c < widget.element.cells[r].length; c++)
                r == _row && c == _column ? cell : widget.element.cells[r][c],
            ],
        ],
      ),
    );
  }

  InputDecoration _decoration(String label) =>
      AppTheme.dashInputDecoration(context, labelText: label, radius: 8);
  @override
  Widget build(BuildContext context) {
    final table = widget.element, columns = table.cells.first.length;
    final fields = {
      ...widget.fields,
      if (_cell.kind == 'field' && !widget.fields.containsKey(_cell.source))
        _cell.source: 'Saved field (${_cell.source})',
    };
    final total = table.columnWidths.fold(0.0, (a, b) => a + b);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 24),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<int>(
                key: ValueKey('table-rows-${table.cells.length}'),
                initialValue: table.cells.length,
                decoration: _decoration('Table rows'),
                items: [
                  for (var n = 1; n <= 12; n++)
                    DropdownMenuItem(value: n, child: Text('$n')),
                ],
                onChanged: widget.enabled
                    ? (n) {
                        if (n != null) _resize(n, columns);
                      }
                    : null,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonFormField<int>(
                key: ValueKey('table-cols-$columns'),
                initialValue: columns,
                decoration: _decoration('Table columns'),
                items: [
                  for (var n = 1; n <= 6; n++)
                    DropdownMenuItem(value: n, child: Text('$n')),
                ],
                onChanged: widget.enabled
                    ? (n) {
                        if (n != null) _resize(table.cells.length, n);
                      }
                    : null,
              ),
            ),
          ],
        ),
        Row(
          children: [
            Checkbox(
              key: const ValueKey('table-header-row'),
              value: table.headerRow,
              onChanged: widget.enabled
                  ? (v) => widget.onChanged(table.copyWith(headerRow: v))
                  : null,
            ),
            const Expanded(child: Text('Header row')),
          ],
        ),
        Row(
          children: [
            Checkbox(
              key: const ValueKey('table-borders'),
              value: table.borders,
              onChanged: widget.enabled
                  ? (v) => widget.onChanged(table.copyWith(borders: v))
                  : null,
            ),
            const Expanded(child: Text('Table borders')),
          ],
        ),
        const Text(
          'Column widths',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        for (var c = 0; c < columns; c++)
          Row(
            children: [
              SizedBox(
                width: 58,
                child: Text(
                  '${c + 1}: ${(table.columnWidths[c] / total * 100).round()}%',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              Expanded(
                child: Slider(
                  key: ValueKey('table-column-width-$c'),
                  min: .1,
                  max: 10,
                  value: table.columnWidths[c].clamp(.1, 10),
                  onChanged: widget.enabled
                      ? (v) => widget.onChanged(
                          table.copyWith(
                            columnWidths: [
                              for (var i = 0; i < columns; i++)
                                i == c ? v : table.columnWidths[i],
                            ],
                          ),
                        )
                      : null,
                ),
              ),
            ],
          ),
        const SizedBox(height: 8),
        const Text('Edit cell', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<int>(
                key: ValueKey('table-cell-row-$_row-${table.cells.length}'),
                initialValue: _row,
                decoration: _decoration('Cell row'),
                items: [
                  for (var r = 0; r < table.cells.length; r++)
                    DropdownMenuItem(value: r, child: Text('${r + 1}')),
                ],
                onChanged: widget.enabled
                    ? (r) {
                        if (r != null) {
                          setState(() {
                            _row = r;
                            _text.text = _cell.text;
                          });
                        }
                      }
                    : null,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonFormField<int>(
                key: ValueKey('table-cell-col-$_column-$columns'),
                initialValue: _column,
                decoration: _decoration('Cell column'),
                items: [
                  for (var c = 0; c < columns; c++)
                    DropdownMenuItem(value: c, child: Text('${c + 1}')),
                ],
                onChanged: widget.enabled
                    ? (c) {
                        if (c != null) {
                          setState(() {
                            _column = c;
                            _text.text = _cell.text;
                          });
                        }
                      }
                    : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          key: ValueKey('table-content-$_row-$_column-${_cell.kind}'),
          initialValue: _cell.kind,
          decoration: _decoration('Cell content'),
          items: const [
            DropdownMenuItem(value: 'text', child: Text('Fixed text')),
            DropdownMenuItem(value: 'field', child: Text('Request field')),
          ],
          onChanged: widget.enabled
              ? (v) {
                  if (v != null) {
                    _edit(
                      v == 'field'
                          ? LocatorPrintTableCell(
                              kind: 'field',
                              source: widget.fields.keys.first,
                            )
                          : const LocatorPrintTableCell(),
                    );
                  }
                }
              : null,
        ),
        const SizedBox(height: 12),
        if (_cell.kind == 'text')
          TextField(
            key: const ValueKey('table-cell-text'),
            controller: _text,
            enabled: widget.enabled,
            maxLength: 500,
            maxLines: 3,
            decoration: _decoration('Cell text'),
            onChanged: (v) => _edit(LocatorPrintTableCell(text: v)),
          ),
        if (_cell.kind == 'field')
          DropdownButtonFormField<String>(
            key: ValueKey('table-source-$_row-$_column-${_cell.source}'),
            initialValue: _cell.source,
            isExpanded: true,
            decoration: _decoration('Request field'),
            items: [
              for (final e in fields.entries)
                DropdownMenuItem(
                  value: e.key,
                  child: Text(e.value, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: widget.enabled
                ? (v) {
                    if (v != null) {
                      _edit(LocatorPrintTableCell(kind: 'field', source: v));
                    }
                  }
                : null,
          ),
        const SizedBox(height: 8),
        const Text(
          'Rows share the table height. Long answers continue on another page.',
          style: TextStyle(fontSize: 12),
        ),
      ],
    );
  }
}
