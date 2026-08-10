import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart';

String _mimeTypeFromFilename(String filename) {
  final parts = filename.toLowerCase().split('.');
  final extension = parts.length > 1 ? parts.last : '';
  return switch (extension) {
    'pdf' => 'application/pdf',
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    _ => 'application/octet-stream',
  };
}

Future<void> openLocatorAttachmentBytes(
  List<int> bytes,
  String filename,
) async {
  final data = Uint8List.fromList(bytes);
  final blob = Blob(
    [data.buffer.toJS].toJS,
    BlobPropertyBag(type: _mimeTypeFromFilename(filename)),
  );
  final url = URL.createObjectURL(blob);
  window.open(url, '_blank');
}
