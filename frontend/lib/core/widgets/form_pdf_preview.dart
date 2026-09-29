import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/core/utils/responsive_right_side_panel.dart';

/// Opens a PDF preview in a right-side slide panel (or full-screen on narrow
/// viewports), matching the DTR Preview style — themed header with icon, print
/// and share actions enabled.
Future<void> showFormPdfPreview({
  required BuildContext context,
  required Uint8List bytes,
  required String title,
  required String filename,
}) => openResponsiveRightSidePanel<void>(
  context: context,
  barrierLabel: 'Close $title',
  breakpoint: 900,
  minWidth: 680,
  initialWidthFraction: 0.62,
  builder: (_) =>
      _FormPdfPreviewPanel(bytes: bytes, title: title, filename: filename),
);

class _FormPdfPreviewPanel extends StatelessWidget {
  const _FormPdfPreviewPanel({
    required this.bytes,
    required this.title,
    required this.filename,
  });

  final Uint8List bytes;
  final String title;
  final String filename;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.dashCanvasOf(context),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Material(
              color: AppTheme.dashPanelOf(context),
              elevation: 1,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 8, 10),
                child: Row(
                  children: [
                    const Icon(Icons.preview_rounded, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          color: AppTheme.dashTextPrimaryOf(context),
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close preview',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: PdfPreview(
                build: (_) async => bytes,
                pdfFileName: filename,
                allowPrinting: true,
                allowSharing: true,
                canChangeOrientation: false,
                canChangePageFormat: false,
                canDebug: false,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
