import 'package:flutter/material.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import '../../../models/locator_print_layout.dart';

class PrintLayoutPageProperties extends StatefulWidget {
  const PrintLayoutPageProperties({
    super.key,
    required this.layout,
    required this.onChanged,
    this.enabled = true,
  });
  final LocatorPrintLayout layout;
  final ValueChanged<LocatorPrintLayout> onChanged;
  final bool enabled;
  @override
  State<PrintLayoutPageProperties> createState() =>
      PrintLayoutPagePropertiesState();
}

class PrintLayoutPagePropertiesState extends State<PrintLayoutPageProperties> {
  final _fontSize = TextEditingController();
  final _margins = {
    for (final side in ['top', 'right', 'bottom', 'left'])
      side: TextEditingController(),
  };
  final _original = <String, String>{};
  String? _error;
  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant PrintLayoutPageProperties oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.layout.paperSize != widget.layout.paperSize ||
        oldWidget.layout.orientation != widget.layout.orientation ||
        oldWidget.layout.fontFamily != widget.layout.fontFamily ||
        oldWidget.layout.defaultFontSize != widget.layout.defaultFontSize ||
        oldWidget.layout.margins.toJson().toString() !=
            widget.layout.margins.toJson().toString()) {
      _sync();
    }
  }

  void _sync() {
    _fontSize.text = widget.layout.defaultFontSize.toString();
    for (final e in _margins.entries) {
      e.value.text =
          ((widget.layout.margins.toJson()[e.key] as num) * 25.4 / 72)
              .toStringAsFixed(2);
      _original[e.key] = e.value.text;
    }
  }

  @override
  void dispose() {
    _fontSize.dispose();
    for (final c in _margins.values) {
      c.dispose();
    }
    super.dispose();
  }

  bool commit({LocatorPrintLayout? base}) =>
      _apply((layout) => layout, base: base);
  bool _apply(
    LocatorPrintLayout Function(LocatorPrintLayout) transform, {
    LocatorPrintLayout? base,
  }) {
    final current = base ?? widget.layout;
    final size = double.tryParse(_fontSize.text);
    final values = <String, double>{};
    for (final e in _margins.entries) {
      final v = double.tryParse(e.value.text);
      if (v == null || !v.isFinite) {
        setState(() => _error = 'Enter valid margins in millimetres.');
        return false;
      }
      values[e.key] = e.value.text == _original[e.key]
          ? (current.margins.toJson()[e.key] as num).toDouble()
          : v * 72 / 25.4;
    }
    if (size == null || !size.isFinite) {
      setState(() => _error = 'Enter a valid default font size.');
      return false;
    }
    final next = transform(
      current
          .withPageSettings(margins: PrintLayoutMargins.fromJson(values))
          .copyWith(defaultFontSize: size),
    );
    final error =
        next.pageSettingsError() ??
        (next.elements.isEmpty ? null : next.validate());
    if (error != null) {
      setState(() => _error = error);
      return false;
    }
    setState(() => _error = null);
    if (next.toJson().toString() != current.toJson().toString()) {
      widget.onChanged(next);
    }
    return true;
  }

  InputDecoration _decoration(String label) =>
      AppTheme.dashInputDecoration(context, labelText: label, radius: 8);
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (_error != null)
        Text(_error!, style: const TextStyle(color: Colors.red)),
      DropdownButtonFormField<String>(
        key: ValueKey('paper-${widget.layout.paperSize}'),
        initialValue: widget.layout.paperSize,
        isExpanded: true,
        decoration: _decoration('Paper size'),
        items: [
          for (final e in printPaperLabels.entries)
            DropdownMenuItem(
              value: e.key,
              child: Text(e.value, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: widget.enabled
            ? (v) {
                if (v != null) {
                  _apply((layout) => layout.withPageSettings(paperSize: v));
                }
              }
            : null,
      ),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(
        key: ValueKey('orientation-${widget.layout.orientation}'),
        initialValue: widget.layout.orientation,
        decoration: _decoration('Orientation'),
        items: const [
          DropdownMenuItem(value: 'portrait', child: Text('Portrait')),
          DropdownMenuItem(value: 'landscape', child: Text('Landscape')),
        ],
        onChanged: widget.enabled
            ? (v) {
                if (v != null) {
                  _apply((layout) => layout.withPageSettings(orientation: v));
                }
              }
            : null,
      ),
      const SizedBox(height: 16),
      const Text('Margins (mm)', style: TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final e in _margins.entries)
            SizedBox(
              width: 124,
              child: TextField(
                key: ValueKey('margin-${e.key}'),
                controller: e.value,
                enabled: widget.enabled,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: _decoration(
                  '${e.key[0].toUpperCase()}${e.key.substring(1)}',
                ),
                onSubmitted: (_) => commit(),
              ),
            ),
        ],
      ),
      const SizedBox(height: 16),
      DropdownButtonFormField<String>(
        key: ValueKey('default-family-${widget.layout.fontFamily}'),
        initialValue: widget.layout.fontFamily ?? 'legacy',
        isExpanded: true,
        decoration: _decoration('Default font family'),
        items: [
          const DropdownMenuItem(
            value: 'legacy',
            child: Text('Original template font'),
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
        onChanged: widget.enabled
            ? (v) {
                if (v != null) {
                  _apply(
                    (layout) => layout.copyWith(
                      fontFamily: v == 'legacy' ? null : v,
                      inheritFont: v == 'legacy',
                    ),
                  );
                }
              }
            : null,
      ),
      const SizedBox(height: 12),
      TextField(
        key: const ValueKey('default-font-size'),
        controller: _fontSize,
        enabled: widget.enabled,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: _decoration('Default font size (pt)'),
        onSubmitted: (_) => commit(),
      ),
      const SizedBox(height: 8),
      const Text(
        'Font size applies to new elements. Individual elements can override the font family and size.',
        style: TextStyle(fontSize: 12),
      ),
    ],
  );
}
