part of 'locator_print_layout_editor.dart';

extension _PrintLayoutDesignControls on _LocatorPrintLayoutEditorState {
  Offset _selectionPagePoint(Offset global) {
    final canvas = _canvasKey.currentContext!.findRenderObject() as RenderBox;
    final point = canvas.globalToLocal(global);
    return Offset(
      point.dx.clamp(0, _layout.pageWidth),
      point.dy.clamp(0, _layout.pageHeight),
    );
  }

  void _beginBoxSelection(DragStartDetails details) {
    if (_busy || _gestureActive || !_commitProperties()) return;
    final keys = HardwareKeyboard.instance;
    _selectionBase =
        keys.isControlPressed || keys.isMetaPressed || keys.isShiftPressed
        ? Set.of(_selectedIds)
        : {};
    final origin = _selectionPagePoint(details.globalPosition);
    _selectionOrigin = origin;
    _selectionBox.value = Rect.fromPoints(origin, origin);
    _gestureActive = true;
    _editorFocus.requestFocus();
  }

  void _updateBoxSelection(DragUpdateDetails details) {
    final origin = _selectionOrigin;
    if (origin == null) return;
    _selectionBox.value = Rect.fromPoints(
      origin,
      _selectionPagePoint(details.globalPosition),
    );
  }

  void _cancelBoxSelection() {
    if (_selectionOrigin == null) return;
    _selectionOrigin = null;
    _selectionBase = {};
    _selectionBox.value = null;
    _gestureActive = false;
  }

  void _finishBoxSelection() {
    final box = _selectionBox.value;
    if (_selectionOrigin == null || box == null) return;
    final enclosed = <String>{..._selectionBase};
    for (final item in _layout.elements) {
      if (box.left <= item.x + .01 &&
          box.top <= item.y + .01 &&
          box.right >= item.x + item.width - .01 &&
          box.bottom >= item.y + item.height - .01) {
        enclosed.add(item.id);
      }
    }
    final ids = PrintLayoutEditing.selection(_layout, enclosed);
    _cancelBoxSelection();
    _updateDesignState(() {
      _select(ids.firstOrNull);
      _selectedIds = ids;
    });
  }

  void _clearCanvasSelection() {
    final keys = HardwareKeyboard.instance;
    if (_busy ||
        keys.isControlPressed ||
        keys.isMetaPressed ||
        keys.isShiftPressed ||
        !_commitProperties()) {
      return;
    }
    _updateDesignState(() => _select(null));
    _editorFocus.requestFocus();
  }

  bool get _canEditSelection =>
      PrintLayoutEditing.editable(_layout, _selectedIds);

  bool _canMoveItem(LocatorPrintElement item) => PrintLayoutEditing.editable(
    _layout,
    _selectedIds.contains(item.id)
        ? _selectedIds
        : PrintLayoutEditing.selection(_layout, {item.id}),
  );

  Rect _movementBounds(LocatorPrintElement item) {
    final ids = _selectedIds.contains(item.id)
        ? _selectedIds
        : PrintLayoutEditing.selection(_layout, {item.id});
    return _layout.elements
        .where((e) => ids.contains(e.id))
        .map((e) => Rect.fromLTWH(e.x, e.y, e.width, e.height))
        .reduce((a, b) => a.expandToInclude(b));
  }

  void _applyDesignLayout(LocatorPrintLayout next, {bool sync = true}) {
    if (_busy || jsonEncode(next.toJson()) == jsonEncode(_layout.toJson())) {
      return;
    }
    final error = next.validate();
    if (error != null) {
      _updateDesignState(() => _error = error);
      return;
    }
    _remember();
    _updateDesignState(() {
      _layout = next;
      _error = null;
      if (sync) _select(_selectedId, preserve: true);
    });
  }

  void _moveSelection(LocatorPrintElement next) {
    if (!_canEditSelection) return;
    if (_selectedIds.length > 1) {
      final previous = _layout.elements.firstWhere((e) => e.id == next.id);
      _applyDesignLayout(
        PrintLayoutEditing.translate(
          _layout,
          _selectedIds,
          next.x - previous.x,
          next.y - previous.y,
        ),
      );
    } else {
      _replace(next, sync: true);
    }
  }

  void _selectLayer(String id, {bool toggle = false}) {
    if (_busy || !_commitProperties()) return;
    _updateDesignState(() => _select(id, toggle: toggle));
    _editorFocus.requestFocus();
  }

  void _toggleLayerLock(String id) {
    if (_busy || !_commitProperties()) return;
    final item = _layout.elements.firstWhere((e) => e.id == id);
    _applyDesignLayout(PrintLayoutEditing.lock(_layout, {id}, !item.locked));
  }

  void _arrange(String action) {
    if (_busy || _gestureActive || !_commitProperties()) return;
    final next = switch (action) {
      'group' => PrintLayoutEditing.group(
        _layout,
        _selectedIds,
        'group_${DateTime.now().microsecondsSinceEpoch}',
      ),
      'ungroup' => PrintLayoutEditing.ungroup(_layout, _selectedIds),
      'lock' || 'unlock' => PrintLayoutEditing.lock(
        _layout,
        _selectedIds,
        action == 'lock',
      ),
      'front' ||
      'back' ||
      'forward' ||
      'backward' => PrintLayoutEditing.reorder(_layout, _selectedIds, action),
      'horizontal' || 'vertical' => PrintLayoutEditing.distribute(
        _layout,
        _selectedIds,
        horizontal: action == 'horizontal',
      ),
      _ => PrintLayoutEditing.align(_layout, _selectedIds, action),
    };
    _applyDesignLayout(next);
    _editorFocus.requestFocus();
  }

  Widget _arrangeMenu() => PopupMenuButton<String>(
    key: const ValueKey('layout-arrange'),
    tooltip: 'Arrange selected elements',
    enabled: !_busy && _selectedIds.isNotEmpty,
    onSelected: _arrange,
    itemBuilder: (_) => [
      for (final entry in const {
        'left': 'Align left',
        'center': 'Align horizontal centers',
        'right': 'Align right',
        'top': 'Align top',
        'middle': 'Align vertical centers',
        'bottom': 'Align bottom',
      }.entries)
        PopupMenuItem(
          value: entry.key,
          key: ValueKey('layout-arrange-${entry.key}'),
          enabled: _canEditSelection,
          child: Text(entry.value),
        ),
      const PopupMenuDivider(),
      for (final entry in const {
        'horizontal': 'Space evenly horizontally',
        'vertical': 'Space evenly vertically',
      }.entries)
        PopupMenuItem(
          value: entry.key,
          key: ValueKey('layout-arrange-${entry.key}'),
          enabled:
              _canEditSelection &&
              _layout.elements
                      .where((e) => _selectedIds.contains(e.id))
                      .map((e) => e.groupId ?? e.id)
                      .toSet()
                      .length >=
                  3,
          child: Text(entry.value),
        ),
      const PopupMenuDivider(),
      PopupMenuItem(
        value: 'group',
        key: const ValueKey('layout-arrange-group'),
        enabled: _canEditSelection && _selectedIds.length > 1,
        child: const Text('Group selection'),
      ),
      PopupMenuItem(
        value: 'ungroup',
        key: const ValueKey('layout-arrange-ungroup'),
        enabled:
            _canEditSelection &&
            _layout.elements.any(
              (e) => _selectedIds.contains(e.id) && e.groupId != null,
            ),
        child: const Text('Ungroup selection'),
      ),
      const PopupMenuDivider(),
      for (final entry in const {
        'front': 'Bring to front',
        'forward': 'Bring forward',
        'backward': 'Send backward',
        'back': 'Send to back',
      }.entries)
        PopupMenuItem(
          value: entry.key,
          key: ValueKey('layout-arrange-${entry.key}'),
          enabled: _canEditSelection,
          child: Text(entry.value),
        ),
      const PopupMenuDivider(),
      PopupMenuItem(
        value: _canEditSelection ? 'lock' : 'unlock',
        key: ValueKey(
          'layout-arrange-${_canEditSelection ? 'lock' : 'unlock'}',
        ),
        child: Text(_canEditSelection ? 'Lock selection' : 'Unlock selection'),
      ),
    ],
    child: const Padding(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.align_horizontal_left, size: 18),
          SizedBox(width: 6),
          Text('Arrange'),
          Icon(Icons.expand_more, size: 16),
        ],
      ),
    ),
  );

  Widget _layers() => Column(
    key: const ValueKey('layout-layers'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        'Drag on empty page space to box-select, or Ctrl/Shift-click elements. Use these checkboxes when elements overlap. Frontmost layers are listed first.',
        style: TextStyle(fontSize: 12),
      ),
      const SizedBox(height: 8),
      ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 260),
        child: SingleChildScrollView(
          primary: false,
          child: Column(
            children: [
              for (final item in _layout.elements.reversed)
                Material(
                  color: Colors.transparent,
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    selected: _selectedIds.contains(item.id),
                    leading: Checkbox(
                      key: ValueKey('layout-layer-select-${item.id}'),
                      value: _selectedIds.contains(item.id),
                      onChanged: _busy
                          ? null
                          : (_) => _selectLayer(item.id, toggle: true),
                    ),
                    title: Text(
                      item.kind == 'text'
                          ? item.text
                          : item.label.isNotEmpty
                          ? item.label
                          : item.kind == 'rectangle'
                          ? 'Rectangle'
                          : item.kind == 'line'
                          ? 'Line'
                          : item.kind == 'table'
                          ? 'Table'
                          : item.source,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                    subtitle: item.groupId == null
                        ? null
                        : const Text('Grouped', style: TextStyle(fontSize: 11)),
                    onTap: _busy ? null : () => _selectLayer(item.id),
                    trailing: IconButton(
                      tooltip: item.locked ? 'Unlock layer' : 'Lock layer',
                      iconSize: 18,
                      icon: Icon(
                        item.locked
                            ? Icons.lock_outline
                            : Icons.lock_open_outlined,
                      ),
                      onPressed: _busy ? null : () => _toggleLayerLock(item.id),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ],
  );

  Widget _appearance(LocatorPrintElement item) =>
      _PrintLayoutAppearanceProperties(
        key: _appearanceKey,
        item: item,
        enabled: !_busy,
        onChanged: (style) => _setAppearance(item.id, style),
      );

  void _setAppearance(String id, PrintElementDecoration style) {
    final current = _layout.elements.firstWhere((e) => e.id == id);
    if (current.locked) return;
    var next = current.copyWith(decoration: style);
    if (current.kind == 'line' && style.borderWidth > current.height) {
      final height = style.borderWidth;
      next = next.copyWith(
        height: height,
        y: (current.y + current.height / 2 - height / 2).clamp(
          _layout.margins.top,
          _layout.pageHeight - _layout.margins.bottom - height,
        ),
      );
    }
    _replace(next, sync: next.height != current.height);
  }
}

class _PrintLayoutAppearanceProperties extends StatefulWidget {
  const _PrintLayoutAppearanceProperties({
    super.key,
    required this.item,
    required this.enabled,
    required this.onChanged,
  });
  final LocatorPrintElement item;
  final bool enabled;
  final ValueChanged<PrintElementDecoration> onChanged;
  @override
  State<_PrintLayoutAppearanceProperties> createState() =>
      _PrintLayoutAppearancePropertiesState();
}

class _PrintLayoutAppearancePropertiesState
    extends State<_PrintLayoutAppearanceProperties> {
  final _width = TextEditingController(),
      _stroke = TextEditingController(),
      _fill = TextEditingController();
  String? _error;
  @override
  void initState() {
    super.initState();
    _sync();
  }

  void _sync() {
    final s = widget.item.decoration;
    _width.text = '${s.borderWidth}';
    _stroke.text = s.borderColor;
    _fill.text = s.fillColor ?? '';
    _error = null;
  }

  @override
  void didUpdateWidget(_PrintLayoutAppearanceProperties old) {
    super.didUpdateWidget(old);
    if (old.item.id != widget.item.id ||
        jsonEncode(old.item.decoration.toJson()) !=
            jsonEncode(widget.item.decoration.toJson())) {
      _sync();
    }
  }

  @override
  void dispose() {
    _width.dispose();
    _stroke.dispose();
    _fill.dispose();
    super.dispose();
  }

  bool commit({List<String>? sides, String? style}) {
    if (!widget.enabled) return true;
    final width = double.tryParse(_width.text.trim());
    final fill = _fill.text.trim();
    final next = widget.item.decoration.copyWith(
      borderWidth: width ?? -1,
      borderColor: _stroke.text.trim(),
      fillColor: fill.isEmpty ? null : fill,
      clearFill: fill.isEmpty,
      borderSides: sides,
      borderStyle: style,
    );
    final error = next.validate();
    setState(() => _error = error);
    if (error != null) return false;
    if (jsonEncode(next.toJson()) ==
        jsonEncode(widget.item.decoration.toJson())) {
      return true;
    }
    widget.onChanged(next);
    return true;
  }

  Widget _colorInput(
    String title,
    TextEditingController controller,
    Key key, {
    bool optional = false,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        title,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 6),
      TextField(
        key: key,
        controller: controller,
        enabled: widget.enabled,
        decoration:
            AppTheme.dashInputDecoration(
              context,
              hintText: optional ? 'None or #RRGGBB' : '#RRGGBB',
              radius: 8,
            ).copyWith(
              suffixIcon: optional
                  ? IconButton(
                      tooltip: 'No fill',
                      onPressed: () {
                        controller.clear();
                        commit();
                      },
                      icon: const Icon(Icons.format_color_reset, size: 18),
                    )
                  : null,
            ),
        onSubmitted: (_) => commit(),
        onTapOutside: (_) => commit(),
      ),
      const SizedBox(height: 10),
    ],
  );
  @override
  Widget build(BuildContext context) => Column(
    key: const ValueKey('layout-appearance'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        widget.item.kind == 'table'
            ? 'Outer borders and fill'
            : 'Borders and fill',
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 8),
      if (widget.item.kind != 'line') ...[
        const Text('Border sides', style: TextStyle(fontSize: 12)),
        Wrap(
          spacing: 4,
          children: [
            for (final side in ['top', 'right', 'bottom', 'left'])
              FilterChip(
                label: Text(side[0].toUpperCase() + side.substring(1)),
                selected: widget.item.decoration.borderSides.contains(side),
                onSelected: widget.enabled
                    ? (selected) {
                        final sides = List<String>.of(
                          widget.item.decoration.borderSides,
                        );
                        selected ? sides.add(side) : sides.remove(side);
                        commit(sides: sides);
                      }
                    : null,
              ),
          ],
        ),
        Wrap(
          children: [
            TextButton(
              onPressed: widget.enabled
                  ? () => commit(sides: ['top', 'right', 'bottom', 'left'])
                  : null,
              child: const Text('All borders'),
            ),
            TextButton(
              onPressed: widget.enabled ? () => commit(sides: []) : null,
              child: const Text('No borders'),
            ),
          ],
        ),
      ],
      TextField(
        key: const ValueKey('layout-border-width'),
        controller: _width,
        enabled: widget.enabled,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: AppTheme.dashInputDecoration(
          context,
          labelText: 'Border width (pt)',
          radius: 8,
        ),
        onSubmitted: (_) => commit(),
        onTapOutside: (_) => commit(),
      ),
      const SizedBox(height: 10),
      DropdownButtonFormField<String>(
        key: ValueKey(
          'layout-border-style-${widget.item.id}-${widget.item.decoration.borderStyle}',
        ),
        initialValue: widget.item.decoration.borderStyle,
        isExpanded: true,
        decoration: AppTheme.dashInputDecoration(
          context,
          labelText: 'Border style',
          radius: 8,
        ),
        items: const [
          DropdownMenuItem(value: 'solid', child: Text('Solid')),
          DropdownMenuItem(value: 'dashed', child: Text('Dashed')),
        ],
        onChanged: widget.enabled
            ? (v) {
                if (v != null) commit(style: v);
              }
            : null,
      ),
      const SizedBox(height: 10),
      _colorInput(
        'Border color',
        _stroke,
        const ValueKey('layout-border-color'),
      ),
      Wrap(
        spacing: 6,
        children: [
          for (final color in ['#000000', '#64748B', '#1E3A5F', '#B91C1C'])
            Tooltip(
              message: 'Border $color',
              child: InkWell(
                onTap: widget.enabled
                    ? () {
                        _stroke.text = color;
                        commit();
                      }
                    : null,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: printLayoutColor(color),
                    border: Border.all(color: AppTheme.dashHairlineOf(context)),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
        ],
      ),
      const SizedBox(height: 10),
      _colorInput(
        'Fill color',
        _fill,
        const ValueKey('layout-fill-color'),
        optional: true,
      ),
      Wrap(
        spacing: 6,
        children: [
          for (final color in ['#FFFFFF', '#EEEEEE', '#FFF3E0', '#E8EDF5'])
            Tooltip(
              message: 'Fill $color',
              child: InkWell(
                onTap: widget.enabled
                    ? () {
                        _fill.text = color;
                        commit();
                      }
                    : null,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: printLayoutColor(color),
                    border: Border.all(color: AppTheme.dashHairlineOf(context)),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
        ],
      ),
      if (_error != null)
        Text(
          _error!,
          style: TextStyle(
            color: Theme.of(context).colorScheme.error,
            fontSize: 12,
          ),
        ),
    ],
  );
}
