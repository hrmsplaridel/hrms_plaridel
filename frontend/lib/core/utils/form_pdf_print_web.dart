import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart';

/// Opens the PDF in a real browser tab (Chrome PDF viewer), then print.
///
/// Hidden-iframe `print()` (used by the `printing` package) often hangs Chrome
/// on "Loading preview..." — especially when a physical printer like Brother is
/// the OS/browser default. A full PDF tab avoids that and never selects a
/// printer itself (the browser picks Destination from its own defaults).
Future<bool> printPdfBytes(Uint8List bytes) async {
  if (bytes.isEmpty) return false;

  final jsBytes = JSUint8Array(
    bytes.buffer.toJS,
    bytes.offsetInBytes,
    bytes.lengthInBytes,
  );
  final blob = Blob(
    <JSAny>[jsBytes].toJS,
    BlobPropertyBag(type: 'application/pdf'),
  );
  final url = URL.createObjectURL(blob);

  final opened = window.open(url, '_blank');
  if (opened == null) {
    // Popup blocked — download so the user can still open/print the file.
    final anchor = HTMLAnchorElement()
      ..href = url
      ..download = 'form.pdf'
      ..style.display = 'none';
    document.body?.append(anchor);
    anchor.click();
    anchor.remove();
    Timer(const Duration(minutes: 2), () => URL.revokeObjectURL(url));
    return true;
  }

  // Let Chrome's PDF viewer finish painting, then open the print dialog from
  // that tab (not from a hidden iframe inside the Flutter app).
  Timer(const Duration(milliseconds: 900), () {
    try {
      opened.focus();
      opened.print();
    } catch (_) {
      // User can still print from the PDF tab (Ctrl+P / print icon).
    }
  });

  Timer(const Duration(minutes: 5), () => URL.revokeObjectURL(url));
  return true;
}
