import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';

class DtrPdfPreviewPanel extends StatelessWidget {
  const DtrPdfPreviewPanel({
    super.key,
    required this.buildPdf,
    required this.pageFormat,
    required this.filename,
  });

  final LayoutCallback buildPdf;
  final PdfPageFormat pageFormat;
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
                        'DTR Preview',
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
                build: buildPdf,
                initialPageFormat: pageFormat,
                pageFormats: {'Selected paper': pageFormat},
                dynamicLayout: true,
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
