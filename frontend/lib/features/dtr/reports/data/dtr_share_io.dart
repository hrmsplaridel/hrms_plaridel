import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
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

/// Saves files through the desktop Save As dialog and shares them on mobile.
/// Returns false when the user cancels the desktop dialog.
Future<bool> saveOrDownloadFile(
  Uint8List bytes,
  String filename,
  String mimeType,
) async {
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    final extension = filename.contains('.')
        ? filename.split('.').last.toLowerCase()
        : null;
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Save attendance export',
      fileName: filename,
      type: extension == null ? FileType.any : FileType.custom,
      allowedExtensions: extension == null ? null : [extension],
      lockParentWindow: true,
    );
    if (path == null) return false;

    await File(path).writeAsBytes(bytes, flush: true);
    return true;
  }

  final xfile = XFile.fromData(bytes, mimeType: mimeType, name: filename);
  await Share.shareXFiles([xfile], subject: 'DTR Export');
  return true;
}
