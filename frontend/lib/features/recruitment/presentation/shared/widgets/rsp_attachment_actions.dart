import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/recruitment/models/recruitment_application.dart';
import 'package:hrms_plaridel/features/recruitment/presentation/shared/widgets/rsp_iframe_preview.dart';

/// Preview + download controls for RSP applicant attachments (admin).
class RspAttachmentActions extends StatelessWidget {
  const RspAttachmentActions({
    super.key,
    required this.path,
    required this.fileName,
  });

  final String path;
  final String fileName;

  Future<String?> _resolveUrl() =>
      RecruitmentRepo.instance.getAttachmentDownloadUrl(
        path,
        fileName: fileName,
      );

  Future<void> _preview(BuildContext context) async {
    final url = await _resolveUrl();
    if (url != null && context.mounted) {
      if (kIsWeb) {
        showRspAttachmentPreviewDialog(
          context,
          url: url,
          fileName: fileName,
          objectPath: path,
        );
        return;
      }

      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not create attachment link. Restart the API and verify '
            'storage configuration.',
          ),
        ),
      );
    }
  }

  Future<void> _download(BuildContext context) async {
    final url = await _resolveUrl();
    if (url != null && context.mounted) {
      final uri = Uri.parse(url).replace(
        queryParameters: {...Uri.parse(url).queryParameters, 'download': '1'},
      );
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not get download link.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final linkColor = AppTheme.dashIsDark(context)
        ? AppTheme.primaryNavyLight
        : AppTheme.primaryNavy;
    return Row(
      children: [
        Expanded(
          child: Text(
            fileName,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppTheme.dashTextPrimaryOf(context),
            ),
          ),
        ),
        IconButton(
          tooltip: 'View — $fileName',
          onPressed: () => _preview(context),
          icon: const Icon(Icons.visibility_outlined, size: 20),
          style: IconButton.styleFrom(
            foregroundColor: linkColor,
            padding: const EdgeInsets.all(4),
            minimumSize: const Size(32, 32),
          ),
        ),
        IconButton(
          tooltip: 'Download — $fileName',
          onPressed: () => _download(context),
          icon: const Icon(Icons.download_rounded, size: 20),
          style: IconButton.styleFrom(
            foregroundColor: linkColor,
            padding: const EdgeInsets.all(4),
            minimumSize: const Size(32, 32),
          ),
        ),
      ],
    );
  }
}

bool _isImageExt(String ext) {
  return const <String>[
    'png',
    'jpg',
    'jpeg',
    'gif',
    'tif',
    'tiff',
    'webp',
    'bmp',
  ].contains(ext.toLowerCase());
}

String _extractExt(String fileName) {
  final lower = fileName.toLowerCase();
  final dot = lower.lastIndexOf('.');
  if (dot == -1 || dot == lower.length - 1) return '';
  return lower.substring(dot + 1);
}

String _withPreviewParam(String url) {
  final uri = Uri.parse(url);
  final qp = <String, String>{...uri.queryParameters};
  qp['preview'] = '1';
  qp.remove('download');
  return uri.replace(queryParameters: qp).toString();
}

Future<void> _openExternal(String url) async {
  final uri = Uri.parse(url);
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

/// Same PDF preview UX as Applications: dialog + browser PDF viewer in an iframe
/// (toolbar, thumbnails, zoom) via the direct attachment URL.
void showRspAttachmentPreviewDialog(
  BuildContext context, {
  required String url,
  required String fileName,
  required String objectPath,
}) {
  showDialog<void>(
    context: context,
    builder: (ctx) => _RspAttachmentPreviewDialog(
      url: url,
      fileName: fileName,
      objectPath: objectPath,
    ),
  );
}

class _RspAttachmentPreviewDialog extends StatefulWidget {
  const _RspAttachmentPreviewDialog({
    required this.url,
    required this.fileName,
    required this.objectPath,
  });

  final String url;
  final String fileName;
  final String objectPath;

  @override
  State<_RspAttachmentPreviewDialog> createState() =>
      _RspAttachmentPreviewDialogState();
}

class _RspAttachmentPreviewDialogState
    extends State<_RspAttachmentPreviewDialog> {
  bool _checking = true;
  String? _error;
  late final String _previewUrl;
  late final bool _isImage;
  late final bool _isPdfOrOffice;

  @override
  void initState() {
    super.initState();
    final ext = _extractExt(widget.fileName).isNotEmpty
        ? _extractExt(widget.fileName)
        : _extractExt(widget.objectPath);
    _isImage = _isImageExt(ext);
    final lower = ext.toLowerCase();
    final isPdf = lower == 'pdf';
    final isWord = const {
      'doc',
      'docx',
      'xls',
      'xlsx',
      'ppt',
      'pptx',
    }.contains(lower);
    _isPdfOrOffice = isPdf || isWord;
    _previewUrl = isWord ? _withPreviewParam(widget.url) : widget.url;
    _preflight();
  }

  Future<void> _preflight() async {
    // Quick existence check so missing files show a clear message instead of
    // Chrome's JSON pretty-print inside the iframe.
    try {
      final res = await Dio().head<void>(
        _previewUrl,
        options: Options(
          followRedirects: true,
          validateStatus: (s) => s != null && s < 600,
        ),
      );
      final status = res.statusCode ?? 0;
      final contentType =
          (res.headers.value('content-type') ?? '').toLowerCase();
      final looksJson = contentType.contains('application/json');
      final looksHtmlError =
          status >= 400 && contentType.contains('text/html');

      if (status >= 400 || looksJson || looksHtmlError) {
        if (!mounted) return;
        setState(() {
          _checking = false;
          _error =
              'Attachment file is missing on the server. Ask the applicant to '
              're-upload this PDF, or restore it from backup.';
        });
        return;
      }
      if (!mounted) return;
      setState(() {
        _checking = false;
        _error = null;
      });
    } catch (_) {
      // If HEAD fails (CORS etc.), still try the iframe — Applications style.
      if (!mounted) return;
      setState(() {
        _checking = false;
        _error = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.sizeOf(context);
    final dialogW = (media.width - 48).clamp(320.0, 960.0);
    final dialogH = (media.height - 48).clamp(420.0, 820.0);
    final downloadUri = Uri.parse(widget.url).replace(
      queryParameters: {
        ...Uri.parse(widget.url).queryParameters,
        'download': '1',
      },
    );

    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: dialogW,
        height: dialogH,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.fileName.isNotEmpty
                          ? widget.fileName
                          : 'Attachment preview',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Open in new tab',
                    onPressed: () => _openExternal(widget.url),
                    icon: const Icon(Icons.open_in_new_rounded),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppTheme.dashMutedSurfaceOf(context),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.dashHairlineOf(context)),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: _buildBody(context),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  TextButton.icon(
                    onPressed: () => _openExternal(downloadUri.toString()),
                    icon: const Icon(Icons.download_rounded, size: 18),
                    label: const Text('Download'),
                  ),
                  FilledButton.icon(
                    onPressed: () => _openExternal(widget.url),
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: const Text('Open file'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_checking) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.broken_image_outlined,
                size: 42,
                color: AppTheme.dashTextSecondaryOf(context),
              ),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.45,
                  color: AppTheme.dashTextPrimaryOf(context),
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    _checking = true;
                    _error = null;
                  });
                  _preflight();
                },
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_isImage) {
      return InteractiveViewer(
        minScale: 0.5,
        maxScale: 4,
        child: Center(
          child: Image.network(
            widget.url,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => _PreviewFallback(url: widget.url),
          ),
        ),
      );
    }

    // Same as Applications: embed the signed file URL so the browser's native
    // PDF viewer (toolbar, thumbnails, zoom) appears inside the dialog.
    if (kIsWeb && _isPdfOrOffice) {
      return RspIframePreview(url: _previewUrl);
    }

    return _PreviewFallback(url: widget.url);
  }
}

class _PreviewFallback extends StatelessWidget {
  const _PreviewFallback({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.insert_drive_file_outlined,
              size: 40,
              color: AppTheme.dashTextSecondaryOf(context),
            ),
            const SizedBox(height: 12),
            Text(
              'Inline preview is not available for this file.\nOpen it in a new tab to view.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: AppTheme.dashTextSecondaryOf(context),
              ),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: () => _openExternal(url),
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              label: const Text('Open in new tab'),
            ),
          ],
        ),
      ),
    );
  }
}
