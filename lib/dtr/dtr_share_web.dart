import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Share/download implementation for web (triggers file download).
Future<void> shareOrDownloadPdf(Uint8List bytes, String filename) async {
  _triggerDownload(bytes, filename, 'application/pdf');
}

Future<void> shareOrDownloadFile(
  Uint8List bytes,
  String filename,
  String mimeType,
) async {
  _triggerDownload(bytes, filename, mimeType);
}

void _triggerDownload(Uint8List bytes, String filename, String mimeType) {
  final jsBytes = JSUint8Array(
    bytes.buffer.toJS,
    bytes.offsetInBytes,
    bytes.lengthInBytes,
  );
  final blob = web.Blob(
    <JSAny>[jsBytes].toJS,
    web.BlobPropertyBag(type: mimeType),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = filename
    ..style.display = 'none';
  web.document.body?.appendChild(anchor);
  anchor.click();
  anchor.remove();
  web.URL.revokeObjectURL(url);
}
