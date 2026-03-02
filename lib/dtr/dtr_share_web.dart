import 'dart:typed_data';

// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

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
  final blob = html.Blob([bytes], mimeType);
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement()
    ..href = url
    ..download = filename
    ..style.display = 'none';
  html.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  html.Url.revokeObjectUrl(url);
}
