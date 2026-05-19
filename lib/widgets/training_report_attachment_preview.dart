import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// How to preview a training-report attachment in the admin / L&D UI.
enum TrainingReportAttachmentPreviewKind {
  image,
  pdf,
  unsupported,
}

TrainingReportAttachmentPreviewKind classifyTrainingReportAttachment({
  String? mimeType,
  String? fileName,
}) {
  final mime = (mimeType ?? '').toLowerCase().trim();
  if (mime.startsWith('image/')) {
    return TrainingReportAttachmentPreviewKind.image;
  }
  if (mime == 'application/pdf' || mime.contains('pdf')) {
    return TrainingReportAttachmentPreviewKind.pdf;
  }

  final name = (fileName ?? '').toLowerCase().trim();
  const imageExt = ['.jpg', '.jpeg', '.png', '.gif', '.webp'];
  for (final e in imageExt) {
    if (name.endsWith(e)) return TrainingReportAttachmentPreviewKind.image;
  }
  if (name.endsWith('.pdf')) return TrainingReportAttachmentPreviewKind.pdf;

  return TrainingReportAttachmentPreviewKind.unsupported;
}

bool _inlineWebViewSupported() {
  if (kIsWeb) return true;
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
    case TargetPlatform.iOS:
    case TargetPlatform.macOS:
      return true;
    default:
      return false;
  }
}

/// Opens a dialog that previews JPG/PNG/etc. inline and PDFs in an embedded WebView
/// when supported; otherwise offers **Open in new tab**.
Future<void> showTrainingReportAttachmentPreview(
  BuildContext context, {
  required String url,
  String? fileName,
  String? mimeType,
}) {
  final kind = classifyTrainingReportAttachment(
    mimeType: mimeType,
    fileName: fileName,
  );
  return showDialog<void>(
    context: context,
    builder: (ctx) {
      return Dialog(
        insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900, maxHeight: 700),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Attachment preview',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(ctx).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                if (fileName != null && fileName.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    fileName.trim(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.black.withValues(alpha: 0.55),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: _AttachmentPreviewBody(url: url, kind: kind),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _AttachmentPreviewBody extends StatelessWidget {
  const _AttachmentPreviewBody({
    required this.url,
    required this.kind,
  });

  final String url;
  final TrainingReportAttachmentPreviewKind kind;

  @override
  Widget build(BuildContext context) {
    switch (kind) {
      case TrainingReportAttachmentPreviewKind.image:
        return ColoredBox(
          color: const Color(0xFFF5F5F5),
          child: InteractiveViewer(
            minScale: 0.5,
            maxScale: 4,
            child: Center(
              child: Image.network(
                url,
                fit: BoxFit.contain,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(),
                    ),
                  );
                },
                errorBuilder: (_, __, ___) =>
                    _OpenInTabFallback(url: url, detail: 'Could not load image.'),
              ),
            ),
          ),
        );
      case TrainingReportAttachmentPreviewKind.pdf:
        return _PdfWebViewPane(url: url);
      case TrainingReportAttachmentPreviewKind.unsupported:
        return _OpenInTabFallback(
          url: url,
          detail:
              'Preview is only available for images and PDF. Open the file in a new tab.',
        );
    }
  }
}

class _OpenInTabFallback extends StatelessWidget {
  const _OpenInTabFallback({
    required this.url,
    this.detail = 'Preview for this file type is not supported.',
  });

  final String url;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.insert_drive_file_outlined,
              size: 40,
              color: Colors.black.withValues(alpha: 0.35),
            ),
            const SizedBox(height: 12),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, height: 1.35),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () async {
                final uri = Uri.parse(url);
                await launchUrl(
                  uri,
                  mode: LaunchMode.externalApplication,
                );
              },
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              label: const Text('Open in new tab'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PdfWebViewPane extends StatefulWidget {
  const _PdfWebViewPane({required this.url});

  final String url;

  @override
  State<_PdfWebViewPane> createState() => _PdfWebViewPaneState();
}

class _PdfWebViewPaneState extends State<_PdfWebViewPane> {
  WebViewController? _controller;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    if (!_inlineWebViewSupported()) {
      _failed = true;
      return;
    }
    final uri = Uri.parse(widget.url);
    if (kIsWeb) {
      final c = WebViewController();
      _controller = c;
      c.loadRequest(uri);
      return;
    }
    final c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFFE8EAED));
    _controller = c;
    c
        .setNavigationDelegate(
          NavigationDelegate(
            onWebResourceError: (_) {
              if (mounted) setState(() => _failed = true);
            },
          ),
        )
        .then((_) => c.loadRequest(uri));
  }

  @override
  Widget build(BuildContext context) {
    if (_failed || _controller == null) {
      return _OpenInTabFallback(
        url: widget.url,
        detail:
            'Embedded PDF preview is not available on this device. Open in a new tab.',
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        WebViewWidget(controller: _controller!),
        Positioned(
          right: 8,
          bottom: 8,
          child: Material(
            color: Colors.white.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(8),
            elevation: 1,
            child: InkWell(
              onTap: () async {
                final uri = Uri.parse(widget.url);
                await launchUrl(
                  uri,
                  mode: LaunchMode.externalApplication,
                );
              },
              borderRadius: BorderRadius.circular(8),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.open_in_new_rounded, size: 16),
                    SizedBox(width: 6),
                    Text('Open', style: TextStyle(fontSize: 12)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
