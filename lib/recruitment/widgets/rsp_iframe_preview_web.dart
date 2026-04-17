// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';

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

    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
      final iframe = html.IFrameElement()
        ..src = widget.url
        ..style.border = '0'
        ..style.width = '100%'
        ..style.height = '100%';
      return iframe;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(child: HtmlElementView(viewType: _viewType));
  }
}
