import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart';

/// Infer MIME type from filename so the browser can render (not treat as text).
String _mimeTypeFromFilename(String filename) {
  final ext = filename.toLowerCase().split('.').lastOrNull ?? '';
  return switch (ext) {
    'pdf' => 'application/pdf',
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    _ => 'application/octet-stream',
  };
}

/// Opens attachment in new browser tab (web).
Future<void> openAttachmentBytes(List<int> bytes, String filename) async {
  final data = Uint8List.fromList(bytes);
  final buffer = data.buffer.toJS;
  final blobParts = [buffer].toJS;
  final mimeType = _mimeTypeFromFilename(filename);
  final blob = Blob(blobParts, BlobPropertyBag(type: mimeType));
  final url = URL.createObjectURL(blob);
  window.open(url, '_blank');
  Future<void>.delayed(const Duration(minutes: 1), () {
    URL.revokeObjectURL(url);
  });
}

/// Downloads attachment bytes through the browser.
Future<String> downloadAttachmentBytes(List<int> bytes, String filename) async {
  final data = Uint8List.fromList(bytes);
  final jsBytes = JSUint8Array(
    data.buffer.toJS,
    data.offsetInBytes,
    data.lengthInBytes,
  );
  final blob = Blob(
    <JSAny>[jsBytes].toJS,
    BlobPropertyBag(type: _mimeTypeFromFilename(filename)),
  );
  final url = URL.createObjectURL(blob);
  final anchor = HTMLAnchorElement()
    ..href = url
    ..download = filename
    ..style.display = 'none';
  document.body?.appendChild(anchor);
  anchor.click();
  anchor.remove();
  URL.revokeObjectURL(url);
  return filename;
}
