import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/core/api/user_facing_api_error.dart';
import '../../../models/locator_print_layout.dart';
import '../../../models/locator_request_type.dart';
import '../../../utils/locator_layout_pdf.dart';
import '../../../utils/locator_form_signatories.dart';
import 'print_layout_table_properties.dart';
import 'print_layout_page_properties.dart';
import 'print_layout_field_dialog.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_type_definition.dart';

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
    this.onCustomFieldsChanged,
    this.onPreviewWithFields,
  });
  final LocatorRequestType requestType;
  final PrintLayoutEditorBindings? bindings;
  final LocatorPrintLayout? initialLayout;
  final Uint8List? backgroundPdf, backgroundImage;
  final Future<void> Function(LocatorPrintLayout) onPreview;
  final ValueChanged<List<LeaveCustomFieldDefinition>>? onCustomFieldsChanged;
  final Future<void> Function(
    LocatorPrintLayout,
    List<LeaveCustomFieldDefinition>,
  )?
  onPreviewWithFields;
  @override
  State<LocatorPrintLayoutEditor> createState() =>
      _LocatorPrintLayoutEditorState();
}

class _LocatorPrintLayoutEditorState extends State<LocatorPrintLayoutEditor> {
  late LocatorPrintLayout _layout;
  late List<LeaveCustomFieldDefinition> _customFields;
  bool _customFieldsChanged = false;
  String? _selectedId, _error;
  Uint8List? _background;
  bool _busy = false, _loadingBackground = false;
  String? _backgroundOrientation, _backgroundPaper;
  final _pagePropertiesKey = GlobalKey<PrintLayoutPagePropertiesState>();
  final _zoom = ValueNotifier<double?>(null);
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
  final _editorFocus = FocusNode(debugLabel: 'Print layout editor');
  final _undoStack = <_LayoutEditorSnapshot>[];
  final _redoStack = <_LayoutEditorSnapshot>[];
  String? _historyGroup;
  bool _gestureActive = false;
  final _fitZoom = ValueNotifier<double>(1);
  late final _zoomChanges = Listenable.merge([_zoom, _fitZoom]);
  (Offset, Offset)? _wheelZoomAnchor;
  bool _wheelZoomPending = false;
  @override
  void initState() {
    super.initState();
    _layout = widget.initialLayout ?? _defaults('portrait');
    _customFields = List.of(widget.requestType.employeeDetailSchema);
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
    _editorFocus.dispose();
    _fitZoom.dispose();
    _zoom.dispose();
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
        ).first.timeout(const Duration(seconds: 15));
        image = await raster.toPng();
      }
      final codec = await ui.instantiateImageCodec(image);
      final frame = await codec.getNextFrame();
      final paper = printPaperFromAspect(
        frame.image.width.toDouble(),
        frame.image.height.toDouble(),
      );
      final orientation = frame.image.width > frame.image.height
          ? 'landscape'
          : 'portrait';
      frame.image.dispose();
      codec.dispose();
      if (!mounted) return;
      setState(() {
        _background = image;
        _backgroundOrientation = orientation;
        _backgroundPaper = paper;
        if (widget.initialLayout == null) {
          _layout = _defaults(orientation).withPageSettings(paperSize: paper);
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
    _historyGroup = null;
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

  _LayoutEditorSnapshot _snapshot() => _LayoutEditorSnapshot(
    layout: _layout,
    fields: List.of(_customFields),
    fieldsChanged: _customFieldsChanged,
    selectedId: _selectedId,
    customCaptions: Set.of(_customSignatureCaptions),
  );

  void _remember({String? group}) {
    if (group == null || group != _historyGroup) {
      _undoStack.add(_snapshot());
      if (_undoStack.length > 100) _undoStack.removeAt(0);
    }
    _historyGroup = group;
    _redoStack.clear();
  }

  void _restore(_LayoutEditorSnapshot snapshot) {
    _layout = snapshot.layout;
    _customFields = List.of(snapshot.fields);
    _customFieldsChanged = snapshot.fieldsChanged;
    _customSignatureCaptions
      ..clear()
      ..addAll(snapshot.customCaptions);
    _select(snapshot.selectedId);
    _error = null;
  }

  void _undo() {
    if (_busy || _gestureActive || _undoStack.isEmpty) return;
    setState(() {
      _redoStack.add(_snapshot());
      _restore(_undoStack.removeLast());
    });
  }

  void _redo() {
    if (_busy || _gestureActive || _redoStack.isEmpty) return;
    setState(() {
      _undoStack.add(_snapshot());
      _restore(_redoStack.removeLast());
    });
  }

  void _deleteSelected() {
    if (_busy || _gestureActive || _selected == null) return;
    _remember();
    setState(() {
      _layout = _layout.copyWith(
        elements: [
          for (final e in _layout.elements)
            if (e.id != _selectedId) e,
        ],
      );
      _select(_layout.elements.firstOrNull?.id);
      _error = null;
    });
    _editorFocus.requestFocus();
  }

  KeyEventResult _onEditorKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || _busy || _gestureActive) {
      return KeyEventResult.ignored;
    }
    // EditableText keeps its own undo, selection, and Delete behavior.
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused?.findAncestorWidgetOfExactType<EditableText>() != null) {
      return KeyEventResult.ignored;
    }
    final keys = HardwareKeyboard.instance;
    if (keys.isControlPressed || keys.isMetaPressed) {
      if (event.logicalKey == LogicalKeyboardKey.keyZ) {
        keys.isShiftPressed ? _redo() : _undo();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.keyY) {
        _redo();
        return KeyEventResult.handled;
      }
    } else if (event.logicalKey == LogicalKeyboardKey.delete) {
      _deleteSelected();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _replace(
    LocatorPrintElement next, {
    bool sync = false,
    String? historyGroup,
    bool recordHistory = true,
  }) {
    if (jsonEncode(next.toJson()) ==
        jsonEncode(
          _layout.elements.firstWhere((e) => e.id == next.id).toJson(),
        )) {
      return;
    }
    if (recordHistory) _remember(group: historyGroup);
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
    if (item == null) {
      return _pagePropertiesKey.currentState?.commit(base: _layout) ?? true;
    }
    if (item.kind == 'signature' &&
        _customSignatureCaptions.contains(item.id) &&
        item.label.trim().isEmpty) {
      setState(
        () => _error = "Enter a custom label or choose Signer's position.",
      );
      return false;
    }
    final original = {
      'x': item.x,
      'y': item.y,
      'width': item.width,
      'height': item.height,
      'font_size': item.fontSize,
    };
    final values = {
      for (final entry in _numbers.entries)
        entry.key: entry.value.text == original[entry.key]!.toStringAsFixed(1)
            ? original[entry.key]
            : double.tryParse(entry.value.text),
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
      fontFamily: values['font_size'] != item.fontSize
          ? item.fontFamily ?? _layout.fontFamily ?? 'sans'
          : item.fontFamily,
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
    return _pagePropertiesKey.currentState?.commit(base: _layout) ?? true;
  }

  Future<void> _preview() async {
    if (!_commitProperties()) return;
    final error = _layout.validate();
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    if (_backgroundOrientation != null &&
        (_layout.orientation != _backgroundOrientation ||
            _layout.paperSize != _backgroundPaper)) {
      setState(
        () => _error =
            'Choose the same paper size and orientation as the background.',
      );
      return;
    }
    setState(() => _busy = true);
    try {
      if (widget.onPreviewWithFields != null) {
        await widget.onPreviewWithFields!(
          _layout,
          List.unmodifiable(_customFields),
        );
      } else {
        await widget.onPreview(_layout);
      }
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
        (_layout.orientation != _backgroundOrientation ||
            _layout.paperSize != _backgroundPaper)) {
      setState(
        () => _error =
            'Choose the same paper size and orientation as the background.',
      );
      return;
    }
    if (_customFieldsChanged) {
      widget.onCustomFieldsChanged?.call(List.unmodifiable(_customFields));
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
  Map<String, String> get _fields => {
    ...?widget.bindings?.fields,
    if (widget.bindings == null) ...{
      'employee_name': 'Employee name',
      'date': 'Date',
      'request_type': 'Request type',
      'office': widget.requestType.locationLabel,
      'reason': 'Remarks / Reasons',
      'time_segments': 'DTR slots',
    },
    for (final field in _customFields) 'custom:${field.key}': field.label,
  };
  Future<void> _createField() async {
    if (!_commitProperties() || widget.onCustomFieldsChanged == null) return;
    if (_customFields.length >= 20 || _layout.elements.length >= 60) {
      setState(
        () => _error = 'Use at most 20 additional fields and 60 page elements.',
      );
      return;
    }
    final field = await showDialog<LeaveCustomFieldDefinition>(
      context: context,
      builder: (_) => PrintLayoutFieldDialog(
        existingFields: List.unmodifiable(_customFields),
      ),
    );
    if (field == null || !mounted) return;
    _remember();
    setState(() {
      _customFields = [..._customFields, field];
      _customFieldsChanged = true;
    });
    _add('field|custom:${field.key}', recordHistory: false);
  }

  void _add(String data, {Offset? point, bool recordHistory = true}) {
    if (!(_pagePropertiesKey.currentState?.commit(base: _layout) ?? true)) {
      return;
    }
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
    final width = math.min(
          _layout.contentWidth,
          kind == 'table'
              ? 400.0
              : kind == 'text'
              ? 300.0
              : 240.0,
        ),
        height = math.min(
          _layout.contentHeight,
          kind == 'table'
              ? math.max(120.0, 3 * (_layout.defaultFontSize * 1.5 + 8))
              : kind == 'signature'
              ? math.max(80.0, _layout.defaultFontSize * 3.5 + 12)
              : kind == 'line'
              ? 2.0
              : math.max(40.0, _layout.defaultFontSize * 1.5 + 12),
        );
    final item = LocatorPrintElement(
      id: 'item_${DateTime.now().microsecondsSinceEpoch}',
      kind: kind,
      source: source,
      text: kind == 'text' ? 'New text' : '',
      label: kind == 'signature' ? '' : label,
      x: (point?.dx ?? math.max(40, _layout.margins.left)).clamp(
        _layout.margins.left,
        _layout.pageWidth - _layout.margins.right - width,
      ),
      y: (point?.dy ?? math.max(180, _layout.margins.top)).clamp(
        _layout.margins.top,
        _layout.pageHeight - _layout.margins.bottom - height,
      ),
      width: width,
      height: height,
      bold: kind == 'text',
      fontSize: _layout.defaultFontSize,
      fontFamily: _layout.fontFamily ?? 'sans',
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
    final trial = _layout.copyWith(elements: [..._layout.elements, item]);
    final validation = trial.validate();
    if (validation != null) {
      setState(() => _error = validation);
      return;
    }
    if (recordHistory) _remember();
    setState(() {
      _layout = _layout.copyWith(elements: [..._layout.elements, item]);
      _select(item.id);
      _error = null;
    });
    _editorFocus.requestFocus();
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

  Widget _pageSettings() => PrintLayoutPageProperties(
    key: _pagePropertiesKey,
    layout: _layout,
    enabled: !_busy,
    onChanged: (next) => setState(() {
      _remember();
      _layout = next;
      _select(_selectedId);
    }),
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
              onPressed: _busy ? null : _deleteSelected,
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
                    _remember();
                    if (value == 'position') {
                      _customSignatureCaptions.remove(selected.id);
                      _replace(
                        selected.copyWith(label: ''),
                        sync: true,
                        recordHistory: false,
                      );
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
                        recordHistory: false,
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
              _replace(
                selected.kind == 'text'
                    ? selected.copyWith(text: value)
                    : selected.copyWith(label: value),
                historyGroup: 'label-${selected.id}',
              );
            },
          ),
        const SizedBox(height: 16),
        if (selected.kind != 'line')
          DropdownButtonFormField<String>(
            key: ValueKey('element-font-${selected.id}-${selected.fontFamily}'),
            initialValue: selected.fontFamily ?? 'inherit',
            isExpanded: true,
            decoration: AppTheme.dashInputDecoration(
              context,
              labelText: 'Element font family',
              radius: 8,
            ),
            items: [
              const DropdownMenuItem(
                value: 'inherit',
                child: Text('Use page font'),
              ),
              for (final e in printFontLabels.entries)
                DropdownMenuItem(
                  value: e.key,
                  child: Text(
                    e.value,
                    style: TextStyle(fontFamily: printFontFamilies[e.key]),
                  ),
                ),
            ],
            onChanged: _busy
                ? null
                : (v) {
                    if (v != null) {
                      _replace(
                        selected.copyWith(
                          fontFamily: v == 'inherit' ? null : v,
                          inheritFont: v == 'inherit',
                        ),
                      );
                    }
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

  Widget _signaturePreview(LocatorPrintElement item, double scale) {
    final styled = item.fontFamily != null || _layout.fontFamily != null;
    final family =
        printFontFamilies[item.fontFamily ?? _layout.fontFamily] ??
        AppTheme.fontFamily;
    final csc = item.signatureStyle == 'csc';
    Widget name() => SizedBox(
      height: (styled || csc ? item.fontSize * 1.2 : 14) * scale,
      child: FittedBox(
        child: Text(
          'Sample signer',
          style: TextStyle(
            color: Colors.black,
            fontFamily: family,
            fontSize: (styled || csc ? item.fontSize : 10) * scale,
            fontWeight: styled ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
    return Column(
      children: [
        const Expanded(child: Icon(Icons.draw_outlined, color: Colors.black26)),
        if (!csc) name(),
        Divider(height: 3 * scale),
        if (csc && item.source != 'applicant') name(),
        Text(
          locatorSignatureCaption(
            item,
            widget.bindings?.sampleSignatory(item.source) ??
                locatorLayoutSampleSignatory(widget.requestType, item.source),
          ),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.clip,
          style: TextStyle(
            color: Colors.black,
            fontFamily: family,
            fontSize:
                (csc
                    ? item.fontSize
                    : styled
                    ? (item.fontSize * .75).clamp(6, 54)
                    : 8) *
                scale,
          ),
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
                          fontFamily:
                              printFontFamilies[item.fontFamily ??
                                  _layout.fontFamily] ??
                              AppTheme.fontFamily,
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
    final customSample = locatorLayoutSample(
      widget.requestType.copyWith(employeeDetailSchema: _customFields),
    );
    final sample = {
      ...?widget.bindings?.sample,
      if (widget.bindings == null) ...customSample,
      'additional_details': customSample['additional_details'],
      'employee_detail_schema_snapshot':
          customSample['employee_detail_schema_snapshot'],
    };
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
                if (!_layout.margins.isEmpty)
                  Positioned(
                    left: _layout.margins.left * scale,
                    top: _layout.margins.top * scale,
                    width: _layout.contentWidth * scale,
                    height: _layout.contentHeight * scale,
                    child: IgnorePointer(
                      child: Container(
                        key: const ValueKey('layout-margin-guides'),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: Colors.blueGrey.withValues(alpha: .5),
                            width: .7,
                          ),
                        ),
                      ),
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
                    margins: _layout.margins,
                    enabled: !_busy,
                    selected: item.id == _selectedId,
                    zoomChanges: _zoomChanges,
                    displayZoom: () => _zoom.value ?? _fitZoom.value,
                    fontFamily: _layout.fontFamily,
                    onGestureChanged: (active) => _gestureActive = active,
                    onSelect: () {
                      setState(() => _select(item.id));
                      _editorFocus.requestFocus();
                    },
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
                          ? _signaturePreview(item, scale)
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
                                      fontFamily:
                                          printFontFamilies[item.fontFamily ??
                                              _layout.fontFamily] ??
                                          AppTheme.fontFamily,
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
                                      fontFamily:
                                          printFontFamilies[item.fontFamily ??
                                              _layout.fontFamily] ??
                                          AppTheme.fontFamily,
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
    _wheelZoomAnchor = null;
    _zoom.value = zoom;
    if (_workspaceVertical.hasClients) _workspaceVertical.jumpTo(0);
    if (_workspaceHorizontal.hasClients) _workspaceHorizontal.jumpTo(0);
  }

  void _onCanvasWheel(PointerSignalEvent event) {
    if (event is! PointerScrollEvent ||
        event.scrollDelta.dy == 0 ||
        _busy ||
        _loadingBackground ||
        _gestureActive) {
      return;
    }
    // Claim the signal before the enclosing scroll views handle it.
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      final current = _zoom.value ?? _fitZoom.value;
      final next = (current * math.pow(1.1, -event.scrollDelta.dy / 100)).clamp(
        .25,
        2.0,
      );
      if (next == current) return;
      final canvas =
          _canvasKey.currentContext?.findRenderObject() as RenderBox?;
      if (canvas == null) return;
      _wheelZoomAnchor = (canvas.globalToLocal(event.position), event.position);
      _zoom.value = next;
      if (_wheelZoomPending) return;
      _wheelZoomPending = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _wheelZoomPending = false;
        final anchor = _wheelZoomAnchor;
        _wheelZoomAnchor = null;
        if (!mounted || anchor == null) return;
        final updated =
            _canvasKey.currentContext?.findRenderObject() as RenderBox?;
        if (updated == null) return;
        final delta = updated.localToGlobal(anchor.$1) - anchor.$2;
        void adjust(ScrollController controller, double change) {
          if (!controller.hasClients) return;
          final position = controller.position;
          controller.jumpTo(
            (position.pixels + change).clamp(
              position.minScrollExtent,
              position.maxScrollExtent,
            ),
          );
        }

        adjust(_workspaceVertical, delta.dy);
        adjust(_workspaceHorizontal, delta.dx);
      });
    });
  }

  Widget _zoomDropdown() => ValueListenableBuilder<double?>(
    valueListenable: _zoom,
    builder: (_, zoom, _) => Container(
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
          value: zoom ?? 0,
          isExpanded: true,
          isDense: true,
          style: TextStyle(
            fontSize: 13,
            fontFamily: AppTheme.fontFamily,
            color: AppTheme.dashTextPrimaryOf(context),
          ),
          items: [
            DropdownMenuItem(value: 0, child: Text('Fit page')),
            DropdownMenuItem(value: .5, child: Text('50%')),
            DropdownMenuItem(value: .75, child: Text('75%')),
            DropdownMenuItem(value: 1, child: Text('100%')),
            DropdownMenuItem(value: 1.25, child: Text('125%')),
            DropdownMenuItem(value: 1.5, child: Text('150%')),
            if (zoom != null && ![.5, .75, 1, 1.25, 1.5].contains(zoom))
              DropdownMenuItem(
                value: zoom,
                child: Text('${(zoom * 100).round()}%'),
              ),
          ],
          onChanged: _busy
              ? null
              : (value) => _setZoom(value == 0 ? null : value),
        ),
      ),
    ),
  );

  Widget _zoomSlider(double width) => SizedBox(
    width: width,
    height: 36,
    child: ListenableBuilder(
      listenable: _zoomChanges,
      builder: (_, _) => Slider(
        key: const ValueKey('layout-zoom-slider'),
        min: .25,
        max: 2,
        divisions: 35,
        value: (_zoom.value ?? _fitZoom.value).clamp(.25, 2),
        label: '${((_zoom.value ?? _fitZoom.value) * 100).round()}%',
        semanticFormatterCallback: (value) =>
            '${(value * 100).round()} percent zoom',
        onChanged: _busy ? null : _setZoom,
      ),
    ),
  );

  Widget _toolbar() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: LayoutBuilder(
      builder: (context, constraints) => Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          IconButton(
            tooltip: 'Undo (Ctrl+Z)',
            constraints: const BoxConstraints.tightFor(width: 36, height: 36),
            onPressed: _busy || _undoStack.isEmpty ? null : _undo,
            icon: const Icon(Icons.undo, size: 20),
          ),
          IconButton(
            tooltip: 'Redo (Ctrl+Y / Ctrl+Shift+Z)',
            constraints: const BoxConstraints.tightFor(width: 36, height: 36),
            onPressed: _busy || _redoStack.isEmpty ? null : _redo,
            icon: const Icon(Icons.redo, size: 20),
          ),
          IconButton(
            tooltip: 'Delete selected element (Delete)',
            constraints: const BoxConstraints.tightFor(width: 36, height: 36),
            onPressed: _busy || _selected == null ? null : _deleteSelected,
            icon: const Icon(Icons.delete_outline, size: 20),
          ),
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
            onSelected: (value) {
              if (value == 'create_field') {
                _createField();
              } else {
                _add(value);
              }
            },
            itemBuilder: (_) => [
              if (widget.onCustomFieldsChanged != null) ...[
                PopupMenuItem(
                  value: 'create_field',
                  enabled:
                      _customFields.length < 20 && _layout.elements.length < 60,
                  child: const Text('Create new field'),
                ),
                const PopupMenuDivider(),
              ],
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
          _zoomDropdown(),
          _zoomSlider(constraints.maxWidth < 600 ? 120 : 160),
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
                  : () {
                      if (_pagePropertiesKey.currentState?.commit(
                            base: _layout,
                          ) ==
                          false) {
                        return;
                      }
                      setState(() => _showSettings = !_showSettings);
                    },
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

  Widget _sheet(double scale, Widget page) {
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
            SizedBox(
              width: _layout.pageWidth * scale,
              height: _layout.pageHeight * scale,
              child: OverflowBox(
                alignment: Alignment.topLeft,
                minWidth: _layout.pageWidth,
                maxWidth: _layout.pageWidth,
                minHeight: _layout.pageHeight,
                maxHeight: _layout.pageHeight,
                child: Transform.scale(
                  scale: scale,
                  alignment: Alignment.topLeft,
                  child: page,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          '${printPaperLabels[_layout.paperSize]} · ${_layout.orientation == 'portrait' ? 'Portrait' : 'Landscape'}',
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
        if (_fitZoom.value != fit) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _fitZoom.value != fit) _fitZoom.value = fit;
          });
        }
        return ValueListenableBuilder<double?>(
          valueListenable: _zoom,
          // Zoom changes the transform, not the page's text and field widgets.
          child: RepaintBoundary(child: _page(1)),
          builder: (context, zoom, page) => Scrollbar(
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
                  child: Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerSignal: _onCanvasWheel,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minWidth: constraints.maxWidth,
                        minHeight: constraints.maxHeight,
                      ),
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: _sheet(zoom ?? fit, page!),
                        ),
                      ),
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
  Widget build(BuildContext context) => Focus(
    focusNode: _editorFocus,
    autofocus: true,
    onKeyEvent: _onEditorKey,
    child: Dialog.fullscreen(
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
                      onPressed: _busy || _loadingBackground
                          ? null
                          : _useLayout,
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
    ),
  );
}

class _LayoutEditorSnapshot {
  const _LayoutEditorSnapshot({
    required this.layout,
    required this.fields,
    required this.fieldsChanged,
    required this.selectedId,
    required this.customCaptions,
  });
  final LocatorPrintLayout layout;
  final List<LeaveCustomFieldDefinition> fields;
  final bool fieldsChanged;
  final String? selectedId;
  final Set<String> customCaptions;
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

// Gestures repaint this element locally; model/history updates happen on release.
class _DraggableLayoutElement extends StatefulWidget {
  const _DraggableLayoutElement({
    super.key,
    required this.item,
    required this.scale,
    required this.pageSize,
    required this.margins,
    required this.enabled,
    required this.selected,
    required this.zoomChanges,
    required this.displayZoom,
    required this.onSelect,
    required this.onMoved,
    required this.onGestureChanged,
    required this.child,
    this.fontFamily,
  });
  final LocatorPrintElement item;
  final double scale;
  final Size pageSize;
  final PrintLayoutMargins margins;
  final bool enabled, selected;
  final Listenable zoomChanges;
  final double Function() displayZoom;
  final String? fontFamily;
  final VoidCallback onSelect;
  final ValueChanged<LocatorPrintElement> onMoved;
  final ValueChanged<bool> onGestureChanged;
  final Widget child;
  @override
  State<_DraggableLayoutElement> createState() =>
      _DraggableLayoutElementState();
}

class _DraggableLayoutElementState extends State<_DraggableLayoutElement> {
  late final ValueNotifier<Rect> _geometry;
  bool _dragging = false;
  String? _resizeHandle;
  Rect? _resizeOrigin;
  Rect get _modelRect => Rect.fromLTWH(
    widget.item.x,
    widget.item.y,
    widget.item.width,
    widget.item.height,
  );
  @override
  void initState() {
    super.initState();
    _geometry = ValueNotifier(_modelRect);
  }

  @override
  void didUpdateWidget(_DraggableLayoutElement oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.x != widget.item.x ||
        oldWidget.item.y != widget.item.y ||
        oldWidget.item.width != widget.item.width ||
        oldWidget.item.height != widget.item.height) {
      _geometry.value = _modelRect;
    }
  }

  @override
  void dispose() {
    _geometry.dispose();
    super.dispose();
  }

  double get _minimumWidth => switch (widget.item.kind) {
    'signature' => 100,
    'table' =>
      20 *
          widget.item.columnWidths.fold(0.0, (a, b) => a + b) /
          widget.item.columnWidths.reduce(math.min),
    _ => 20,
  };
  double get _minimumHeight {
    final item = widget.item;
    if (item.kind == 'signature') {
      final minimum = item.signatureStyle == 'csc'
          ? (item.source == 'applicant' ? 18.0 : 32.0)
          : 60.0;
      return item.fontFamily != null || widget.fontFamily != null
          ? math.max(minimum, item.fontSize * 3.5 + 12)
          : minimum;
    }
    return switch (item.kind) {
      'field' => 20,
      'text' => 12,
      'table' => item.cells.length * (item.fontSize * 1.5 + 8),
      _ => 2,
    };
  }

  void _move(DragUpdateDetails details) {
    final rect = _geometry.value;
    final next = rect.topLeft + details.delta / widget.scale;
    _geometry.value = Rect.fromLTWH(
      next.dx.clamp(
        widget.margins.left,
        widget.pageSize.width - widget.margins.right - rect.width,
      ),
      next.dy.clamp(
        widget.margins.top,
        widget.pageSize.height - widget.margins.bottom - rect.height,
      ),
      rect.width,
      rect.height,
    );
  }

  void _resize(DragUpdateDetails details) {
    final handle = _resizeHandle!;
    final rect = _geometry.value;
    final delta = details.delta / widget.scale;
    var left = rect.left,
        right = rect.right,
        top = rect.top,
        bottom = rect.bottom;
    if (handle.contains('w')) {
      left = (left + delta.dx).clamp(
        widget.margins.left,
        right - _minimumWidth,
      );
    }
    if (handle.contains('e')) {
      right = (right + delta.dx).clamp(
        left + _minimumWidth,
        widget.pageSize.width - widget.margins.right,
      );
    }
    if (handle.contains('n')) {
      top = (top + delta.dy).clamp(widget.margins.top, bottom - _minimumHeight);
    }
    if (handle.contains('s')) {
      bottom = (bottom + delta.dy).clamp(
        top + _minimumHeight,
        widget.pageSize.height - widget.margins.bottom,
      );
    }
    _geometry.value = Rect.fromLTRB(left, top, right, bottom);
  }

  void _finishGesture() {
    if (!_dragging) return;
    _dragging = false;
    _resizeHandle = null;
    widget.onGestureChanged(false);
    final rect = _geometry.value;
    widget.onMoved(
      widget.item.copyWith(
        x: rect.left,
        y: rect.top,
        width: rect.width,
        height: rect.height,
      ),
    );
  }

  void _cancelResize() {
    if (!_dragging || _resizeOrigin == null) return;
    _geometry.value = _resizeOrigin!;
    _dragging = false;
    _resizeHandle = null;
    widget.onGestureChanged(false);
  }

  Widget _handle(String direction, Rect rect) {
    final hitSize = 14.0 / widget.displayZoom();
    final x = direction.contains('w')
        ? 0.0
        : direction.contains('e')
        ? rect.width * widget.scale - hitSize
        : (rect.width * widget.scale - hitSize) / 2;
    final y = direction.contains('n')
        ? 0.0
        : direction.contains('s')
        ? rect.height * widget.scale - hitSize
        : (rect.height * widget.scale - hitSize) / 2;
    return Positioned(
      left: x,
      top: y,
      width: hitSize,
      height: hitSize,
      child: MouseRegion(
        cursor: switch (direction) {
          'nw' || 'se' => SystemMouseCursors.resizeUpLeftDownRight,
          'ne' || 'sw' => SystemMouseCursors.resizeUpRightDownLeft,
          'n' || 's' => SystemMouseCursors.resizeUpDown,
          _ => SystemMouseCursors.resizeLeftRight,
        },
        child: Listener(
          onPointerCancel: (_) => _cancelResize(),
          child: GestureDetector(
            key: ValueKey('layout-resize-${widget.item.id}-$direction'),
            behavior: HitTestBehavior.opaque,
            dragStartBehavior: DragStartBehavior.down,
            onPanStart: widget.enabled
                ? (_) {
                    _dragging = true;
                    _resizeHandle = direction;
                    _resizeOrigin = _geometry.value;
                    widget.onGestureChanged(true);
                    widget.onSelect();
                  }
                : null,
            onPanUpdate: widget.enabled ? _resize : null,
            onPanEnd: widget.enabled ? (_) => _finishGesture() : null,
            onPanCancel: widget.enabled ? _cancelResize : null,
            child: Center(
              child: Container(
                width: 7 / widget.displayZoom(),
                height: 7 / widget.displayZoom(),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(
                    color: AppTheme.primaryNavy,
                    width: 1 / widget.displayZoom(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<Rect>(
    valueListenable: _geometry,
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
                widget.onGestureChanged(true);
                widget.onSelect();
              }
            : null,
        onPanUpdate: widget.enabled ? _move : null,
        onPanEnd: widget.enabled ? (_) => _finishGesture() : null,
        onPanCancel: widget.enabled ? _finishGesture : null,
        child: RepaintBoundary(child: widget.child),
      ),
    ),
    builder: (context, rect, child) => Positioned(
      left: rect.left * widget.scale,
      top: rect.top * widget.scale,
      width: rect.width * widget.scale,
      height: rect.height * widget.scale,
      child: Stack(
        fit: StackFit.expand,
        children: [
          child!,
          if (widget.selected)
            Positioned.fill(
              child: ListenableBuilder(
                listenable: widget.zoomChanges,
                builder: (_, _) => RepaintBoundary(
                  child: Stack(
                    children: [
                      for (final direction
                          in widget.item.kind == 'line'
                              ? ['w', 'e']
                              : rect.height * widget.displayZoom() < 42
                              ? ['nw', 'ne', 'e', 'se', 'sw', 'w']
                              : ['nw', 'n', 'ne', 'e', 'se', 's', 'sw', 'w'])
                        _handle(direction, rect),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
