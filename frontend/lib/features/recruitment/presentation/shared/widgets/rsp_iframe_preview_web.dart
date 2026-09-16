import 'dart:async';

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

/// Web PDF/doc preview that does **not** use [HtmlElementView].
///
/// Flutter platform views break inside nested overlays (Applicant Details
/// drawer + preview dialog) and often navigate the iframe to a dead
/// `localhost` port ("localhost refused to connect").
/// A real DOM iframe attached to `document.body` avoids that.
class RspIframePreview extends StatefulWidget {
  const RspIframePreview({super.key, required this.url});

  final String url;

  @override
  State<RspIframePreview> createState() => _RspIframePreviewState();
}

class _RspIframePreviewState extends State<RspIframePreview> {
  web.HTMLIFrameElement? _iframe;
  Timer? _syncTimer;

  @override
  void initState() {
    super.initState();
    final iframe = web.HTMLIFrameElement()
      ..src = widget.url
      ..style.border = '0'
      ..style.position = 'fixed'
      ..style.margin = '0'
      ..style.padding = '0'
      ..style.zIndex = '2147483646'
      ..style.backgroundColor = '#ffffff'
      ..setAttribute('allowfullscreen', 'true')
      ..setAttribute('loading', 'eager')
      ..title = 'Attachment preview';
    web.document.body?.append(iframe);
    _iframe = iframe;
    var ticks = 0;
    _syncTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      _syncPosition();
      ticks += 1;
      if (ticks >= 40) timer.cancel();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncPosition());
  }

  @override
  void didUpdateWidget(covariant RspIframePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _iframe?.src = widget.url;
    }
    _syncPosition();
  }

  void _syncPosition() {
    final iframe = _iframe;
    if (iframe == null || !mounted) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) {
      iframe.style.visibility = 'hidden';
      return;
    }
    final offset = box.localToGlobal(Offset.zero);
    final size = box.size;
    if (size.width < 8 || size.height < 8) {
      iframe.style.visibility = 'hidden';
      return;
    }
    iframe.style
      ..visibility = 'visible'
      ..left = '${offset.dx}px'
      ..top = '${offset.dy}px'
      ..width = '${size.width}px'
      ..height = '${size.height}px';
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    _iframe?.remove();
    _iframe = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncPosition());
    return const SizedBox.expand();
  }
}
