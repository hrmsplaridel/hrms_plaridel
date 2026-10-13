import 'dart:typed_data';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:printing/printing.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/core/api/user_facing_api_error.dart';
import '../../../models/locator_print_layout.dart';
import '../../../models/locator_request_type.dart';
import '../../../utils/locator_layout_pdf.dart';
import '../../../utils/locator_form_signatories.dart';
import 'print_layout_table_properties.dart';

/// Domain-specific fields and sample values for the shared printed page editor.
class PrintLayoutEditorBindings {
  const PrintLayoutEditorBindings({
    required this.fields,
    required this.signatures,
    required this.sample,
    required this.defaultLayout,
    required this.sampleSignatory,
  });
  final Map<String, String> fields, signatures;
  final Map<String, dynamic> sample;
  final LocatorPrintLayout Function(String orientation) defaultLayout;
  final LocatorPrintedSignatory Function(String source) sampleSignatory;
}

class LocatorPrintLayoutEditor extends StatefulWidget {
  const LocatorPrintLayoutEditor({
    super.key,
    required this.requestType,
    this.initialLayout,
    this.bindings,
    this.backgroundPdf,
    this.backgroundImage,
    required this.onPreview,
  });
  final LocatorRequestType requestType;
  final PrintLayoutEditorBindings? bindings;
  final LocatorPrintLayout? initialLayout;
  final Uint8List? backgroundPdf, backgroundImage;
  final Future<void> Function(LocatorPrintLayout) onPreview;
  @override
  State<LocatorPrintLayoutEditor> createState() =>
      _LocatorPrintLayoutEditorState();
}

class _LocatorPrintLayoutEditorState extends State<LocatorPrintLayoutEditor> {
  late LocatorPrintLayout _layout;
  String? _selectedId, _error;
  Uint8List? _background;
  bool _busy = false, _loadingBackground = false;
  String? _backgroundOrientation;
  double? _zoom;
  bool _showGrid = false, _showSettings = false;
  final _workspaceVertical = ScrollController();
  final _workspaceHorizontal = ScrollController();
  final _canvasKey = GlobalKey();
  final _numbers = {
    for (final name in ['x', 'y', 'width', 'height', 'font_size'])
      name: TextEditingController(),
  };
  final _label = TextEditingController();
  final _customSignatureCaptions = <String>{};
  @override
  void initState() {
    super.initState();
    _layout = widget.initialLayout ?? _defaults('portrait');
    _select(_layout.elements.firstOrNull?.id);
    _loadBackground();
  }

  @override
  void dispose() {
    for (final c in _numbers.values) {
      c.dispose();
    }
    _label.dispose();
    _workspaceVertical.dispose();
    _workspaceHorizontal.dispose();
    super.dispose();
  }

  LocatorPrintElement? get _selected =>
      _layout.elements.where((e) => e.id == _selectedId).firstOrNull;
  Future<void> _loadBackground() async {
    if (widget.backgroundPdf == null && widget.backgroundImage == null) return;
    setState(() => _loadingBackground = true);
    try {
      var image = widget.backgroundImage;
      if (image == null) {
        final raster = await Printing.raster(
          widget.backgroundPdf!,
          pages: const [0],
          dpi: 72,
        ).first;
        image = await raster.toPng();
      }
      final codec = await ui.instantiateImageCodec(image);
      final frame = await codec.getNextFrame();
      final orientation = frame.image.width > frame.image.height
          ? 'landscape'
          : 'portrait';
      frame.image.dispose();
      codec.dispose();
      if (!mounted) return;
      setState(() {
        _background = image;
        _backgroundOrientation = orientation;
        if (widget.initialLayout == null) {
          _layout = _defaults(orientation);
          _select(_layout.elements.firstOrNull?.id);
        }
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not display the background. Retry or use PDF preview to check placement.',
        );
      }
    } finally {
      if (mounted) setState(() => _loadingBackground = false);
    }
  }

  void _select(String? id) {
    _selectedId = id;
    final item = _selected;
    if (item == null) return;
    for (final entry in {
      'x': item.x,
      'y': item.y,
      'width': item.width,
      'height': item.height,
      'font_size': item.fontSize,
    }.entries) {
      _numbers[entry.key]!.text = entry.value.toStringAsFixed(1);
    }
    _label.text = item.kind == 'text' ? item.text : item.label;
  }

  void _replace(LocatorPrintElement next, {bool sync = false}) {
    setState(() {
      _layout = _layout.copyWith(
        elements: [
          for (final item in _layout.elements) item.id == next.id ? next : item,
        ],
      );
      _error = null;
      if (sync) _select(next.id);
    });
  }

  bool _commitProperties() {
    final item = _selected;
    if (item == null) return true;
    if (item.kind == 'signature' &&
        _customSignatureCaptions.contains(item.id) &&
        item.label.trim().isEmpty) {
      setState(
        () => _error = "Enter a custom label or choose Signer's position.",
      );
      return false;
    }
    final values = {
      for (final entry in _numbers.entries)
        entry.key: double.tryParse(entry.value.text),
    };
    if (values.values.any((v) => v == null || !v.isFinite)) {
      setState(() => _error = 'Enter valid dimensions.');
      return false;
    }
    final next = item.copyWith(
      x: values['x'],
      y: values['y'],
      width: values['width'],
      height: values['height'],
      fontSize: values['font_size'],
    );
    final trial = _layout.copyWith(
      elements: [
        for (final old in _layout.elements) old.id == next.id ? next : old,
      ],
    );
    final error = trial.validate();
    if (error != null) {
      setState(() => _error = error);
      return false;
    }
    _replace(next);
    return true;
  }

  Future<void> _preview() async {
    if (!_commitProperties()) return;
    final error = _layout.validate();
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    if (_backgroundOrientation != null &&
        _layout.orientation != _backgroundOrientation) {
      setState(
        () => _error = 'Choose the same page orientation as the background.',
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.onPreview(_layout);
    } catch (e) {
      if (mounted) setState(() => _error = userFacingApiError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _useLayout() {
    if (!_commitProperties()) return;
    final error = _layout.validate();
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    if (_backgroundOrientation != null &&
        _layout.orientation != _backgroundOrientation) {
      setState(
        () => _error = 'Choose the same page orientation as the background.',
      );
      return;
    }
    Navigator.of(context).pop(_layout);
  }

  LocatorPrintLayout _defaults(String orientation) =>
      widget.bindings?.defaultLayout(orientation) ??
      LocatorPrintLayout.defaults(widget.requestType, orientation: orientation);
  Map<String, String> get _signatures =>
      widget.bindings?.signatures ??
      const {
        'applicant': 'Employee signature',
        'department_head': 'Department signature',
        'hr_approver': 'Final signature',
      };
  Map<String, String> get _fields =>
      widget.bindings?.fields ??
      {
        'employee_name': 'Employee name',
        'date': 'Date',
        'request_type': 'Request type',
        'office': widget.requestType.locationLabel,
        'reason': 'Remarks / Reasons',
        'time_segments': 'DTR slots',
        for (final field in widget.requestType.employeeDetailSchema)
          'custom:${field.key}': field.label,
      };
  void _add(String data, {Offset? point}) {
    if (_layout.elements.length >= 60) {
      setState(() => _error = 'Use at most 60 elements.');
      return;
    }
    final parts = data.split('|'),
        kind = parts.first,
        source = parts.length > 1 ? parts[1] : '';
    final label = kind == 'signature'
        ? switch (source) {
            'applicant' => 'Employee',
            'department_head' => 'Head of Office',
            _ => 'Final approver',
          }
        : _fields[source] ?? '';
    final width = kind == 'table'
            ? 400.0
            : kind == 'text'
            ? 300.0
            : 240.0,
        height = kind == 'table'
            ? 120.0
            : kind == 'signature'
            ? 80.0
            : kind == 'line'
            ? 2.0
            : 40.0;
    final item = LocatorPrintElement(
      id: 'item_${DateTime.now().microsecondsSinceEpoch}',
      kind: kind,
      source: source,
      text: kind == 'text' ? 'New text' : '',
      label: kind == 'signature' ? '' : label,
      x: (point?.dx ?? 40).clamp(0, _layout.pageWidth - width),
      y: (point?.dy ?? 180).clamp(0, _layout.pageHeight - height),
      width: width,
      height: height,
      bold: kind == 'text',
      columnWidths: kind == 'table' ? const [1, 1] : const [],
      cells: kind == 'table'
          ? const [
              [
                LocatorPrintTableCell(text: 'Column 1'),
                LocatorPrintTableCell(text: 'Column 2'),
              ],
              [LocatorPrintTableCell(), LocatorPrintTableCell()],
              [LocatorPrintTableCell(), LocatorPrintTableCell()],
            ]
          : const [],
    );
    setState(() {
      _layout = _layout.copyWith(elements: [..._layout.elements, item]);
      _select(item.id);
      _error = null;
    });
  }

  Widget _paletteButton(String label, String data) => Draggable<String>(
    data: data,
    feedback: Material(
      elevation: 3,
      borderRadius: BorderRadius.circular(8),
      child: Padding(padding: const EdgeInsets.all(10), child: Text(label)),
    ),
    child: OutlinedButton.icon(
      onPressed: _busy ? null : () => _add(data),
      icon: const Icon(Icons.add, size: 16),
      label: Text(label, overflow: TextOverflow.ellipsis),
    ),
  );
  Widget _section(String title, IconData icon, Widget child) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppTheme.dashPanelOf(context),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppTheme.dashHairlineOf(context)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: AppTheme.primaryNavy),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        child,
      ],
    ),
  );

  Widget _controls() => Container(
    key: const ValueKey('layout-inspector'),
    color: AppTheme.dashMutedSurfaceOf(context),
    child: SingleChildScrollView(
      primary: false,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _section(
            'Page settings',
            Icons.description_outlined,
            _pageSettings(),
          ),
          const SizedBox(height: 12),
          _section('Element properties', Icons.tune, _elementProperties()),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: AppTheme.dashPanelOf(context),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.dashHairlineOf(context)),
            ),
            child: ExpansionTile(
              leading: const Icon(
                Icons.add_box_outlined,
                size: 18,
                color: AppTheme.primaryNavy,
              ),
              title: const Text(
                'Add to page',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
              subtitle: const Text(
                'Click or drag a field',
                style: TextStyle(fontSize: 12),
              ),
              shape: const Border(),
              collapsedShape: const Border(),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [_palette()],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _pageSettings() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        _layout.orientation == 'portrait'
            ? 'A4 · 210 × 297 mm'
            : 'A4 · 297 × 210 mm',
        style: TextStyle(
          fontSize: 12,
          color: AppTheme.dashTextSecondaryOf(context),
        ),
      ),
      const SizedBox(height: 16),
      DropdownButtonFormField<String>(
        initialValue: _layout.orientation,
        key: ValueKey(_layout.orientation),
        style: TextStyle(
          fontSize: 14,
          fontFamily: AppTheme.fontFamily,
          color: AppTheme.dashTextPrimaryOf(context),
        ),
        decoration: AppTheme.dashInputDecoration(
          context,
          labelText: 'A4 orientation',
          radius: 8,
        ),
        items: const [
          DropdownMenuItem(value: 'portrait', child: Text('Portrait')),
          DropdownMenuItem(value: 'landscape', child: Text('Landscape')),
        ],
        onChanged: _busy
            ? null
            : (value) {
                if (value == null) return;
                final old = _layout,
                    next = _layout.copyWith(orientation: value);
                setState(() {
                  _layout = next.copyWith(
                    elements: [
                      for (final e in old.elements)
                        e.copyWith(
                          x: (e.x / old.pageWidth * next.pageWidth).clamp(
                            0,
                            next.pageWidth - e.width.clamp(20, next.pageWidth),
                          ),
                          y: (e.y / old.pageHeight * next.pageHeight).clamp(
                            0,
                            next.pageHeight -
                                e.height.clamp(2, next.pageHeight),
                          ),
                          width: e.width.clamp(20, next.pageWidth),
                          height: e.height.clamp(2, next.pageHeight),
                        ),
                    ],
                  );
                  _select(_selectedId);
                });
              },
      ),
    ],
  );

  Widget _palette() => Wrap(
    spacing: 6,
    runSpacing: 6,
    children: [
      _paletteButton('Text / title', 'text'),
      _paletteButton('Line', 'line'),
      _paletteButton('Table', 'table'),
      for (final entry in _fields.entries)
        _paletteButton(entry.value, 'field|${entry.key}'),
      for (final entry in _signatures.entries)
        _paletteButton(entry.value, 'signature|${entry.key}'),
    ],
  );

  Widget _elementProperties() {
    final selected = _selected;
    if (selected == null) {
      return Text(
        'Select an element on the page to edit it.',
        style: TextStyle(
          fontSize: 13,
          color: AppTheme.dashTextSecondaryOf(context),
        ),
      );
    }
    final automaticCaption =
        selected.kind == 'signature' &&
        selected.label.isEmpty &&
        !_customSignatureCaptions.contains(selected.id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                switch (selected.kind) {
                  'text' => 'Text / title',
                  'line' => 'Line',
                  'table' => 'Table',
                  'signature' => 'Signature',
                  _ => selected.label.isEmpty ? 'Field' : selected.label,
                },
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.dashTextSecondaryOf(context),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Remove element',
              onPressed: _busy
                  ? null
                  : () => setState(() {
                      _layout = _layout.copyWith(
                        elements: _layout.elements
                            .where((e) => e.id != selected.id)
                            .toList(),
                      );
                      _select(_layout.elements.firstOrNull?.id);
                    }),
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
        if (selected.kind == 'signature') ...[
          DropdownButtonFormField<String>(
            key: ValueKey('caption-${selected.id}-$automaticCaption'),
            initialValue: automaticCaption ? 'position' : 'custom',
            isExpanded: true,
            style: TextStyle(
              fontSize: 14,
              fontFamily: AppTheme.fontFamily,
              color: AppTheme.dashTextPrimaryOf(context),
            ),
            decoration: AppTheme.dashInputDecoration(
              context,
              labelText: 'Signature caption',
              radius: 8,
            ),
            items: const [
              DropdownMenuItem(
                value: 'position',
                child: Text(
                  "Signer's position",
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              DropdownMenuItem(value: 'custom', child: Text('Custom label')),
            ],
            onChanged: _busy
                ? null
                : (value) {
                    if (value == 'position') {
                      _customSignatureCaptions.remove(selected.id);
                      _replace(selected.copyWith(label: ''), sync: true);
                    } else if (value == 'custom') {
                      _customSignatureCaptions.add(selected.id);
                      _replace(
                        selected.copyWith(
                          label: selected.label.isEmpty
                              ? locatorSignatureCaption(
                                  selected,
                                  const LocatorPrintedSignatory(),
                                )
                              : selected.label,
                        ),
                        sync: true,
                      );
                    }
                  },
          ),
          const SizedBox(height: 8),
          if (automaticCaption)
            Text(
              'Uses the position recorded for this signer on the request.',
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.dashTextSecondaryOf(context),
              ),
            ),
          const SizedBox(height: 8),
        ],
        if (selected.kind != 'line' &&
            selected.kind != 'table' &&
            !automaticCaption)
          TextField(
            controller: _label,
            maxLength: selected.kind == 'text' ? 500 : 100,
            maxLines: selected.kind == 'text' ? 2 : 1,
            style: TextStyle(
              fontSize: 14,
              color: AppTheme.dashTextPrimaryOf(context),
            ),
            decoration: AppTheme.dashInputDecoration(
              context,
              labelText: selected.kind == 'text' ? 'Text' : 'Label',
              radius: 8,
            ).copyWith(counterText: ''),
            onChanged: (value) {
              if (selected.kind == 'signature') {
                _customSignatureCaptions.add(selected.id);
              }
              _replace(
                selected.kind == 'text'
                    ? selected.copyWith(text: value)
                    : selected.copyWith(label: value),
              );
            },
          ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final entry in const {
              'x': 'Left',
              'y': 'Top',
              'width': 'Width',
              'height': 'Height',
              'font_size': 'Font size',
            }.entries)
              SizedBox(
                width: 124,
                child: TextField(
                  controller: _numbers[entry.key],
                  style: TextStyle(
                    fontSize: 14,
                    color: AppTheme.dashTextPrimaryOf(context),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: AppTheme.dashInputDecoration(
                    context,
                    labelText: '${entry.value} (pt)',
                    radius: 8,
                  ),
                  onSubmitted: (_) => _commitProperties(),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          key: ValueKey('${selected.id}-${selected.align}'),
          initialValue: selected.align,
          style: TextStyle(
            fontSize: 14,
            fontFamily: AppTheme.fontFamily,
            color: AppTheme.dashTextPrimaryOf(context),
          ),
          decoration: AppTheme.dashInputDecoration(
            context,
            labelText: 'Alignment',
            radius: 8,
          ),
          items: const [
            DropdownMenuItem(value: 'left', child: Text('Left')),
            DropdownMenuItem(value: 'center', child: Text('Center')),
            DropdownMenuItem(value: 'right', child: Text('Right')),
          ],
          onChanged: (value) {
            if (value != null) _replace(selected.copyWith(align: value));
          },
        ),
        Row(
          children: [
            Checkbox(
              value: selected.bold,
              onChanged: (value) => _replace(selected.copyWith(bold: value)),
            ),
            const Text('Bold'),
          ],
        ),
        if (selected.kind == 'table')
          PrintLayoutTableProperties(
            key: ValueKey('table-properties-${selected.id}'),
            element: selected,
            fields: _fields,
            enabled: !_busy,
            onChanged: (next) => _replace(next, sync: true),
          ),
        if (selected.kind == 'field')
          Row(
            children: [
              Checkbox(
                value: selected.showLabel,
                onChanged: (value) =>
                    _replace(selected.copyWith(showLabel: value)),
              ),
              const Text('Show label'),
            ],
          ),
      ],
    );
  }

  Widget _tablePreview(
    LocatorPrintElement item,
    double scale,
    Map<String, dynamic> form,
  ) {
    if (item.cells.isEmpty || item.columnWidths.isEmpty) {
      return const SizedBox();
    }
    final count =
        ((item.height / item.cells.length - 8) / (item.fontSize * 1.5))
            .floor()
            .clamp(1, 100);
    return Column(
      children: [
        for (var r = 0; r < item.cells.length; r++)
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var c = 0; c < item.cells[r].length; c++)
                  Expanded(
                    flex: (item.columnWidths[c] * 1000).round().clamp(1, 10000),
                    child: Container(
                      padding: EdgeInsets.all(4 * scale),
                      decoration: BoxDecoration(
                        color: item.headerRow && r == 0
                            ? Colors.grey.shade100
                            : null,
                        border: item.borders
                            ? Border.all(color: Colors.black, width: .5 * scale)
                            : null,
                      ),
                      child: Text(
                        item.cells[r][c].kind == 'field'
                            ? locatorLayoutValue(item.cells[r][c].source, form)
                            : item.cells[r][c].text,
                        textAlign: switch (item.align) {
                          'center' => TextAlign.center,
                          'right' => TextAlign.right,
                          _ => TextAlign.left,
                        },
                        maxLines: count,
                        overflow: TextOverflow.clip,
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: item.fontSize * scale,
                          height: 1.5,
                          fontWeight: item.bold || (item.headerRow && r == 0)
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _page(double scale) {
    final sample =
        widget.bindings?.sample ?? locatorLayoutSample(widget.requestType);
    return Align(
      alignment: Alignment.topCenter,
      child: SizedBox(
        width: _layout.pageWidth * scale,
        height: _layout.pageHeight * scale,
        child: DragTarget<String>(
          onAcceptWithDetails: (details) {
            final box =
                _canvasKey.currentContext!.findRenderObject() as RenderBox;
            final point = box.globalToLocal(details.offset);
            _add(details.data, point: point / scale);
          },
          builder: (context, candidates, rejected) => Material(
            key: _canvasKey,
            color: Colors.white,
            elevation: 2,
            child: Stack(
              children: [
                if (_background != null)
                  Positioned.fill(
                    child: RepaintBoundary(
                      child: Image.memory(_background!, fit: BoxFit.fill),
                    ),
                  ),
                if (_showGrid)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: RepaintBoundary(
                        child: CustomPaint(
                          key: const ValueKey('layout-grid'),
                          painter: _LayoutGridPainter(scale),
                        ),
                      ),
                    ),
                  ),
                for (final item in _layout.elements)
                  _DraggableLayoutElement(
                    key: ValueKey('layout-node-${item.id}'),
                    item: item,
                    scale: scale,
                    pageSize: Size(_layout.pageWidth, _layout.pageHeight),
                    enabled: !_busy,
                    onSelect: () => setState(() => _select(item.id)),
                    onMoved: (next) => _replace(next, sync: true),
                    child: Container(
                      padding: EdgeInsets.all(item.kind == 'line' ? 0 : scale),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: item.id == _selectedId
                              ? const Color(0xFFF56600)
                              : Colors.transparent,
                        ),
                      ),
                      child: item.kind == 'table'
                          ? _tablePreview(item, scale, sample)
                          : item.kind == 'line'
                          ? const Divider(color: Colors.black, height: 1)
                          : item.kind == 'signature'
                          ? Column(
                              children: [
                                const Expanded(
                                  child: Icon(
                                    Icons.draw_outlined,
                                    color: Colors.black26,
                                  ),
                                ),
                                Text(
                                  'Sample signer',
                                  style: TextStyle(
                                    color: Colors.black,
                                    fontSize: 10 * scale,
                                  ),
                                ),
                                const Divider(height: 2),
                                Text(
                                  locatorSignatureCaption(
                                    item,
                                    widget.bindings?.sampleSignatory(
                                          item.source,
                                        ) ??
                                        locatorLayoutSampleSignatory(
                                          widget.requestType,
                                          item.source,
                                        ),
                                  ),
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  style: TextStyle(
                                    color: Colors.black,
                                    fontSize: 8 * scale,
                                  ),
                                ),
                              ],
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (item.kind == 'field' && item.showLabel)
                                  Text(
                                    item.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.clip,
                                    style: TextStyle(
                                      color: Colors.black,
                                      fontSize: 8 * scale,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                Expanded(
                                  child: Text(
                                    item.kind == 'text'
                                        ? item.text
                                        : locatorLayoutValue(
                                            item.source,
                                            sample,
                                          ),
                                    textAlign: switch (item.align) {
                                      'center' => TextAlign.center,
                                      'right' => TextAlign.right,
                                      _ => TextAlign.left,
                                    },
                                    overflow: TextOverflow.clip,
                                    style: TextStyle(
                                      color: Colors.black,
                                      fontSize: item.fontSize * scale,
                                      fontWeight: item.bold
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _setZoom(double? zoom) {
    setState(() => _zoom = zoom);
    if (_workspaceVertical.hasClients) _workspaceVertical.jumpTo(0);
    if (_workspaceHorizontal.hasClients) _workspaceHorizontal.jumpTo(0);
  }

  Widget _toolbar() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: LayoutBuilder(
      builder: (context, constraints) => Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _add('text'),
            icon: const Icon(Icons.title, size: 18),
            label: const Text('Text'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 36),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: const TextStyle(
                fontSize: 13,
                fontFamily: AppTheme.fontFamily,
                fontWeight: FontWeight.w500,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _add('line'),
            icon: const Icon(Icons.horizontal_rule, size: 18),
            label: const Text('Line'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 36),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: const TextStyle(
                fontSize: 13,
                fontFamily: AppTheme.fontFamily,
                fontWeight: FontWeight.w500,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _add('table'),
            icon: const Icon(Icons.table_chart_outlined, size: 18),
            label: const Text('Insert table'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 36),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: const TextStyle(
                fontSize: 13,
                fontFamily: AppTheme.fontFamily,
                fontWeight: FontWeight.w500,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Insert field',
            enabled: !_busy,
            onSelected: _add,
            itemBuilder: (_) => [
              for (final entry in _fields.entries)
                PopupMenuItem(
                  value: 'field|${entry.key}',
                  child: Text(entry.value),
                ),
              const PopupMenuDivider(),
              for (final entry in _signatures.entries)
                PopupMenuItem(
                  value: 'signature|${entry.key}',
                  child: Text(entry.value),
                ),
            ],
            child: Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                border: Border.all(color: AppTheme.dashHairlineOf(context)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add, size: 18, color: AppTheme.primaryNavy),
                  SizedBox(width: 6),
                  Text('Insert field', style: TextStyle(fontSize: 13)),
                  SizedBox(width: 4),
                  Icon(Icons.expand_more, size: 16),
                ],
              ),
            ),
          ),
          Container(
            height: 36,
            width: 126,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              border: Border.all(color: AppTheme.dashHairlineOf(context)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<double>(
                key: const ValueKey('layout-zoom'),
                value: _zoom ?? 0,
                isExpanded: true,
                isDense: true,
                style: TextStyle(
                  fontSize: 13,
                  fontFamily: AppTheme.fontFamily,
                  color: AppTheme.dashTextPrimaryOf(context),
                ),
                items: const [
                  DropdownMenuItem(value: 0, child: Text('Fit page')),
                  DropdownMenuItem(value: .5, child: Text('50%')),
                  DropdownMenuItem(value: .75, child: Text('75%')),
                  DropdownMenuItem(value: 1, child: Text('100%')),
                  DropdownMenuItem(value: 1.25, child: Text('125%')),
                  DropdownMenuItem(value: 1.5, child: Text('150%')),
                ],
                onChanged: _busy
                    ? null
                    : (value) => _setZoom(value == 0 ? null : value),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Fit page',
            constraints: const BoxConstraints.tightFor(width: 36, height: 36),
            onPressed: _busy ? null : () => _setZoom(null),
            icon: const Icon(Icons.fit_screen_outlined, size: 20),
          ),
          IconButton(
            tooltip: _showGrid ? 'Hide grid' : 'Show grid',
            constraints: const BoxConstraints.tightFor(width: 36, height: 36),
            isSelected: _showGrid,
            onPressed: _busy
                ? null
                : () => setState(() => _showGrid = !_showGrid),
            icon: const Icon(Icons.grid_4x4_outlined, size: 20),
            selectedIcon: const Icon(
              Icons.grid_4x4,
              size: 20,
              color: AppTheme.primaryNavy,
            ),
          ),
          if (constraints.maxWidth < 818)
            IconButton(
              tooltip: 'Page and element settings',
              constraints: const BoxConstraints.tightFor(width: 36, height: 36),
              isSelected: _showSettings,
              onPressed: _busy
                  ? null
                  : () => setState(() => _showSettings = !_showSettings),
              icon: const Icon(Icons.tune, size: 20),
              selectedIcon: const Icon(
                Icons.tune,
                size: 20,
                color: AppTheme.primaryNavy,
              ),
            ),
        ],
      ),
    ),
  );

  Widget _sheet(double scale) {
    final rulerColor = AppTheme.dashTextSecondaryOf(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: Center(
                child: Text(
                  'mm',
                  style: TextStyle(fontSize: 9, color: rulerColor),
                ),
              ),
            ),
            RepaintBoundary(
              child: CustomPaint(
                size: Size(_layout.pageWidth * scale, 24),
                painter: _LayoutRulerPainter(
                  scale: scale,
                  vertical: false,
                  color: rulerColor,
                ),
              ),
            ),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RepaintBoundary(
              child: CustomPaint(
                size: Size(24, _layout.pageHeight * scale),
                painter: _LayoutRulerPainter(
                  scale: scale,
                  vertical: true,
                  color: rulerColor,
                ),
              ),
            ),
            _page(scale),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'A4 · ${_layout.orientation == 'portrait' ? 'Portrait' : 'Landscape'}',
          style: TextStyle(fontSize: 11, color: rulerColor),
        ),
      ],
    );
  }

  Widget _workspace() => Container(
    key: const ValueKey('layout-workspace'),
    color: AppTheme.dashIsDark(context)
        ? const Color(0xFF12151C)
        : const Color(0xFFE7EAF0),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final fit = math
            .min(
              (constraints.maxWidth - 72) / _layout.pageWidth,
              (constraints.maxHeight - 96) / _layout.pageHeight,
            )
            .clamp(.15, 1.2);
        final scale = _zoom ?? fit;
        return Scrollbar(
          controller: _workspaceVertical,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _workspaceVertical,
            child: Scrollbar(
              controller: _workspaceHorizontal,
              thumbVisibility: true,
              scrollbarOrientation: ScrollbarOrientation.bottom,
              child: SingleChildScrollView(
                controller: _workspaceHorizontal,
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minWidth: constraints.maxWidth,
                    minHeight: constraints.maxHeight,
                  ),
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: _sheet(scale),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    ),
  );

  @override
  Widget build(BuildContext context) => Dialog.fullscreen(
    backgroundColor: AppTheme.dashPanelOf(context),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 8, 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.primaryNavy.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.design_services_outlined,
                  color: AppTheme.primaryNavy,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Printed form layout',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      widget.requestType.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.dashTextSecondaryOf(context),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Close',
                onPressed: _busy ? null : () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (_loadingBackground) const LinearProgressIndicator(),
        Divider(height: 1, color: AppTheme.dashHairlineOf(context)),
        _toolbar(),
        Divider(height: 1, color: AppTheme.dashHairlineOf(context)),
        Expanded(
          child: AbsorbPointer(
            absorbing: _busy,
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < 850) {
                  return _showSettings ? _controls() : _workspace();
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _workspace()),
                    VerticalDivider(
                      width: 1,
                      color: AppTheme.dashHairlineOf(context),
                    ),
                    SizedBox(width: 340, child: _controls()),
                  ],
                );
              },
            ),
          ),
        ),
        Divider(height: 1, color: AppTheme.dashHairlineOf(context)),
        Padding(
          padding: const EdgeInsets.all(12),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final note = Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.description_outlined,
                    size: 16,
                    color: AppTheme.primaryNavy,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${_layout.elements.length} elements',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.dashTextSecondaryOf(context),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Tooltip(
                    message:
                        'Long or unplaced answers continue on another page.',
                    child: Icon(
                      Icons.info_outline,
                      size: 16,
                      color: AppTheme.dashTextSecondaryOf(context),
                    ),
                  ),
                ],
              );
              final actions = Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _busy || _loadingBackground ? null : _preview,
                    icon: const Icon(Icons.visibility_outlined, size: 18),
                    label: const Text('Preview layout'),
                  ),
                  FilledButton.icon(
                    onPressed: _busy || _loadingBackground ? null : _useLayout,
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('Use layout'),
                  ),
                ],
              );
              if (constraints.maxWidth < 600) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(alignment: Alignment.centerRight, child: actions),
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: note),
                  actions,
                ],
              );
            },
          ),
        ),
      ],
    ),
  );
}

class _LayoutRulerPainter extends CustomPainter {
  const _LayoutRulerPainter({
    required this.scale,
    required this.vertical,
    required this.color,
  });
  final double scale;
  final bool vertical;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final extent = vertical ? size.height : size.width;
    final mm = 72 / 25.4 * scale;
    final paint = Paint()
      ..color = color.withValues(alpha: .5)
      ..strokeWidth = .7;
    for (var value = 0; value * mm <= extent; value += 5) {
      final position = value * mm;
      final major = value % 20 == 0;
      final tick = major ? 8.0 : 4.0;
      canvas.drawLine(
        vertical ? Offset(24 - tick, position) : Offset(position, 24 - tick),
        vertical ? Offset(24, position) : Offset(position, 24),
        paint,
      );
      if (major) {
        final text = TextPainter(
          text: TextSpan(
            text: '$value',
            style: TextStyle(
              fontSize: 8,
              fontFamily: AppTheme.fontFamily,
              color: color,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        if (position + (vertical ? text.height : text.width) < extent) {
          text.paint(
            canvas,
            vertical ? Offset(1, position + 2) : Offset(position + 2, 1),
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(_LayoutRulerPainter oldDelegate) =>
      oldDelegate.scale != scale ||
      oldDelegate.vertical != vertical ||
      oldDelegate.color != color;
}

class _LayoutGridPainter extends CustomPainter {
  const _LayoutGridPainter(this.scale);
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    final spacing = 72 / 25.4 * 10 * scale;
    final paint = Paint()
      ..color = AppTheme.primaryNavy.withValues(alpha: .14)
      ..strokeWidth = .6;
    for (var x = spacing; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = spacing; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_LayoutGridPainter oldDelegate) =>
      oldDelegate.scale != scale;
}

// Pointer movement only updates this element's position. The editor model and
// property inputs are synchronized once the drag ends (including cancellation).
class _DraggableLayoutElement extends StatefulWidget {
  const _DraggableLayoutElement({
    super.key,
    required this.item,
    required this.scale,
    required this.pageSize,
    required this.enabled,
    required this.onSelect,
    required this.onMoved,
    required this.child,
  });

  final LocatorPrintElement item;
  final double scale;
  final Size pageSize;
  final bool enabled;
  final VoidCallback onSelect;
  final ValueChanged<LocatorPrintElement> onMoved;
  final Widget child;

  @override
  State<_DraggableLayoutElement> createState() =>
      _DraggableLayoutElementState();
}

class _DraggableLayoutElementState extends State<_DraggableLayoutElement> {
  late final ValueNotifier<Offset> _position;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    _position = ValueNotifier(Offset(widget.item.x, widget.item.y));
  }

  @override
  void didUpdateWidget(_DraggableLayoutElement oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.x != widget.item.x ||
        oldWidget.item.y != widget.item.y) {
      _position.value = Offset(widget.item.x, widget.item.y);
    }
  }

  @override
  void dispose() {
    _position.dispose();
    super.dispose();
  }

  void _move(DragUpdateDetails details) {
    final next = _position.value + details.delta / widget.scale;
    _position.value = Offset(
      next.dx.clamp(0, widget.pageSize.width - widget.item.width),
      next.dy.clamp(0, widget.pageSize.height - widget.item.height),
    );
  }

  void _finishDrag() {
    if (!_dragging) return;
    _dragging = false;
    widget.onMoved(
      widget.item.copyWith(x: _position.value.dx, y: _position.value.dy),
    );
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<Offset>(
    valueListenable: _position,
    child: MouseRegion(
      cursor: SystemMouseCursors.move,
      child: GestureDetector(
        key: ValueKey('layout-element-${widget.item.id}'),
        behavior: HitTestBehavior.opaque,
        dragStartBehavior: DragStartBehavior.down,
        onTap: widget.enabled ? widget.onSelect : null,
        onPanStart: widget.enabled
            ? (_) {
                _dragging = true;
                widget.onSelect();
              }
            : null,
        onPanUpdate: widget.enabled ? _move : null,
        onPanEnd: widget.enabled ? (_) => _finishDrag() : null,
        onPanCancel: widget.enabled ? _finishDrag : null,
        child: RepaintBoundary(child: widget.child),
      ),
    ),
    builder: (context, position, child) => Positioned(
      left: position.dx * widget.scale,
      top: position.dy * widget.scale,
      width: widget.item.width * widget.scale,
      height: widget.item.height * widget.scale,
      child: child!,
    ),
  );
}
