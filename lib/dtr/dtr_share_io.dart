import 'dart:typed_data';

import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

/// Share/download implementation for mobile and desktop (uses share_plus).
Future<void> shareOrDownloadPdf(Uint8List bytes, String filename) async {
  await Printing.sharePdf(bytes: bytes, filename: filename);
}

Future<void> shareOrDownloadFile(
  Uint8List bytes,
  String filename,
  String mimeType,
) async {
  final xfile = XFile.fromData(bytes, mimeType: mimeType, name: filename);
  await Share.shareXFiles([xfile], subject: 'DTR Export');
}
