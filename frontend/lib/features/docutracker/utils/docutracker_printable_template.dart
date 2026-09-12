import 'package:flutter/services.dart';
import 'package:printing/printing.dart';

class DocuTrackerPrintableTemplate {
  DocuTrackerPrintableTemplate._();

  static const String a4LetterheadAsset = 'assets/forms/a4_letter.pdf';
  static Uint8List? _cachedA4Letterhead;

  /// Rasterizes the same official A4 letterhead used by the existing BI form.
  static Future<Uint8List?> loadA4LetterheadPng() async {
    if (_cachedA4Letterhead case final cached?) return cached;
    try {
      final printingInfo = await Printing.info().timeout(
        const Duration(seconds: 8),
      );
      if (!printingInfo.canRaster) return null;
      final data = await rootBundle.load(a4LetterheadAsset);
      final pages = Printing.raster(
        data.buffer.asUint8List(),
        pages: const [0],
        dpi: 144,
      ).timeout(const Duration(seconds: 15));
      await for (final page in pages) {
        final png = await page.toPng();
        _cachedA4Letterhead = png;
        return png;
      }
    } catch (_) {
      // The printable page frame provides a programmatic fallback.
    }
    return null;
  }
}
