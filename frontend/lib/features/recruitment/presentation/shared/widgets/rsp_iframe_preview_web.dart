import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

/// Minimal web-only inline preview for PDFs/docs using an `<iframe>`.
class RspIframePreview extends StatefulWidget {
  const RspIframePreview({super.key, required this.url});

  final String url;

  @override
  State<RspIframePreview> createState() => _RspIframePreviewState();
}

class _RspIframePreviewState extends State<RspIframePreview> {
  static int _counter = 0;
  late final String _viewType;

  @override
  void initState() {
    super.initState();
    _viewType = 'rsp-attachment-iframe-${_counter++}';
    final src = widget.url;

    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
      final iframe = web.HTMLIFrameElement()
        ..src = src
        ..style.border = '0'
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.backgroundColor = '#ffffff'
        ..setAttribute('allowfullscreen', 'true')
        ..setAttribute('loading', 'eager')
        ..title = 'Attachment preview';
      return iframe;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(child: HtmlElementView(viewType: _viewType));
  }
}
