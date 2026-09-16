import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

Future<Uint8List> buildDocuTrackerA4Pdf(List<Uint8List> pageImages) async {
  if (pageImages.isEmpty) {
    throw ArgumentError.value(pageImages, 'pageImages', 'cannot be empty');
  }
  final document = pw.Document();
  for (final bytes in pageImages) {
    document.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.Image(
          pw.MemoryImage(bytes),
          width: PdfPageFormat.a4.width,
          height: PdfPageFormat.a4.height,
          fit: pw.BoxFit.fill,
        ),
      ),
    );
  }
  return document.save();
}
