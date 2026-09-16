import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

/// Saves bytes to temp file and opens with system default app.
Future<void> openAttachmentBytes(List<int> bytes, String filename) async {
  final tempDir = await getTemporaryDirectory();
  final safeName = filename.replaceAll(RegExp(r'[^\w\-.]'), '_');
  final file = File('${tempDir.path}/leave_attachment_$safeName');
  await file.writeAsBytes(bytes);
  await launchUrl(Uri.file(file.path), mode: LaunchMode.externalApplication);
}

/// Saves attachment bytes to the user's downloads folder.
Future<String> downloadAttachmentBytes(List<int> bytes, String filename) async {
  final downloadsDir =
      await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
  final safeName = filename.replaceAll(RegExp(r'[^\w\-.]'), '_');
  final dotIndex = safeName.lastIndexOf('.');
  final stem = dotIndex > 0 ? safeName.substring(0, dotIndex) : safeName;
  final extension = dotIndex > 0 ? safeName.substring(dotIndex) : '';
  var file = File('${downloadsDir.path}/$safeName');
  var suffix = 1;
  while (await file.exists()) {
    file = File('${downloadsDir.path}/$stem ($suffix)$extension');
    suffix += 1;
  }
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}
