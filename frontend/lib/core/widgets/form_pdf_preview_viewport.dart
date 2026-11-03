import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';

enum _PreviewFit { page, width }

/// A view-only transform of rasterized pages. PDF generation, printing and
/// sharing remain owned by PdfPreview and never use this transform.
class FormPdfPreviewViewport extends StatefulWidget {
  const FormPdfPreviewViewport({
    super.key,
    required this.pages,
    required this.rasterDpi,
  }) : assert(rasterDpi > 0);

  final List<PdfPreviewPageData> pages;
  final double rasterDpi;

  @override
  State<FormPdfPreviewViewport> createState() => _FormPdfPreviewViewportState();
}

class _FormPdfPreviewViewportState extends State<FormPdfPreviewViewport> {
  static const _minScale = .1;
  static const _maxScale = 4.0;
  static const _padding = 16.0;
  static const _gap = 16.0;
  final _controller = TransformationController();
  Size _viewport = Size.zero;
  Size _scene = Size.zero;
  double _firstPageHeight = 0;
  _PreviewFit? _fitMode = _PreviewFit.width;

  double get _scale => _controller.value.getMaxScaleOnAxis();
  Offset get _translation {
    final value = _controller.value.getTranslation();
    return Offset(value.x, value.y);
  }

  @override
  void initState() {
    super.initState();
    _controller.addListener(_changed);
  }

  void _changed() {
    setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_changed);
    _controller.dispose();
    super.dispose();
  }

  void _setView(double scale, Offset translation) {
    double bound(double offset, double page, double viewport) {
      if (page <= viewport) return (viewport - page) / 2;
      return offset.clamp(viewport - page, 0).toDouble();
    }

    final x = bound(translation.dx, _scene.width * scale, _viewport.width);
    final y = bound(translation.dy, _scene.height * scale, _viewport.height);
    _controller.value = Matrix4.identity()
      ..setEntry(0, 0, scale)
      ..setEntry(1, 1, scale)
      ..setEntry(2, 2, scale)
      ..setEntry(0, 3, x)
      ..setEntry(1, 3, y);
  }

  void _zoom(double requested, [Offset? focalPoint]) {
    _fitMode = null;
    final focal = focalPoint ?? _viewport.center(Offset.zero);
    final scenePoint = _controller.toScene(focal);
    final scale = requested.clamp(_minScale, _maxScale).toDouble();
    _setView(scale, focal - scenePoint * scale);
  }

  void _fit(_PreviewFit mode) {
    _fitMode = mode;
    var scale = _viewport.width / _scene.width;
    if (mode == _PreviewFit.page) {
      scale = math.min(
        scale,
        _viewport.height / (_firstPageHeight + _padding * 2),
      );
    }
    _setView(scale.clamp(_minScale, _maxScale).toDouble(), Offset.zero);
  }

  void _scroll(PointerSignalEvent event) {
    if (event is PointerScaleEvent) {
      // InteractiveViewer handles trackpad pinch; claim the event so the web
      // host does not also zoom the entire browser page.
      GestureBinding.instance.pointerSignalResolver.register(event, (_) {});
      return;
    }
    if (event is! PointerScrollEvent) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (resolved) {
      _handleScroll(resolved as PointerScrollEvent);
    });
  }

  void _handleScroll(PointerScrollEvent event) {
    if (HardwareKeyboard.instance.isControlPressed) {
      // Clamp the exponent too: some wheels report very large deltas.
      final factor = math.exp((-event.scrollDelta.dy / 300).clamp(-4, 4));
      _zoom(_scale * factor, event.localPosition);
    } else {
      _setView(_scale, _translation - event.scrollDelta);
    }
  }

  Widget _toolbar(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surface,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 4,
        children: [
          IconButton(
            tooltip: 'Zoom out',
            onPressed: _scale <= _minScale + .0001
                ? null
                : () => _zoom(_scale / 1.2),
            icon: const Icon(Icons.remove_rounded),
          ),
          SizedBox(
            width: 52,
            child: Semantics(
              label: 'Preview zoom',
              value: '${(_scale * 100).round()} percent',
              child: Text(
                '${(_scale * 100).round()}%',
                textAlign: TextAlign.center,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Zoom in',
            onPressed: _scale >= _maxScale - .0001
                ? null
                : () => _zoom(_scale * 1.2),
            icon: const Icon(Icons.add_rounded),
          ),
          TextButton(
            onPressed: () => _fit(_PreviewFit.page),
            child: const Text('Fit page'),
          ),
          TextButton(
            onPressed: () => _fit(_PreviewFit.width),
            child: const Text('Fit width'),
          ),
          const Tooltip(
            message:
                'Ctrl + mouse wheel to zoom. Scroll to move through pages. Pinch to zoom on touch screens. Preview zoom does not change the printed form.',
            child: Padding(
              padding: EdgeInsets.all(8),
              child: Icon(Icons.info_outline_rounded, size: 18),
            ),
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (widget.pages.isEmpty) return const SizedBox.shrink();
    // At 72 logical pixels per inch the zoom percentage stays independent of
    // screen density and viewport size. Images are rasterized at a fixed DPI.
    final sizes = widget.pages
        .map(
          (page) => Size(
            page.width * 72 / widget.rasterDpi,
            page.height * 72 / widget.rasterDpi,
          ),
        )
        .toList();
    final scene = Size(
      sizes.map((size) => size.width).reduce(math.max) + _padding * 2,
      sizes.fold<double>(0, (sum, size) => sum + size.height) +
          _gap * (sizes.length - 1) +
          _padding * 2,
    );
    return Column(
      children: [
        _toolbar(context),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final viewport = constraints.biggest;
              if (_viewport != viewport || _scene != scene) {
                _viewport = viewport;
                _scene = scene;
                _firstPageHeight = sizes.first.height;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted || _viewport.isEmpty) return;
                  final fit = _fitMode;
                  if (fit != null) {
                    _fit(fit);
                  } else {
                    _setView(_scale, _translation);
                  }
                });
              }
              return Listener(
                key: const ValueKey('pdf-preview-viewport'),
                behavior: HitTestBehavior.opaque,
                onPointerSignal: _scroll,
                child: InteractiveViewer(
                  transformationController: _controller,
                  alignment: Alignment.topLeft,
                  constrained: false,
                  minScale: _minScale,
                  maxScale: _maxScale,
                  // Handle wheel signals above, keeping ordinary scroll separate
                  // from Ctrl + wheel. Touch/trackpad pinch still uses the viewer.
                  scaleFactor: double.infinity,
                  trackpadScrollCausesScale: true,
                  onInteractionUpdate: (details) {
                    if (details.scale != 1) _fitMode = null;
                  },
                  child: SizedBox(
                    key: const ValueKey('pdf-preview-pages'),
                    width: scene.width,
                    height: scene.height,
                    child: Padding(
                      padding: const EdgeInsets.all(_padding),
                      child: Column(
                        children: [
                          for (var i = 0; i < widget.pages.length; i++) ...[
                            if (i > 0) const SizedBox(height: _gap),
                            Container(
                              width: sizes[i].width,
                              height: sizes[i].height,
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black26,
                                    blurRadius: 4,
                                    offset: Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Image(
                                image: widget.pages[i].image,
                                fit: BoxFit.fill,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
