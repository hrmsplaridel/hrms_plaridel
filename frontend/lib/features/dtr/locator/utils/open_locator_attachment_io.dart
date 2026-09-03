import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

Future<void> openLocatorAttachmentBytes(
  List<int> bytes,
  String filename,
) async {
  final tempDir = await getTemporaryDirectory();
  final safeName = filename.replaceAll(RegExp(r'[^\w\-.]'), '_');
  final file = File('${tempDir.path}/locator_attachment_$safeName');
  await file.writeAsBytes(bytes);
  await launchUrl(Uri.file(file.path), mode: LaunchMode.externalApplication);
}
