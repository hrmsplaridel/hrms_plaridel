import 'package:flutter/material.dart';

/// Stub when not compiling for web; never shown when used only under `kIsWeb`.
class RspIframePreview extends StatelessWidget {
  const RspIframePreview({super.key, required this.url});

  final String url;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
