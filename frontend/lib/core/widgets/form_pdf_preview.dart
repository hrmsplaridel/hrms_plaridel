import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

Future<void> showFormPdfPreview({
  required BuildContext context,
  required Uint8List bytes,
  required String title,
  required String filename,
}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (context) => Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: PdfPreview(
          build: (_) async => bytes,
          pdfFileName: filename,
          allowPrinting: false,
          allowSharing: false,
          canChangePageFormat: false,
          canChangeOrientation: false,
          canDebug: false,
          useActions: false,
          maxPageWidth: 900,
        ),
      ),
    ),
  ),
);
