import 'package:flutter/material.dart';

import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/recruitment/data/exam_image_support.dart';

/// Network image for exam questions / answer choices.
///
/// Always keeps the aspect ratio ([BoxFit.contain]) and never exceeds its
/// parent. With [boxHeight] it fills a fixed-height box (used by choice cards);
/// otherwise it sizes naturally up to [maxHeight] (used by question figures).
class ExamImage extends StatelessWidget {
  const ExamImage({
    super.key,
    required this.path,
    this.boxHeight,
    this.maxHeight = 360,
    this.borderRadius = 10,
    this.background,
  });

  final String path;
  final double? boxHeight;
  final double maxHeight;
  final double borderRadius;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final url = examImageUrl(path);
    final image = Image.network(
      url,
      fit: BoxFit.contain,
      width: boxHeight != null ? double.infinity : null,
      height: boxHeight,
      alignment: Alignment.center,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return SizedBox(
          height: boxHeight ?? 120,
          child: const Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.2),
            ),
          ),
        );
      },
      errorBuilder: (context, error, stack) => SizedBox(
        height: boxHeight ?? 96,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.broken_image_outlined,
                color: AppTheme.dashTextSecondaryOf(context),
              ),
              const SizedBox(height: 4),
              Text(
                'Image unavailable',
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.dashTextSecondaryOf(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: ColoredBox(
        color: background ?? Colors.white,
        child: boxHeight != null
            ? SizedBox(height: boxHeight, child: image)
            : ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxHeight),
                child: Center(child: image),
              ),
      ),
    );
  }
}

/// Question figure with optional caption; tap opens the zoomable viewer.
class ExamQuestionFigure extends StatelessWidget {
  const ExamQuestionFigure({
    super.key,
    required this.path,
    this.caption,
    this.maxHeight = 360,
  });

  final String path;
  final String? caption;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final cap = (caption ?? '').trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Tooltip(
          message: 'Tap to enlarge',
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => showExamImageViewer(context, path: path, caption: cap),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppTheme.primaryNavy.withValues(alpha: 0.14),
                ),
              ),
              child: Stack(
                children: [
                  ExamImage(path: path, maxHeight: maxHeight),
                  Positioned(
                    right: 6,
                    bottom: 6,
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.zoom_in_rounded,
                        size: 18,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (cap.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            cap,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              fontStyle: FontStyle.italic,
              height: 1.35,
              color: AppTheme.dashTextSecondaryOf(context),
            ),
          ),
        ],
      ],
    );
  }
}

/// Full-screen style viewer with pinch / scroll zoom and pan.
Future<void> showExamImageViewer(
  BuildContext context, {
  required String path,
  String? caption,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.85),
    builder: (ctx) {
      final cap = (caption ?? '').trim();
      return Dialog(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Stack(
              children: [
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: ColoredBox(
                      color: Colors.white,
                      child: Column(
                        children: [
                          Expanded(
                            child: InteractiveViewer(
                              minScale: 1,
                              maxScale: 6,
                              child: Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Image.network(
                                    examImageUrl(path),
                                    fit: BoxFit.contain,
                                    errorBuilder: (context, e, s) =>
                                        const Center(
                                          child: Text('Image unavailable'),
                                        ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (cap.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                              child: Text(
                                cap,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: IconButton.filled(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(ctx).pop(),
                    style: IconButton.styleFrom(
                      backgroundColor: AppTheme.primaryNavy,
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ),
                Positioned(
                  left: 14,
                  bottom: cap.isNotEmpty ? 48 : 14,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Pinch or scroll to zoom',
                      style: TextStyle(color: Colors.white, fontSize: 11.5),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      );
    },
  );
}
