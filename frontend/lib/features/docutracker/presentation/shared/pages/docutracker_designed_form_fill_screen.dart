import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import 'package:hrms_plaridel/features/docutracker/data/providers/docutracker_provider.dart';
import 'package:hrms_plaridel/features/docutracker/models/document.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_builder.dart';
import 'package:hrms_plaridel/features/docutracker/models/docutracker_memo_template.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/pages/docutracker_document_builder_screen.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/widgets/docutracker_builder_chrome.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/widgets/docutracker_error_banner.dart';
import 'package:hrms_plaridel/features/docutracker/theme/docutracker_tokens.dart';
import 'package:hrms_plaridel/features/docutracker/utils/docutracker_designed_form_fill.dart';
import 'package:hrms_plaridel/features/docutracker/utils/docutracker_designed_print.dart';
import 'package:hrms_plaridel/features/docutracker/utils/docutracker_print_layout.dart';
import 'package:hrms_plaridel/features/dtr/locator/models/locator_print_layout.dart';

/// Employee fill surface for types with a saved Printed Form layout.
///
/// Shows the admin-designed page (including Memo overrides). Employees edit
/// designated field insides only. Layout chrome, shapes, background, and
/// signature slots stay fixed to the designed positions.
class DocuTrackerDesignedFormFillScreen extends StatefulWidget {
  const DocuTrackerDesignedFormFillScreen({super.key, required this.document});

  final DocuTrackerDocument document;

  @override
  State<DocuTrackerDesignedFormFillScreen> createState() =>
      _DocuTrackerDesignedFormFillScreenState();
}

class _DocuTrackerDesignedFormFillScreenState
    extends State<DocuTrackerDesignedFormFillScreen> {
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, FocusNode> _focusNodes = {};

  DocuTrackerDocument? _document;
  DocuTrackerDocumentBuilderData? _builder;
  DocuTrackerMemoTemplate? _memo;
  LocatorPrintLayout? _layout;
  Uint8List? _backgroundPng;
  List<DocuTrackerSignatureField> _signatureFields = const [];
  String? _error;
  bool _loading = true;
  bool _saving = false;
  bool _dirty = false;
  bool _canEdit = false;
  double _zoom = 1;
  bool _fitWidth = true;

  DocuTrackerDocument get _doc => _document ?? widget.document;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    for (final node in _focusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final documentId = widget.document.id?.trim() ?? '';
    if (documentId.isEmpty) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Save the draft before opening this form.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final provider = context.read<DocuTrackerProvider>();
      final latest =
          await provider.fetchDocument(documentId) ?? widget.document;
      final config = await loadDocuTrackerDocumentPrintConfig(documentId);
      if (!mounted) return;

      if (config == null) {
        // No published printed form: use the free document builder instead.
        if (!mounted) return;
        final navigator = Navigator.of(context);
        await navigator.pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => DocuTrackerDocumentBuilderScreen(document: latest),
          ),
        );
        return;
      }

      Uint8List? backgroundPng;
      if (config.hasBackground) {
        backgroundPng = await _loadBackgroundPng(documentId);
      }

      final builder = await provider.loadDocumentBuilder(documentId);
      if (!mounted) return;

      final memo = builder?.pages.isNotEmpty == true
          ? builder!.pages.first.memo
          : null;

      _disposeEditors();
      final values = docuTrackerFillValuesFromDocument(latest, memo: memo);
      for (final element in config.layout.elements) {
        if (element.kind != 'field') continue;
        final source = element.source.trim();
        if (source.isEmpty) continue;
        _controllers.putIfAbsent(
          source,
          () => TextEditingController(text: values[source] ?? ''),
        );
        _focusNodes.putIfAbsent(source, FocusNode.new);
      }

      setState(() {
        _document = latest;
        _builder = builder;
        _memo = memo;
        _layout = config.layout;
        _backgroundPng = backgroundPng;
        _signatureFields = builder?.signatureFields ?? const [];
        _canEdit = builder?.canEditLayout == true;
        _dirty = false;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load the printed form for this document.';
      });
    }
  }

  Future<Uint8List?> _loadBackgroundPng(String documentId) async {
    try {
      final bytes = await context
          .read<DocuTrackerProvider>()
          .loadDocumentPrintBackground(documentId);
      if (bytes == null || bytes.isEmpty) return null;
      final raster = await Printing.raster(
        bytes,
        pages: const [0],
        dpi: 96,
      ).first.timeout(const Duration(seconds: 15));
      return await raster.toPng();
    } catch (_) {
      return null;
    }
  }

  void _disposeEditors() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    for (final node in _focusNodes.values) {
      node.dispose();
    }
    _controllers.clear();
    _focusNodes.clear();
  }

  void _markDirty() {
    if (_dirty) return;
    setState(() => _dirty = true);
  }

  Future<bool> _save() async {
    if (!_canEdit || _saving) return false;
    final documentId = _doc.id;
    if (documentId == null) return false;

    final subject = _controllers['subject']?.text.trim();
    final title =
        (_controllers['title']?.text.trim().isNotEmpty == true
            ? _controllers['title']!.text.trim()
            : null) ??
        (subject?.isNotEmpty == true ? subject : null) ??
        _doc.title;
    final body =
        (_controllers['body'] ?? _controllers['description'])?.text ??
        _doc.description;

    setState(() {
      _saving = true;
      _error = null;
    });
    final provider = context.read<DocuTrackerProvider>();
    try {
      DocuTrackerMemoTemplate? nextMemo = _memo;
      final builder = _builder;
      if (docuTrackerDocumentIsMemo(_doc) && builder != null) {
        nextMemo = DocuTrackerMemoTemplate(
          to: _controllers['to']?.text ?? _memo?.to ?? '',
          subject:
              subject ??
              _controllers['title']?.text ??
              _memo?.subject ??
              title,
          date: _controllers['date']?.text ?? _memo?.date ?? '',
          cc: _controllers['cc']?.text ?? _memo?.cc ?? '',
        );
        final pages = <DocuTrackerDocumentPage>[
          if (builder.pages.isEmpty)
            DocuTrackerDocumentPage(delta: const [], memo: nextMemo)
          else
            for (var i = 0; i < builder.pages.length; i++)
              i == 0
                  ? DocuTrackerDocumentPage(
                      delta: builder.pages[i].delta,
                      memo: nextMemo,
                    )
                  : builder.pages[i],
        ];
        final savedBuilder = await provider.saveDocumentBuilder(
          documentId: documentId,
          pages: pages,
          signatureFields: builder.signatureFields,
          revision: builder.revision,
        );
        if (!mounted) return false;
        if (savedBuilder == null) {
          setState(() {
            _saving = false;
            _error = provider.builderError ?? 'Could not save the form.';
          });
          return false;
        }
        _builder = savedBuilder;
        _memo = savedBuilder.pages.isNotEmpty
            ? savedBuilder.pages.first.memo
            : nextMemo;
        _signatureFields = savedBuilder.signatureFields;
      }

      final updated = await provider.updateDocumentMetadata(
        documentId: documentId,
        title: title.isEmpty ? _doc.title : title,
        description: body,
      );
      if (!mounted) return false;
      if (updated == null) {
        setState(() {
          _saving = false;
          _error = provider.error ?? 'Could not save the form.';
        });
        return false;
      }
      final values = docuTrackerFillValuesFromDocument(
        updated,
        memo: _memo ?? nextMemo,
      );
      for (final entry in _controllers.entries) {
        final next = values[entry.key];
        if (next != null && entry.value.text != next) {
          entry.value.text = next;
        }
      }
      setState(() {
        _document = updated;
        _saving = false;
        _dirty = false;
      });
      return true;
    } catch (_) {
      if (!mounted) return false;
      setState(() {
        _saving = false;
        _error = 'Could not save the form.';
      });
      return false;
    }
  }

  Future<void> _openBuilderForSignatures() async {
    if (_dirty && _canEdit) {
      final saved = await _save();
      if (!saved || !mounted) return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => DocuTrackerDocumentBuilderScreen(document: _doc),
      ),
    );
    if (mounted) await _load();
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent ||
        event.scrollDelta.dy == 0 ||
        _loading ||
        _saving) {
      return;
    }
    final keys = HardwareKeyboard.instance;
    if (!(keys.isControlPressed || keys.isMetaPressed)) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (resolved) {
      final scroll = resolved as PointerScrollEvent;
      final factor = math.exp((-scroll.scrollDelta.dy / 300).clamp(-4.0, 4.0));
      if (!mounted) return;
      setState(() {
        _fitWidth = false;
        _zoom = (_zoom * factor).clamp(0.5, 3.0);
      });
    });
  }

  Future<bool> _onWillPop() async {
    if (!_dirty || !_canEdit) return true;
    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Unsaved changes'),
        content: const Text('Save your form before leaving?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop('discard'),
            child: const Text('Discard'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop('cancel'),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop('save'),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (action == 'cancel' || action == null) return false;
    if (action == 'discard') return true;
    return _save();
  }

  @override
  Widget build(BuildContext context) {
    final layout = _layout;
    return PopScope(
      canPop: !(_dirty && _canEdit),
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        if (await _onWillPop() && mounted) {
          navigator.pop();
        }
      },
      child: Scaffold(
        backgroundColor: DocuTrackerTokens.canvasOf(context),
        appBar: AppBar(
          title: Text(_doc.title.isEmpty ? 'Fill form' : _doc.title),
          actions: [
            if (_canEdit)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilledButton.tonalIcon(
                  key: const ValueKey('docutracker-fill-save'),
                  onPressed: _saving || !_dirty
                      ? null
                      : () => unawaited(_save()),
                  icon: _saving
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          _dirty
                              ? Icons.save_outlined
                              : Icons.check_circle_outline,
                        ),
                  label: Text(_saving ? 'Saving…' : 'Save Draft'),
                ),
              ),
            IconButton(
              tooltip: 'Signatures',
              onPressed: _loading
                  ? null
                  : () => unawaited(_openBuilderForSignatures()),
              icon: const Icon(Icons.draw_outlined),
            ),
          ],
        ),
        body: Column(
          children: [
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(8),
                child: DocuTrackerErrorBanner(message: _error!),
              ),
            if (!_loading && layout != null)
              Material(
                color: DocuTrackerTokens.brandSoftOf(
                  context,
                ).withValues(alpha: 0.45),
                child: const Padding(
                  padding: EdgeInsets.fromLTRB(14, 10, 14, 10),
                  child: Row(
                    children: [
                      Icon(Icons.edit_note_rounded, size: 18),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Fill the fields on this form. Labels, background, and '
                          'signature places stay fixed by the administrator.',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : layout == null
                  ? const Center(child: Text('Printed form unavailable.'))
                  : Listener(
                      onPointerSignal: _onPointerSignal,
                      child: _buildCanvas(layout),
                    ),
            ),
            DocuTrackerBuilderCanvasBar(
              pageLabel: 'Page 1 of 1',
              zoomLabel: '${(_zoom * 100).round()}%',
              pageCount: 1,
              enabled: !_loading && !_saving,
              canGoPrevious: false,
              canGoNext: false,
              onPrevious: null,
              onNext: null,
              onPickPage: (_) {},
              canZoomOut: !_loading && _zoom > 0.5,
              canZoomIn: !_loading && _zoom < 3,
              onZoomOut: () => setState(() {
                _fitWidth = false;
                _zoom = (_zoom - 0.1).clamp(0.5, 3.0);
              }),
              onZoomIn: () => setState(() {
                _fitWidth = false;
                _zoom = (_zoom + 0.1).clamp(0.5, 3.0);
              }),
              onFitPage: () => setState(() {
                _fitWidth = false;
                _zoom = 1;
              }),
              onFitWidth: () => setState(() {
                _fitWidth = true;
                _zoom = 1;
              }),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCanvas(LocatorPrintLayout layout) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final pad = MediaQuery.sizeOf(context).width < 600 ? 10.0 : 20.0;
        final pageW = layout.pageWidth;
        final pageH = layout.pageHeight;
        final widthFit = math.max(
          0.01,
          (constraints.maxWidth - pad * 2) / pageW,
        );
        final heightFit = math.max(
          0.01,
          (constraints.maxHeight - pad * 2) / pageH,
        );
        final scale =
            (_fitWidth ? widthFit : math.min(widthFit, heightFit)) * _zoom;
        return SingleChildScrollView(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: constraints.maxWidth,
                minHeight: constraints.maxHeight,
              ),
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(pad),
                  child: SizedBox(
                    width: pageW * scale,
                    height: pageH * scale,
                    child: FittedBox(
                      fit: BoxFit.fill,
                      child: SizedBox(
                        width: pageW,
                        height: pageH,
                        child: _buildPage(layout),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPage(LocatorPrintLayout layout) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 28,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        children: [
          if (_backgroundPng != null)
            Positioned.fill(
              child: Image.memory(_backgroundPng!, fit: BoxFit.fill),
            ),
          for (final element in layout.elements) _buildElement(element),
        ],
      ),
    );
  }

  Widget _buildElement(LocatorPrintElement element) {
    final child = switch (element.kind) {
      'text' => _fixedText(element),
      'field' => _fieldEditor(element),
      'signature' => _signatureSlot(element),
      'line' => CustomPaint(painter: _LinePainter(element)),
      'rectangle' => DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(
            color: Colors.black87,
            width: math.max(0.6, element.decoration.borderWidth),
          ),
          color: element.decoration.fillColor == null
              ? Colors.transparent
              : const Color(0x14000000),
        ),
      ),
      'table' => _staticTable(element),
      _ => const SizedBox.shrink(),
    };
    return Positioned(
      left: element.x,
      top: element.y,
      width: element.width,
      height: element.height,
      child: child,
    );
  }

  Widget _fixedText(LocatorPrintElement element) {
    return IgnorePointer(
      child: Align(
        alignment: _align(element.align),
        child: Text(
          element.text,
          style: TextStyle(
            color: Colors.black,
            fontSize: element.fontSize,
            fontWeight: element.bold ? FontWeight.w700 : FontWeight.w400,
            fontFamily: element.fontFamily,
          ),
        ),
      ),
    );
  }

  Widget _fieldEditor(LocatorPrintElement element) {
    final source = element.source.trim();
    final writable =
        _canEdit && !_saving && docuTrackerFillSourceIsWritable(source);
    final controller = _controllers[source];
    final focusNode = _focusNodes[source];
    final label = element.showLabel ? element.label.trim() : '';

    if (controller == null || focusNode == null) {
      return _readOnlyValue(
        element,
        docuTrackerFillValuesFromDocument(_doc)[source] ?? '',
      );
    }

    return AnimatedBuilder(
      animation: focusNode,
      builder: (context, _) {
        final focused = focusNode.hasFocus;
        return DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(
              color: focused && writable
                  ? DocuTrackerTokens.brand
                  : Colors.transparent,
              width: focused && writable ? 1.5 : 0,
            ),
            color: focused && writable
                ? DocuTrackerTokens.brand.withValues(alpha: 0.06)
                : Colors.transparent,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (label.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 2, right: 2, top: 1),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: math.max(8, element.fontSize - 2),
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                ),
              Expanded(
                child: TextField(
                  key: ValueKey('docutracker-fill-field-$source'),
                  controller: controller,
                  focusNode: focusNode,
                  readOnly: !writable,
                  maxLines: null,
                  expands: true,
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: element.fontSize,
                    fontWeight: element.bold
                        ? FontWeight.w700
                        : FontWeight.w400,
                    fontFamily: element.fontFamily,
                  ),
                  textAlign: switch (element.align) {
                    'center' => TextAlign.center,
                    'right' => TextAlign.right,
                    _ => TextAlign.left,
                  },
                  decoration: const InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                  ),
                  onChanged: writable ? (_) => _markDirty() : null,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _readOnlyValue(LocatorPrintElement element, String value) {
    final label = element.showLabel ? element.label.trim() : '';
    return IgnorePointer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (label.isNotEmpty)
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: math.max(8, element.fontSize - 2),
                fontWeight: FontWeight.w600,
              ),
            ),
          Expanded(
            child: Align(
              alignment: _align(element.align),
              child: Text(
                value,
                style: TextStyle(
                  color: Colors.black,
                  fontSize: element.fontSize,
                  fontWeight: element.bold ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _signatureSlot(LocatorPrintElement element) {
    final source = element.source.trim();
    DocuTrackerSignatureField? field;
    for (final candidate in _signatureFields) {
      final label = candidate.label.toLowerCase();
      final key = source.replaceAll('_', ' ');
      final catalog =
          docuTrackerPrintLayoutSignatures()[source]?.toLowerCase() ?? '';
      if (label.contains(key) ||
          key.contains(label) ||
          (catalog.isNotEmpty && catalog == label)) {
        field = candidate;
        break;
      }
    }
    final bytes = field?.signatureImageBytes;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.black54, width: 0.8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: bytes != null && bytes.isNotEmpty
                ? Image.memory(bytes, fit: BoxFit.contain)
                : const SizedBox.shrink(),
          ),
          Text(
            element.showLabel
                ? (element.label.trim().isEmpty
                      ? (docuTrackerPrintLayoutSignatures()[source] ?? source)
                      : element.label)
                : '',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: element.fontSize, color: Colors.black87),
          ),
        ],
      ),
    );
  }

  Widget _staticTable(LocatorPrintElement element) {
    if (element.cells.isEmpty) return const SizedBox.shrink();
    return Table(
      border: element.borders
          ? TableBorder.all(color: Colors.black87, width: 0.6)
          : null,
      children: [
        for (final row in element.cells)
          TableRow(
            children: [
              for (final cell in row)
                Padding(
                  padding: const EdgeInsets.all(3),
                  child: Text(
                    cell.kind == 'field'
                        ? (docuTrackerFillValuesFromDocument(
                                _doc,
                              )[cell.source] ??
                              '')
                        : cell.text,
                    style: TextStyle(
                      fontSize: element.fontSize,
                      color: Colors.black,
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }

  Alignment _align(String align) => switch (align) {
    'center' => Alignment.center,
    'right' => Alignment.centerRight,
    _ => Alignment.centerLeft,
  };
}

class _LinePainter extends CustomPainter {
  _LinePainter(this.element);
  final LocatorPrintElement element;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black87
      ..strokeWidth = math.max(0.8, element.decoration.borderWidth);
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _LinePainter oldDelegate) =>
      oldDelegate.element != element;
}
